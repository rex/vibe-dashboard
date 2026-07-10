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

    private var rawFleet = Fleet()
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

    // ---- background agent monitor (lightweight — no full rescan) ----
    private var agentMonitor: Task<Void, Never>?
    private var agentRefreshInFlight = false

    /// Auto-refresh ONLY live-agent detection every `interval` seconds — Pierce's ask:
    /// agents update in the background without a full app rescan. Ticks IMMEDIATELY on
    /// start (a fresh launch must not wait a full interval for its first agent read),
    /// then sleeps between ticks (Task.sleep, never a repeatForever/CPU spinner).
    /// Started from the app root BEFORE the initial rescan is awaited, so a slow — or
    /// wedged — fleet scan can never keep agent detection from running (the original
    /// "auto-refresh doesn't work": the monitor start was sequenced AFTER a rescan
    /// that hung, so it never started at all).
    func startAgentMonitor(interval: TimeInterval = 30) {
        guard agentMonitor == nil else { return }
        agentMonitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAgents()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
    func stopAgentMonitor() { agentMonitor?.cancel(); agentMonitor = nil }

    // ---- FSEvents: push-based updates (the 30s poll stays as the safety net) ----
    private var agentFsWatcher: FSEventsWatcher?
    private var repoFsWatcher: FSEventsWatcher?
    private var agentFsDebounce: Task<Void, Never>?
    private var repoFsDebounce: [String: Task<Void, Never>] = [:]
    private var repoRescanCooldown: [String: Date] = [:]

    /// Watch the agent transcript stores and the scan roots. Transcript writes →
    /// near-instant `refreshAgents`; repo writes → per-repo debounced
    /// `rescan(repoId:)`, so a commit / branch move / file edit re-scores JUST that
    /// repo seconds later — no full sweep. FSEvents streams are kernel-coalesced
    /// per directory TREE (no per-file descriptors), so three streams cover
    /// everything at negligible cost.
    func startFsMonitors() {
        stopFsMonitors()
        let home = NSHomeDirectory()
        agentFsWatcher = FSEventsWatcher(
            paths: [home + "/.claude/projects", home + "/.codex/sessions"],
            latency: 0.8) { [weak self] _ in
            Task { @MainActor [weak self] in self?.debouncedAgentRefresh() }
        }
        repoFsWatcher = FSEventsWatcher(
            paths: roots.map { ($0 as NSString).expandingTildeInPath },
            latency: 2.0) { [weak self] paths in
            Task { @MainActor [weak self] in self?.handleRepoEvents(paths) }
        }
    }
    func stopFsMonitors() {
        agentFsWatcher?.stop(); agentFsWatcher = nil
        repoFsWatcher?.stop(); repoFsWatcher = nil
    }

    private var lastAgentRefresh = Date.distantPast

    /// Trailing debounce with a 5s floor between refreshes. A busy session appends
    /// to its transcript every few seconds; refreshing on each write re-enumerated
    /// ~/.claude/projects and spawned git diff/status per session ~once a second —
    /// a large slice of the measured CPU burn. 5s keeps cards feeling live.
    private func debouncedAgentRefresh() {
        agentFsDebounce?.cancel()
        let sinceLast = Date().timeIntervalSince(lastAgentRefresh)
        let delay = max(1.2, 5.0 - sinceLast)
        agentFsDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.lastAgentRefresh = Date()
            await self.refreshAgents()
        }
    }

    private func handleRepoEvents(_ paths: [String]) {
        let repoList = rawFleet.repos.map {
            (id: $0.id, absPath: ($0.absolutePath as NSString).expandingTildeInPath)
        }
        guard !repoList.isEmpty else { return }
        var hit = Set<String>()
        for path in paths {
            if let id = RepoEventMapper.repoId(for: path, repos: repoList) { hit.insert(id) }
        }
        for id in hit {
            // A repo with a LIVE agent churns files continuously — re-probing it
            // every few seconds is pure heat. Let it settle longer; the 30s agent
            // monitor and the eventual quiet period keep it honest.
            let agentBusy = rawFleet.repos.first { $0.id == id }?.agentActive == true
            scheduleRepoRescan(id, delay: agentBusy ? 10 : 3)
        }
    }

    /// Trailing debounce per repo, with a post-rescan cooldown: the rescan's own
    /// `git status` may refresh `.git/index` and echo one event back — without the
    /// cooldown that echo would re-trigger forever.
    private func scheduleRepoRescan(_ id: String, delay: TimeInterval = 3) {
        if let last = repoRescanCooldown[id], Date().timeIntervalSince(last) < 5 { return }
        repoFsDebounce[id]?.cancel()
        repoFsDebounce[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if self.isScanning {                       // a sweep is running — retry after it
                self.scheduleRepoRescan(id, delay: 3)
                return
            }
            self.repoFsDebounce[id] = nil
            self.repoRescanCooldown[id] = Date()
            await self.rescan(repoId: id)
        }
    }

    /// Re-detect live agent sessions and update ONLY the agent field on each repo — no
    /// git/census/docs re-probe. A COMPLETE session (> 1h idle, dropped by the probe)
    /// clears its repo's agent. All sessions + measured work are gathered up front
    /// (async), then applied in one synchronous main-actor pass against the CURRENT
    /// rawFleet — so a full rescan that completed during the awaits is never clobbered.
    /// Coalesced: a tick that lands while one is still probing is dropped, not queued
    /// (the in-flight pass already reads the freshest state).
    func refreshAgents(now: Date = Date()) async {
        guard !agentRefreshInFlight else { return }
        agentRefreshInFlight = true
        defer { agentRefreshInFlight = false }
        let sessions = await AgentProbe.sessions(now: now)
        var work: [String: AgentProbe.WorkStat] = [:]
        for s in sessions { work[s.id] = await AgentProbe.workStat(cwd: s.cwd, now: now) }
        applyAgentSessions(sessions, work: work, now: now)
    }

    private func applyAgentSessions(_ sessions: [AgentProbe.Session],
                                    work: [String: AgentProbe.WorkStat], now: Date) {
        var repos = rawFleet.repos
        var target: [Int: [AgentInfo]] = [:]
        for s in sessions {
            let sessionCwd = AgentTranscriptProbe.normalizedPath(s.cwd)
            guard let idx = repos.indices
                .filter({
                    let repoPath = AgentTranscriptProbe.normalizedPath(repos[$0].absolutePath)
                    return sessionCwd == repoPath || sessionCwd.hasPrefix(repoPath + "/")
                })
                .max(by: { repos[$0].absolutePath.count < repos[$1].absolutePath.count }) else { continue }
            target[idx, default: []].append(AgentInfo.live(session: s, work: work[s.id] ?? AgentProbe.WorkStat(),
                                                           clean: repos[idx].worktree.clean,
                                                           branch: repos[idx].build.branch, now: now))
        }
        var changed = false
        for i in repos.indices {
            let agents = (target[i] ?? []).sorted {
                ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast)
            }
            // MEANINGFUL change only. A busy session's transcript grows every few
            // seconds, bumping lastActivity on every probe — treating that as
            // "changed" reassembled the whole fleet (and re-laid-out every view)
            // near-continuously: a `sample` showed 16 Fleet.assembles in 5s at ~50%
            // CPU. Volatile timestamp drift refreshes on the slow poll instead.
            if Self.agentsMeaningfullyDiffer(repos[i].agents, agents) {
                let hadAgents = repos[i].agentActive
                repos[i].agents = agents
                repos[i].agent = agents.first
                changed = true
                // A session appearing/vanishing changes grading (guardrail-less
                // live agent is a critical factor; dirty is softened mid-work) —
                // re-grade in place so health tracks reality between sweeps.
                if hadAgents != repos[i].agentActive {
                    Self.regrade(&repos, at: i, now: now)
                }
            }
        }
        guard changed else { return }   // no agent state moved — skip the re-assemble (idle = zero work)
        rawFleet = Fleet.assemble(scanner: rawFleet.scanner, appBuild: rawFleet.appBuild, repos: repos,
                                  activity: rawFleet.activity, autopilot: rawFleet.autopilot,
                                  catalog: rawFleet.skillCatalog)
        applyVisibility()
    }

    /// Sessions differ in a way worth re-rendering the fleet for: composition,
    /// lifecycle state, measured work, or telemetry — OR the freshest activity
    /// moved by more than a minute (so "last activity Nm ago" stays honest without
    /// re-assembling on every transcript append).
    nonisolated static func agentsMeaningfullyDiffer(_ old: [AgentInfo], _ new: [AgentInfo]) -> Bool {
        guard old.count == new.count else { return true }
        for (a, b) in zip(old, new) {
            if a.id != b.id || a.state != b.state || a.sessionKind != b.sessionKind
                || a.filesTouched != b.filesTouched || a.linesAdded != b.linesAdded
                || a.linesRemoved != b.linesRemoved || a.model != b.model
                || a.contextTokens != b.contextTokens || a.note != b.note
                || a.branch != b.branch { return true }
            let ta = a.lastActivityAt ?? .distantPast
            let tb = b.lastActivityAt ?? .distantPast
            if abs(tb.timeIntervalSince(ta)) > 60 { return true }
        }
        return false
    }

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

    private func applyVisibility() {
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
