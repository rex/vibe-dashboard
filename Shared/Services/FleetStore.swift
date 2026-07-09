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
                repos[i].agents = agents
                repos[i].agent = agents.first
                changed = true
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
