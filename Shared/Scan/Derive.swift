// Derive.swift — turn raw probe facts into gates, compliance, health, findings.

import Foundation

enum Derive {
    /// A VIBE.yaml that parsed but declares no enforceable policy — an empty doc or a
    /// bare `project:` stub. Detected from the already-built policy sections, so NO new
    /// Repo field is needed: the repo has a parseable VIBE.yaml yet not one
    /// architecture / quality_gates / workflow / security section is present. This is
    /// exactly the "reads as managed, governs nothing" laundering the app must surface.
    static func isPolicyStub(_ r: Repo) -> Bool {
        r.vibePresent && !r.vibeMalformed && PolicyProbe.declaresNoEnforceablePolicy(sections: r.policy)
    }

    static func gates(_ r: Repo) -> [Gate] {
        var g: [Gate] = []
        // The gate machinery itself: a policy'd repo with no Makefile can't run ANY
        // gate — surfacing that here is the fix for "gates green but there's no Makefile".
        let hasMake = r.makefile.count > 0
        g.append(Gate(name: "make", command: "make help", status: hasMake ? .ok : .fail,
                      detail: hasMake ? "\(r.makefile.count) targets" : "no Makefile — gates cannot run"))
        g.append(Gate(name: "lint", command: "make lint", status: .skip, detail: hasMake ? "advisory" : "no Makefile"))
        g.append(Gate(name: "typecheck", command: "make typecheck", status: .skip, detail: hasMake ? "run to check" : "no Makefile"))
        // Soft-limit files are IN POLICY (under hard) — never a gate warning. Files
        // matched by exclude_globs are out of scope entirely — not a god-file here.
        let arch: GateStatus = r.census.godFiles.isEmpty ? .ok : .fail
        let excluded = r.census.excludedGodFiles.count
        let exclNote = excluded > 0 ? " · \(excluded) excluded" : ""
        let archDetail = r.census.godFiles.isEmpty
            ? (r.census.softCount > 0 ? "\(r.census.softCount) over soft · in policy" : "within limits") + exclNote
            : "\(r.census.godFiles.count) god-file\(r.census.godFiles.count == 1 ? "" : "s")" + exclNote
        g.append(Gate(name: "architecture", command: "make check-architecture", status: arch, detail: archDetail))
        g.append(Gate(name: "tests", command: "make test", status: .skip, detail: "run to check"))
        if let cov = r.coverage, let floor = r.coverageFloor {
            g.append(Gate(name: "coverage", command: "floor \(floor)", status: cov >= floor ? .ok : .warn, detail: "\(cov)%"))
        }
        let skel: GateStatus = r.drift.behind == nil ? .ok : .warn
        g.append(Gate(name: "check-skeleton", command: "make check-skeleton", status: skel, detail: r.drift.behind ?? "current"))
        return g
    }

    // MARK: - Severity-weighted grading
    //
    // The old model was a flat OR: ANY one of a dozen conditions forced .danger, so
    // a repo with a single dirty file rated as horribly as one with committed
    // secrets — exactly the alert fatigue this app exists to avoid ("a red dot must
    // mean something"). Now every problem is a FACTOR with a weight; the factor
    // list is the visible "why this grade" breakdown, compliance is 100 + Σdelta,
    // and health falls out of the score — except CRITICAL factors (governance
    // fraud, conflicts, secrets, an unguarded live agent), which force danger
    // regardless of how clean everything else is.

    static func factors(_ r: Repo, signedRequired: Bool) -> [GradeFactor] {
        var f: [GradeFactor] = []
        func add(_ label: String, _ delta: Int, _ tone: VibeTone,
                 critical: Bool = false, _ detail: String) {
            f.append(GradeFactor(label: label, delta: delta, tone: tone,
                                 critical: critical, detail: detail))
        }

        // ---- critical: red no matter what else looks like ----
        switch r.management {
        case .unmanaged:
            add("unmanaged — no VIBE.yaml", -30, .danger, critical: true,
                "no policy governs this repo; agents have worked here with zero guardrails")
        case .partial:
            add("no Makefile — gates can't run", -12, .warn,
                "policy is declared but nothing can execute it")
        case .skeleton: break
        }
        if r.vibeMalformed {
            add("VIBE.yaml won't parse", -25, .danger, critical: true,
                "a policy file exists but silently enforces nothing")
        } else if isPolicyStub(r) {
            add("VIBE.yaml declares no enforceable policy", -25, .danger, critical: true,
                "parses as managed while governing nothing")
        }
        if !r.hygiene.conflictFiles.isEmpty {
            add("merge markers in \(r.hygiene.conflictFiles.count) file\(plural(r.hygiene.conflictFiles.count))",
                -30, .danger, critical: true, "live <<<<<<< markers — a green build is lying")
        }
        if !r.hygiene.secretFiles.isEmpty {
            add("\(r.hygiene.secretFiles.count) secret\(plural(r.hygiene.secretFiles.count)) tracked in git",
                -25, .danger, critical: true, ".env / keys committed — rotate and remove")
        }
        if r.agentActive && !r.hasActiveGuardrail() {
            add("live agent with no guardrail", -15, .danger, critical: true,
                "an agent is editing with no PreToolUse hook to intercept it")
        }

        // ---- proportional: scale with how bad it actually is ----
        if !r.worktree.clean {
            let n = max(r.worktree.unstaged, 1)
            var delta = n <= 2 ? -8 : n <= 10 ? -14 : -20
            var label = "\(n) uncommitted file\(plural(n))"
            if r.agentActive {
                delta /= 2   // a live session is dirty by definition — mid-work, not forgotten
                label += " (agent mid-work)"
            }
            add(label, delta, .warn, "uncommitted work on disk — gone if the tree is lost")
        }
        if r.worktree.unpushed > 0 {
            let n = r.worktree.unpushed
            add("\(n) unpushed commit\(plural(n))", n <= 2 ? -6 : -12, .warn,
                "committed but not on any remote — not really saved")
        }
        let gods = r.census.godFiles.count
        if gods > 0 {
            add("\(gods) god-file\(plural(gods))", -8 * min(gods, 3), gods >= 3 ? .danger : .warn,
                "over the hard line limit and in scope")
        }
        if signedRequired && !r.worktree.signed {
            add("unsigned commits (policy requires signing)", -15, .warn,
                "workflow.signed_commits_required is true; HEAD isn't signed")
        }
        let missingHooks = r.hooks.filter { $0.status == .missing }.count
        if missingHooks > 0 {
            add("\(missingHooks) hook\(plural(missingHooks)) point at missing scripts", -10, .warn,
                "wired in settings but not on disk — the gate runs nothing")
        }
        let stubHooks = r.hooks.filter { $0.status == .nothing }.count
        if stubHooks > 0 {
            add("\(stubHooks) stub hook\(plural(stubHooks))", -6, .warn,
                "installed but enforces nothing")
        }
        if r.docs.taskState.status == .fail {
            add("TASK_STATE.md over hard limit", -6, .warn,
                "\(r.docs.taskState.lines) lines — a dumping ground, not a plan")
        }
        if r.docs.changelog.status == .fail {
            add("CHANGELOG \(r.docs.changelog.behind) behind", -6, .warn,
                "release notes are fiction right now")
        }
        if !r.hygiene.trackedJunk.isEmpty {
            add("dependency dirs committed", -8, .warn,
                r.hygiene.trackedJunk.joined(separator: ", "))
        }
        let abandoned = r.worktrees.filter { $0.state == .abandoned }.count
        if abandoned > 0 {
            add("\(abandoned) abandoned worktree\(plural(abandoned))", -4 * min(abandoned, 2), .warn,
                "created and forgotten")
        }
        if let cov = r.coverage, let floor = r.coverageFloor, cov < floor {
            add("coverage \(cov)% under floor \(floor)%", -min(10, (floor - cov) / 2), .warn,
                "below the declared minimum")
        }
        if r.drift.behind != nil {
            add("skeleton \(r.drift.behind ?? "behind")", -5, .warn,
                "stamped \(r.drift.version ?? "—") vs fleet-latest \(r.drift.latest ?? "—")")
        }
        let failedMcp = r.mcp.filter { $0.status == .failed }.count
        if failedMcp > 0 {
            add("\(failedMcp) MCP server\(plural(failedMcp)) failing", -3, .warn, "recent calls failed")
        }
        if !r.hygiene.junkFiles.isEmpty {
            add("\(r.hygiene.junkFiles.count) stray backup/dupe file\(plural(r.hygiene.junkFiles.count))",
                -3, .neutral, "Finder/agent leftovers")
        }
        if r.hygiene.stashCount > 0 {
            add("\(r.hygiene.stashCount) forgotten stash\(r.hygiene.stashCount == 1 ? "" : "es")",
                -2, .neutral, "work parked in git stash")
        }
        return f
    }

    /// compliance = 100 + Σdelta, clamped. The factor list and the score can never
    /// disagree because one is computed from the other.
    static func score(_ factors: [GradeFactor]) -> Int {
        Swift.min(100, Swift.max(0, 100 + factors.reduce(0) { $0 + $1.delta }))
    }

    /// Health bands: a critical factor is always danger; otherwise the score
    /// decides — ≥95 ok, 60–94 warn, <60 danger. One dirty file (−8 → 92) reads
    /// warn with a visible reason; danger means compounding real problems.
    static func healthBand(_ factors: [GradeFactor]) -> Health {
        if factors.contains(where: \.critical) { return .danger }
        let s = score(factors)
        if s < 60 { return .danger }
        return s >= 95 ? .ok : .warn
    }

    static func compliance(_ r: Repo, signedRequired: Bool) -> Int {
        score(factors(r, signedRequired: signedRequired))
    }

    static func health(_ r: Repo, signedRequired: Bool) -> Health {
        healthBand(factors(r, signedRequired: signedRequired))
    }

    private static func plural(_ n: Int) -> String { n == 1 ? "" : "s" }

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
            add(.med, "Drift", "skeleton \(behind) behind",
                "Stamped \(r.drift.version ?? "—") vs fleet-latest \(r.drift.latest ?? "—"). Reconcile with the skeleton.", "reconcile")
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
        // A VIBE.yaml that PARSES but declares no enforceable policy launders a repo
        // into "managed" while governing nothing — the exact green-but-fake this app
        // exists to catch. Fires independently of management level (even .skeleton, when
        // a Makefile is present but the policy body is a stub).
        if isPolicyStub(r) {
            add(.high, "Managed", "VIBE.yaml declares no enforceable policy",
                "It parses — so the repo reads as managed — but with no architecture, quality_gates, workflow, or security section, not one rule is actually enforced.", "open file")
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
