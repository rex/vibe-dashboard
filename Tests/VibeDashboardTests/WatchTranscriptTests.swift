// WatchTranscriptTests.swift — parser + tailer tests for the agent watch window,
// driven by real transcript line shapes. (Journal/discovery: WatchDiscoveryTests.)

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
