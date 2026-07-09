import Testing
import Foundation
@testable import VibeDashboard

@Suite("transcript-backed live sessions")
struct TranscriptSessionTests {
    @Test("Codex Desktop fractional timestamps parse")
    func fractionalTimestampParses() throws {
        let parsed = try #require(AgentTranscriptProbe.parseTimestamp("2026-07-09T03:32:21.584Z"))
        let whole = try #require(RelTime.iso.date(from: "2026-07-09T03:32:21Z"))
        #expect(abs(parsed.timeIntervalSince(whole) - 0.584) < 0.001)
    }

    @Test("fresh mtime does not resurrect a transcript whose embedded activity is complete")
    func staleEmbeddedTimestampDrops() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:00:00Z"))
        let body = try claudeLine(
            timestamp: "2026-07-09T01:30:00Z",
            cwd: "/Users/dev/Code/stale",
            id: "old"
        )
        let file = try transcriptFile(body, mtime: now)

        #expect(AgentTranscriptProbe.session(path: file.path, tool: "claude-code", now: now) == nil)
    }

    @Test("codex session_meta payload cwd is accepted")
    func codexPayloadCwd() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:00:00Z"))
        let body = try codexLine(
            timestamp: "2026-07-09T02:59:00.123Z",
            payloadTimestamp: "2026-07-09T02:58:00.456Z",
            cwd: "/Users/dev/Code/__APPS/macOS/vibe-dashboard",
            id: "codex-1"
        )
        let file = try transcriptFile(body, mtime: now)

        let session = try #require(AgentTranscriptProbe.session(path: file.path, tool: "codex", now: now))
        #expect(session.id == "codex:codex-1")
        #expect(session.cwd == "/Users/dev/Code/__APPS/macOS/vibe-dashboard")
        #expect(session.state == .active)
        #expect(session.lastActivity == AgentTranscriptProbe.parseTimestamp("2026-07-09T02:59:00.123Z"))
    }

    @Test("codex recursively scans older start-date folders")
    func codexRecursiveStartDateScan() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:00:00Z"))
        let root = try tempDir()
        let oldStartDir = root.appendingPathComponent("2026/07/06")
        try FileManager.default.createDirectory(at: oldStartDir, withIntermediateDirectories: true)
        let file = oldStartDir.appendingPathComponent("rollout-live.jsonl")
        let body = try codexLine(
            timestamp: "2026-07-09T02:59:00.123Z",
            payloadTimestamp: "2026-07-09T02:58:00.456Z",
            cwd: "/Users/dev/Code/live",
            id: "codex-old-start-live"
        )
        try writeTranscript(body, to: file, mtime: now)

        let sessions = AgentTranscriptProbe.codexSessions(root: root.path, now: now)
        #expect(sessions.map(\.id) == ["codex:codex-old-start-live"])
    }

    @Test("codex session id stays stable when tail events have response ids")
    func codexSessionIDIgnoresResponseIDs() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:30:00Z"))
        let body = try [
            codexLine(
                timestamp: "2026-07-09T03:03:54.993Z",
                payloadTimestamp: "2026-07-09T03:03:54.414Z",
                cwd: "/Users/dev/Code/__APPS/macOS/vibe-dashboard",
                id: "019f44d4"
            ),
            responseItemLine(timestamp: "2026-07-09T03:29:00.584Z", id: "fc_not_a_session")
        ].joined(separator: "\n")
        let file = try transcriptFile(body, mtime: now)

        let session = try #require(AgentTranscriptProbe.session(path: file.path, tool: "codex", now: now))
        #expect(session.id == "codex:019f44d4")
        #expect(session.lastActivity == AgentTranscriptProbe.parseTimestamp("2026-07-09T03:29:00.584Z"))
    }

    @Test("a workflow is ONE session card, not one per agent file")
    func workflowCollapsesToOneSession() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:00:00Z"))
        let root = try tempDir()
        let nested = root
            .appendingPathComponent("project")
            .appendingPathComponent("session")
            .appendingPathComponent("subagents")
            .appendingPathComponent("workflows")
            .appendingPathComponent("wf_123")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for (name, ts) in [("agent-a.jsonl", "2026-07-09T02:40:00Z"),
                           ("agent-b.jsonl", "2026-07-09T02:50:00Z"),
                           ("agent-c.jsonl", "2026-07-09T02:55:00Z")] {
            let body = try claudeLine(timestamp: ts, cwd: "/Users/dev/Code/live", id: "subagent")
            try writeTranscript(body, to: nested.appendingPathComponent(name),
                                mtime: #require(RelTime.iso.date(from: ts)))
        }
        try "{\"type\":\"started\",\"agentId\":\"a\"}"
            .write(to: nested.appendingPathComponent("journal.jsonl"), atomically: true, encoding: .utf8)

        let sessions = AgentTranscriptProbe.claudeSessions(root: root.path, now: now)
        #expect(sessions.map(\.id) == ["claude-code:wf:wf_123"])
        #expect(sessions.first?.cwd == "/Users/dev/Code/live")
        #expect(sessions.first?.kind == .workflow)
        #expect(sessions.first?.workflowId == "wf_123")
        #expect(sessions.first?.lastActivity == RelTime.iso.date(from: "2026-07-09T02:55:00Z"))
    }

    @Test("subagents fold into their live parent session and extend its activity")
    func subagentsFoldIntoParent() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:00:00Z"))
        let root = try tempDir()
        let project = root.appendingPathComponent("project")
        let subDir = project.appendingPathComponent("session").appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        // Parent transcript went quiet 50 minutes ago (would be idle on its own)…
        let parentBody = try claudeLine(timestamp: "2026-07-09T02:10:00Z",
                                        cwd: "/Users/dev/Code/live", id: "parent")
        try writeTranscript(parentBody, to: project.appendingPathComponent("session.jsonl"),
                            mtime: #require(RelTime.iso.date(from: "2026-07-09T02:10:00Z")))
        // …but its subagent wrote 1 minute ago.
        let childBody = try claudeLine(timestamp: "2026-07-09T02:59:00Z",
                                       cwd: "/Users/dev/Code/live", id: "child")
        try writeTranscript(childBody, to: subDir.appendingPathComponent("agent-a.jsonl"),
                            mtime: #require(RelTime.iso.date(from: "2026-07-09T02:59:00Z")))

        let sessions = AgentTranscriptProbe.claudeSessions(root: root.path, now: now)
        #expect(sessions.map(\.id) == ["claude-code:parent"])   // no separate subagent card
        #expect(sessions.first?.state == .active)               // child work keeps it live
        #expect(sessions.first?.lastActivity == RelTime.iso.date(from: "2026-07-09T02:59:00Z"))
    }

    @Test("plain claude subagents are distinguished from workflow agents")
    func plainClaudeSubagentKind() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:00:00Z"))
        let root = try tempDir()
        let nested = root
            .appendingPathComponent("project")
            .appendingPathComponent("session")
            .appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("agent-a.jsonl")
        let body = try claudeLine(
            timestamp: "2026-07-09T02:50:00Z",
            cwd: "/Users/dev/Code/live",
            id: "subagent"
        )
        try writeTranscript(body, to: file, mtime: now)

        let session = try #require(AgentTranscriptProbe.claudeSessions(root: root.path, now: now).first)
        #expect(session.kind == .subagent)
        #expect(session.workflowId == nil)
    }

    @Test("root claude transcripts remain standard sessions")
    func rootClaudeTranscriptKind() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:00:00Z"))
        let root = try tempDir()
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("root.jsonl")
        let body = try claudeLine(
            timestamp: "2026-07-09T02:50:00Z",
            cwd: "/Users/dev/Code/live",
            id: "root"
        )
        try writeTranscript(body, to: file, mtime: now)

        let session = try #require(AgentTranscriptProbe.claudeSessions(root: root.path, now: now).first)
        #expect(session.kind == .standard)
        #expect(session.workflowId == nil)
    }

    @Test("multiple live transcripts in one cwd remain distinct sessions")
    func multipleSessionsPerCwd() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:00:00Z"))
        let oneBody = try claudeLine(
            timestamp: "2026-07-09T02:59:00Z",
            cwd: "/Users/dev/Code/live",
            id: "one"
        )
        let twoBody = try claudeLine(
            timestamp: "2026-07-09T02:58:00Z",
            cwd: "/Users/dev/Code/live",
            id: "two"
        )
        let one = try transcriptFile(oneBody, mtime: now)
        let two = try transcriptFile(twoBody, mtime: now)

        let sessions = AgentTranscriptProbe.transcriptSessions(
            paths: [one.path, two.path],
            tool: "claude-code",
            now: now
        )
        #expect(sessions.map(\.id) == ["claude-code:one", "claude-code:two"])
    }

    private func transcriptFile(_ body: String, mtime: Date) throws -> URL {
        let dir = try tempDir()
        let file = dir.appendingPathComponent(UUID().uuidString + ".jsonl")
        try writeTranscript(body, to: file, mtime: mtime)
        return file
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-agent-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeTranscript(_ body: String, to file: URL, mtime: Date) throws {
        try body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
    }

    private func claudeLine(timestamp: String, cwd: String, id: String) throws -> String {
        try jsonLine([
            "timestamp": timestamp,
            "type": "assistant",
            "cwd": cwd,
            "sessionId": id,
            "message": ["content": [String]()]
        ])
    }

    private func codexLine(timestamp: String, payloadTimestamp: String,
                           cwd: String, id: String) throws -> String {
        try jsonLine([
            "timestamp": timestamp,
            "type": "session_meta",
            "payload": [
                "id": id,
                "cwd": cwd,
                "timestamp": payloadTimestamp
            ]
        ])
    }

    private func responseItemLine(timestamp: String, id: String) throws -> String {
        try jsonLine([
            "timestamp": timestamp,
            "type": "response_item",
            "payload": [
                "type": "function_call",
                "id": id
            ]
        ])
    }

    private func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
