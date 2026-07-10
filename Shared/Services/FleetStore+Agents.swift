// FleetStore+Agents.swift — the live-agent monitor + FSEvents push layer.
// Split from FleetStore.swift for the 400-line hard gate (this app enforces the
// same limit it measures). Stored properties remain in the class body.

import SwiftUI

extension FleetStore {
    // ---- background agent monitor (lightweight — no full rescan) ----

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


    /// LEADING-EDGE schedule with a 5s floor — never cancel-and-reschedule. The
    /// cancel-based debounce LIVELOCKED under continuous transcript churn: each
    /// new event cancelled the pending refresh before its sleep elapsed, so the
    /// FSEvents path never fired at all while agents streamed (a brand-new session
    /// then waited on the 30s poll — on a starved main thread). One pending task
    /// fires ~1.2–5s after the first event of a burst; later events ride along.
    private func debouncedAgentRefresh() {
        guard agentFsDebounce == nil else { return }
        let sinceLast = Date().timeIntervalSince(lastAgentRefresh)
        let delay = max(1.2, 5.0 - sinceLast)
        agentFsDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.agentFsDebounce = nil
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
            // A repo with a LIVE agent churns files continuously — and a full
            // per-repo probe (census walk + hygiene content scan + git) costs real
            // multi-core seconds. Re-probing three busy repos every ~10s was a
            // steady background burn. 30s keeps grades tracking a spree closely
            // enough; the agent monitor keeps the live-session info fresh
            // separately, and the final quiet-period rescan lands the end state.
            let agentBusy = rawFleet.repos.first { $0.id == id }?.agentActive == true
            scheduleRepoRescan(id, delay: agentBusy ? 30 : 3)
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

}
