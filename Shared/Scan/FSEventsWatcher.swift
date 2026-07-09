// FSEventsWatcher.swift — thin wrapper over the macOS FSEvents API.
//
// One kernel-coalesced STREAM per set of directory trees. Unlike Linux inotify
// (per-directory watch descriptors with a global limit) or kqueue (one file
// descriptor per watched FILE), FSEvents reads a system-wide change journal —
// watching all of ~/Code costs the same handful of resources as watching one
// folder, so "inode watcher exhaustion" cannot happen here. Events arrive
// per-path (kFSEventStreamCreateFlagFileEvents), coalesced by `latency`.

import Foundation
import CoreServices

final class FSEventsWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "vibe.fsevents", qos: .utility)
    fileprivate let onPaths: @Sendable ([String]) -> Void

    /// Starts watching immediately; nil when the stream can't be created (e.g. no
    /// valid paths). Callbacks arrive on an internal utility queue — hop to the
    /// main actor yourself.
    init?(paths: [String], latency: TimeInterval,
          onPaths: @escaping @Sendable ([String]) -> Void) {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return nil }
        self.onPaths = onPaths

        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents)
            | UInt32(kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, fsEventsTrampoline, &context, existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(flags)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}

/// C trampoline: recover the watcher from the context pointer and hand the raw
/// char** path list over as Swift strings.
private func fsEventsTrampoline(_ stream: ConstFSEventStreamRef,
                                _ info: UnsafeMutableRawPointer?,
                                _ count: Int,
                                _ eventPaths: UnsafeMutableRawPointer,
                                _ flags: UnsafePointer<FSEventStreamEventFlags>,
                                _ ids: UnsafePointer<FSEventStreamEventId>) {
    guard let info else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
    let raw = eventPaths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>?.self)
    var paths: [String] = []
    paths.reserveCapacity(count)
    for i in 0..<count {
        if let p = raw[i] { paths.append(String(cString: p)) }
    }
    if !paths.isEmpty { watcher.onPaths(paths) }
}

// MARK: - Event → repo mapping (pure, testable)

/// Decide which repo (if any) a filesystem event belongs to, filtering the noise
/// that would otherwise re-score repos on every build artifact write.
enum RepoEventMapper {
    /// Generated/dependency dirs whose churn never changes a repo's git-derived
    /// state in a way the user acted on.
    static let noiseDirs: Set<String> = [
        "node_modules", ".venv", "venv", "DerivedData", "build", "dist", ".build",
        ".next", "target", "__pycache__", ".pytest_cache", ".mypy_cache", ".cache",
        ".swiftpm", "Pods",
    ]

    /// Inside `.git`, only the index / HEAD / refs are signal (staging, commits,
    /// branch moves, fetches). objects/, logs/, hooks output etc. churn constantly.
    static func isNoise(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        if parts.last == ".DS_Store" { return true }
        if let gitIdx = parts.firstIndex(of: ".git") {
            let inner = parts[(gitIdx + 1)...]
            guard let first = inner.first else { return true }        // .git dir itself
            return !(first == "index" || first == "HEAD" || first == "refs")
        }
        return parts.contains { noiseDirs.contains($0) }
    }

    /// The DEEPEST repo whose absolute path prefixes the event path — nested repos
    /// map to the child, not the umbrella workspace. Nil for noise or non-repo paths.
    static func repoId(for eventPath: String, repos: [(id: String, absPath: String)]) -> String? {
        guard !isNoise(eventPath) else { return nil }
        return repos
            .filter { eventPath == $0.absPath || eventPath.hasPrefix($0.absPath + "/") }
            .max { $0.absPath.count < $1.absPath.count }?
            .id
    }
}
