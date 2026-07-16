// FSEventsWatcherTests.swift — real kernel event delivery, not just path mapping.

import Foundation
import Testing
@testable import VibeDashboard

@Suite("FSEvents watcher")
struct FSEventsWatcherTests {
    @Test("a nested transcript write reaches the watcher")
    func nestedTranscriptWrite() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-fsevents-" + UUID().uuidString)
        let nested = root.appendingPathComponent("project/session/subagents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let latch = EventLatch()
        let watcher = try #require(FSEventsWatcher(paths: [root.path], latency: 0.05) { paths in
            latch.record(paths)
        })
        try await Task.sleep(for: .milliseconds(100))
        let transcript = nested.appendingPathComponent("agent-new.jsonl")
        try "{}\n".write(to: transcript, atomically: true, encoding: .utf8)

        let paths = await Task.detached { latch.wait(timeout: 5) }.value
        withExtendedLifetime(watcher) {}
        #expect(paths != nil)
    }

    private final class EventLatch: @unchecked Sendable {
        private let lock = NSLock()
        private let signal = DispatchSemaphore(value: 0)
        private var paths: [String]?

        func record(_ newPaths: [String]) {
            lock.lock()
            if paths == nil { paths = newPaths; signal.signal() }
            lock.unlock()
        }

        func wait(timeout: TimeInterval) -> [String]? {
            signal.wait(timeout: .now() + timeout) == .success ? paths : nil
        }
    }
}
