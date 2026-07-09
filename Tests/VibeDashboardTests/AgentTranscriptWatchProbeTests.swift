import Testing
import Foundation
@testable import VibeDashboard

@Suite("transcript watch panes")
struct TranscriptWatchPaneTests {
    @Test("watch parser renders Codex rollout messages and tool calls")
    func codexWatchEvents() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:30:00Z"))
        let body = try [
            codexMessageLine(timestamp: "2026-07-09T03:20:00Z", role: "user",
                             blockType: "input_text", text: "Please inspect the app."),
            codexMessageLine(timestamp: "2026-07-09T03:21:00Z", role: "assistant",
                             blockType: "output_text", text: "I found the issue."),
            codexCallLine(timestamp: "2026-07-09T03:22:00Z", name: "exec_command",
                          arguments: #"{"cmd":"make test"}"#),
            codexOutputLine(timestamp: "2026-07-09T03:23:00Z", output: "TEST SUCCEEDED")
        ].joined(separator: "\n")
        let file = try transcriptFile(body, mtime: now)

        let pane = try #require(AgentTranscriptWatchProbe.panes(path: file.path, kind: .standard).first)
        #expect(pane.phaseLabel == nil)
        #expect(pane.events.map(\.kind) == [.text, .text, .toolUse, .toolResult])
        #expect(pane.events[0].body == "Please inspect the app.")
        #expect(pane.events[2].title == "exec_command")
        #expect(pane.events[2].body.contains(#""cmd" : "make test""#))
        #expect(pane.events[3].body == "TEST SUCCEEDED")
    }

    @Test("workflow watch panes show phase labels")
    func workflowWatchPhaseLabels() throws {
        let now = try #require(RelTime.iso.date(from: "2026-07-09T03:30:00Z"))
        let dir = try tempDir()
        let one = dir.appendingPathComponent("agent-a.jsonl")
        let two = dir.appendingPathComponent("agent-b.jsonl")
        try writeTranscript(
            codexMessageLine(timestamp: "2026-07-09T03:20:00Z", role: "assistant",
                             blockType: "output_text", text: "step one"),
            to: one,
            mtime: now
        )
        try writeTranscript(
            codexMessageLine(timestamp: "2026-07-09T03:20:10Z", role: "assistant",
                             blockType: "output_text", text: "step two"),
            to: two,
            mtime: now
        )

        let panes = AgentTranscriptWatchProbe.panes(path: one.path, kind: .workflow)
        #expect(panes.map(\.phaseLabel) == ["phase 1", "phase 2"])
    }

    private func transcriptFile(_ body: String, mtime: Date) throws -> URL {
        let dir = try tempDir()
        let file = dir.appendingPathComponent(UUID().uuidString + ".jsonl")
        try writeTranscript(body, to: file, mtime: mtime)
        return file
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-watch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeTranscript(_ body: String, to file: URL, mtime: Date) throws {
        try body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
    }

    private func codexMessageLine(timestamp: String, role: String,
                                  blockType: String, text: String) throws -> String {
        try jsonLine([
            "timestamp": timestamp,
            "type": "response_item",
            "payload": [
                "type": "message",
                "id": UUID().uuidString,
                "role": role,
                "content": [["type": blockType, "text": text]]
            ]
        ])
    }

    private func codexCallLine(timestamp: String, name: String, arguments: String) throws -> String {
        try jsonLine([
            "timestamp": timestamp,
            "type": "response_item",
            "payload": [
                "type": "function_call",
                "id": UUID().uuidString,
                "name": name,
                "arguments": arguments
            ]
        ])
    }

    private func codexOutputLine(timestamp: String, output: String) throws -> String {
        try jsonLine([
            "timestamp": timestamp,
            "type": "response_item",
            "payload": [
                "type": "function_call_output",
                "call_id": UUID().uuidString,
                "output": output
            ]
        ])
    }

    private func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
