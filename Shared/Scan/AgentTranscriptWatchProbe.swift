// AgentTranscriptWatchProbe.swift - read a focused transcript/workflow for the watch sheet.

import Foundation

enum TranscriptEventKind: String, Sendable, Hashable { case text, toolUse, toolResult, meta }

struct TranscriptEvent: Identifiable, Sendable, Hashable {
    var id: String
    var kind: TranscriptEventKind
    var role: String
    var title: String
    var body: String
    var timestamp: Date?
    var isError: Bool = false
}

struct TranscriptPane: Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var path: String
    var phaseIndex: Int
    var events: [TranscriptEvent]
}

enum AgentTranscriptWatchProbe {
    private static var fm: FileManager { .default }
    private static let maxBytes = 512 * 1024
    private static let maxEvents = 160
    private static let phaseGap: TimeInterval = 5

    private struct PaneSnapshot {
        var path: String
        var title: String
        var subtitle: String
        var firstActivity: Date?
        var events: [TranscriptEvent]
    }

    private struct EventPayload {
        var role: String
        var title: String
        var body: String
        var isError = false
    }

    static func panes(path: String, kind: AgentSessionKind) -> [TranscriptPane] {
        let paths = panePaths(path: path, kind: kind)
        let raw = paths.compactMap { pane(path: $0) }
            .sorted { ($0.firstActivity ?? .distantPast) < ($1.firstActivity ?? .distantPast) }
        var phase = 1
        var previous: Date?
        return raw.map { item in
            if let previous, let current = item.firstActivity,
               current.timeIntervalSince(previous) > phaseGap { phase += 1 }
            if let current = item.firstActivity { previous = current }
            return TranscriptPane(
                id: item.path,
                title: item.title,
                subtitle: item.subtitle,
                path: item.path,
                phaseIndex: phase,
                events: item.events
            )
        }
    }

    private static func panePaths(path: String, kind: AgentSessionKind) -> [String] {
        guard kind == .workflow else { return [path] }
        let dir = (path as NSString).deletingLastPathComponent
        let files = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        let agentFiles = files.filter { $0.hasPrefix("agent-") && $0.hasSuffix(".jsonl") }
        return agentFiles.map { (dir as NSString).appendingPathComponent($0) }.sorted()
    }

    private static func pane(path: String) -> PaneSnapshot? {
        guard fm.fileExists(atPath: path) else { return nil }
        let text = readSuffix(path, bytes: maxBytes)
        let parsedEvents = Array(lines(text).flatMap { events(from: $0) }.suffix(maxEvents))
        let title = titleFor(path: path)
        let first = parsedEvents.compactMap { $0.timestamp }.min()
        let subtitle = subtitleFor(path: path, events: parsedEvents)
        return PaneSnapshot(path: path, title: title, subtitle: subtitle,
                            firstActivity: first, events: parsedEvents)
    }

    private static func events(from line: String) -> [TranscriptEvent] {
        guard let obj = object(line) else { return [] }
        let ts = (obj["timestamp"] as? String).flatMap(AgentTranscriptProbe.parseTimestamp)
        let role = ((obj["message"] as? [String: Any])?["role"] as? String)
            ?? (obj["type"] as? String) ?? "event"
        let base = "\(obj["uuid"] as? String ?? UUID().uuidString)"
        guard let message = obj["message"] as? [String: Any] else {
            if let content = obj["content"] as? String, !content.isEmpty {
                return [event(id: base, kind: .meta,
                              payload: EventPayload(role: role, title: obj["type"] as? String ?? "event",
                                                    body: content),
                              timestamp: ts)]
            }
            return []
        }
        if let content = message["content"] as? String, !content.isEmpty {
            return [event(id: base, kind: .text,
                          payload: EventPayload(role: role, title: role, body: content),
                          timestamp: ts)]
        }
        guard let blocks = message["content"] as? [[String: Any]] else { return [] }
        return blocks.enumerated().compactMap { index, block in
            let id = base + ":\(index)"
            switch block["type"] as? String {
            case "text":
                return event(id: id, kind: .text,
                             payload: EventPayload(role: role, title: role,
                                                   body: block["text"] as? String ?? ""),
                             timestamp: ts)
            case "tool_use":
                let name = block["name"] as? String ?? "tool"
                return event(id: id, kind: .toolUse,
                             payload: EventPayload(role: role, title: name,
                                                   body: pretty(block["input"])),
                             timestamp: ts)
            case "tool_result":
                let isError = block["is_error"] as? Bool ?? false
                return event(id: id, kind: .toolResult,
                             payload: EventPayload(role: role, title: "tool result",
                                                   body: contentString(block["content"]),
                                                   isError: isError),
                             timestamp: ts)
            default:
                return nil
            }
        }
    }

    private static func event(id: String, kind: TranscriptEventKind,
                              payload: EventPayload, timestamp: Date?) -> TranscriptEvent {
        TranscriptEvent(id: id, kind: kind, role: payload.role, title: payload.title,
                        body: payload.body.trimmingCharacters(in: .whitespacesAndNewlines),
                        timestamp: timestamp, isError: payload.isError)
    }

    private static func titleFor(path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private static func subtitleFor(path: String, events: [TranscriptEvent]) -> String {
        let dir = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let now = Date()
        let last = events.compactMap { $0.timestamp }.max().map { RelTime.ago($0, now: now) } ?? "no events"
        return "\(dir) · \(events.count) events · \(last)"
    }

    private static func contentString(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let blocks = value as? [[String: Any]] {
            return blocks.map { block in
                switch block["type"] as? String {
                case "text": return block["text"] as? String ?? ""
                case "image": return "[image]"
                default: return pretty(block)
                }
            }.joined(separator: "\n")
        }
        return pretty(value)
    }

    private static func pretty(_ value: Any?) -> String {
        guard let value else { return "" }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        else { return String(describing: value) }
        return String(decoding: data, as: UTF8.self)
    }

    private static func readSuffix(_ path: String, bytes: Int) -> String {
        guard let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? fh.seek(toOffset: offset)
        return String(decoding: (try? fh.readToEnd()) ?? Data(), as: UTF8.self)
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
