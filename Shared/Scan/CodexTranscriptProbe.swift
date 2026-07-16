// CodexTranscriptProbe.swift — parent/child rollout grouping for Codex Desktop.

import Foundation

/// Codex writes every session as a rollout in a date directory. A subagent keeps
/// its own `id` but records the originating thread in `session_id`; that durable
/// link is the workflow contract used by both the fleet card and watch window.
enum CodexTranscriptProbe {
    struct Link: Sendable {
        var id: String
        var parentID: String
        var isSubagent: Bool
    }

    private struct Rollout {
        var session: AgentProbe.Session
        var link: Link
    }

    static func sessions(root: String, now: Date) -> [AgentProbe.Session] {
        let rollouts = rolloutFiles(in: root).compactMap { path -> Rollout? in
            guard let session = AgentTranscriptProbe.session(path: path, tool: "codex", now: now) else {
                return nil
            }
            let fallback = session.id.replacingOccurrences(of: "codex:", with: "")
            return Rollout(session: session, link: link(for: path, fallbackID: fallback))
        }
        let families = Dictionary(grouping: rollouts, by: { $0.link.parentID })
        return families.values.flatMap { family in
            guard family.count > 1, family.contains(where: { $0.link.isSubagent }) else {
                return family.map(\.session)
            }
            return [workflow(from: family, now: now)]
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Read the members that share `parentID` from the active rollout date
    /// directory. Watch discovery repeats this cheaply so a child spawned after a
    /// watch window opens becomes a new vertical pane without reopening the window.
    static func workflowPaths(parentID: String, adjacentTo transcriptPath: String,
                              now: Date = Date()) -> [String] {
        let dir = (transcriptPath as NSString).deletingLastPathComponent
        let members = rolloutFiles(in: dir).filter {
            link(for: $0).parentID == parentID && isRecent($0, now: now)
        }
        return members.sorted {
            let left = link(for: $0)
            let right = link(for: $1)
            if left.isSubagent != right.isSubagent { return !left.isSubagent }
            return left.id < right.id
        }
    }

    static func link(for path: String) -> Link {
        let fallback = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return link(for: path, fallbackID: fallback)
    }

    private static func workflow(from family: [Rollout], now: Date) -> AgentProbe.Session {
        let parentID = family[0].link.parentID
        let parent = family.first { !$0.link.isSubagent && $0.link.id == parentID }
        let newest = family.max { $0.session.lastActivity < $1.session.lastActivity } ?? family[0]
        var grouped = parent?.session ?? newest.session
        grouped.id = "codex:wf:\(parentID)"
        grouped.kind = .workflow
        grouped.workflowId = parentID
        grouped.lastActivity = newest.session.lastActivity
        grouped.state = AgentProbe.lifecycle(age: now.timeIntervalSince(newest.session.lastActivity)) ?? .idle
        grouped.telemetry = newest.session.telemetry
        grouped.agentCount = family.count
        grouped.transcriptPath = parent?.session.transcriptPath ?? newest.session.transcriptPath
        grouped.memberTranscriptPaths = family.sorted {
            if $0.link.isSubagent != $1.link.isSubagent { return !$0.link.isSubagent }
            return $0.link.id < $1.link.id
        }
        .compactMap(\.session.transcriptPath)
        return grouped
    }

    private static func rolloutFiles(in root: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        var paths: [String] = []
        for case let relative as String in enumerator {
            let name = (relative as NSString).lastPathComponent
            guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
            let path = (root as NSString).appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                paths.append(path)
            }
        }
        return paths
    }

    private static func isRecent(_ path: String, now: Date) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date
        else { return false }
        // Keep the same grace period as the transcript probe: a just-written
        // rollout can have a stale event timestamp while its file is still live.
        return now.timeIntervalSince(modified) < AgentProbe.retentionWindow + 10 * 60
    }

    private static func link(for path: String, fallbackID: String) -> Link {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return Link(id: fallbackID, parentID: fallbackID, isSubagent: false)
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "session_meta",
                  let payload = object["payload"] as? [String: Any]
            else { continue }
            let id = (payload["id"] as? String) ?? fallbackID
            let parentID = (payload["session_id"] as? String) ?? id
            let source = payload["thread_source"] as? String
            return Link(id: id, parentID: parentID, isSubagent: source == "subagent" || id != parentID)
        }
        return Link(id: fallbackID, parentID: fallbackID, isSubagent: false)
    }
}
