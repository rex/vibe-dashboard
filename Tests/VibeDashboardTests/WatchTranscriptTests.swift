// WatchTranscriptTests.swift — parser, tailer, journal, and pane-discovery tests
// for the agent watch window, driven by real transcript line shapes.

import Testing
import Foundation
@testable import VibeDashboard

@Suite("watch transcript parsing")
struct WatchTranscriptParserTests {
    @Test("claude assistant blocks: text + thinking + tool_use")
    func claudeAssistantBlocks() throws {
        let line = """
        {"type":"assistant","timestamp":"2026-07-09T03:21:00Z","uuid":"u1","message":{"role":"assistant","content":[\
        {"type":"thinking","thinking":"weigh the options"},\
        {"type":"text","text":"Fixing it now."},\
        {"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"make test","description":"Run tests"}}]}}
        """
        var state = WatchTailState()
        WatchTailer.apply(line: line, to: &state)
        #expect(state.events.map(\.kind) == [.thinking, .assistant, .tool])
        #expect(state.events[0].body == "weigh the options")
        #expect(state.events[1].body == "Fixing it now.")
        #expect(state.events[2].title == "Bash")
        #expect(state.events[2].summary == "make test")
        #expect(state.events[2].output == nil)
        #expect(state.pending["tu1"] == 2)
    }

    @Test("claude tool_result pairs onto its tool_use")
    func claudeToolResultPairs() throws {
        var state = WatchTailState()
        WatchTailer.apply(line: #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu9","name":"Read","input":{"file_path":"/tmp/a.swift"}}]}}"#,
                          to: &state)
        WatchTailer.apply(line: #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu9","content":"file body here","is_error":false}]}}"#,
                          to: &state)
        #expect(state.events.count == 1)
        #expect(state.events[0].output == "file body here")
        #expect(state.events[0].isError == false)
        #expect(state.pending.isEmpty)
    }

    @Test("orphan tool_result still renders instead of vanishing")
    func orphanResultSurvives() throws {
        var state = WatchTailState()
        WatchTailer.apply(line: #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"missing","content":"late output","is_error":true}]}}"#,
                          to: &state)
        #expect(state.events.count == 1)
        #expect(state.events[0].title == "tool result")
        #expect(state.events[0].output == "late output")
        #expect(state.events[0].isError)
    }

    @Test("claude plain-string user message becomes a user row")
    func claudeStringContent() throws {
        var state = WatchTailState()
        WatchTailer.apply(line: #"{"type":"user","timestamp":"2026-07-09T03:20:00Z","message":{"role":"user","content":"hello there"}}"#,
                          to: &state)
        #expect(state.events.map(\.kind) == [.user])
        #expect(state.events[0].body == "hello there")
    }

    @Test("codex: developer messages skipped, reasoning becomes thinking, call pairs with output")
    func codexShapes() throws {
        var state = WatchTailState()
        WatchTailer.apply(line: #"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"giant instruction dump"}]}}"#,
                          to: &state)
        WatchTailer.apply(line: #"{"type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"planning the fix"}]}}"#,
                          to: &state)
        WatchTailer.apply(line: #"{"type":"response_item","payload":{"type":"function_call","call_id":"c1","name":"exec_command","arguments":"{\"cmd\":\"make test\"}"}}"#,
                          to: &state)
        WatchTailer.apply(line: #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"c1","output":"{\"output\":\"TEST SUCCEEDED\",\"metadata\":{\"exit_code\":0}}"}}"#,
                          to: &state)
        #expect(state.events.map(\.kind) == [.thinking, .tool])
        #expect(state.events[0].body == "planning the fix")
        #expect(state.events[1].title == "exec_command")
        #expect(state.events[1].summary == "make test")
        #expect(state.events[1].output == "TEST SUCCEEDED")
        #expect(!state.events[1].isError)
    }

    @Test("codex non-zero exit_code marks the tool row as an error")
    func codexExitCodeError() throws {
        let (body, isError) = WatchTranscriptParser.codexOutput(
            "{\"output\":\"boom\",\"metadata\":{\"exit_code\":2}}")
        #expect(body == "boom")
        #expect(isError)
    }

    @Test("codex custom_tool_call keeps raw (non-JSON) input and summarizes its first line")
    func codexCustomToolCall() throws {
        var state = WatchTailState()
        WatchTailer.apply(line: #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"p1","name":"apply_patch","input":"*** Begin Patch\n*** Update File: a.swift\n+let x = 1"}}"#,
                          to: &state)
        #expect(state.events[0].inputIsJSON == false)
        #expect(state.events[0].summary == "*** Update File: a.swift")
    }

    @Test("tool summaries pick the salient argument")
    func toolSummaries() throws {
        #expect(WatchTranscriptParser.toolSummary(name: "Bash",
                                                  input: ["command": "ls -la", "description": "list"]) == "ls -la")
        #expect(WatchTranscriptParser.toolSummary(name: "Read",
                                                  input: ["file_path": "/x/y.swift"]) == "/x/y.swift")
        #expect(WatchTranscriptParser.toolSummary(name: "TodoWrite",
                                                  input: ["todos": [1, 2, 3]]) == "3 todos")
        let long = String(repeating: "a", count: 200)
        #expect(WatchTranscriptParser.toolSummary(name: "Bash", input: ["command": long]).count == 111)
    }
}

@Suite("watch tailer")
struct WatchTailerTests {
    private func tempFile() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-tail-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("t.jsonl").path
    }
    private func line(_ text: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":"\#(text)"}}"# + "\n"
    }

    @Test("reads only appended bytes across ticks and carries partial lines")
    func incrementalAppend() throws {
        let path = tempFile()
        let now = Date()
        try line("one").write(toFile: path, atomically: false, encoding: .utf8)
        var s = WatchTailer.advance(path: path, state: WatchTailState(), now: now)
        #expect(s.events.map(\.body) == ["one"])

        // Append a COMPLETE line plus a partial one — the partial must not parse yet.
        let partial = #"{"type":"assistant","message":{"role":"assis"#
        let fh = FileHandle(forWritingAtPath: path)!
        fh.seekToEndOfFile()
        fh.write((line("two") + partial).data(using: .utf8)!)
        try fh.close()
        s = WatchTailer.advance(path: path, state: s, now: now)
        #expect(s.events.map(\.body) == ["one", "two"])
        #expect(s.carry == partial)

        // Finish the partial line — it joins the carry and parses whole.
        let fh2 = FileHandle(forWritingAtPath: path)!
        fh2.seekToEndOfFile()
        fh2.write(#"tant","content":"three"}}"#.data(using: .utf8)!)
        fh2.write("\n".data(using: .utf8)!)
        try fh2.close()
        s = WatchTailer.advance(path: path, state: s, now: now)
        #expect(s.events.map(\.body) == ["one", "two", "three"])
    }

    @Test("a shrunken file resets the tail instead of reading garbage")
    func truncationResets() throws {
        let path = tempFile()
        let now = Date()
        try (line("one") + line("two")).write(toFile: path, atomically: false, encoding: .utf8)
        var s = WatchTailer.advance(path: path, state: WatchTailState(), now: now)
        #expect(s.events.count == 2)
        try line("fresh").write(toFile: path, atomically: false, encoding: .utf8)   // smaller file
        s = WatchTailer.advance(path: path, state: s, now: now)
        #expect(s.events.map(\.body) == ["fresh"])
    }

    @Test("unchanged files return the same state without work")
    func unchangedNoop() throws {
        let path = tempFile()
        try line("one").write(toFile: path, atomically: false, encoding: .utf8)
        let s1 = WatchTailer.advance(path: path, state: WatchTailState(), now: Date())
        let s2 = WatchTailer.advance(path: path, state: s1, now: Date().addingTimeInterval(5))
        #expect(s1 == s2)
    }

    @Test("the retention cap trims from the front and rebases pending tool indices")
    func capTrimsAndRebases() throws {
        var s = WatchTailState()
        for i in 0..<WatchTailer.maxEvents {
            s.events.append(WatchEvent(id: "e\(i)", kind: .assistant, title: "assistant", body: "x"))
        }
        s.pending = ["k": WatchTailer.maxEvents - 1]
        WatchTailer.apply(line: #"{"type":"assistant","message":{"role":"assistant","content":"overflow"}}"#,
                          to: &s)
        #expect(s.events.count == WatchTailer.maxEvents)
        #expect(s.trimmed == 1)
        #expect(s.pending["k"] == WatchTailer.maxEvents - 2)
        #expect(s.events.last?.body == "overflow")
    }
}

@Suite("watch journal + discovery")
struct WatchDiscoveryTests {
    @Test("journal parse: spawn order + results")
    func journalParse() throws {
        let j = WatchJournal.parse("""
        {"type":"started","key":"v2:aa","agentId":"a1"}
        {"type":"started","key":"v2:bb","agentId":"a2"}
        {"type":"result","key":"v2:aa","agentId":"a1","result":{"ok":true}}
        """)
        #expect(j.startOrder == ["a1", "a2"])
        #expect(j.results["a1"]?.contains("\"ok\"") == true)
        #expect(j.results["a2"] == nil)
    }

    @Test("workflow discovery: lanes titled from meta.json, lifecycle from journal")
    func workflowDiscovery() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-wf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let event = #"{"type":"assistant","timestamp":"2026-07-09T03:20:00Z","message":{"role":"assistant","content":"hi"}}"#
        try (event + "\n").write(to: dir.appendingPathComponent("agent-a1.jsonl"), atomically: true, encoding: .utf8)
        try (event + "\n").write(to: dir.appendingPathComponent("agent-a2.jsonl"), atomically: true, encoding: .utf8)
        try #"{"agentType":"general-purpose","description":"Audit the gates"}"#
            .write(to: dir.appendingPathComponent("agent-a1.meta.json"), atomically: true, encoding: .utf8)
        try """
        {"type":"started","agentId":"a1"}
        {"type":"started","agentId":"a2"}
        {"type":"result","agentId":"a1","result":"done"}
        """.write(to: dir.appendingPathComponent("journal.jsonl"), atomically: true, encoding: .utf8)

        let target = AgentWatchTarget(repoName: "repo", repoPath: "/tmp/repo", tool: "claude-code",
                                      kind: .workflow,
                                      transcriptPath: dir.appendingPathComponent("agent-a1.jsonl").path,
                                      workflowId: "wf_x")
        let snap = AgentWatchModel.discoverLanes(target: target,
                                                 prior: AgentWatchModel.Snapshot(lanes: [], meta: WatchWorkflowMeta()))
        #expect(snap.lanes.count == 2)   // both agents still running in parallel → 2 lanes
        #expect(snap.returned == 1 && snap.total == 2)
        let all = snap.lanes.flatMap(\.segments)
        let p1 = try #require(all.first { $0.path.hasSuffix("agent-a1.jsonl") })
        #expect(p1.title == "Audit the gates")
        #expect(p1.badge == "general-purpose")
        #expect(p1.done)
        #expect(p1.outcome?.contains("done") == true)
        let p2 = try #require(all.first { $0.path.hasSuffix("agent-a2.jsonl") })
        #expect(p2.title == "agent a2")
        #expect(!p2.done)
    }

    @Test("lane replay: a returned agent's lane is continued by the next spawn")
    func laneHandoff() throws {
        // Wave 1: a, b, c in parallel. a returns → a2 continues lane 0.
        // b returns → b2 continues lane 1. c never returns; synth starts after
        // a2/b2 return and takes the lowest freed lane (0) — convergence.
        let events: [WatchJournal.Event] = [
            .init(kind: .started, agentId: "a"), .init(kind: .started, agentId: "b"),
            .init(kind: .started, agentId: "c"),
            .init(kind: .result, agentId: "a"), .init(kind: .started, agentId: "a2"),
            .init(kind: .result, agentId: "b"), .init(kind: .started, agentId: "b2"),
            .init(kind: .result, agentId: "a2"), .init(kind: .result, agentId: "b2"),
            .init(kind: .started, agentId: "synth"),
        ]
        let lanes = AgentWatchModel.assignLanes(events: events)
        #expect(lanes == [["a", "a2", "synth"], ["b", "b2"], ["c"]])
    }

    @Test("lane replay: duplicate started (resume) is idempotent; unknown result ignored")
    func laneReplayIdempotent() throws {
        let events: [WatchJournal.Event] = [
            .init(kind: .started, agentId: "a"), .init(kind: .started, agentId: "a"),
            .init(kind: .result, agentId: "ghost"),
            .init(kind: .result, agentId: "a"), .init(kind: .started, agentId: "b"),
        ]
        #expect(AgentWatchModel.assignLanes(events: events) == [["a", "b"]])
    }

    @Test("workflow plan meta parses from the persisted script literal")
    func scriptMetaParses() throws {
        let script = """
        // header comment
        export const meta = {
          name: 'vibe-remediation-wave1',
          description: 'Tier-0/3 trust fixes: self-integrity gate+CI, de-fabricate panels',
          phases: [
            { title: 'Fix', detail: '3 file-disjoint slices in parallel' },
            { title: 'Verify', detail: 'build + test gate' },
          ],
        }
        const COMMON = `whatever { braces } inside a template`
        """
        let meta = WatchWorkflowMeta.parseScriptMeta(script)
        #expect(meta.name == "vibe-remediation-wave1")
        #expect(meta.description?.hasPrefix("Tier-0/3 trust fixes") == true)
        #expect(meta.phases == ["Fix", "Verify"])
        #expect(!meta.isTerminal)
    }

    @Test("script meta handles escaped quotes and double-quoted strings")
    func scriptMetaEscapes() throws {
        let script = """
        export const meta = { name: "wf-x", description: 'it\\'s fine', phases: [] }
        """
        let meta = WatchWorkflowMeta.parseScriptMeta(script)
        #expect(meta.name == "wf-x")
        #expect(meta.description == "it's fine")
        #expect(meta.phases.isEmpty)
    }

    @Test("target from a session without a transcript is refused")
    func targetRequiresTranscript() throws {
        var agent = AgentInfo()
        agent.tool = "aider"
        let repo = Repo(id: "r", name: "r", path: "~/Code/r", absolutePath: "~/Code/r")
        #expect(AgentWatchTarget(agent: agent, repo: repo) == nil)
    }

    @Test("lane titles fall back to the agent's prompt when meta has no description")
    func promptTitleFallback() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-title-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("agent-x.jsonl")
        try #"{"type":"user","agentId":"x","message":{"role":"user","content":"\nREPO: /x. You are the VERIFY stage.\nRun make test."}}"#
            .write(to: file, atomically: true, encoding: .utf8)
        #expect(WatchAgentMeta.promptTitle(transcriptPath: file.path)
                == "REPO: /x. You are the VERIFY stage.")
        #expect(WatchAgentMeta.promptTitle(transcriptPath: "/nonexistent") == nil)
    }
}

@Suite("fsevents repo mapping")
struct RepoEventMapperTests {
    private let repos = [
        (id: "umbrella", absPath: "/Users/p/Code/eco"),
        (id: "child", absPath: "/Users/p/Code/eco/api"),
        (id: "other", absPath: "/Users/p/Code/other"),
    ]

    @Test("deepest repo wins for nested paths")
    func deepestRepo() throws {
        #expect(RepoEventMapper.repoId(for: "/Users/p/Code/eco/api/src/main.go", repos: repos) == "child")
        #expect(RepoEventMapper.repoId(for: "/Users/p/Code/eco/README.md", repos: repos) == "umbrella")
        #expect(RepoEventMapper.repoId(for: "/Users/p/Code/unrelated/x", repos: repos) == nil)
    }

    @Test("noise never triggers: build dirs, .DS_Store, .git internals except index/HEAD/refs")
    func noiseFiltering() throws {
        #expect(RepoEventMapper.isNoise("/r/node_modules/x/index.js"))
        #expect(RepoEventMapper.isNoise("/r/build/out.o"))
        #expect(RepoEventMapper.isNoise("/r/.DS_Store"))
        #expect(RepoEventMapper.isNoise("/r/.git/objects/ab/cdef"))
        #expect(RepoEventMapper.isNoise("/r/.git/logs/HEAD"))
        #expect(!RepoEventMapper.isNoise("/r/.git/index"))
        #expect(!RepoEventMapper.isNoise("/r/.git/HEAD"))
        #expect(!RepoEventMapper.isNoise("/r/.git/refs/heads/main"))
        #expect(!RepoEventMapper.isNoise("/r/src/main.swift"))
        #expect(RepoEventMapper.repoId(for: "/Users/p/Code/eco/api/node_modules/a.js", repos: repos) == nil)
    }
}
