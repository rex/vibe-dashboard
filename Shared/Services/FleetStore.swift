// FleetStore.swift — the single @Observable fleet state the UI reads.

import SwiftUI

@MainActor
@Observable
final class FleetStore {
    private(set) var fleet = Fleet()
    private(set) var isScanning = false
    private(set) var lastScan: Date? = nil
    var roots: [String]

    // Ignore list — one-off repos the user doesn't want to manage.
    private(set) var ignoredIds: Set<String> = []
    private(set) var showIgnored = false

    private var rawFleet = Fleet()
    private var scanner: FleetScanner
    private static let ignoreKey = "vibe.ignored"
    private static let showIgnoredKey = "vibe.showIgnored"

    /// The live store, for the few main-actor call sites that need repo lookup but
    /// aren't handed it via the environment (e.g. `AppState.runFix` resolving a
    /// finding's repo path to reveal in Finder). Weak — the app root owns the store.
    static weak var current: FleetStore?

    init(roots: [String]? = nil) {
        let r = roots ?? FleetStore.defaultRoots()
        self.roots = r
        self.scanner = FleetScanner(roots: r)
        ignoredIds = Set(UserDefaults.standard.stringArray(forKey: Self.ignoreKey) ?? [])
        showIgnored = UserDefaults.standard.bool(forKey: Self.showIgnoredKey)
        FleetStore.current = self
    }

    static func defaultRoots() -> [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: "vibe.roots"), !saved.isEmpty { return saved }
        return [(NSHomeDirectory() as NSString).appendingPathComponent("Code")]
    }

    func setRoots(_ r: [String]) {
        roots = r
        scanner = FleetScanner(roots: r)
        UserDefaults.standard.set(r, forKey: "vibe.roots")
    }

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        let build = Self.appBuild()
        let host = Self.hostName()
        rawFleet = await scanner.scan(appBuild: build, host: host)
        applyVisibility()
        lastScan = Date()
        isScanning = false
    }

    /// Re-probe ONE repo's git-derived signals (worktree, worktrees, build, scm) — the
    /// state a commit / push / prune actually changes — and re-grade it in place,
    /// instead of sweeping the whole fleet. A full sweep re-probes every managed repo
    /// and, as TASK_STATE warns, can lock the machine for one edit. Docs/census/hooks
    /// are left as the last full scan measured them (a git write doesn't touch those),
    /// so this refreshes exactly what changed and nothing it can't honestly claim.
    /// Re-grading is essential: a resolved dirty/unpushed/unsigned state MUST clear its
    /// findings, else the UI would keep showing a fixed problem as still-open.
    func rescan(repoId: String) async {
        guard !isScanning, let idx = rawFleet.repos.firstIndex(where: { $0.id == repoId }) else { return }
        isScanning = true
        let now = Date()
        let abs = (rawFleet.repos[idx].absolutePath as NSString).expandingTildeInPath
        let git = await GitProbe.probe(abs, now: now)
        var repos = rawFleet.repos
        var r = repos[idx]
        let signedReq = r.signedRequired
        if git.isRepo {
            r.worktree = git.worktree
            r.worktrees = git.worktrees
            r.build = DeriveIntegrations.build(abs, git: git)
            r.scm = DeriveIntegrations.scm(branch: git.branch, remotes: git.remotes,
                                           worktree: git.worktree, signedRequired: signedReq)
        }
        r.gates = Derive.gates(r)
        r.compliance = Derive.compliance(r, signedRequired: signedReq)
        r.health = Derive.health(r, signedRequired: signedReq)
        r.surprises = Derive.surprises(r, signedRequired: signedReq, hardLimit: 400)
        r.checkedAt = now
        repos[idx] = r
        rawFleet = Fleet.assemble(scanner: rawFleet.scanner, appBuild: rawFleet.appBuild, repos: repos,
                                  activity: rawFleet.activity, autopilot: rawFleet.autopilot,
                                  catalog: rawFleet.skillCatalog)
        applyVisibility()
        lastScan = now
        isScanning = false
    }

    // ---- ignore / visibility ----
    func isIgnored(_ id: String) -> Bool { ignoredIds.contains(id) }
    var ignoredCount: Int { rawFleet.repos.filter { ignoredIds.contains($0.id) }.count }

    func ignore(_ id: String) { ignoredIds.insert(id); persistIgnore(); applyVisibility() }
    func unignore(_ id: String) { ignoredIds.remove(id); persistIgnore(); applyVisibility() }
    func toggleIgnore(_ id: String) { isIgnored(id) ? unignore(id) : ignore(id) }
    func toggleShowIgnored() {
        showIgnored.toggle()
        UserDefaults.standard.set(showIgnored, forKey: Self.showIgnoredKey)
        applyVisibility()
    }

    private func persistIgnore() {
        UserDefaults.standard.set(Array(ignoredIds), forKey: Self.ignoreKey)
    }

    private func applyVisibility() {
        let repos = showIgnored ? rawFleet.repos : rawFleet.repos.filter { !ignoredIds.contains($0.id) }
        fleet = Fleet.assemble(scanner: rawFleet.scanner, appBuild: rawFleet.appBuild, repos: repos,
                               activity: rawFleet.activity, autopilot: rawFleet.autopilot,
                               catalog: rawFleet.skillCatalog)
    }

    static func appBuild() -> AppBuild {
        AppBuild(version: "v" + BuildInfo.marketingVersion, commit: BuildInfo.commitShortSHA,
                 date: BuildInfo.commitDateShort, channel: "dev", codename: "phosphor")
    }
    static func hostName() -> String {
        var h = ProcessInfo.processInfo.hostName
        if let dot = h.firstIndex(of: ".") { h = String(h[..<dot]) }
        return h.isEmpty ? "localhost" : h
    }
}
