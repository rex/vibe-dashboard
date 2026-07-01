// AgentProbe.swift — best-effort detection of live coding-agent sessions.
//
// Heuristic: scan running processes for `claude` / `codex`, then resolve each
// one's working directory via `lsof` and map it onto a scanned repo. This is
// a signal, not a guarantee — a headless agent with a detached cwd may be missed.

import Foundation

enum AgentProbe {
    struct Session: Sendable {
        var pid: Int
        var tool: String        // claude-code | codex
        var cwd: String
        var elapsed: String
    }

    static func sessions() async -> [Session] {
        let ps = await ProcessRunner.run("/bin/ps", ["-axo", "pid=,etime=,command="])
        guard ps.ok else { return [] }
        var found: [Session] = []
        for raw in ps.lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            guard !lower.contains("vibedashboard") else { continue }
            let tool: String?
            if lower.contains("claude") && !lower.contains("claude-preview") { tool = "claude-code" }
            else if lower.range(of: "(^|/| )codex( |$|-)", options: .regularExpression) != nil { tool = "codex" }
            else { tool = nil }
            guard let tool else { continue }

            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, let pid = Int(parts[0]) else { continue }
            let etime = parts[1]
            guard let cwd = await cwd(of: pid), !cwd.isEmpty else { continue }
            found.append(Session(pid: pid, tool: tool, cwd: cwd, elapsed: humanize(etime)))
        }
        return found
    }

    private static func cwd(of pid: Int) async -> String? {
        let r = await ProcessRunner.run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"])
        guard r.ok else { return nil }
        return r.lines.first { $0.hasPrefix("n/") }.map { String($0.dropFirst()) }
    }

    /// ps etime "MM:SS" / "HH:MM:SS" / "D-HH:MM:SS" → "6m" / "2h" / "3d".
    private static func humanize(_ etime: String) -> String {
        if etime.contains("-") { return etime.split(separator: "-").first.map { "\($0)d" } ?? etime }
        let comps = etime.split(separator: ":").compactMap { Int($0) }
        switch comps.count {
        case 3: return "\(comps[0])h"
        case 2: return comps[0] > 0 ? "\(comps[0])m" : "\(comps[1])s"
        default: return etime
        }
    }
}
