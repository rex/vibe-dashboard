// FleetStore.swift — the single @Observable fleet state the UI reads.

import SwiftUI

@MainActor
@Observable
final class FleetStore {
    private(set) var fleet = Fleet()
    /// True ONLY during a full fleet sweep. Targeted single-repo refreshes track in
    /// `refreshingRepoIds` instead — FSEvents-driven per-repo re-probes fire every
    /// few seconds while an agent hammers a repo, and routing them through this flag
    /// lit the global "scanning" indicator near-permanently (read as a hung scan).
    private(set) var isScanning = false
    private(set) var refreshingRepoIds: Set<String> = []
    private(set) var lastScan: Date? = nil
    var roots: [String]

    // Ignore list — one-off repos the user doesn't want to manage.
    private(set) var ignoredIds: Set<String> = []
    private(set) var showIgnored = false
    /// "VIBE only": show — and COUNT — only repos instrumented with a VIBE.yaml.
    /// Distinct from ignoring: an uninstrumented repo isn't unwanted, it just isn't
    /// under policy yet, and Pierce mostly reasons about the instrumented fleet.
    private(set) var instrumentedOnly = false

    // Internal (not private): FleetStore+Agents.swift mutates the raw fleet
    // from the monitor/FSEvents paths. Module-internal only.
    var rawFleet = Fleet()
    private var scanner: FleetScanner
    private static let ignoreKey = "vibe.ignored"
    private static let showIgnoredKey = "vibe.showIgnored"
    private static let instrumentedOnlyKey = "vibe.instrumentedOnly"

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
        instrumentedOnly = UserDefaults.standard.bool(forKey: Self.instrumentedOnlyKey)
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
        if repoFsWatcher != nil { startFsMonitors() }   // re-aim the streams at the new roots
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

    /// Re-probe ONE repo through the SAME full per-repo pipeline the sweep uses —
    /// policy, census (incl. exclude_globs), docs, hygiene, hooks, git — then
    /// re-grade it and its workspace ancestors in place. A VIBE.yaml edit (e.g.
    /// "exclude this god-file") therefore propagates to every view seconds later
    /// without a fleet sweep; a full sweep re-probes every managed repo and can
    /// lock the machine for one edit. Re-grading is essential: a resolved finding
    /// MUST disappear, else the UI keeps showing a fixed problem as still-open.
    func rescan(repoId: String) async {
        guard !isScanning, !refreshingRepoIds.contains(repoId),
              let idx = rawFleet.repos.firstIndex(where: { $0.id == repoId }) else { return }
        refreshingRepoIds.insert(repoId)
        defer { refreshingRepoIds.remove(repoId) }
        let now = Date()
        let old = rawFleet.repos[idx]
        let abs = (old.absolutePath as NSString).expandingTildeInPath
        var fresh = await scanner.probeRepo(abs, now: now)
        // A single-repo probe can't know fleet topology or live sessions — carry them.
        fresh.id = old.id
        fresh.kind = old.kind
        fresh.parentId = old.parentId
        fresh.children = old.children
        fresh.agents = old.agents
        fresh.agent = old.agent
        // The fleet may have re-scanned or re-shuffled during the await — re-resolve.
        guard let liveIdx = rawFleet.repos.firstIndex(where: { $0.id == repoId }) else { return }
        var repos = rawFleet.repos
        repos[liveIdx] = fresh
        Self.regrade(&repos, at: liveIdx, now: now)
        rawFleet = Fleet.assemble(scanner: rawFleet.scanner, appBuild: rawFleet.appBuild, repos: repos,
                                  activity: rawFleet.activity, autopilot: rawFleet.autopilot,
                                  catalog: rawFleet.skillCatalog)
        applyVisibility()
        lastScan = now
    }

    /// Re-grade one repo (drift vs fleet-latest, gates, factors, compliance, health,
    /// surprises) and refresh its workspace ancestors' rollups. Pure CPU — shared by
    /// the targeted rescan and the agent monitor (a session appearing/vanishing
    /// changes guardrail/dirty grading, so agent changes must re-grade too).
    static func regrade(_ repos: inout [Repo], at idx: Int, now: Date) {
        let latest = SkeletonProbe.latest(repos.compactMap { $0.drift.version })
        FleetScanner.gradeRepo(&repos[idx], latest: latest,
                               waivedIDs: WaiverLedger.activeIDsFromDefaults(now: now))
        repos[idx].checkedAt = now

        var idxById: [String: Int] = [:]
        for i in repos.indices { idxById[repos[i].id] = i }
        var cur = repos[idx].parentId
        var hops = 0
        while let pid = cur, let pi = idxById[pid], hops < 64 {
            let kids = repos[pi].children.compactMap { idxById[$0] }
            repos[pi].health = kids.map { repos[$0].health }.max() ?? .ok
            repos[pi].compliance = kids.isEmpty ? 100
                : kids.reduce(0) { $0 + repos[$1].compliance } / kids.count
            cur = repos[pi].parentId
            hops += 1
        }
    }

    // ---- agent/FS monitor state (methods live in FleetStore+Agents.swift;
    // stored properties must live in the class body) ----
    var agentMonitor: Task<Void, Never>?
    var agentRefreshInFlight = false
    var agentFsWatcher: FSEventsWatcher?
    var repoFsWatcher: FSEventsWatcher?
    var agentFsDebounce: Task<Void, Never>?
    var repoFsDebounce: [String: Task<Void, Never>] = [:]
    var repoRescanCooldown: [String: Date] = [:]
    var lastAgentRefresh = Date.distantPast

    /// Re-grade every leaf from its EXISTING probe facts — the waiver ledger
    /// changed, the filesystem didn't, so this is pure CPU and instant. Waiving or
    /// un-waiving a finding updates compliance/health/feeds everywhere immediately.
    func applyWaivers() {
        var repos = rawFleet.repos
        let latest = SkeletonProbe.latest(repos.compactMap { $0.drift.version })
        let waivedIDs = WaiverLedger.activeIDsFromDefaults()
        for i in repos.indices where repos[i].kind != .workspace {
            FleetScanner.gradeRepo(&repos[i], latest: latest, waivedIDs: waivedIDs)
        }
        // Workspace rollups from re-graded children (same shape as the sweep's pass 2).
        var idxById: [String: Int] = [:]
        for i in repos.indices { idxById[repos[i].id] = i }
        for i in repos.indices where repos[i].kind == .workspace {
            let kids = repos[i].children.compactMap { idxById[$0] }
            repos[i].health = kids.map { repos[$0].health }.max() ?? .ok
            repos[i].compliance = kids.isEmpty ? 100
                : kids.reduce(0) { $0 + repos[$1].compliance } / kids.count
        }
        rawFleet = Fleet.assemble(scanner: rawFleet.scanner, appBuild: rawFleet.appBuild, repos: repos,
                                  activity: rawFleet.activity, autopilot: rawFleet.autopilot,
                                  catalog: rawFleet.skillCatalog)
        applyVisibility()
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

    func toggleInstrumentedOnly() {
        instrumentedOnly.toggle()
        UserDefaults.standard.set(instrumentedOnly, forKey: Self.instrumentedOnlyKey)
        applyVisibility()
    }
    /// Repos hidden by the VIBE-only filter right now (0 when the filter is off).
    var uninstrumentedHiddenCount: Int {
        guard instrumentedOnly else { return 0 }
        return rawFleet.repos.filter { $0.kind != .workspace && !$0.vibePresent }.count
    }

    private func persistIgnore() {
        UserDefaults.standard.set(Array(ignoredIds), forKey: Self.ignoreKey)
    }

    func applyVisibility() {
        var repos = showIgnored ? rawFleet.repos : rawFleet.repos.filter { !ignoredIds.contains($0.id) }
        if instrumentedOnly {
            // VIBE-only: uninstrumented repos leave the views AND every rollup/total
            // (assemble recomputes from what remains). Workspaces stay as structure.
            repos = repos.filter { $0.kind == .workspace || $0.vibePresent }
        }
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
