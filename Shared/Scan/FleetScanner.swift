// FleetScanner.swift — walk the roots, probe every repo, assemble the Fleet.

import Foundation

struct FleetScanner: Sendable {
    var roots: [String]

    init(roots: [String]? = nil) {
        self.roots = roots ?? [(NSHomeDirectory() as NSString).appendingPathComponent("Code")]
    }

    private static var fm: FileManager { .default }
    private var home: String { NSHomeDirectory() }

    func scan(now: Date = Date(), appBuild: AppBuild, host: String) async -> Fleet {
        let start = Date()
        let candidates = discover()

        // Determine managed repos with a CHEAP marker check BEFORE probing.
        // Fully probing every git repo under ~/Code (191+) would spawn thousands
        // of git/lsof subprocesses and lock the machine up — so we only probe
        // managed (agentic) repos plus their workspace ancestors.
        let managedPaths = candidates.filter { isManagedMarker($0) }
        var keepPaths = Set(managedPaths)
        for m in managedPaths {
            for c in candidates where c != m && m.hasPrefix(c + "/") { keepPaths.insert(c) }
        }

        // Probe the kept set with BOUNDED concurrency. Each probe spawns a fistful
        // of git/lsof subprocesses; firing all repos at once spawns thousands and
        // locks the machine (learned the hard way). Cap in-flight probes instead.
        var repos: [Repo] = await withTaskGroup(of: Repo.self) { group in
            let limit = 8
            var it = keepPaths.makeIterator()
            var started = 0
            while started < limit, let abs = it.next() { group.addTask { await probeRepo(abs, now: now) }; started += 1 }
            var acc: [Repo] = []
            for await r in group {
                acc.append(r)
                if let abs = it.next() { group.addTask { await probeRepo(abs, now: now) } }
            }
            return acc
        }

        // Nesting: parent = longest kept path that is a strict path prefix.
        var idByAbs: [String: String] = [:]
        for r in repos { idByAbs[r.absolutePath] = r.id }
        for i in repos.indices {
            let mine = repos[i].absolutePath
            let parent = keepPaths.filter { $0 != mine && mine.hasPrefix($0 + "/") }.max { $0.count < $1.count }
            repos[i].parentId = parent.flatMap { idByAbs[$0] }
        }
        var childrenOf: [String: [String]] = [:]
        for r in repos { if let p = r.parentId { childrenOf[p, default: []].append(r.id) } }

        // Owner filter: keep only repos whose origin I own (github acme/acme-labs/widgets
        // or gitea git.example.com), plus the workspace ancestors of owned repos.
        var owned = Set(repos.filter { isOwned($0) }.map { $0.id })
        var grew = true
        while grew {
            grew = false
            for r in repos where owned.contains(r.id) {
                if let p = r.parentId, !owned.contains(p) { owned.insert(p); grew = true }
            }
        }
        if !owned.isEmpty {
            repos = repos.filter { owned.contains($0.id) }
            childrenOf = [:]
            for r in repos { if let p = r.parentId { childrenOf[p, default: []].append(r.id) } }
        }

        // Live agent sessions → attach to the deepest matching repo, with REAL
        // measured diff/mtime telemetry (never constants).
        await attachLiveSessions(&repos, now: now)

        // Mark workspaces + derive health/compliance/gates/surprises.
        for i in repos.indices {
            let kids = childrenOf[repos[i].id] ?? []
            let wsPath = (repos[i].absolutePath as NSString).appendingPathComponent("WORKSPACE.yaml")
            if !kids.isEmpty || FleetScanner.fm.fileExists(atPath: wsPath) {
                repos[i].kind = .workspace
                repos[i].children = kids
            }
        }
        FleetScanner.grade(&repos)

        // Scanner + activity + assembly. `lastSweepAt` is the REAL scan time (renders
        // via RelTime.ago so it ages between manual scans); `swept` is the measured
        // wall-clock duration. No online/watching/sweep fabrication.
        let elapsedMs = String(format: "%.1f ms", Date().timeIntervalSince(start) * 1000)
        let leaves = repos.filter { $0.kind != .workspace }
        let scanner = ScannerState(host: host, root: displayPath(roots.first ?? "~/Code"),
                                   lastSweepAt: now, swept: elapsedMs,
                                   lastSweep: RelTime.ago(now, now: now))
        var activity: [ActivityEntry] = []
        var seq = 0
        activity.append(ActivityEntry(t: "now", kind: "scan", repo: "—",
            msg: "swept \(scanner.root) · \(leaves.count) repos · \(repos.count - leaves.count) workspaces · \(elapsedMs)",
            tone: .ok, seq: seq)); seq += 1
        for r in repos where r.agentActive {
            activity.append(ActivityEntry(t: r.agent?.elapsed ?? "now", kind: "agent", repo: r.name,
                msg: "\(r.agent?.tool ?? "agent") · live session on \(r.agent?.branch ?? "main")",
                tone: r.health == .danger ? .danger : .warn, seq: seq)); seq += 1
        }

        return Fleet.assemble(scanner: scanner, appBuild: appBuild, repos: repos,
                              activity: activity, autopilot: Reference.defaultAutopilot(repoCount: leaves.count),
                              catalog: Reference.skillCatalog)
    }

    /// Attach live agent sessions to the deepest matching repo, with REAL measured
    /// diff/mtime telemetry (never constants).
    private func attachLiveSessions(_ repos: inout [Repo], now: Date) async {
        let sessions = await AgentProbe.sessions()
        for s in sessions {
            guard let idx = repos.indices
                .filter({ s.cwd == repos[$0].absolutePath || s.cwd.hasPrefix(repos[$0].absolutePath + "/") })
                .max(by: { repos[$0].absolutePath.count < repos[$1].absolutePath.count }) else { continue }
            let work = await AgentProbe.workStat(cwd: repos[idx].absolutePath, now: now)
            repos[idx].agent = AgentInfo(
                active: true, tool: s.tool, branch: repos[idx].build.branch, elapsed: s.elapsed,
                filesTouched: work.filesTouched,
                linesAdded: work.measured ? work.linesAdded : nil,
                linesRemoved: work.measured ? work.linesRemoved : nil,
                lastActivity: work.lastWrite.map { RelTime.ago($0, now: now) } ?? "—",
                note: agentNote(work, clean: repos[idx].worktree.clean))
        }
    }

    /// Honest one-line session summary built from the measured diff — no constants.
    private func agentNote(_ work: AgentProbe.WorkStat, clean: Bool) -> String {
        if work.filesTouched > 0 {
            return "\(work.filesTouched) file\(work.filesTouched == 1 ? "" : "s") changed since last commit"
        }
        return clean ? "live session · working tree clean" : "untracked changes in the working tree"
    }

    /// Derive gates/compliance/health/surprises for every repo, in TWO passes so
    /// workspace rollups read freshly-graded children (a single pass rolled up a
    /// stale pre-grade snapshot, so every workspace always showed ok/100 regardless
    /// of how broken its children were — hiding the exact surprises this app exists for).
    private static func grade(_ repos: inout [Repo]) {
        let latestSkeleton = SkeletonProbe.latest(repos.compactMap { $0.drift.version })

        // PASS 1 — grade every leaf repo.
        for i in repos.indices where repos[i].kind != .workspace {
            let signedReq = repos[i].signedRequired
            repos[i].drift = SkeletonProbe.drift(version: repos[i].drift.version, latest: latestSkeleton)
            repos[i].gates = Derive.gates(repos[i])
            repos[i].compliance = Derive.compliance(repos[i], signedRequired: signedReq)
            repos[i].health = Derive.health(repos[i], signedRequired: signedReq)
            repos[i].surprises = Derive.surprises(repos[i], signedRequired: signedReq, hardLimit: 400)
            repos[i].checked = "just now"
        }

        // PASS 2 — roll workspaces up from LIVE (already-graded) children, deepest
        // first so a nested workspace is rolled up before its parent reads it.
        var idxById: [String: Int] = [:]
        for i in repos.indices { idxById[repos[i].id] = i }
        func depth(_ id: String) -> Int {
            var d = 0, cur: Int? = idxById[id]
            while let i = cur, let p = repos[i].parentId, let pi = idxById[p], d < 64 { d += 1; cur = pi }
            return d
        }
        for i in repos.indices.filter({ repos[$0].kind == .workspace })
            .sorted(by: { depth(repos[$0].id) > depth(repos[$1].id) }) {
            let kids = repos[i].children.compactMap { idxById[$0] }
            repos[i].health = kids.map { repos[$0].health }.max() ?? .ok
            repos[i].compliance = kids.isEmpty ? 100 : kids.reduce(0) { $0 + repos[$1].compliance } / kids.count
            repos[i].desc = "Workspace · \(kids.count) managed repo\(kids.count == 1 ? "" : "s")"
            repos[i].stack = "workspace"
            repos[i].checked = "just now"
        }
    }

    // ---- discovery ----
    private func discover() -> [String] {
        var out: Set<String> = []
        for root in roots where isDir(root) { walk(root, depth: 0, into: &out) }
        return out.sorted()
    }
    private func walk(_ dir: String, depth: Int, into out: inout Set<String>) {
        guard depth <= 3, let items = try? FleetScanner.fm.contentsOfDirectory(atPath: dir) else { return }
        for name in items where !FileProbes.skipDirs.contains(name) && !name.hasPrefix(".") {
            let abs = (dir as NSString).appendingPathComponent(name)
            guard isDir(abs) else { continue }
            if isCandidate(abs) { out.insert(abs); walk(abs, depth: depth + 1, into: &out) }
            else { walk(abs, depth: depth + 1, into: &out) }
        }
    }
    private func isCandidate(_ abs: String) -> Bool {
        ["/.git", "/VIBE.yaml", "/WORKSPACE.yaml"].contains { FleetScanner.fm.fileExists(atPath: abs + $0) }
    }
    /// Cheap check (no probing) for whether a repo is agentic/managed.
    private func isManagedMarker(_ abs: String) -> Bool {
        ["/VIBE.yaml", "/AGENTS.md", "/.claude", "/WORKSPACE.yaml"].contains { FleetScanner.fm.fileExists(atPath: abs + $0) }
    }
    /// Whether a repo's origin belongs to me (github acme/acme-labs/widgets or gitea git.example.com).
    private func isOwned(_ r: Repo) -> Bool {
        let owners = ["acme", "acme-labs", "widgets"]
        for rem in r.scm.remotes {
            let u = rem.url.lowercased()
            if u.contains("git.example.com") { return true }
            if u.contains("github.com") {
                for o in owners where u.contains("github.com:\(o)/") || u.contains("github.com/\(o)/") { return true }
            }
        }
        return false
    }
    private func isDir(_ path: String) -> Bool {
        var d: ObjCBool = false
        return FleetScanner.fm.fileExists(atPath: path, isDirectory: &d) && d.boolValue
    }
    private func displayPath(_ abs: String) -> String {
        abs.hasPrefix(home) ? "~" + abs.dropFirst(home.count) : abs
    }
    private func idFor(_ abs: String) -> String {
        displayPath(abs).replacingOccurrences(of: "~/", with: "").replacingOccurrences(of: "/", with: "·")
    }

    // ---- per-repo probe ----
    private func probeRepo(_ abs: String, now: Date) async -> Repo {
        let vibe = PolicyProbe.load(abs)
        let idn = FileProbes.identity(abs, vibe: vibe)
        let git = await GitProbe.probe(abs, now: now)
        let (soft, hard) = limits(vibe)
        let walk = FileProbes.walk(abs, soft: soft, hard: hard,
                                   ansible: idn.stack.contains("ansible"), excludes: excludeGlobs(vibe))
        let census = walk.census
        let docs = await FileProbes.docs(abs, now: now)

        var r = Repo(id: idFor(abs), name: (abs as NSString).lastPathComponent, path: displayPath(abs), absolutePath: abs)
        r.stack = idn.stack; r.framework = idn.framework; r.pm = idn.pm; r.lifecycle = idn.lifecycle
        r.desc = (vibe?["project"] as? [String: Any])?["description"] as? String ?? Brand.langOf(idn.stack).label
        r.worktree = git.worktree
        r.worktrees = git.worktrees
        r.serena = FileProbes.serena(abs, now: now)
        r.hooks = HooksMcpProbe.hooks(abs)
        r.mcp = HooksMcpProbe.mcp(abs)
        r.census = census
        r.docs = docs
        r.coverageFloor = coverageFloor(vibe)
        r.makefile = DeriveIntegrations.makefile(abs)
        r.scm = DeriveIntegrations.scm(branch: git.branch, remotes: git.remotes,
                                       worktree: git.worktree, signedRequired: signedRequired(vibe))
        r.ci = DeriveIntegrations.ci(abs, stack: idn.stack)
        r.containers = DeriveIntegrations.containers(abs)
        r.skills = DeriveIntegrations.skills(abs, vibe: vibe, stack: idn.stack)
        r.build = DeriveIntegrations.build(abs, git: git)
        r.policy = vibe.map { PolicyProbe.sections($0) } ?? []
        r.hygiene = await HygieneProbe.probe(abs, conflicts: walk.conflicts, junk: walk.junk)
        r.drift.version = SkeletonProbe.version(abs)
        let vibePresent = FileProbes.exists(FileProbes.join(abs, "VIBE.yaml"))
        r.vibePresent = vibePresent
        r.vibeMalformed = vibePresent && vibe == nil   // on disk but Yams couldn't parse it
        r.managed = vibePresent
            || FileProbes.exists(FileProbes.join(abs, "AGENTS.md"))
            || FileProbes.exists(FileProbes.join(abs, ".claude"))
        r.management = classifyManagement(vibePresent: vibePresent, parsed: vibe != nil, makefileCount: r.makefile.count)
        r.signedRequired = signedRequired(vibe)
        r.checkedAt = now          // real probe time — RepoTabsCore renders RelTime.ago so it ages
        return r
    }

    /// How completely the skeleton governs a repo (see ManagementLevel).
    private func classifyManagement(vibePresent: Bool, parsed: Bool, makefileCount: Int) -> ManagementLevel {
        guard vibePresent else { return .unmanaged }   // an agent has been here; no policy governs it
        guard parsed else { return .partial }          // VIBE.yaml on disk but unparseable — broken policy
        return makefileCount > 0 ? .skeleton : .partial // policy without a Makefile can't run its gates
    }

    private func limits(_ vibe: [String: Any]?) -> (Int, Int) {
        guard let arch = vibe?["architecture"] as? [String: Any],
              let mx = arch["max_lines_per_file"] as? [String: Any] else { return (250, 400) }
        return (mx["soft"] as? Int ?? 250, mx["hard"] as? Int ?? 400)
    }
    /// The repo's `architecture.exclude_globs` — files matching these are out of
    /// scope for the god-file census (shown for visibility, never graded).
    private func excludeGlobs(_ vibe: [String: Any]?) -> [String] {
        guard let arch = vibe?["architecture"] as? [String: Any],
              let globs = arch["exclude_globs"] as? [String] else { return [] }
        return globs.filter { !$0.isEmpty }
    }
    private func coverageFloor(_ vibe: [String: Any]?) -> Int? {
        ((vibe?["quality_gates"] as? [String: Any])?["coverage"] as? [String: Any])?["minimum_percentage"] as? Int
    }
    private func signedRequired(_ vibe: [String: Any]?) -> Bool {
        (vibe?["workflow"] as? [String: Any])?["signed_commits_required"] as? Bool ?? false
    }
}
