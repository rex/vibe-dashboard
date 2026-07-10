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
        guard !isScanning, let idx = rawFleet.repos.firstIndex(where: { $0.id == repoId }) else { return }
        isScanning = true
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
        var repos = rawFleet.repos
        repos[idx] = fresh
        Self.regrade(&repos, at: idx, now: now)
        rawFleet = Fleet.assemble(scanner: rawFleet.scanner, appBuild: rawFleet.appBuild, repos: repos,
                                  activity: rawFleet.activity, autopilot: rawFleet.autopilot,
                                  catalog: rawFleet.skillCatalog)
        applyVisibility()
        lastScan = now
        isScanning = false
    }

    /// Re-grade one repo (drift vs fleet-latest, gates, factors, compliance, health,
    /// surprises) and refresh its workspace ancestors' rollups. Pure CPU — shared by
    /// the targeted rescan and the agent monitor (a session appearing/vanishing
    /// changes guardrail/dirty grading, so agent changes must re-grade too).
    static func regrade(_ repos: inout [Repo], at idx: Int, now: Date) {
        let latest = SkeletonProbe.latest(repos.compactMap { $0.drift.version })
        let signedReq = repos[idx].signedRequired
        repos[idx].drift = SkeletonProbe.drift(version: repos[idx].drift.version, latest: latest)
        repos[idx].gates = Derive.gates(repos[idx])
        let factors = Derive.factors(repos[idx], signedRequired: signedReq)
        repos[idx].gradeFactors = factors
        repos[idx].compliance = Derive.score(factors)
        repos[idx].health = Derive.healthBand(factors)
        repos[idx].surprises = Derive.surprises(repos[idx], signedRequired: signedReq, hardLimit: 400)
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

    private func debouncedAgentRefresh() {
        agentFsDebounce?.cancel()
        agentFsDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.refreshAgents()
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
        for id in hit { scheduleRepoRescan(id) }
    }

    /// Trailing debounce per repo, with a post-rescan cooldown: the rescan's own
    /// `git status` may refresh `.git/index` and echo one event back — without the
    /// cooldown that echo would re-trigger forever.
    private func scheduleRepoRescan(_ id: String, delay: TimeInterval = 2.5) {
        if let last = repoRescanCooldown[id], Date().timeIntervalSince(last) < 3 { return }
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
            if repos[i].agents != agents || repos[i].agent != agents.first {
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
