// AgentTranscriptProbe.swift - JSONL-backed live coding-agent session detection.

import Foundation

enum AgentTranscriptProbe {
    private static var fm: FileManager { .default }
    private static let mtimeSlack: TimeInterval = 10 * 60
    private static let headBytes = 256 * 1024
    private static let tailBytes = 1024 * 1024
    nonisolated(unsafe) private static let fractionalISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Claude sessions, collapsed to the units a human thinks in: one card per MAIN
    /// session (its subagents/workflow children extend its liveness rather than
    /// spawning their own cards), plus one card per live WORKFLOW (grouped by its
    /// directory — never one card per workflow agent file). A subagent whose parent
    /// session file is missing still surfaces on its own rather than vanishing.
    static func claudeSessions(
        root: String = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects"),
        now: Date
    ) -> [AgentProbe.Session] {
        var mains: [String] = []
        var workflowAgents: [String: [String]] = [:]   // workflow dir → agent-*.jsonl
        var subagents: [String] = []
        for path in jsonlFiles(under: root) {
            switch transcriptShape(path: path, tool: "claude-code").kind {
            case .standard:
                mains.append(path)
            case .workflow where isAgentFile(path):
                workflowAgents[(path as NSString).deletingLastPathComponent, default: []].append(path)
            case .subagent where isAgentFile(path):
                subagents.append(path)
            default:
                break   // journal.jsonl and other sidecars are not sessions
            }
        }

        // Newest child write per parent session file — a main session whose workflow
        // has been grinding for 90 minutes is still ACTIVE even if its own transcript
        // went quiet (results only land in it when the workflow returns).
        var childActivity: [String: Date] = [:]
        for child in subagents + workflowAgents.values.flatMap({ $0 }) {
            guard let parent = parentSessionFile(of: child), let m = mtime(child) else { continue }
            if childActivity[parent].map({ m > $0 }) ?? true { childActivity[parent] = m }
        }

        var out: [AgentProbe.Session] = []
        var liveParents = Set<String>()
        for main in mains {
            guard let s = session(path: main, tool: "claude-code", now: now,
                                  descendantActivity: childActivity[main]) else { continue }
            out.append(s)
            liveParents.insert(main)
        }
        for (dir, files) in workflowAgents {
            if let s = workflowSession(dir: dir, files: files, now: now) { out.append(s) }
        }
        for orphan in subagents where parentSessionFile(of: orphan).map({ !liveParents.contains($0) }) ?? true {
            if let s = session(path: orphan, tool: "claude-code", now: now) { out.append(s) }
        }
        return out.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// One session for a whole workflow: representative = the newest-written agent
    /// transcript (its embedded timestamps drive lifecycle), identity = the workflow
    /// id, so the Agents grid shows "the workflow", not eight agent-file cards.
    static func workflowSession(dir: String, files: [String], now: Date) -> AgentProbe.Session? {
        let newest = files
            .filter { recentlyTouched($0, now: now) }
            .max { (mtime($0) ?? .distantPast) < (mtime($1) ?? .distantPast) }
        guard let newest, var s = session(path: newest, tool: "claude-code", now: now) else { return nil }
        s.id = "claude-code:wf:" + (s.workflowId ?? (dir as NSString).lastPathComponent)
        return s
    }

    static func isAgentFile(_ path: String) -> Bool {
        (path as NSString).lastPathComponent.hasPrefix("agent-")
    }

    /// `…/projects/<slug>/<session>/subagents/…/agent-x.jsonl` → the parent session's
    /// own transcript `…/projects/<slug>/<session>.jsonl`. Nil when the path has no
    /// `subagents` ancestor.
    static func parentSessionFile(of path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let idx = parts.firstIndex(of: "subagents"), idx >= 1 else { return nil }
        return "/" + parts[..<idx].joined(separator: "/") + ".jsonl"
    }

    static func codexSessions(
        root: String = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/sessions"),
        now: Date
    ) -> [AgentProbe.Session] {
        transcriptSessions(paths: jsonlFiles(under: root), tool: "codex", now: now)
    }

    static func transcriptSessions(paths: [String], tool: String, now: Date) -> [AgentProbe.Session] {
        paths.compactMap { session(path: $0, tool: tool, now: now) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// `descendantActivity`: the newest write among the session's child transcripts
    /// (subagents / workflow agents). It extends the session's life and its shown
    /// "last activity" — the parent transcript goes quiet while children work, and
    /// idling out a session mid-workflow would be a lie.
    ///
    /// Content-derived facts are CACHED on (mtime, size): detection runs every few
    /// seconds while agents stream, and re-reading ~1.25 MB per recent transcript
    /// per pass burned a steady ~20% of a core. Lifecycle stays time-derived.
    static func session(path: String, tool: String, now: Date,
                        descendantActivity: Date? = nil) -> AgentProbe.Session? {
        let childRecent = descendantActivity
            .map { now.timeIntervalSince($0) < AgentProbe.retentionWindow + mtimeSlack } ?? false
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        let recentOwn = now.timeIntervalSince(mtime) < AgentProbe.retentionWindow + mtimeSlack
        guard recentOwn || childRecent else { return nil }

        let size = (attrs[.size] as? UInt64) ?? 0
        let facts = TranscriptFactsCache.facts(path: path, mtime: mtime, size: size) {
            parseFacts(path: path, tool: tool)
        }
        guard let last = [facts.last, descendantActivity].compactMap({ $0 }).max(),
              let state = AgentProbe.lifecycle(age: now.timeIntervalSince(last)),
              let cwd = facts.cwd, !cwd.isEmpty else { return nil }

        let shape = transcriptShape(path: path, tool: tool)
        return AgentProbe.Session(
            id: "\(tool):\(facts.sessionKey ?? (path as NSString).lastPathComponent)",
            pid: 0,
            tool: tool,
            cwd: normalizedPath(cwd),
            elapsed: RelTime.compact(now.timeIntervalSince(facts.start ?? last)),
            lastActivity: last,
            state: state,
            kind: shape.kind,
            transcriptPath: path,
            workflowId: shape.workflowId,
            telemetry: facts.telemetry
        )
    }

    /// The expensive part — head+tail reads and line parsing. Pure function of the
    /// file content; called only when (mtime, size) changed.
    private static func parseFacts(path: String, tool: String) -> TranscriptFacts {
        let head = readPrefix(path, bytes: headBytes)
        let tail = readSuffix(path, bytes: tailBytes)
        var f = TranscriptFacts()
        f.last = newestTimestamp(in: tail) ?? newestTimestamp(in: head)
        f.cwd = newestCwd(in: tail) ?? firstCwd(in: head)
        f.start = firstTimestamp(in: head) ?? f.last
        f.sessionKey = sessionIdentifier(head: head, tail: tail)
        f.telemetry = SessionTelemetry.read(tail: tail, tool: tool)
        return f
    }

    static func normalizedPath(_ path: String) -> String {
        var resolved = ((path as NSString).expandingTildeInPath as NSString).resolvingSymlinksInPath
        while resolved.count > 1 && resolved.hasSuffix("/") { resolved.removeLast() }
        return resolved
    }

    static func jsonStringValues(in text: String, key: String) -> [String] {
        let needle = "\"\(key)\""
        var values: [String] = []
        var searchStart = text.startIndex
        while let keyRange = text.range(of: needle, range: searchStart..<text.endIndex) {
            var i = keyRange.upperBound
            skipWhitespace(text, &i)
            guard i < text.endIndex, text[i] == ":" else {
                searchStart = keyRange.upperBound
                continue
            }
            i = text.index(after: i)
            skipWhitespace(text, &i)
            guard i < text.endIndex, text[i] == "\"" else {
                searchStart = i
                continue
            }
            i = text.index(after: i)
            var value = ""
            var escaped = false
            while i < text.endIndex {
                let ch = text[i]
                if escaped {
                    value.append(ch)
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    values.append(value)
                    break
                } else {
                    value.append(ch)
                }
                i = text.index(after: i)
            }
            searchStart = i
        }
        return values
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        RelTime.iso.date(from: raw) ?? fractionalISO.date(from: raw)
    }

    static func transcriptShape(path: String, tool: String) -> (kind: AgentSessionKind, workflowId: String?) {
        guard tool == "claude-code" else { return (.standard, nil) }
        let parts = normalizedPath(path).split(separator: "/").map(String.init)
        guard let subagents = parts.firstIndex(of: "subagents") else { return (.standard, nil) }
        let afterSubagents = parts.index(after: subagents)
        if afterSubagents < parts.endIndex, parts[afterSubagents] == "workflows" {
            let workflowIndex = parts.index(after: afterSubagents)
            if workflowIndex < parts.endIndex, parts[workflowIndex].hasPrefix("wf_") {
                return (.workflow, parts[workflowIndex])
            }
            return (.workflow, nil)
        }
        return (.subagent, nil)
    }

    private static func recentlyTouched(_ path: String, now: Date) -> Bool {
        guard let m = mtime(path) else { return false }
        return now.timeIntervalSince(m) < AgentProbe.retentionWindow + mtimeSlack
    }

    private static func mtime(_ path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private static func jsonlFiles(under root: String) -> [String] {
        guard let enumerator = fm.enumerator(atPath: root) else { return [] }
        var paths: [String] = []
        for case let rel as String in enumerator where rel.hasSuffix(".jsonl") {
            let abs = (root as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: abs, isDirectory: &isDir), !isDir.boolValue {
                paths.append(abs)
            }
        }
        return paths
    }

    private static func readPrefix(_ path: String, bytes: Int) -> String {
        guard let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? fh.close() }
        let data = (try? fh.read(upToCount: bytes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func readSuffix(_ path: String, bytes: Int) -> String {
        guard let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? fh.seek(toOffset: offset)
        let data = (try? fh.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func firstTimestamp(in text: String) -> Date? {
        for line in lines(text) {
            if let ts = timestamp(in: object(line)) { return ts }
        }
        return jsonStringValues(in: text, key: "timestamp").first.flatMap(parseTimestamp)
    }

    private static func newestTimestamp(in text: String) -> Date? {
        for line in lines(text).reversed() {
            if let ts = timestamp(in: object(line)) { return ts }
        }
        return jsonStringValues(in: text, key: "timestamp").last.flatMap(parseTimestamp)
    }

    private static func firstCwd(in text: String) -> String? {
        for line in lines(text) {
            if let value = string(in: object(line), keys: ["cwd"]) { return value }
        }
        return jsonStringValues(in: text, key: "cwd").first
    }

    private static func newestCwd(in text: String) -> String? {
        for line in lines(text).reversed() {
            if let value = string(in: object(line), keys: ["cwd"]) { return value }
        }
        return jsonStringValues(in: text, key: "cwd").last
    }

    private static func firstString(in text: String, keys: [String]) -> String? {
        for line in lines(text) {
            if let value = string(in: object(line), keys: keys) { return value }
        }
        for key in keys {
            if let value = jsonStringValues(in: text, key: key).first { return value }
        }
        return nil
    }

    private static func newestString(in text: String, keys: [String]) -> String? {
        for line in lines(text).reversed() {
            if let value = string(in: object(line), keys: keys) { return value }
        }
        for key in keys {
            if let value = jsonStringValues(in: text, key: key).last { return value }
        }
        return nil
    }

    private static func sessionIdentifier(head: String, tail: String) -> String? {
        for line in lines(head) + lines(tail) {
            guard let obj = object(line), obj["type"] as? String == "session_meta" else { continue }
            if let value = string(in: obj, keys: ["sessionId", "session_id", "id"]) { return value }
        }
        return newestString(in: tail, keys: ["sessionId", "session_id"])
            ?? firstString(in: head, keys: ["sessionId", "session_id", "id"])
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func timestamp(in obj: [String: Any]?) -> Date? {
        guard let raw = string(in: obj, keys: ["timestamp"]) else { return nil }
        return parseTimestamp(raw)
    }

    private static func string(in obj: [String: Any]?, keys: [String]) -> String? {
        guard let obj else { return nil }
        for key in keys {
            if let value = obj[key] as? String, !value.isEmpty { return value }
        }
        if let payload = obj["payload"] as? [String: Any] {
            for key in keys {
                if let value = payload[key] as? String, !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func skipWhitespace(_ text: String, _ i: inout String.Index) {
        while i < text.endIndex, text[i].isWhitespace {
            i = text.index(after: i)
        }
    }
}
