// Fleet.swift — the assembled fleet snapshot + derived rollups.

import Foundation

struct ScannerState: Sendable, Hashable {
    var online: Bool = true
    var host: String = "localhost"
    var root: String = "~/Code"
    var sweep: String = "10s"
    var lastSweep: String = "just now"
    var watching: Bool = true
    var swept: String = "—"
    var scanning: Bool = false
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
    var totals = FleetTotals()
    var findings: [Finding] = []
    var skillRollup: [SkillRollup] = []

    var sessions: [Repo] { leaves.filter { $0.agentActive } }
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

        // nested tree: workspaces (alpha) + their children (alpha), then top-level repos (alpha).
        var tree: [TreeNode] = []
        for ws in f.workspaces {
            tree.append(TreeNode(repoId: ws.id, depth: 0))
            let kids = ws.children.compactMap { f.byId[$0] }.sorted(by: byName)
            for c in kids { tree.append(TreeNode(repoId: c.id, depth: 1)) }
        }
        for r in f.leaves where r.parentId == nil {
            tree.append(TreeNode(repoId: r.id, depth: 0))
        }
        f.tree = tree

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
        t.agentsActive = leaves.filter { $0.agentActive }.count
        t.abandonedWorktrees = leaves.reduce(0) { $0 + $1.abandonedWorktrees }
        t.staleWorktrees = leaves.reduce(0) { $0 + $1.staleWorktrees }
        t.bloatedDocs = leaves.filter { $0.docs.taskState.status == .fail || $0.docs.agentsMd.status == .fail }.count
        t.staleChangelogs = leaves.filter { $0.docs.changelog.status != .ok }.count
        t.serenaActive = leaves.filter { $0.serena?.active == true }.count
        t.mcpFailed = leaves.reduce(0) { $0 + $1.mcp.filter { $0.status == .failed }.count }
        t.guardrailless = leaves.filter { $0.agentActive && !$0.hasActiveGuardrail() }.count
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
}
