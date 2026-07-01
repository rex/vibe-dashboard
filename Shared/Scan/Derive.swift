// Derive.swift — turn raw probe facts into gates, compliance, health, findings.

import Foundation

enum Derive {
    static func gates(_ r: Repo) -> [Gate] {
        var g: [Gate] = []
        g.append(Gate(name: "lint", command: "make lint", status: .skip, detail: "advisory"))
        g.append(Gate(name: "typecheck", command: "make typecheck", status: .skip, detail: "run to check"))
        let arch: GateStatus = r.census.godFiles.isEmpty ? (r.census.softCount > 0 ? .warn : .ok) : .fail
        let archDetail = r.census.godFiles.isEmpty
            ? (r.census.softCount > 0 ? "\(r.census.softCount) over soft" : "within limits")
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
        if !r.worktree.clean { s -= 5 }
        if r.worktree.unpushed > 0 { s -= 3 }
        if signedRequired && !r.worktree.signed { s -= 15 }
        if r.drift.behind != nil { s -= 6 }
        switch r.docs.changelog.status { case .fail: s -= 5; case .warn: s -= 3; default: break }
        switch r.docs.taskState.status { case .fail: s -= 6; case .warn: s -= 3; default: break }
        if let cov = r.coverage, let floor = r.coverageFloor, cov < floor { s -= (floor - cov) / 2 }
        if r.agentActive && !r.hasActiveGuardrail() { s -= 10 }
        if r.mcp.contains(where: { $0.status == .failed }) { s -= 3 }
        return Swift.min(100, Swift.max(30, s))
    }

    static func health(_ r: Repo, signedRequired: Bool) -> Health {
        let danger = !r.census.godFiles.isEmpty
            || (signedRequired && !r.worktree.signed)
            || (r.agentActive && !r.hasActiveGuardrail())
            || r.docs.changelog.status == .fail
            || r.docs.taskState.status == .fail
            || r.hooks.contains { $0.status == .missing }
        if danger { return .danger }
        let warn = !r.worktree.clean || r.drift.behind != nil || r.census.softCount > 0
            || r.docs.changelog.status == .warn || r.docs.taskState.status == .warn
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
            add(gf.lines > hardLimit + 60 ? .high : .med, "Census", "god-file: \((gf.path as NSString).lastPathComponent)",
                "\(gf.lines) lines — over hard \(hardLimit). Split it before review rubber-stamps it.", "split file")
        }
        // worktree
        if signedRequired && !r.worktree.signed {
            add(.high, "Worktree", "unsigned commits", "signed_commits_required is true; commits are not signed.", "sign + push")
        }
        if !r.worktree.clean {
            add(r.worktree.unstaged > 5 ? .med : .low, "Worktree", "\(r.worktree.unstaged) unstaged change\(r.worktree.unstaged == 1 ? "" : "s")",
                "Dirty tree; clean_worktree_required_on_completion is true.", "commit…")
        }
        // drift
        if let behind = r.drift.behind {
            add(.med, "Drift", "skeleton \(behind) behind", "\(r.drift.files) skeleton-owned files drifted.", "reconcile")
        }
        // docs
        if r.docs.taskState.status != .ok {
            add(r.docs.taskState.status == .fail ? .high : .low, "Docs", "TASK_STATE.md \(r.docs.taskState.lines) lines",
                "Agent state file is oversized — it's a dumping ground, not a plan.", "open file")
        }
        if r.docs.changelog.status != .ok {
            add(r.docs.changelog.status == .fail ? .med : .low, "Docs", "CHANGELOG.md \(r.docs.changelog.behind) behind",
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
            add(.med, "MCP", "\(m.name) mounted broadly", "The agent has read/write beyond the repo via \(m.name). Scope it.", "scope server")
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
}
