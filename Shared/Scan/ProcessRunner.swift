// ProcessRunner.swift — async shell-out for git / make, off the main actor.

import Foundation

struct ProcessResult: Sendable {
    var stdout: String
    var stderr: String
    var code: Int32
    var ok: Bool { code == 0 }
    var lines: [String] { stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
}

enum ProcessRunner {
    /// Run an executable and capture output. Never throws; a failure to spawn
    /// yields code = -1. Runs on a background queue.
    static func run(_ launchPath: String, _ args: [String],
                    cwd: String? = nil, env: [String: String]? = nil,
                    timeout: TimeInterval = 20) async -> ProcessResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ProcessResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: launchPath)
                proc.arguments = args
                if let cwd { proc.currentDirectoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath) }
                var environment = ProcessInfo.processInfo.environment
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

                // Read pipes fully to avoid deadlock on large output.
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()

                cont.resume(returning: ProcessResult(
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self),
                    code: proc.terminationStatus))
            }
        }
    }

    private static let gitPaths = ["/opt/homebrew/bin/git", "/usr/bin/git", "/usr/local/bin/git"]
    static var gitPath: String { gitPaths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git" }

    /// Convenience: run git in a repo.
    static func git(_ args: [String], cwd: String) async -> ProcessResult {
        await run(gitPath, args, cwd: cwd)
    }
}
