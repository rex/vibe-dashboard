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

        // Unpushed (ahead of upstream). When the branch has no upstream configured,
        // `@{u}..HEAD` fails and `line` returns nil — that used to silently leave
        // unpushed = 0, so a branch with a dozen never-pushed commits graded "in sync".
        // Fall back to "commits not on ANY remote" (the same proxy the worktree
        // classifier uses) so the headline never-pushed signal still fires.
        if let n = await line(["rev-list", "--count", "@{u}..HEAD"], abs), let c = Int(n) {
            f.worktree.unpushed = c
        } else if let n = await line(["rev-list", "--count", "HEAD", "--not", "--remotes"], abs), let c = Int(n) {
            f.worktree.unpushed = c
        }

        // Signature across the last N commits (bounded — no full-history walk). Sampling
        // only HEAD is false-pos/neg-prone under an all-commits-signed policy, so we mark
        // signed only when EVERY recent commit carries a signature. No commit yet (or
        // `log` fails) ⇒ indeterminate ⇒ keep the default (true) rather than inferring
        // from config (which grades intent, not fact) or flagging a 0-commit repo.
        if let out = await line(["log", "-20", "--format=%G?"], abs), let all = Self.allSigned(out) {
            f.worktree.signed = all
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

    /// Do ALL sampled commits carry a signature? `nil` when the sample is empty
    /// (indeterminate — caller keeps its default). Pure + testable. `%G?` codes:
    /// G/U/X/Y/R/E each mean a signature is present (valid, unknown-validity, expired,
    /// expired-key, revoked, or uncheckable); `N` = none, `B` = bad — neither counts.
    static func allSigned(_ log: String) -> Bool? {
        let present: Set<String> = ["G", "U", "X", "Y", "R", "E"]
        let codes = log.split(whereSeparator: { $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !codes.isEmpty else { return nil }
        return codes.allSatisfy { present.contains($0) }
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
        for pair in parseWorktrees(r.stdout, repoAbs: abs) {
            out.append(await classify(path: pair.path, branch: pair.branch, now: now))
        }
        return out
    }

    /// Parse `git worktree list --porcelain` into (path, branch) pairs, EXCLUDING the
    /// main worktree (`repoAbs`). Pure + testable. A DETACHED worktree emits
    /// `HEAD <sha>` + `detached` with no `branch ` line; the old parser required a
    /// branch line and silently DROPPED those — a classic place for stranded work.
    /// Record them under a synthetic `detached@<short-sha>` label, reusing the existing
    /// Worktree.branch field (no model change).
    static func parseWorktrees(_ stdout: String, repoAbs: String) -> [(path: String, branch: String)] {
        var pairs: [(path: String, branch: String)] = []
        var curPath: String?, curBranch: String?, curHead: String?
        var curDetached = false
        func flush() {
            defer { curPath = nil; curBranch = nil; curHead = nil; curDetached = false }
            guard let p = curPath, p != repoAbs else { return }
            if let br = curBranch {
                pairs.append((p, br))
            } else if curDetached {
                let short = curHead.map { String($0.prefix(8)) } ?? "unknown"
                pairs.append((p, "detached@\(short)"))
            }
        }
        for ln in stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            if ln.hasPrefix("worktree ") { flush(); curPath = String(ln.dropFirst(9)) }
            else if ln.hasPrefix("HEAD ") { curHead = String(ln.dropFirst(5)) }
            else if ln.hasPrefix("branch ") { curBranch = String(ln.dropFirst(7)).replacingOccurrences(of: "refs/heads/", with: "") }
            else if ln == "detached" { curDetached = true }
            else if ln.isEmpty { flush() }
        }
        flush()
        return pairs
    }

    /// Worktree life classification from last-commit age + unpushed commit count.
    private static func classify(path: String, branch: String, now: Date) async -> Worktree {
        var lastRel = "—"
        var age: TimeInterval = 0
        if let iso = await line(["log", "-1", "--format=%cI"], path), let d = ISO8601DateFormatter().date(from: iso) {
            lastRel = RelTime.ago(d, now: now)
            age = now.timeIntervalSince(d)
        }
        // Commits that exist only on this branch (not on any remote) — a proxy for unlanded work.
        let commits = Int((await line(["rev-list", "--count", "HEAD", "--not", "--remotes"], path)) ?? "0") ?? 0
        let days = age / 86_400
        // Lifecycle is AGE-based ("created and forgotten"). The old logic gated
        // "abandoned" on `commits == 0`, so a worktree sitting on unpushed commits for
        // months could NEVER be abandoned — inverting the very case worth pruning.
        let state: WorktreeLife = days < 7 ? .active
            : days > 30 ? .abandoned
            : .stale
        return Worktree(branch: branch, created: lastRel, lastCommit: lastRel, commits: commits, state: state)
    }
}
