// ProcessRunner.swift — async shell-out for git / make, off the main actor.

import Foundation

struct ProcessResult: Sendable {
    var stdout: String
    var stderr: String
    var code: Int32
    var truncated: Bool = false   // a stream exceeded the per-stream byte cap and was clipped
    var ok: Bool { code == 0 }
    var lines: [String] { stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
}

enum ProcessRunner {
    /// Thread-safe accumulator for the two pipes (drained concurrently). The
    /// happens-before edge is the DispatchGroup, but the compiler can't see it,
    /// so the lock keeps strict concurrency honest too.
    private final class IOBox: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data(), err = Data()
        private var outTrunc = false, errTrunc = false
        /// Append up to `cap` bytes per stream; bytes beyond the cap are dropped and the
        /// stream is flagged truncated. The drain loop keeps reading past the cap
        /// (discarding here) so the child never blocks on a full pipe.
        func append(_ d: Data, isOut: Bool, cap: Int) {
            lock.lock(); defer { lock.unlock() }
            if isOut { Self.appendCapped(&out, &outTrunc, d, cap) }
            else { Self.appendCapped(&err, &errTrunc, d, cap) }
        }
        private static func appendCapped(_ buf: inout Data, _ trunc: inout Bool, _ d: Data, _ cap: Int) {
            let room = cap - buf.count
            if room >= d.count { buf.append(d) }
            else { if room > 0 { buf.append(d.prefix(room)) }; trunc = true }
        }
        var stdout: String { lock.lock(); defer { lock.unlock() }; return String(decoding: out, as: UTF8.self) }
        var stderr: String { lock.lock(); defer { lock.unlock() }; return String(decoding: err, as: UTF8.self) }
        var truncated: Bool { lock.lock(); defer { lock.unlock() }; return outTrunc || errTrunc }
    }
    private final class ProcRef: @unchecked Sendable { let p: Process; init(_ p: Process) { self.p = p } }

    /// Per-stream output cap. A pathological command (a huge `git log`, a runaway build)
    /// can emit gigabytes; we keep at most this much per stream and mark the result
    /// `truncated` rather than ballooning memory. 12 MB dwarfs any real git/make output
    /// this app parses, so healthy commands are never clipped.
    private static let maxBytesPerStream = 12 * 1024 * 1024

    /// Run an executable and capture output. Never throws; a failure to spawn
    /// yields code = -1. Runs on a background queue. A hung child is killed after
    /// `timeout`s (SIGTERM, then SIGKILL) so one stuck git can't stall the scan.
    static func run(_ launchPath: String, _ args: [String],
                    cwd: String? = nil, env: [String: String]? = nil,
                    timeout: TimeInterval = 20) async -> ProcessResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ProcessResult, Never>) in
            // ONE consistent QoS end-to-end, and NOTHING blocks a thread waiting on
            // lower-QoS work. The prior version blocked a user-initiated thread on
            // `group.wait()` for default-QoS pipe handlers — a priority inversion that
            // could stall the whole scan (isScanning stuck → "constantly scanning").
            let queue = DispatchQueue(label: "procrunner", qos: .utility, attributes: .concurrent)
            queue.async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: launchPath)
                proc.arguments = args
                if let cwd { proc.currentDirectoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath) }
                var environment = ProcessInfo.processInfo.environment
                // A GUI app launched from Finder/Xcode inherits a MINIMAL PATH
                // (/usr/bin:/bin:…) that omits Homebrew — so `git -S` can't find its
                // `gpg` child ("cannot run gpg: No such file or directory"), and make/
                // xcodegen/etc. would fail the same way. Prepend the standard tool dirs.
                environment["PATH"] = Self.toolPath(environment["PATH"])
                environment["GIT_OPTIONAL_LOCKS"] = "0"
                environment["GIT_TERMINAL_PROMPT"] = "0"
                if let env { environment.merge(env) { _, new in new } }
                proc.environment = environment

                let outPipe = Pipe(), errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                do { try proc.run() } catch {
                    cont.resume(returning: ProcessResult(stdout: "", stderr: "\(error)", code: -1))
                    return
                }

                // Drain both pipes concurrently, each to EOF on its own thread — no
                // sequential pipe-buffer deadlock, and no cross-QoS blocking wait.
                let box = IOBox()
                let group = DispatchGroup()
                let cap = Self.maxBytesPerStream
                for (pipe, isOut) in [(outPipe, true), (errPipe, false)] {
                    group.enter()
                    queue.async {
                        // Chunked drain (not readDataToEndOfFile) so memory stays CAPPED:
                        // keep reading to EOF — the child never blocks on a full pipe — but
                        // IOBox discards bytes past the cap and flags truncation.
                        let handle = pipe.fileHandleForReading
                        while true {
                            let chunk = handle.availableData   // blocks until data, empty at EOF
                            if chunk.isEmpty { break }
                            box.append(chunk, isOut: isOut, cap: cap)
                        }
                        group.leave()
                    }
                }

                // Watchdog: a hung child gets SIGTERM at the deadline, SIGKILL after —
                // that closes its pipes, unblocking the reads so we can never hang forever.
                let ref = ProcRef(proc)
                let wq = DispatchQueue(label: "procrunner.watchdog")
                let term = DispatchWorkItem { if ref.p.isRunning { ref.p.terminate() } }
                let kill9 = DispatchWorkItem { if ref.p.isRunning { kill(ref.p.processIdentifier, SIGKILL) } }
                wq.asyncAfter(deadline: .now() + timeout, execute: term)
                wq.asyncAfter(deadline: .now() + timeout + 3, execute: kill9)

                // Non-blocking: resume once both pipes hit EOF (child has exited).
                group.notify(queue: queue) {
                    proc.waitUntilExit()   // pipes at EOF → child gone → returns immediately
                    term.cancel(); kill9.cancel()
                    cont.resume(returning: ProcessResult(stdout: box.stdout, stderr: box.stderr,
                                                         code: proc.terminationStatus, truncated: box.truncated))
                }
            }
        }
    }

    private static let gitPaths = ["/opt/homebrew/bin/git", "/usr/bin/git", "/usr/local/bin/git"]
    static var gitPath: String { gitPaths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git" }

    /// PATH for every subprocess: the standard CLI tool dirs (Homebrew first, so a
    /// Homebrew git/gpg/make wins) prepended to whatever the app inherited, deduped in
    /// order. Pure + testable. This is what lets a signed `git commit -S` find `gpg`,
    /// and `make`/`xcodegen` find their tools, from a Finder/Xcode-launched GUI app.
    static func toolPath(_ inherited: String?) -> String {
        let toolDirs = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
                        "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (inherited ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>(); var out: [String] = []
        for p in toolDirs + existing where !p.isEmpty && seen.insert(p).inserted { out.append(p) }
        return out.joined(separator: ":")
    }

    /// Convenience: run git in a repo.
    static func git(_ args: [String], cwd: String) async -> ProcessResult {
        await run(gitPath, args, cwd: cwd)
    }
}
