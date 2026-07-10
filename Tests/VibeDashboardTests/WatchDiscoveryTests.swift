// WatchDiscoveryTests.swift — journal replay, lane discovery, and lane-identity
// stability for the agent watch window.

import Testing
import Foundation
@testable import VibeDashboard

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

    /// A standard session fixture: `<dir>/sess.jsonl` + `<dir>/sess/subagents/`.
    private func standardFixture() throws -> (target: AgentWatchTarget, subagents: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-std-" + UUID().uuidString)
        let subagents = dir.appendingPathComponent("sess/subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        let main = dir.appendingPathComponent("sess.jsonl")
        try "{}\n".write(to: main, atomically: true, encoding: .utf8)
        return (AgentWatchTarget(repoName: "repo", repoPath: "/tmp/repo", tool: "claude-code",
                                 kind: .standard, transcriptPath: main.path, workflowId: nil),
                subagents)
    }

    @Test("standard lanes: ids stick to their file when a new wave interleaves alphabetically")
    func standardLaneStability() throws {
        let (target, subagents) = try standardFixture()
        try "{}\n".write(to: subagents.appendingPathComponent("agent-bb.jsonl"),
                         atomically: true, encoding: .utf8)
        let s1 = AgentWatchModel.discoverLanes(
            target: target, prior: .init(lanes: [], meta: WatchWorkflowMeta()))
        #expect(s1.lanes.map(\.id) == [0, 1])
        #expect(s1.lanes[1].segments.first?.path.hasSuffix("agent-bb.jsonl") == true)

        // Wave 2 lands a file that SORTS BEFORE bb — bb must keep lane 1.
        try "{}\n".write(to: subagents.appendingPathComponent("agent-aa.jsonl"),
                         atomically: true, encoding: .utf8)
        let s2 = AgentWatchModel.discoverLanes(target: target, prior: s1)
        #expect(s2.lanes.map(\.id) == [0, 1, 2])
        #expect(s2.lanes[1].segments.first?.path.hasSuffix("agent-bb.jsonl") == true)
        #expect(s2.lanes[2].segments.first?.path.hasSuffix("agent-aa.jsonl") == true)
    }

    @Test("standard lanes: a laned file outliving the recency filter stays put")
    func standardLaneRetention() throws {
        let (target, subagents) = try standardFixture()
        let file = subagents.appendingPathComponent("agent-old.jsonl")
        try "{}\n".write(to: file, atomically: true, encoding: .utf8)
        let s1 = AgentWatchModel.discoverLanes(
            target: target, prior: .init(lanes: [], meta: WatchWorkflowMeta()))
        #expect(s1.lanes.count == 2)

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-2 * 60 * 60)], ofItemAtPath: file.path)
        let s2 = AgentWatchModel.discoverLanes(target: target, prior: s1)
        #expect(s2.lanes.map(\.id) == [0, 1])   // still shown — it was being watched
        let s0 = AgentWatchModel.discoverLanes(
            target: target, prior: .init(lanes: [], meta: WatchWorkflowMeta()))
        #expect(s0.lanes.count == 1)   // but a FRESH watch doesn't admit a stale file
    }

    @Test("workflow lanes: slot ids survive a slot whose file hasn't appeared yet")
    func workflowSlotIdsStable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-slot-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        {"type":"started","agentId":"a1"}
        {"type":"started","agentId":"a2"}
        """.write(to: dir.appendingPathComponent("journal.jsonl"), atomically: true, encoding: .utf8)
        try "{}\n".write(to: dir.appendingPathComponent("agent-a2.jsonl"),
                         atomically: true, encoding: .utf8)
        let target = AgentWatchTarget(repoName: "repo", repoPath: "/tmp/repo", tool: "claude-code",
                                      kind: .workflow,
                                      transcriptPath: dir.appendingPathComponent("agent-a2.jsonl").path,
                                      workflowId: "wf_x")
        let s1 = AgentWatchModel.discoverLanes(
            target: target, prior: .init(lanes: [], meta: WatchWorkflowMeta()))
        #expect(s1.lanes.map(\.id) == [1])   // a2 keeps replay slot 1, not compressed to 0

        try "{}\n".write(to: dir.appendingPathComponent("agent-a1.jsonl"),
                         atomically: true, encoding: .utf8)
        let s2 = AgentWatchModel.discoverLanes(target: target, prior: s1)
        #expect(s2.lanes.map(\.id) == [0, 1])
        #expect(s2.lanes[1].segments.first?.path.hasSuffix("agent-a2.jsonl") == true)
    }

    @Test("workflow extras: admitted on second sighting, stable high id, then migrate into their slot")
    func workflowExtrasDebounced() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-extra-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("agent-x.jsonl")
        try "{}\n".write(to: file, atomically: true, encoding: .utf8)
        let target = AgentWatchTarget(repoName: "repo", repoPath: "/tmp/repo", tool: "claude-code",
                                      kind: .workflow, transcriptPath: file.path, workflowId: "wf_x")

        let s1 = AgentWatchModel.discoverLanes(
            target: target, prior: .init(lanes: [], meta: WatchWorkflowMeta()))
        #expect(s1.lanes.isEmpty)                        // first sighting: journal line in flight
        #expect(s1.pendingExtras.contains(file.path))
        let s2 = AgentWatchModel.discoverLanes(target: target, prior: s1)
        #expect(s2.lanes.map(\.id) == [AgentWatchModel.extraLaneBase])   // second: admitted, high id
        try #"{"type":"started","agentId":"x"}"#
            .write(to: dir.appendingPathComponent("journal.jsonl"), atomically: true, encoding: .utf8)
        let s3 = AgentWatchModel.discoverLanes(target: target, prior: s2)
        #expect(s3.lanes.map(\.id) == [0])               // journal caught up: its replay slot
        #expect(s3.pendingExtras.isEmpty)
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
