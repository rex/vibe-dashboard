// AgentWatchModel.swift — the observable model behind one agent watch window.
//
// The window renders LANES, not one-pane-per-agent: a lane is a concurrency slot
// whose stream CONTINUES across phase handoffs. Lane assignment replays the
// workflow journal — when an agent returns its lane frees, and the next spawned
// agent picks up that lane with a visible hop divider, so a 3-wide, 3-phase
// workflow reads as 3 continuous streams instead of 9 scattered panes. All file
// IO runs off the main actor; the UI re-renders only when a cheap fingerprint
// says something actually changed.

import Foundation

/// One agent's transcript segment (a lane holds 1..n of these, chronological).
struct WatchPane: Identifiable, Sendable, Hashable {
    var id: String { path }
    var path: String
    var title: String
    var badge: String?            // agentType / provider label
    var isMain = false            // the session's own transcript
    var order: Int = .max         // journal spawn order
    var done = false              // journal recorded a result for this agent
    var outcome: String? = nil    // the recorded result payload (pretty, clipped)
    var tail = WatchTailState()

    var firstEventAt: Date? { tail.events.first(where: { $0.timestamp != nil })?.timestamp }
    var lastEventAt: Date? { tail.events.last(where: { $0.timestamp != nil })?.timestamp }
    func isStreaming(now: Date) -> Bool {
        guard !done, let g = tail.lastGrowth else { return false }
        return now.timeIntervalSince(g) < 20
    }
}

/// A concurrency slot: agents that hand off to each other, rendered as ONE
/// continuous stream with hop dividers between segments.
struct WatchLane: Identifiable, Sendable, Hashable {
    var id: Int                   // lane index — stable for the whole watch
    var segments: [WatchPane]

    var current: WatchPane? { segments.last }
    var eventTotal: Int { segments.reduce(0) { $0 + $1.tail.seq } }
    var done: Bool { segments.allSatisfy(\.done) && !segments.isEmpty }
    func isStreaming(now: Date) -> Bool { segments.contains { $0.isStreaming(now: now) } }
}

@MainActor
@Observable
final class AgentWatchModel {
    private(set) var lanes: [WatchLane] = []
    private(set) var workflowMeta = WatchWorkflowMeta()
    private(set) var returnedCount = 0
    private(set) var agentTotal = 0
    private(set) var now = Date()
    let target: AgentWatchTarget

    private var loop: Task<Void, Never>?
    private var fsWatcher: FSEventsWatcher?
    private var fingerprint = ""
    private var tickCount = 0

    init(target: AgentWatchTarget) { self.target = target }

    /// Event-driven when FSEvents attaches to the transcript dirs (ticks land
    /// ~150ms after a write); the poll loop remains as a slow safety net —
    /// fast (0.7s) only if the watcher couldn't start.
    func start() {
        guard loop == nil else { return }
        fsWatcher = FSEventsWatcher(paths: watchDirs, latency: 0.15) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pokeNow() }
        }
        let interval: TimeInterval = fsWatcher != nil ? 3.0 : 0.7
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
    func stop() {
        loop?.cancel(); loop = nil
        fsWatcher?.stop(); fsWatcher = nil
    }

    /// Run one tick immediately (an FSEvents nudge) without waiting for the loop.
    func pokeNow() { Task { await tick() } }

    /// The directory trees whose writes mean "this window has new content".
    private var watchDirs: [String] {
        switch target.kind {
        case .workflow:
            return [(target.transcriptPath as NSString).deletingLastPathComponent]
        case .standard where target.tool == "claude-code":
            // The project slug dir covers the main transcript AND the session's
            // subagents tree (created lazily — a recursive watch sees it appear).
            return [(target.transcriptPath as NSString).deletingLastPathComponent]
        default:
            return [(target.transcriptPath as NSString).deletingLastPathComponent]
        }
    }

    private func tick() async {
        let target = self.target
        let snapshot = Snapshot(lanes: lanes, meta: workflowMeta)
        let discover = tickCount % 4 == 0    // re-list agent files every ~3s; tail every tick
        tickCount += 1
        let updated = await Task.detached(priority: .utility) {
            Self.compute(target: target, prior: snapshot, discover: discover, now: Date())
        }.value
        now = Date()
        let fp = Self.fingerprint(updated.lanes)
        if fp != fingerprint || updated.meta != workflowMeta {
            fingerprint = fp
            lanes = updated.lanes
            workflowMeta = updated.meta
            returnedCount = updated.returned
            agentTotal = updated.total
        }
    }

    struct Snapshot: Sendable {
        var lanes: [WatchLane]
        var meta: WatchWorkflowMeta
        var returned = 0
        var total = 0
    }

    /// Cheap change detector — avoids replacing (and re-diffing) hundreds of event
    /// rows when a tick found nothing new.
    nonisolated static func fingerprint(_ lanes: [WatchLane]) -> String {
        lanes.map { lane in
            "\(lane.id)[" + lane.segments
                .map { "\($0.path):\($0.tail.offset):\($0.tail.seq):\($0.done ? 1 : 0)" }
                .joined(separator: ",") + "]"
        }.joined(separator: "|")
    }

    // MARK: - Off-main tick body (pure functions of the filesystem)

    nonisolated static func compute(target: AgentWatchTarget, prior: Snapshot,
                                    discover: Bool, now: Date) -> Snapshot {
        var next = prior
        if discover || prior.lanes.isEmpty {
            next = discoverLanes(target: target, prior: prior)
        }
        for l in next.lanes.indices {
            for s in next.lanes[l].segments.indices {
                next.lanes[l].segments[s].tail = WatchTailer.advance(
                    path: next.lanes[l].segments[s].path,
                    state: next.lanes[l].segments[s].tail, now: now)
            }
        }
        return next
    }

    /// Enumerate transcripts + journal + plan sidecars and shape them into lanes.
    /// Existing segments keep their tail state; agents that appear mid-watch join
    /// a freed lane (the hop) or open a new one (a wider fan-out).
    nonisolated static func discoverLanes(target: AgentWatchTarget, prior: Snapshot) -> Snapshot {
        var byPath: [String: WatchPane] = [:]
        for lane in prior.lanes {
            for seg in lane.segments { byPath[seg.path] = seg }
        }
        // Title/badge are computed ONCE per pane (title derivation may read the
        // transcript head — no reason to redo it every discovery tick); lifecycle
        // fields refresh every time.
        func pane(path: String, title: @autoclosure () -> String, badge: String?, isMain: Bool,
                  order: Int, done: Bool, outcome: String?) -> WatchPane {
            var p = byPath[path] ?? WatchPane(path: path, title: title(), badge: badge)
            p.isMain = isMain
            p.order = order; p.done = done; p.outcome = outcome
            return p
        }

        switch target.kind {
        case .workflow:
            let dir = (target.transcriptPath as NSString).deletingLastPathComponent
            let journal = WatchJournal.read(dir: dir)
            let meta = WatchWorkflowMeta.load(workflowDir: dir)
            var byAgentId: [String: WatchPane] = [:]
            var extras: [WatchPane] = []   // on disk but not (yet) in the journal
            for path in agentFiles(in: dir) {
                let agentId = agentId(of: path)
                let m = WatchAgentMeta.read(transcriptPath: path)
                let p = pane(path: path,
                             title: m.description
                                 ?? WatchAgentMeta.promptTitle(transcriptPath: path)
                                 ?? "agent \(agentId.prefix(7))",
                             badge: m.agentType,
                             isMain: false,
                             order: journal.startOrder.firstIndex(of: agentId) ?? .max,
                             done: journal.results[agentId] != nil,
                             outcome: journal.results[agentId])
                if journal.startOrder.contains(agentId) { byAgentId[agentId] = p }
                else { extras.append(p) }
            }
            var laneAgents = assignLanes(events: journal.events)
                .map { $0.compactMap { byAgentId[$0] } }
                .filter { !$0.isEmpty }
            laneAgents += extras.sorted { $0.path < $1.path }.map { [$0] }
            let lanes = laneAgents.enumerated().map { WatchLane(id: $0.offset, segments: $0.element) }
            return Snapshot(lanes: lanes, meta: meta,
                            returned: journal.results.count,
                            total: max(journal.startOrder.count, byAgentId.count + extras.count))

        case .standard where target.tool == "claude-code":
            var lanes = [WatchLane(id: 0, segments: [
                pane(path: target.transcriptPath, title: target.repoName, badge: target.tool,
                     isMain: true, order: -1, done: false, outcome: nil),
            ])]
            for (i, path) in recentSubagentFiles(mainTranscript: target.transcriptPath).enumerated() {
                let m = WatchAgentMeta.read(transcriptPath: path)
                lanes.append(WatchLane(id: i + 1, segments: [
                    pane(path: path,
                         title: m.description
                             ?? WatchAgentMeta.promptTitle(transcriptPath: path)
                             ?? "subagent \(agentId(of: path).prefix(7))",
                         badge: m.agentType ?? "subagent",
                         isMain: false, order: .max, done: false, outcome: nil),
                ]))
            }
            return Snapshot(lanes: lanes, meta: WatchWorkflowMeta(),
                            returned: 0, total: lanes.count)

        default:
            let lane = WatchLane(id: 0, segments: [
                pane(path: target.transcriptPath, title: target.repoName, badge: target.tool,
                     isMain: true, order: -1, done: false, outcome: nil),
            ])
            return Snapshot(lanes: [lane], meta: WatchWorkflowMeta(), returned: 0, total: 1)
        }
    }

    /// Replay the journal into lanes. `started` takes the lowest freed lane (that
    /// is the handoff — the previous occupant just returned) or opens a new one;
    /// `result` frees the agent's lane. The journal carries no explicit parent
    /// links, so temporal handoff IS the lineage signal — matching how pipelined
    /// stages actually spawn (stage N+1 starts the moment stage N returns).
    nonisolated static func assignLanes(events: [WatchJournal.Event]) -> [[String]] {
        var lanes: [[String]] = []
        var laneOf: [String: Int] = [:]
        var free: [Int] = []
        for event in events {
            switch event.kind {
            case .started:
                guard laneOf[event.agentId] == nil else { continue }
                let lane: Int
                if free.isEmpty {
                    lanes.append([])
                    lane = lanes.count - 1
                } else {
                    free.sort()
                    lane = free.removeFirst()
                }
                lanes[lane].append(event.agentId)
                laneOf[event.agentId] = lane
            case .result:
                if let lane = laneOf[event.agentId], !free.contains(lane) { free.append(lane) }
            }
        }
        return lanes
    }

    nonisolated static func agentFiles(in dir: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { $0.hasPrefix("agent-") && $0.hasSuffix(".jsonl") }
            .sorted().map { (dir as NSString).appendingPathComponent($0) }
    }

    nonisolated static func agentId(of path: String) -> String {
        let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return base.hasPrefix("agent-") ? String(base.dropFirst("agent-".count)) : base
    }

    /// A live session's own Agent-tool subagents: `<sessionDir>/subagents/agent-*.jsonl`
    /// with recent activity. Workflow transcripts live deeper (`subagents/workflows/…`)
    /// and are watched via their own workflow card — not duplicated here.
    nonisolated static func recentSubagentFiles(mainTranscript: String,
                                                now: Date = Date()) -> [String] {
        let sessionDir = (mainTranscript as NSString).deletingPathExtension
        let dir = (sessionDir as NSString).appendingPathComponent("subagents")
        return agentFiles(in: dir).filter { path in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let m = attrs[.modificationDate] as? Date else { return false }
            return now.timeIntervalSince(m) < AgentProbe.retentionWindow
        }
    }
}
