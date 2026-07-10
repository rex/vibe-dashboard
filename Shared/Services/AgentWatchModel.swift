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

/// One lane's observable container. Lanes update INDEPENDENTLY: mutating a box
/// re-renders only that lane's subtree. Publishing a whole `[WatchLane]` array
/// instead re-rendered every lane (8-wide × hundreds of rows) on every content
/// tick (~3Hz while streaming) — the sampled 22k-layout-frames/5s main-thread
/// storm that starved the rest of the app.
@MainActor
@Observable
final class WatchLaneBox: Identifiable {
    var lane: WatchLane
    var now = Date()          // per-lane clock: bumped with content or on the slow staleness pass
    nonisolated let id: Int
    init(_ lane: WatchLane) {
        self.lane = lane
        self.id = lane.id
    }
}

@MainActor
@Observable
final class AgentWatchModel {
    private(set) var laneBoxes: [WatchLaneBox] = []   // array identity changes only on add/remove/reorder
    private(set) var workflowMeta = WatchWorkflowMeta()
    private(set) var returnedCount = 0
    private(set) var agentTotal = 0
    private(set) var streamingCount = 0   // toolbar pulse reads THIS scalar, never the lane array
    let target: AgentWatchTarget

    var lanes: [WatchLane] { laneBoxes.map(\.lane) }   // action-time snapshot (expand-all, tests)

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

    /// FSEvents nudge — coalesced to one in-flight tick + a short settle so a burst
    /// of transcript appends becomes one refresh, not a refresh per append.
    func pokeNow() {
        guard !pokePending else { return }
        pokePending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            self.pokePending = false
            await self.tick()
        }
    }

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

    /// Run one tick immediately (an FSEvents nudge) — COALESCED: streaming agents
    /// emit events several times a second, and ticking per event re-entered the
    /// observable graph continuously. One pending poke at a time.
    private var pokePending = false

    private func tick() async {
        let target = self.target
        let snapshot = Snapshot(lanes: lanes, meta: workflowMeta)
        let discover = tickCount % 4 == 0    // re-list agent files every ~3s; tail every tick
        tickCount += 1
        let updated = await Task.detached(priority: .utility) {
            Self.compute(target: target, prior: snapshot, discover: discover, now: Date())
        }.value
        // PER-LANE application: only a lane whose content changed gets its box
        // mutated — and only that lane's subtree re-renders. Nothing here writes
        // whole-window observable state on a content tick; that pattern (array
        // republish + a shared `now`) re-laid-out all 8 lanes ~3×/s while
        // streaming (sampled: 22k layout frames/5s) and starved the app.
        let wall = Date()
        if laneBoxes.count == updated.lanes.count,
           zip(laneBoxes, updated.lanes).allSatisfy({ $0.id == $1.id }) {
            for (box, fresh) in zip(laneBoxes, updated.lanes) {
                if box.lane != fresh {
                    box.lane = fresh
                    box.now = wall
                } else if wall.timeIntervalSince(box.now) > 5 {
                    box.now = wall   // slow staleness pass: streaming badge decays honestly
                }
            }
        } else {
            var existing: [Int: WatchLaneBox] = [:]
            for box in laneBoxes { existing[box.id] = box }
            laneBoxes = updated.lanes.map { fresh in
                if let box = existing[fresh.id] {
                    if box.lane != fresh { box.lane = fresh; box.now = wall }
                    return box
                }
                return WatchLaneBox(fresh)
            }
        }
        if updated.meta != workflowMeta { workflowMeta = updated.meta }
        if updated.returned != returnedCount { returnedCount = updated.returned }
        if updated.total != agentTotal { agentTotal = updated.total }
        let streaming = updated.lanes.filter { $0.isStreaming(now: wall) }.count
        if streaming != streamingCount { streamingCount = streaming }
    }

    struct Snapshot: Sendable {
        var lanes: [WatchLane]
        var meta: WatchWorkflowMeta
        var returned = 0
        var total = 0
        /// Workflow agent files seen on disk but not (yet) in the journal. A file
        /// is admitted as an "extra" lane only on its SECOND consecutive sighting —
        /// freshly spawned agents beat their own journal line to disk by well under
        /// a discovery cycle, and admitting them instantly made a lane flash into
        /// existence and immediately migrate into its replay slot.
        var pendingExtras: Set<String> = []
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
            next = discoverLanes(target: target, prior: prior, now: now)
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
}
