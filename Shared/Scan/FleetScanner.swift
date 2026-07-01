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

        // Probe every candidate concurrently.
        var repos: [Repo] = await withTaskGroup(of: Repo.self) { group in
            for abs in candidates { group.addTask { await probeRepo(abs, now: now) } }
            var acc: [Repo] = []
            for await r in group { acc.append(r) }
            return acc
        }

        // Nesting: parent = longest candidate that is a strict path prefix.
        let absSet = Set(repos.map(\.absolutePath))
        var idByAbs: [String: String] = [:]
        for r in repos { idByAbs[r.absolutePath] = r.id }
        for i in repos.indices {
            let mine = repos[i].absolutePath
            let parent = absSet.filter { $0 != mine && mine.hasPrefix($0 + "/") }.max { $0.count < $1.count }
            repos[i].parentId = parent.flatMap { idByAbs[$0] }
        }
        // Keep only managed repos (+ their ancestors, which become workspaces).
        var keep = Set(repos.filter { $0.managed }.map { $0.id })
        var changed = true
        while changed {
            changed = false
            for r in repos where keep.contains(r.id) {
                if let p = r.parentId, !keep.contains(p) { keep.insert(p); changed = true }
            }
        }
        repos = repos.filter { keep.contains($0.id) }
        var childrenOf: [String: [String]] = [:]
        for r in repos { if let p = r.parentId, keep.contains(p) { childrenOf[p, default: []].append(r.id) } }

        // Live agent sessions → attach to the deepest matching repo.
        let sessions = await AgentProbe.sessions()
        for s in sessions {
            guard let idx = repos.indices
                .filter({ s.cwd == repos[$0].absolutePath || s.cwd.hasPrefix(repos[$0].absolutePath + "/") })
                .max(by: { repos[$0].absolutePath.count < repos[$1].absolutePath.count }) else { continue }
            repos[idx].agent = AgentInfo(active: true, tool: s.tool, branch: repos[idx].build.branch,
                                         elapsed: s.elapsed, filesTouched: repos[idx].worktree.unstaged,
                                         lastActivity: "just now", note: "live edit session")
        }

        // Mark workspaces + derive health/compliance/gates/surprises.
        for i in repos.indices {
            let kids = childrenOf[repos[i].id] ?? []
            if !kids.isEmpty || FleetScanner.fm.fileExists(atPath: (repos[i].absolutePath as NSString).appendingPathComponent("WORKSPACE.yaml")) {
                repos[i].kind = .workspace
                repos[i].children = kids
            }
        }
        let byId = Dictionary(uniqueKeysWithValues: repos.map { ($0.id, $0) })
        for i in repos.indices {
            let signedReq = repos[i].scm.signed || true   // signed_commits assumed required by policy
            if repos[i].kind == .workspace {
                let children = repos[i].children.compactMap { byId[$0] }
                let worst = children.map(\.health).max() ?? .ok
                repos[i].health = worst
                repos[i].compliance = children.isEmpty ? 100 : children.map(\.compliance).reduce(0, +) / children.count
                repos[i].desc = "Workspace · \(children.count) managed repo\(children.count == 1 ? "" : "s")"
                repos[i].stack = "workspace"
                continue
            }
            repos[i].gates = Derive.gates(repos[i])
            repos[i].compliance = Derive.compliance(repos[i], signedRequired: signedReq)
            repos[i].health = Derive.health(repos[i], signedRequired: signedReq)
            repos[i].surprises = Derive.surprises(repos[i], signedRequired: signedReq, hardLimit: 400)
            repos[i].checked = "just now"
        }

        // Scanner + activity + assembly.
        let elapsedMs = String(format: "%.1f ms", Date().timeIntervalSince(start) * 1000)
        let leaves = repos.filter { $0.kind != .workspace }
        let scanner = ScannerState(online: true, host: host, root: displayPath(roots.first ?? "~/Code"),
                                   sweep: "10s", lastSweep: "just now", watching: true, swept: elapsedMs)
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
        let census = FileProbes.census(abs, soft: soft, hard: hard, ansible: idn.stack.contains("ansible"))
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
        r.scm = DeriveIntegrations.scm(branch: git.branch, remotes: git.remotes, worktree: git.worktree, signedRequired: signedRequired(vibe))
        r.ci = DeriveIntegrations.ci(abs, stack: idn.stack)
        r.containers = DeriveIntegrations.containers(abs)
        r.skills = DeriveIntegrations.skills(abs, vibe: vibe, stack: idn.stack)
        r.build = DeriveIntegrations.build(abs, git: git)
        r.policy = vibe.map { PolicyProbe.sections($0) } ?? []
        r.managed = FileProbes.exists(FileProbes.join(abs, "VIBE.yaml"))
            || FileProbes.exists(FileProbes.join(abs, "AGENTS.md"))
            || FileProbes.exists(FileProbes.join(abs, ".claude"))
        r.checked = "just now"
        return r
    }

    private func limits(_ vibe: [String: Any]?) -> (Int, Int) {
        guard let arch = vibe?["architecture"] as? [String: Any],
              let mx = arch["max_lines_per_file"] as? [String: Any] else { return (250, 400) }
        return (mx["soft"] as? Int ?? 250, mx["hard"] as? Int ?? 400)
    }
    private func coverageFloor(_ vibe: [String: Any]?) -> Int? {
        ((vibe?["quality_gates"] as? [String: Any])?["coverage"] as? [String: Any])?["minimum_percentage"] as? Int
    }
    private func signedRequired(_ vibe: [String: Any]?) -> Bool {
        (vibe?["workflow"] as? [String: Any])?["signed_commits_required"] as? Bool ?? false
    }
}
