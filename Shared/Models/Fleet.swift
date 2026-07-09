// Fleet.swift — the assembled fleet snapshot + derived rollups.

import Foundation

/// State of the on-demand fleet scan. This app runs a MANUAL scan (triggered by
/// the user / a rescan) — there is no fsevents watcher and no sweep timer, so
/// nothing here may imply continuous monitoring. `lastSweepAt` + `swept` are the
/// only real telemetry; the legacy flags below are kept solely so readers outside
/// this slice keep compiling and are no longer rendered as "live/online/watching".
struct ScannerState: Sendable, Hashable {
    var host: String = "localhost"
    var root: String = "~/Code"
    var rootsAbs: [String] = []      // absolute scan roots — rides here so re-assembly (visibility/single-repo rescan) rebuilds the sidebar tree against the same roots the scan used
    var lastSweepAt: Date? = nil     // real completion time of the last scan (nil = never swept)
    var swept: String = "—"          // real wall-clock duration of the last scan ("12.3 ms")
    var scanning: Bool = false

    // Deprecated fabrications — no watcher/timer exists. Kept for source
    // compatibility (FleetView still reads `lastSweep`); prefer lastSweepAt.
    var lastSweep: String = "—"      // frozen-at-scan relative string; use lastSweepAt + RelTime.ago
    var online: Bool = false
    var watching: Bool = false
    var sweep: String = ""
}

struct AppBuild: Sendable, Hashable {
    var version: String = "v0.1.0"
    var commit: String = "-------"
    var date: String = "—"
    var channel: String = "dev"
    var codename: String = "phosphor"
}

struct FleetTotals: Sendable, Hashable {
    var repos = 0, workspaces = 0
    var healthy = 0, warn = 0, danger = 0
    var surprises = 0, godFiles = 0, dirty = 0
    var compliance = 100
    var agentsActive = 0
    var abandonedWorktrees = 0, staleWorktrees = 0
    var bloatedDocs = 0, staleChangelogs = 0
    var serenaActive = 0, mcpFailed = 0, guardrailless = 0
}

struct TreeNode: Identifiable, Sendable, Hashable {
    var repoId: String
    var depth: Int
    var id: String { repoId }
}

struct FleetAgentSession: Identifiable, Sendable, Hashable {
    var repo: Repo
    var agent: AgentInfo
    var id: String { repo.id + "·" + (agent.id.isEmpty ? agent.tool ?? "agent" : agent.id) }
}

/// A node in the sidebar's filesystem tree.
///
/// The sidebar mirrors the on-disk shape of the scan root. A `repo` node is a real
/// managed repo (a plain repo OR a `workspace` with a WORKSPACE.yaml) — selectable,
/// and collapsible when it nests children. A `group` node is a plain intermediate
/// directory that merely *contains* codebases but is not itself initialized as a
/// workspace (e.g. `__APPS`, `macOS`, `__INFRASTRUCTURE`): purely structural — it
/// groups the repos beneath it and is never selectable / navigable.
enum SidebarNodeKind: String, Sendable, Hashable { case repo, group }

struct SidebarNode: Identifiable, Sendable, Hashable {
    var kind: SidebarNodeKind
    var id: String            // STABLE + UNIQUE ForEach id: repo.id for repos, "group:<absPath>" for groups
    var depth: Int            // 0 == just below the scan root; drives indentation
    var repoId: String?       // the repo's id (nil for group nodes — the "not selectable" contract)
    var name: String          // display name (repo name / directory basename)
    var absolutePath: String  // canonical absolute path — the dedup key (never emitted twice)
    var hasChildren: Bool     // has at least one child row (→ show a disclosure control)
    var isWorkspace: Bool     // repo nodes: a WORKSPACE.yaml workspace
    var repoCount: Int        // group nodes: number of repo descendants; 0 for repo nodes
}

struct SkillUser: Identifiable, Sendable, Hashable {
    var repoId: String
    var name: String
    var status: SkillState
    var installed: String?
    var note: String?
    var id: String { repoId }
}

struct SkillRollup: Identifiable, Sendable, Hashable {
    var skillId: String
    var name: String
    var kind: String
    var latest: String
    var ns: String
    var owns: String
    var users: [SkillUser]
    var count: Int
    var issues: Int
    var id: String { skillId }
}

struct Fleet: Sendable {
    var scanner = ScannerState()
    var appBuild = AppBuild()
    var repos: [Repo] = []
    var activity: [ActivityEntry] = []
    var autopilot: [AutopilotRule] = []
    var skillCatalog: [SkillDef] = []

    // derived (stored, computed by `assemble`)
    var byId: [String: Repo] = [:]
    var leaves: [Repo] = []
    var workspaces: [Repo] = []
    var tree: [TreeNode] = []
    var sidebarTree: [SidebarNode] = []   // filesystem tree (repos + structural group dirs) for the sidebar
    var totals = FleetTotals()
    var findings: [Finding] = []
    var skillRollup: [SkillRollup] = []

    var sessions: [FleetAgentSession] {
        leaves.flatMap { repo in
            repo.agentSessions.map { FleetAgentSession(repo: repo, agent: $0) }
        }
        .sorted {
            ($0.agent.lastActivityAt ?? .distantPast) > ($1.agent.lastActivityAt ?? .distantPast)
        }
    }
    var worktreeSprawl: [(repo: Repo, worktree: Worktree)] {
        leaves.flatMap { r in r.worktrees.map { (r, $0) } }
    }
    func repo(_ id: String?) -> Repo? { id.flatMap { byId[$0] } }

    static func assemble(scanner: ScannerState, appBuild: AppBuild, repos: [Repo],
                         activity: [ActivityEntry], autopilot: [AutopilotRule],
                         catalog: [SkillDef]) -> Fleet {
        var f = Fleet()
        f.scanner = scanner
        f.appBuild = appBuild
        f.repos = repos
        f.activity = activity
        f.autopilot = autopilot
        f.skillCatalog = catalog
        f.byId = Dictionary(uniqueKeysWithValues: repos.map { ($0.id, $0) })
        let byName: (Repo, Repo) -> Bool = { $0.name.lowercased() < $1.name.lowercased() }
        f.leaves = repos.filter { $0.kind != .workspace }.sorted(by: byName)
        f.workspaces = repos.filter { $0.kind == .workspace }.sorted(by: byName)

        // nested tree: TOP-LEVEL workspaces (alpha) + their children (alpha), then
        // top-level repos (alpha). A repo that is BOTH a workspace AND a child of
        // another workspace must appear ONCE — `placed` guarantees no duplicate id
        // reaches ForEach (duplicate ids → "undefined results" + render thrash).
        var tree: [TreeNode] = []
        var placed = Set<String>()
        for ws in f.workspaces where ws.parentId == nil {
            guard placed.insert(ws.id).inserted else { continue }
            tree.append(TreeNode(repoId: ws.id, depth: 0))
            let kids = ws.children.compactMap { f.byId[$0] }.sorted(by: byName)
            for c in kids where placed.insert(c.id).inserted {
                tree.append(TreeNode(repoId: c.id, depth: 1))
            }
        }
        for r in f.leaves where r.parentId == nil && placed.insert(r.id).inserted {
            tree.append(TreeNode(repoId: r.id, depth: 0))
        }
        f.tree = tree
        f.sidebarTree = buildSidebarTree(repos: repos, roots: scanner.rootsAbs)

        let leaves = f.leaves
        var t = FleetTotals()
        t.repos = leaves.count
        t.workspaces = f.workspaces.count
        t.healthy = leaves.filter { $0.health == .ok }.count
        t.warn = leaves.filter { $0.health == .warn }.count
        t.danger = leaves.filter { $0.health == .danger }.count
        t.surprises = leaves.reduce(0) { $0 + $1.surprises.count }
        t.godFiles = leaves.reduce(0) { $0 + $1.census.godFiles.count }
        t.dirty = leaves.filter { !$0.worktree.clean }.count
        t.compliance = leaves.isEmpty ? 100 : Int((leaves.reduce(0) { $0 + $1.compliance }) / leaves.count)
        t.agentsActive = leaves.reduce(0) { $0 + $1.agentSessions.count }
        t.abandonedWorktrees = leaves.reduce(0) { $0 + $1.abandonedWorktrees }
        t.staleWorktrees = leaves.reduce(0) { $0 + $1.staleWorktrees }
        t.bloatedDocs = leaves.filter { $0.docs.taskState.status == .fail || $0.docs.agentsMd.status == .fail }.count
        t.staleChangelogs = leaves.filter { $0.docs.changelog.status != .ok }.count
        t.serenaActive = leaves.filter { $0.serena?.active == true }.count
        t.mcpFailed = leaves.reduce(0) { $0 + $1.mcp.filter { $0.status == .failed }.count }
        t.guardrailless = leaves.reduce(0) { $0 + ($1.hasActiveGuardrail() ? 0 : $1.agentSessions.count) }
        f.totals = t

        f.findings = leaves.flatMap { r in
            r.surprises.map { var s = $0; s.repoId = r.id; s.repoName = r.name; return s }
        }.sorted { $0.severity < $1.severity }

        f.skillRollup = catalog.compactMap { def in
            let users: [SkillUser] = leaves.compactMap { r in
                guard let use = r.skills.first(where: { $0.skillId == def.skillId }) else { return nil }
                return SkillUser(repoId: r.id, name: r.name, status: use.status,
                                 installed: use.installed, note: use.note)
            }
            guard !users.isEmpty else { return nil }
            return SkillRollup(skillId: def.skillId, name: def.name, kind: def.kind,
                               latest: def.version, ns: def.ns, owns: def.owns,
                               users: users, count: users.count,
                               issues: users.filter { $0.status != .ok }.count)
        }
        return f
    }

    /// Build the sidebar's filesystem tree from the repos' absolute paths.
    ///
    /// The sidebar must mirror the on-disk shape of the scan root, so the segments
    /// *between* a root and each repo become nodes: a segment that is itself a managed
    /// repo/workspace is a selectable `repo` node; a segment that only groups codebases
    /// (e.g. `__APPS/macOS`) is a structural `group` node. The tree is recursive to
    /// arbitrary depth — workspace → workspace → repo all nest naturally because depth
    /// is just the segment index. Output is a pre-order flattened list (`depth` drives
    /// indentation); the view applies collapse. Every absolute path is emitted at most
    /// once (`emitted`), so no repo is ever listed twice — and two repos that merely
    /// share a *name* keep their distinct paths and both appear.
    static func buildSidebarTree(repos: [Repo], roots: [String]) -> [SidebarNode] {
        func norm(_ p: String) -> String {
            var s = (p as NSString).expandingTildeInPath
            while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
            return s
        }
        // Known repo paths → repo (defensive dedup: distinct paths are expected).
        var repoByPath: [String: Repo] = [:]
        for r in repos { let p = norm(r.absolutePath); if repoByPath[p] == nil { repoByPath[p] = r } }
        let normRoots = roots.map(norm).sorted { $0.count > $1.count }   // longest root wins

        // Assemble the directory forest keyed by absolute path (each path a node once).
        var children: [String: [String]] = [:]
        var childSeen: [String: Set<String>] = [:]
        var topSeen = Set<String>()
        var topOrder: [String] = []
        func link(_ parent: String?, _ child: String) {
            if let par = parent {
                if childSeen[par, default: []].insert(child).inserted { children[par, default: []].append(child) }
            } else if topSeen.insert(child).inserted { topOrder.append(child) }
        }
        for r in repos {
            let p = norm(r.absolutePath)
            guard let root = normRoots.first(where: { p == $0 || p.hasPrefix($0 + "/") }) else {
                link(nil, p); continue   // no matching root → place at top, no group ancestors
            }
            var rel = String(p.dropFirst(root.count))
            while rel.hasPrefix("/") { rel.removeFirst() }
            let segs = rel.split(separator: "/").map(String.init)
            guard !segs.isEmpty else { continue }   // repo == root (shouldn't happen)
            var prefix = root, parent: String? = nil
            for seg in segs { prefix += "/" + seg; link(parent, prefix); parent = prefix }
        }

        // Flatten pre-order; assign depth; dedup by absolute path.
        func lastComp(_ path: String) -> String { (path as NSString).lastPathComponent }
        func sortKids(_ paths: [String]) -> [String] {
            paths.sorted { a, b in
                let la = lastComp(a).lowercased(), lb = lastComp(b).lowercased()
                return la == lb ? a < b : la < lb
            }
        }
        func repoDescendants(_ path: String) -> Int {
            (children[path] ?? []).reduce(0) { $0 + (repoByPath[$1] != nil ? 1 : 0) + repoDescendants($1) }
        }
        var out: [SidebarNode] = []
        var emitted = Set<String>()
        func visit(_ path: String, _ depth: Int) {
            guard emitted.insert(path).inserted else { return }
            let repo = repoByPath[path]
            out.append(SidebarNode(
                kind: repo != nil ? .repo : .group,
                id: repo.map(\.id) ?? ("group:" + path),
                depth: depth,
                repoId: repo?.id,
                name: repo?.name ?? lastComp(path),
                absolutePath: path,
                hasChildren: !(children[path] ?? []).isEmpty,
                isWorkspace: repo?.isWorkspace ?? false,
                repoCount: repo == nil ? repoDescendants(path) : 0))
            for k in sortKids(children[path] ?? []) { visit(k, depth + 1) }
        }
        for t in sortKids(topOrder) { visit(t, 0) }
        return out
    }
}
