import Foundation
import Testing
@testable import VibeDashboard

@Suite("Codex subagent identity")
struct CodexSubagentIdentityTests {
    @Test("child rollout id wins over inherited parent session id")
    func childRolloutKeepsItsOwnIdentity() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-15T13:30:00Z"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("rollout-child.jsonl")
        let child = try meta(id: "child", parentID: "parent", cwd: "/Users/dev/Code/live")
        let inherited = try meta(id: "parent", parentID: nil, cwd: "/Users/dev/Code/live")
        let activity = #"{"timestamp":"2026-07-15T13:29:00Z","type":"event_msg","payload":{"type":"task_started"}}"#
        try [child, inherited, activity].joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

        let session = try #require(AgentTranscriptProbe.session(path: file.path, tool: "codex", now: now))
        #expect(session.id == "codex:child")
        #expect(session.kind == .subagent)
    }

    private func meta(id: String, parentID: String?, cwd: String) throws -> String {
        var payload: [String: Any] = ["id": id, "cwd": cwd, "thread_source": "subagent"]
        if let parentID { payload["session_id"] = parentID }
        let data = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": payload])
        return String(decoding: data, as: UTF8.self)
    }
}
