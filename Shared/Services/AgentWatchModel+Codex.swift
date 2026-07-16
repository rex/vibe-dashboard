// AgentWatchModel+Codex.swift — Codex parent/subagent workflow lane discovery.

import Foundation

extension AgentWatchModel {
    /// Codex has no journal equivalent that describes handoff slots. Its parent
    /// `session_id` relationship is still explicit, so each known rollout gets a
    /// stable vertical lane and a newly spawned child joins the open window on the
    /// next discovery pass.
    nonisolated static func codexWorkflowSnapshot(
        target: AgentWatchTarget, prior: Snapshot, existing: [String: WatchPane]
    ) -> Snapshot {
        let discovered = target.workflowId.map {
            CodexTranscriptProbe.workflowPaths(parentID: $0, adjacentTo: target.transcriptPath)
        } ?? []
        var paths: [String] = []
        for path in [target.transcriptPath] + target.memberTranscriptPaths + discovered
            where !paths.contains(path) {
            paths.append(path)
        }

        var laneByPath: [String: Int] = [:]
        for lane in prior.lanes {
            guard let segment = lane.segments.first else { continue }
            laneByPath[segment.path] = lane.id
        }
        var nextID = max(0, (laneByPath.values.max() ?? -1) + 1)
        var lanes: [WatchLane] = []
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let isParent = path == target.transcriptPath
            let laneID: Int
            if let existing = laneByPath[path] {
                laneID = existing
            } else if isParent, !laneByPath.values.contains(0) {
                laneID = 0
                nextID = max(nextID, 1)
            } else {
                laneID = nextID
                nextID += 1
            }
            let link = CodexTranscriptProbe.link(for: path)
            let title = isParent ? "parent session" : "subagent \(link.id.prefix(7))"
            var pane = existing[path] ?? WatchPane(path: path, title: title,
                                                    badge: isParent ? "codex" : "subagent")
            pane.isMain = isParent
            pane.order = laneID
            pane.done = false
            pane.outcome = nil
            lanes.append(WatchLane(id: laneID, segments: [pane]))
        }
        lanes.sort { $0.id < $1.id }
        return Snapshot(lanes: lanes, meta: WatchWorkflowMeta(), returned: 0, total: lanes.count)
    }
}
