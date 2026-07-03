// Derive.swift — turn raw probe facts into gates, compliance, health, findings.

import Foundation

enum Derive {
    static func gates(_ r: Repo) -> [Gate] {
        var g: [Gate] = []
        // The gate machinery itself: a policy'd repo with no Makefile can't run ANY
        // gate — surfacing that here is the fix for "gates green but there's no Makefile".
        let hasMake = r.makefile.count > 0
        g.append(Gate(name: "make", command: "make help", status: hasMake ? .ok : .fail,
                      detail: hasMake ? "\(r.makefile.count) targets" : "no Makefile — gates cannot run"))
        g.append(Gate(name: "lint", command: "make lint", status: .skip, detail: hasMake ? "advisory" : "no Makefile"))
        g.append(Gate(name: "typecheck", command: "make typecheck", status: .skip, detail: hasMake ? "run to check" : "no Makefile"))
        // Soft-limit files are IN POLICY (under hard) — never a gate warning.
        let arch: GateStatus = r.census.godFiles.isEmpty ? .ok : .fail
        let archDetail = r.census.godFiles.isEmpty
            ? (r.census.softCount > 0 ? "\(r.census.softCount) over soft · in policy" : "within limits")
            : "\(r.census.godFiles.count) god-file\(r.census.godFiles.count == 1 ? "" : "s")"
        g.append(Gate(name: "architecture", command: "make check-architecture", status: arch, detail: archDetail))
        g.append(Gate(name: "tests", command: "make test", status: .skip, detail: "run to check"))
        if let cov = r.coverage, let floor = r.coverageFloor {
            g.append(Gate(name: "coverage", command: "floor \(floor)", status: cov >= floor ? .ok : .warn, detail: "\(cov)%"))
        }
        let skel: GateStatus = r.drift.behind == nil ? .ok : .warn
        g.append(Gate(name: "check-skeleton", command: "make check-skeleton", status: skel, detail: r.drift.behind ?? "current"))
        return g
    }

    static func compliance(_ r: Repo, signedRequired: Bool) -> Int {
        var s = 100
        s -= r.census.godFiles.count * 8
        if !r.worktree.clean { s -= 12 }
        if r.worktree.unpushed > 0 { s -= 8 }
        if signedRequired && !r.worktree.signed { s -= 15 }
        if r.drift.behind != nil { s -= 6 }
        s -= hygienePenalty(r)
        switch r.docs.changelog.status { case .fail: s -= 5; default: break }
        switch r.docs.taskState.status { case .fail: s -= 6; default: break }
        if let cov = r.coverage, let floor = r.coverageFloor, cov < floor { s -= (floor - cov) / 2 }
        if r.agentActive && !r.hasActiveGuardrail() { s -= 10 }
        if r.mcp.contains(where: { $0.status == .failed }) { s -= 3 }
        return Swift.min(100, Swift.max(0, s))
    }

    /// Compliance penalty for management level + hygiene shenanigans.
    private static func hygienePenalty(_ r: Repo) -> Int {
        var p = 0
        switch r.management {
        case .unmanaged: p += 40
        case .partial: p += 12
        case .skeleton: break
        }
        if r.vibeMalformed { p += 20 }
        if !r.hygiene.conflictFiles.isEmpty { p += 25 }
        if !r.hygiene.secretFiles.isEmpty { p += 20 }
        if !r.hygiene.trackedJunk.isEmpty { p += 8 }
        if !r.hygiene.junkFiles.isEmpty { p += 3 }
        if r.hygiene.stashCount > 0 { p += 3 }
        return p
    }

    static func health(_ r: Repo, signedRequired: Bool) -> Health {
        // Dirty/unpushed trees and other "nasty surprises" are PROBLEMS, not warnings —
        // forgotten uncommitted work is the single biggest thing this app hunts for.
        let danger = !r.census.godFiles.isEmpty
            || !r.worktree.clean                                   // uncommitted changes
            || r.worktree.unpushed > 0                             // committed but never pushed
            || r.management == .unmanaged                          // no policy governs it
            || r.vibeMalformed                                     // VIBE.yaml on disk but won't parse
            || !r.hygiene.conflictFiles.isEmpty                    // merge markers left in files
            || !r.hygiene.secretFiles.isEmpty                      // secrets committed to git
            || !r.hygiene.trackedJunk.isEmpty                      // node_modules/DerivedData committed
            || (signedRequired && !r.worktree.signed)
            || (r.agentActive && !r.hasActiveGuardrail())
            || r.docs.changelog.status == .fail
            || r.docs.taskState.status == .fail
            || r.hooks.contains { $0.status == .missing }
        if danger { return .danger }
        // Amber = real-but-not-urgent: skeleton drift, incomplete scaffold, coverage,
        // flaky MCP, stray junk files, parked stashes. Soft-limit files are IN POLICY.
        let warn = r.drift.behind != nil
            || r.management == .partial
            || !r.hygiene.junkFiles.isEmpty
            || r.hygiene.stashCount > 0
            || (r.coverage.map { c in (r.coverageFloor.map { c < $0 } ?? false) } ?? false)
            || r.mcp.contains { $0.status == .failed || $0.broad }
        return warn ? .warn : .ok
    }

    static func surprises(_ r: Repo, signedRequired: Bool, hardLimit: Int) -> [Finding] {
        var f: [Finding] = []
        func add(_ sev: Severity, _ pass: String, _ what: String, _ why: String, _ fix: String?) {
            f.append(Finding(severity: sev, pass: pass, what: what, why: why, fix: fix))
        }
        // agent oversight
        if r.agentActive {
            if !r.hasActiveGuardrail() {
                add(.high, "Hooks", "\(r.agent?.tool ?? "agent") active with no PreToolUse guardrail",
                    "A live agent can run any Bash/Write with nothing to intercept it.", "install hooks")
            }
            if r.serena == nil {
                add(.low, "Agent", "no Serena project", "The agent greps blind — no symbolic index.", "init serena")
            }
        }
        // census
        for gf in r.census.godFiles {
            // Full path, not basename — two `page.tsx` in different dirs must not
            // collide into the same finding id (duplicate ForEach ids break the list).
            add(gf.lines > hardLimit + 60 ? .high : .med, "Census", "god-file: \(gf.path)",
                "\(gf.lines) lines — over hard \(hardLimit). Split it before review rubber-stamps it.", "split file")
        }
        // management, worktree hygiene & shenanigans (kept in a helper for clarity)
        f.append(contentsOf: hygieneFindings(r, signedRequired: signedRequired))
        // drift
        if let behind = r.drift.behind {
            add(.med, "Drift", "skeleton \(behind) behind", "\(r.drift.files) skeleton-owned files drifted.", "reconcile")
        }
        // docs — only HARD-limit bloat is a problem; soft is in policy.
        if r.docs.taskState.status == .fail {
            add(.high, "Docs", "TASK_STATE.md \(r.docs.taskState.lines) lines",
                "Agent state file is over the hard limit — a dumping ground, not a plan.", "open file")
        }
        if r.docs.changelog.status == .fail {
            add(.med, "Docs", "CHANGELOG.md \(r.docs.changelog.behind) behind",
                "Last entry \(r.docs.changelog.lastUpdated). Release notes are fiction right now.", "open file")
        }
        // hooks
        for h in r.hooks where h.status == .missing {
            add(.high, "Hooks", "\(h.event) hook points at a missing script",
                "\(h.command) is wired but not on disk — the gate runs nothing.", "install hooks")
        }
        for h in r.hooks where h.status == .nothing {
            add(.med, "Hooks", "\(h.event) guard enforces nothing",
                "\(h.command) is a stub that exits 0 — it looks installed but blocks nothing.", "install hooks")
        }
        // mcp
        for m in r.mcp where m.broad {
            add(.med, "MCP", "\(m.name) mounted broadly", "Read/write reaches beyond the repo via \(m.name). Scope it.", "scope server")
        }
        for m in r.mcp where m.status == .failed {
            add(.med, "MCP", "\(m.name) unreachable", "Recent \(m.name) calls failed — token expired or server down.", "reconnect")
        }
        // coverage
        if let cov = r.coverage, let floor = r.coverageFloor, cov < floor {
            add(.med, "Gates", "coverage \(cov)% / \(floor)", "Below floor.", "open tests")
        }
        // worktree sprawl
        let abandoned = r.worktrees.filter { $0.state == .abandoned }
        if !abandoned.isEmpty {
            add(.med, "Worktree", "\(abandoned.count) abandoned worktree\(abandoned.count == 1 ? "" : "s")",
                "Created and forgotten — prune before they rot.", "prune")
        }
        return f.sorted { $0.severity < $1.severity }
    }

    /// Management + worktree + "classic vibe-coding shenanigan" findings — the
    /// nasty surprises a policy file never tells you about.
    private static func hygieneFindings(_ r: Repo, signedRequired: Bool) -> [Finding] {
        var f: [Finding] = []
        func add(_ sev: Severity, _ pass: String, _ what: String, _ why: String, _ fix: String?) {
            f.append(Finding(severity: sev, pass: pass, what: what, why: why, fix: fix))
        }
        // management — the primary danger: repos slipping out of skeleton governance
        if r.management == .unmanaged {
            add(.high, "Managed", "UNMANAGED — no VIBE.yaml",
                "No policy file governs this repo. An agent has worked here with zero guardrails.", "open file")
        } else if r.vibeMalformed {
            add(.high, "Managed", "VIBE.yaml is unparseable",
                "A policy file exists but doesn't parse — silently, nothing is being enforced.", "open file")
        } else if r.management == .partial {
            add(.med, "Managed", "no Makefile — gates can't run",
                "Policy is declared but there's no Makefile, so not one gate can actually execute.", "open file")
        }
        // worktree — dirty/unpushed trees are PROBLEMS (the nasty-surprise headline)
        if signedRequired && !r.worktree.signed {
            add(.high, "Worktree", "unsigned commits", "signed_commits_required is true; commits are not signed.", "sign + push")
        }
        if !r.worktree.clean {
            let n = r.worktree.unstaged
            add(.high, "Worktree", "\(n) uncommitted change\(n == 1 ? "" : "s")",
                r.agentActive ? "A live agent is editing — this work vanishes if it walks away without committing."
                              : "Uncommitted work sitting on disk. The classic nasty surprise you come back to.", "commit…")
        }
        if r.worktree.unpushed > 0 {
            add(.high, "Worktree", "\(r.worktree.unpushed) commit\(r.worktree.unpushed == 1 ? "" : "s") not pushed",
                "Committed but never pushed — it isn't really saved until it's on the remote.", "sign + push")
        }
        // hygiene — classic vibe-coding shenanigans
        if let first = r.hygiene.conflictFiles.first {
            add(.high, "Hygiene", "merge markers in \(r.hygiene.conflictFiles.count) file\(r.hygiene.conflictFiles.count == 1 ? "" : "s")",
                "Live merge markers in \(first) — a green build is lying.", "open file")
        }
        if let first = r.hygiene.secretFiles.first {
            add(.high, "Hygiene", "secret tracked in git: \((first as NSString).lastPathComponent)",
                "\(r.hygiene.secretFiles.count) secret file(s) committed (.env / keys). Rotate + git-rm before this leaks.", "open file")
        }
        if !r.hygiene.trackedJunk.isEmpty {
            add(.med, "Hygiene", "\(r.hygiene.trackedJunk.joined(separator: ", ")) committed",
                "Dependency/build output is in git history — bloats the repo and rots fast.", "open file")
        }
        if let first = r.hygiene.junkFiles.first {
            add(.low, "Hygiene", "\(r.hygiene.junkFiles.count) stray backup/dupe file\(r.hygiene.junkFiles.count == 1 ? "" : "s")",
                "Cruft like \((first as NSString).lastPathComponent) — agent/Finder leftovers.", "open file")
        }
        if r.hygiene.stashCount > 0 {
            add(.low, "Worktree", "\(r.hygiene.stashCount) forgotten stash\(r.hygiene.stashCount == 1 ? "" : "es")",
                "Work parked in git stash and forgotten — pop it or drop it before it's lost.", "open console")
        }
        return f
    }
}
