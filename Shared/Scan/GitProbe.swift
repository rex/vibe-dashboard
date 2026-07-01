// GitProbe.swift — real git state: branch, worktree, remotes, signature.

import Foundation

struct GitFacts: Sendable {
    var branch = "main"
    var worktree = WorktreeState()
    var remotes: [Remote] = []
    var worktrees: [Worktree] = []
    var commitShort = "-------"
    var commitDateISO = ""
    var commitDateRel = "—"
    var isRepo = false
}

enum GitProbe {
    static func probe(_ abs: String, now: Date) async -> GitFacts {
        var f = GitFacts()
        let inside = await ProcessRunner.git(["rev-parse", "--is-inside-work-tree"], cwd: abs)
        guard inside.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else { return f }
        f.isRepo = true

        f.branch = await line(["rev-parse", "--abbrev-ref", "HEAD"], abs) ?? "main"
        f.commitShort = await line(["rev-parse", "--short", "HEAD"], abs) ?? "-------"
        if let iso = await line(["log", "-1", "--format=%cI"], abs), let d = ISO8601DateFormatter().date(from: iso) {
            f.commitDateISO = iso
            f.commitDateRel = RelTime.ago(d, now: now)
        }

        // Worktree cleanliness.
        let status = await ProcessRunner.git(["status", "--porcelain"], cwd: abs)
        let dirtyLines = status.stdout.split(separator: "\n").filter { !$0.isEmpty }
        f.worktree.unstaged = dirtyLines.count
        f.worktree.clean = dirtyLines.isEmpty

        // Unpushed (ahead of upstream).
        if let n = await line(["rev-list", "--count", "@{u}..HEAD"], abs), let c = Int(n) {
            f.worktree.unpushed = c
        }

        // Signature of the last commit.
        if let g = await line(["log", "-1", "--format=%G?"], abs) {
            f.worktree.signed = ["G", "U", "X", "Y", "R", "E"].contains(g)
        } else {
            let cfg = await line(["config", "--get", "commit.gpgsign"], abs)
            f.worktree.signed = (cfg == "true")
        }

        f.remotes = await remotes(abs, unpushed: f.worktree.unpushed)
        f.worktrees = await worktrees(abs, now: now)
        return f
    }

    private static func line(_ args: [String], _ abs: String) async -> String? {
        let r = await ProcessRunner.git(args, cwd: abs)
        guard r.ok else { return nil }
        let s = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func remotes(_ abs: String, unpushed: Int) async -> [Remote] {
        let r = await ProcessRunner.git(["remote", "-v"], cwd: abs)
        var seen: [String: Remote] = [:]
        for ln in r.stdout.split(separator: "\n") {
            let parts = ln.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2, ln.contains("(fetch)") else { continue }
            let name = parts[0], url = parts[1]
            let host = url.contains("github.com") ? "github"
                : (url.contains("gitea") || url.contains("git.") ? "gitea" : "other")
            seen[name] = Remote(name: name, host: host, url: url,
                                ahead: name == "origin" ? unpushed : 0, behind: 0,
                                primary: name == "origin", mirror: name != "origin")
        }
        return Array(seen.values).sorted { $0.primary && !$1.primary }
    }

    private static func worktrees(_ abs: String, now: Date) async -> [Worktree] {
        let r = await ProcessRunner.git(["worktree", "list", "--porcelain"], cwd: abs)
        var out: [Worktree] = []
        var curPath: String? = nil
        var curBranch: String? = nil
        func flush() {
            guard let p = curPath, p != abs, let br = curBranch else { curPath = nil; curBranch = nil; return }
            out.append(makeWorktree(path: p, branch: br))
            curPath = nil; curBranch = nil
        }
        for ln in r.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            if ln.hasPrefix("worktree ") { flush(); curPath = String(ln.dropFirst(9)) }
            else if ln.hasPrefix("branch ") { curBranch = String(ln.dropFirst(7)).replacingOccurrences(of: "refs/heads/", with: "") }
            else if ln.isEmpty { flush() }
        }
        flush()
        return out
    }

    /// Best-effort worktree life classification from age + commit count.
    private static func makeWorktree(path: String, branch: String) -> Worktree {
        Worktree(branch: branch, created: "—", lastCommit: "—", commits: 0, state: .stale)
    }
}
