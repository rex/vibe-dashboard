// AgentWatchModel+Discovery.swift — filesystem + journal → lanes.
//
// LANE IDENTITY IS SACRED: boxes (and the panes the user is reading) are matched
// by lane id across ticks, so an id must never drift to a different agent's
// stream. Workflow lanes take their id from the journal replay slot (append-only,
// deterministic); standard-session lanes stick to their FILE for the life of the
// window; on-disk-but-unjournaled extras live in their own id space.

import Foundation

extension AgentWatchModel {
    /// Lane ids for agent files that are on disk but not in the journal live in
    /// their own id space so they can never collide with (or reshuffle) the
    /// journal's replay-slot ids.
    nonisolated static let extraLaneBase = 1_000

    /// Enumerate transcripts + journal + plan sidecars and shape them into lanes.
    /// Existing segments keep their tail state; agents that appear mid-watch join
    /// a freed lane (the hop) or open a new one (a wider fan-out).
    ///
    /// LANE IDENTITY IS SACRED: boxes (and the panes the user is reading) are
    /// matched by lane id across ticks, so an id must never drift to a different
    /// agent's stream. Workflow lanes take their id from the journal replay slot
    /// (append-only, deterministic); standard-session lanes stick to their FILE
    /// for the life of the window.
    nonisolated static func discoverLanes(target: AgentWatchTarget, prior: Snapshot,
                                          now: Date = Date()) -> Snapshot {
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
            var extras: [String: WatchPane] = [:]   // path → on disk but not (yet) in the journal
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
                else { extras[path] = p }
            }
            // Slot lanes keep their replay-slot index as id even while a slot's
            // agent file hasn't appeared yet — compressing out the gap used to
            // renumber every lane after it, and their panes jumped between boxes
            // when the missing file landed.
            var lanes: [WatchLane] = []
            for (slot, agentIds) in assignLanes(events: journal.events).enumerated() {
                let segments = agentIds.compactMap { byAgentId[$0] }
                if !segments.isEmpty { lanes.append(WatchLane(id: slot, segments: segments)) }
            }
            let priorExtraIds: [String: Int] = prior.lanes.reduce(into: [:]) { acc, lane in
                if lane.id >= extraLaneBase, let p = lane.segments.first { acc[p.path] = lane.id }
            }
            var nextExtraId = max(extraLaneBase - 1, priorExtraIds.values.max() ?? 0) + 1
            var shownExtras = 0
            for (path, p) in extras.sorted(by: { $0.key < $1.key }) {
                let id: Int
                if let kept = priorExtraIds[path] {
                    id = kept
                } else if prior.pendingExtras.contains(path) {
                    id = nextExtraId
                    nextExtraId += 1
                } else {
                    continue   // first sighting — its journal line is almost certainly in flight
                }
                lanes.append(WatchLane(id: id, segments: [p]))
                shownExtras += 1
            }
            lanes.sort { $0.id < $1.id }
            return Snapshot(lanes: lanes, meta: meta,
                            returned: journal.results.count,
                            total: max(journal.startOrder.count, byAgentId.count + shownExtras),
                            pendingExtras: Set(extras.keys))

        case .standard where target.tool == "claude-code":
            var lanes = [WatchLane(id: 0, segments: [
                pane(path: target.transcriptPath, title: target.repoName, badge: target.tool,
                     isMain: true, order: -1, done: false, outcome: nil),
            ])]
            // Subagent lanes are keyed by FILE, not by list position. Agent ids
            // are random hex, so a new wave's files interleave alphabetically —
            // positional ids shifted almost every lane and a completed pane
            // "reset" into a different agent's stream (a 19-subagent, 3-wave
            // session hit this live). Once a file has a lane it keeps it for the
            // life of the window; the recency filter only gates NEW admissions,
            // and new agents append after the highest existing id.
            var idOf: [String: Int] = [:]
            for lane in prior.lanes {
                guard let seg = lane.segments.first, !seg.isMain else { continue }
                idOf[seg.path] = lane.id
            }
            var nextId = (idOf.values.max() ?? 0) + 1
            let kept = idOf.keys.filter { FileManager.default.fileExists(atPath: $0) }
            let fresh = recentSubagentFiles(mainTranscript: target.transcriptPath, now: now)
            for path in Set(kept).union(fresh).sorted() {
                let id: Int
                if let existing = idOf[path] {
                    id = existing
                } else {
                    id = nextId
                    nextId += 1
                }
                let m = WatchAgentMeta.read(transcriptPath: path)
                lanes.append(WatchLane(id: id, segments: [
                    pane(path: path,
                         title: m.description
                             ?? WatchAgentMeta.promptTitle(transcriptPath: path)
                             ?? "subagent \(agentId(of: path).prefix(7))",
                         badge: m.agentType ?? "subagent",
                         isMain: false, order: .max, done: false, outcome: nil),
                ]))
            }
            lanes.sort { $0.id < $1.id }
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
