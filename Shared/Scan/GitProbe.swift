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
        // The repo must OWN the git it found. A candidate dir with a VIBE.yaml but
        // no .git of its own (e.g. agentic-skeleton/templates/greenfield inside
        // agent-skills) makes every git command walk UP to the enclosing repo —
        // attributing the PARENT's branch/dirty state/worktrees to a phantom repo
        // and duplicating its worktrees across the fleet (the ForEach id collision
        // Pierce hit). Toplevel ≠ the probed path ⇒ honestly not a git repo itself.
        let top = await line(["rev-parse", "--show-toplevel"], abs)
        guard let top, (top as NSString).resolvingSymlinksInPath
                == (abs as NSString).resolvingSymlinksInPath else { return f }
        f.isRepo = true

        f.branch = await line(["rev-parse", "--abbrev-ref", "HEAD"], abs) ?? "main"
        f.commitShort = await line(["rev-parse", "--short", "HEAD"], abs) ?? "-------"
        if let iso = await line(["log", "-1", "--format=%cI"], abs), let d = RelTime.iso.date(from: iso) {
            f.commitDateISO = iso
            f.commitDateRel = RelTime.ago(d, now: now)
        }

        // Worktree cleanliness. Keep the RAW porcelain lines (capped so a pathological
        // tree can't balloon the model/hash) alongside the count — the Overview renders
        // the real changed-file list, grouped, not just a number.
        let status = await ProcessRunner.git(["status", "--porcelain"], cwd: abs)
        let dirtyLines = status.stdout.split(separator: "\n").filter { !$0.isEmpty }
        f.worktree.unstaged = dirtyLines.count
        f.worktree.clean = dirtyLines.isEmpty
        f.worktree.statusLines = dirtyLines.prefix(500).map(String.init)

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

        // Is HEAD signed? Read the raw commit object and look for a `gpgsig` header — this
        // detects a signature's PRESENCE without invoking gpg to VERIFY it. `git log
        // --format=%G?` verifies, which — now that the PATH fix makes gpg reachable —
        // spawns gpg per commit and HANGS the whole fleet scan on a keyserver/agent lookup
        // for any foreign signing key (repos carry bot/other-author commits). Presence is
        // the right signal for "does this repo sign" and it's instant, gpg-free, unblockable.
        // No commit yet (cat-file fails) ⇒ keep the default (true): nothing to be unsigned.
        let commitObj = await ProcessRunner.git(["cat-file", "commit", "HEAD"], cwd: abs)
        if commitObj.ok { f.worktree.signed = Self.isSignedCommitObject(commitObj.stdout) }

        f.remotes = await remotes(abs, branch: f.branch)
        f.worktrees = await worktrees(abs, now: now)
        return f
    }

    private static func line(_ args: [String], _ abs: String) async -> String? {
        let r = await ProcessRunner.git(args, cwd: abs)
        guard r.ok else { return nil }
        let s = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// A commit is signed iff its raw object carries a `gpgsig` (or `gpgsig-sha256`)
    /// header — in the HEADER block, before the blank line that starts the message, so a
    /// message that merely mentions "gpgsig" doesn't false-positive. Pure + testable: no
    /// gpg is ever run, so this can neither verify nor block. Presence, not validity, is
    /// what "is this repo signing" needs (and it fixed the false-"unsigned" cry-wolf too).
    static func isSignedCommitObject(_ raw: String) -> Bool {
        let headers = raw.components(separatedBy: "\n\n").first ?? raw
        return headers.split(separator: "\n").contains {
            $0.hasPrefix("gpgsig ") || $0.hasPrefix("gpgsig-sha256 ")
        }
    }

    /// All remotes with a PER-REMOTE ahead count. Captures BOTH (fetch) and (push)
    /// URLs — a `set-url --push` mirror can push to an owned host while fetching from a
    /// foreign one, and looking only at (fetch) would miss that owned mirror. Each
    /// remote's `ahead` is measured against ITS OWN tracking refs (not origin's number
    /// copied across then zeroed elsewhere), so an un-mirrored remote shows the real
    /// backlog it is missing — which matters under a "push to ALL remotes" rule.
    private static func remotes(_ abs: String, branch: String) async -> [Remote] {
        let r = await ProcessRunner.git(["remote", "-v"], cwd: abs)
        var fetchURL: [String: String] = [:], pushURL: [String: String] = [:]
        var order: [String] = []
        for ln in r.stdout.split(separator: "\n") {
            let parts = ln.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let name = parts[0], url = parts[1]
            if !order.contains(name) { order.append(name) }
            if ln.contains("(push)") { pushURL[name] = url }
            else if ln.contains("(fetch)") { fetchURL[name] = url }
        }
        var out: [Remote] = []
        for name in order {
            let display = displayURL(fetch: fetchURL[name], push: pushURL[name])
            guard !display.isEmpty else { continue }
            let ahead = await aheadOf(remote: name, branch: branch, abs: abs)
            out.append(Remote(name: name, host: hostClass(display), url: display,
                              ahead: ahead, behind: 0,
                              primary: name == "origin", mirror: name != "origin"))
        }
        return out.sorted { $0.primary && !$1.primary }
    }

    /// Which URL represents a remote: the fetch URL by default, but the push URL when
    /// fetch is NOT owned and push IS (a `set-url --push` owned mirror) so the owner
    /// filter and UI both reflect the owned host. Pure + testable.
    static func displayURL(fetch: String?, push: String?, scope: OwnerScope = .current) -> String {
        if let f = fetch, let p = push, f != p,
           !isOwnedRemoteURL(f, scope: scope), isOwnedRemoteURL(p, scope: scope) { return p }
        return fetch ?? push ?? ""
    }

    /// Commits on HEAD not yet on `remote`. Uses `<remote>/<branch>..HEAD` when that
    /// tracking ref exists; otherwise falls back to "commits on no ref of <remote>" so a
    /// branch never pushed to this remote still reports an honest backlog rather than 0.
    private static func aheadOf(remote: String, branch: String, abs: String) async -> Int {
        if let n = await line(["rev-list", "--count", "\(remote)/\(branch)..HEAD"], abs), let c = Int(n) { return c }
        if let n = await line(["rev-list", "--count", "HEAD", "--not", "--remotes=\(remote)"], abs), let c = Int(n) { return c }
        return 0
    }

    static func hostClass(_ url: String) -> String {
        url.contains("github.com") ? "github"
            : (url.contains("gitea") || url.contains("git.") ? "gitea" : "other")
    }

    /// (host, owner) parsed from a git remote URL in scp, ssh://, https://, or git://
    /// form — pure + testable. All of these yield host "github.com", owner "acme":
    ///   `git@github.com:acme/x.git`  ·  `ssh://git@github.com/acme/x`  ·  `https://github.com/acme/x.git`
    /// Returns nil when no host can be recovered.
    static func remoteIdentity(_ url: String) -> (host: String, owner: String)? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let hadScheme = s.contains("://")
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }            // drop scheme://
        if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }  // drop user@
        // scp form is `host:owner/repo` (no scheme) — turn that first ':' into '/'.
        // With a scheme, a ':' after the host is a port and is stripped below.
        if !hadScheme, let colon = s.firstIndex(of: ":") { s.replaceSubrange(colon...colon, with: "/") }
        let parts = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard var host = parts.first, !host.isEmpty else { return nil }
        if hadScheme, let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }   // strip :port
        let owner = parts.count >= 2 ? parts[1] : ""
        let cleanOwner = owner.hasSuffix(".git") ? String(owner.dropLast(4)) : owner
        return (host.lowercased(), cleanOwner.lowercased())
    }

    /// Whether a remote URL points at a host/owner in the configured `OwnerScope`
    /// — your own git hosts and/or GitHub orgs (see `OwnerScope`). Form-agnostic
    /// (scp ≡ ssh ≡ https). Pure + testable. With an empty scope (the default),
    /// nothing matches — the fleet keeps managed repos by default instead.
    static func isOwnedRemoteURL(_ url: String, scope: OwnerScope = .current) -> Bool {
        guard let id = remoteIdentity(url) else { return false }
        if scope.hosts.contains(where: { id.host.contains($0) }) { return true }
        if id.host.contains("github.com") { return scope.githubOwners.contains(id.owner) }
        return false
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
        if let iso = await line(["log", "-1", "--format=%cI"], path), let d = RelTime.iso.date(from: iso) {
            lastRel = RelTime.ago(d, now: now)
            age = now.timeIntervalSince(d)
        }
        // Commits that exist only on this branch (not on any remote) — a proxy for unlanded work.
        let commits = Int((await line(["rev-list", "--count", "HEAD", "--not", "--remotes"], path)) ?? "0") ?? 0
        // Uncommitted edits INSIDE the linked worktree — stranded work the age-based
        // lifecycle alone can't see (a worktree edited yesterday but never committed
        // still ages toward "abandoned"). Measured, not inferred.
        let dirty = await isDirty(path)
        let days = age / 86_400
        // Lifecycle is AGE-based ("created and forgotten"). The old logic gated
        // "abandoned" on `commits == 0`, so a worktree sitting on unpushed commits for
        // months could NEVER be abandoned — inverting the very case worth pruning.
        let state: WorktreeLife = days < 7 ? .active
            : days > 30 ? .abandoned
            : .stale
        return Worktree(path: path, branch: branch, created: lastRel, lastCommit: lastRel,
                        commits: commits, state: state, dirty: dirty)
    }

    /// Does `git status --porcelain` report any change in the worktree at `path`?
    private static func isDirty(_ path: String) async -> Bool {
        let s = await ProcessRunner.git(["status", "--porcelain"], cwd: path)
        guard s.ok else { return false }
        return s.stdout.split(separator: "\n").contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
