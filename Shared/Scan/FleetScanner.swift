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

        // Owner filter (optional; off by default — see OwnerScope): keep only repos
        // whose origin matches your configured git hosts / GitHub orgs, plus the
        // workspace ancestors of owned repos. An empty scope keeps every managed repo.
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
                                   rootsAbs: roots,
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
    /// diff/mtime telemetry (never constants). Shares AgentInfo.live with the store's
    /// background refresh so a full scan and a 2-minute refresh build identical sessions.
    private func attachLiveSessions(_ repos: inout [Repo], now: Date) async {
        let sessions = await AgentProbe.sessions(now: now)
        var target: [Int: [AgentInfo]] = [:]
        for s in sessions {
            let sessionCwd = AgentTranscriptProbe.normalizedPath(s.cwd)
            guard let idx = repos.indices
                .filter({
                    let repoPath = AgentTranscriptProbe.normalizedPath(repos[$0].absolutePath)
                    return sessionCwd == repoPath || sessionCwd.hasPrefix(repoPath + "/")
                })
                .max(by: { repos[$0].absolutePath.count < repos[$1].absolutePath.count }) else { continue }
            let work = await AgentProbe.workStat(cwd: repos[idx].absolutePath, now: now)
            target[idx, default: []].append(AgentInfo.live(session: s, work: work,
                                                           clean: repos[idx].worktree.clean,
                                                           branch: repos[idx].build.branch, now: now))
        }
        for i in repos.indices {
            let agents = (target[i] ?? []).sorted {
                ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast)
            }
            repos[i].agents = agents
            repos[i].agent = agents.first
        }
    }

    /// Derive gates/compliance/health/surprises for every repo, in TWO passes so
    /// workspace rollups read freshly-graded children (a single pass rolled up a
    /// stale pre-grade snapshot, so every workspace always showed ok/100 regardless
    /// of how broken its children were — hiding the exact surprises this app exists for).
    private static func grade(_ repos: inout [Repo]) {
        let latestSkeleton = SkeletonProbe.latest(repos.compactMap { $0.drift.version })
        let waivedIDs = WaiverLedger.activeIDsFromDefaults()

        // PASS 1 — grade every leaf repo. Factors are computed ONCE and stored —
        // they ARE the grade (score + health derive from them) and the UI's
        // "why this grade" breakdown reads the same list, so they can't disagree.
        for i in repos.indices where repos[i].kind != .workspace {
            gradeRepo(&repos[i], latest: latestSkeleton, waivedIDs: waivedIDs)
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

    /// Grade ONE repo from its already-probed facts: drift vs fleet-latest, gates,
    /// waiver-aware factors → score/health, and surprises split into open vs waived
    /// (a waived finding leaves the feed AND the grade, and comes back when its
    /// waiver expires). Shared by the full sweep, the targeted rescan, and the
    /// instant regrade that runs when a waiver is recorded or lifted.
    static func gradeRepo(_ r: inout Repo, latest: String?, waivedIDs: Set<String>) {
        let signedReq = r.signedRequired
        r.drift = SkeletonProbe.drift(version: r.drift.version, latest: latest)
        r.gates = Derive.gates(r)
        let all = Derive.surprises(r, signedRequired: signedReq, hardLimit: 400)
        let waived = all.filter { waivedIDs.contains("\(r.id)·\($0.pass)·\($0.what)") }
        r.surprises = all.filter { !waivedIDs.contains("\(r.id)·\($0.pass)·\($0.what)") }
        r.waivedSurprises = waived
        let factors = Derive.factors(r, signedRequired: signedReq,
                                     waived: Derive.WaivedFacts.parse(waived))
        r.gradeFactors = factors
        r.compliance = Derive.score(factors)
        r.health = Derive.healthBand(factors)
    }

    // ---- discovery ----
    private func discover() -> [String] {
        var out: Set<String> = []
        for root in roots where isDir(root) { walk(root, depth: 0, into: &out) }
        return out.sorted()
    }
    private func walk(_ dir: String, depth: Int, into out: inout Set<String>) {
        // Cap depth so a pathological tree can't runaway, but keep it deep enough that a
        // managed repo nested under ecosystem/workspace/... (depth 4+) is still found —
        // the old cap of 3 made those invisible. `skipDirs` already prunes the heavy
        // vendored trees (node_modules, .build, DerivedData, vendor, …), so the extra
        // levels only descend real project dirs.
        guard depth <= 6, let items = try? FleetScanner.fm.contentsOfDirectory(atPath: dir) else { return }
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
    /// Whether a repo counts as "mine". A remote matching the configured `OwnerScope`
    /// (in ANY url form — scp, ssh, https) wins outright. A MANAGED repo with no
    /// matching remote is OWNED BY DEFAULT: it already passed the VIBE.yaml/marker
    /// filter, so it's a repo configured locally, and dropping it — an scp/ssh remote a
    /// literal-substring match would miss, or no remote at all — would make your own
    /// repo invisible to the tool meant to oversee it.
    private func isOwned(_ r: Repo) -> Bool { Self.isOwnedRepo(remotes: r.scm.remotes, managed: r.managed) }

    /// Pure ownership decision — testable without constructing a full `Repo`.
    static func isOwnedRepo(remotes: [Remote], managed: Bool, scope: OwnerScope = .current) -> Bool {
        for rem in remotes where GitProbe.isOwnedRemoteURL(rem.url, scope: scope) { return true }
        return managed
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
    // Internal (not private): FleetStore.rescan(repoId:) runs this SAME full pipeline
    // for one repo, so a targeted refresh sees everything a sweep sees (census,
    // policy, docs, hygiene — not just git) without re-probing the fleet.
    func probeRepo(_ abs: String, now: Date) async -> Repo {
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
        r.coverage = CoverageProbe.coverage(abs)   // real % from an on-disk artifact, else nil (honest absence)
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
