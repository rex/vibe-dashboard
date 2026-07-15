// TranscriptFactsCache.swift — parse a transcript only when its bytes changed.
//
// Session detection runs every few seconds while agents stream. Re-reading the
// head+tail (~1.25 MB) of every recent transcript on every pass burned ~20% of a
// core continuously (sampled). The expensive part — timestamps, cwd, session key,
// telemetry — is a pure function of the FILE CONTENT, so it caches perfectly on
// (mtime, size); lifecycle/state stay time-dependent and are derived per call.

import Foundation

/// The content-derived facts of one transcript file.
struct TranscriptFacts: Sendable {
    var start: Date?
    var last: Date?
    var cwd: String?
    var sessionKey: String?
    var kind: AgentSessionKind = .standard
    var telemetry = SessionTelemetry()
}

enum TranscriptFactsCache {
    private struct Entry {
        var mtime: Date
        var size: UInt64
        var facts: TranscriptFacts
    }

    nonisolated(unsafe) private static var entries: [String: Entry] = [:]
    private static let lock = NSLock()
    private static let capacity = 512   // recent-transcript working set is ~dozens

    /// Cached facts for `path` at the given stat, or compute-and-store via `parse`.
    static func facts(path: String, mtime: Date, size: UInt64,
                      parse: () -> TranscriptFacts) -> TranscriptFacts {
        lock.lock()
        if let e = entries[path], e.mtime == mtime, e.size == size {
            let cached = e.facts
            lock.unlock()
            return cached
        }
        lock.unlock()

        let fresh = parse()          // file IO outside the lock
        lock.lock()
        if entries.count >= capacity, entries[path] == nil {
            // Crude pressure valve — the working set never realistically hits this.
            entries.removeAll(keepingCapacity: true)
        }
        entries[path] = Entry(mtime: mtime, size: size, facts: fresh)
        lock.unlock()
        return fresh
    }

    /// Test hook: forget everything.
    static func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
