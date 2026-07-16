// AgentProbe.swift — best-effort detection of live coding-agent sessions.
//
// Heuristic: scan running processes for a coding-agent CLI (claude/codex/aider/
// gemini/opencode), resolve each one's working directory via `lsof`, and map it
// onto a scanned repo. For a matched session we measure the REAL uncommitted diff
// (`git diff --numstat HEAD`) and the newest working-tree mtime — no constants.
// This is a signal, not a guarantee — a headless agent with a detached cwd may be
// missed, and precision is preferred over recall (a false "live session" is a bug).

import Foundation

/// A session's lifecycle stage from its last activity. A session > `retentionWindow`
/// idle is COMPLETE and no longer surfaced at all (dropped by the probe).
enum AgentState: String, Sendable, Hashable { case active, idle }

enum AgentSessionKind: String, Sendable, Hashable, Codable {
    case standard, subagent, workflow
}

enum AgentProbe {
    /// Pierce's lifecycle spec: a session is ACTIVE for 15 min after its last activity,
    /// then IDLE up to 1 hour, then COMPLETE (dropped — no longer shown).
    static let activeWindow: TimeInterval = 15 * 60
    static let retentionWindow: TimeInterval = 60 * 60

    struct Session: Sendable {
        var id: String
        var pid: Int
        var tool: String        // claude-code | codex | aider | gemini | opencode
        var cwd: String
        var elapsed: String
        var lastActivity: Date
        var state: AgentState
        var kind: AgentSessionKind = .standard
        var transcriptPath: String? = nil
        var workflowId: String? = nil
        var agentCount: Int? = nil   // workflow cards: agent transcripts currently in play
        var memberTranscriptPaths: [String] = []  // workflow panes, parent first when known
        var telemetry = SessionTelemetry()   // model / effort / context tokens (nil = not recorded)
    }

    /// Measured, uncommitted work for a live session — every field is real.
    struct WorkStat: Sendable {
        var filesTouched: Int = 0
        var linesAdded: Int = 0
        var linesRemoved: Int = 0
        var lastWrite: Date? = nil    // newest mtime among changed/untracked files
        var measured: Bool = false    // did `git diff` run? distinguishes a real 0 from "unknown"
    }

    static var fm: FileManager { .default }

    static func sessions(now: Date = Date()) async -> [Session] {
        // PRIMARY - coding agents append a transcript per session. Liveness comes from
        // the transcript's embedded event timestamps, not the file mtime: mtime can be
        // refreshed by compaction/indexing and resurrect a dead session.
        var found = claudeTranscriptSessions(now: now) + codexTranscriptSessions(now: now)
        let transcriptCwds = Set(found.map { AgentTranscriptProbe.normalizedPath($0.cwd) })
        // SUPPLEMENT — ps for OTHER agent CLIs (aider/gemini/opencode) with no transcript
        // store here. Only where no transcript already claimed the cwd.
        for s in await psSessions(now: now)
            where !transcriptCwds.contains(AgentTranscriptProbe.normalizedPath(s.cwd)) {
            found.append(s)
        }
        return found.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Live Claude sessions from transcript JSONLs under ~/.claude/projects, including
    /// nested subagent workflow transcripts.
    static func claudeTranscriptSessions(now: Date) -> [Session] {
        AgentTranscriptProbe.claudeSessions(now: now)
    }

    /// Live Codex sessions from ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl. Only today's
    /// and yesterday's date dirs are scanned (a fresh session is < 1h old), so the deep,
    /// ever-growing session archive is never enumerated.
    static func codexTranscriptSessions(now: Date) -> [Session] {
        AgentTranscriptProbe.codexSessions(now: now)
    }

    /// Lifecycle from a session's age since last activity: active (< 15m), idle (< 1h), or
    /// nil = COMPLETE (no longer surfaced). Pure + testable. A negative age (clock skew /
    /// a future mtime) is treated as active.
    static func lifecycle(age: TimeInterval) -> AgentState? {
        if age < activeWindow { return .active }        // includes negative (clock skew)
        if age < retentionWindow { return .idle }
        return nil
    }

    private static func psSessions(now: Date) async -> [Session] {
        let ps = await ProcessRunner.run("/bin/ps", ["-axo", "pid=,etime=,command="])
        guard ps.ok else { return [] }
        var found: [Session] = []
        for raw in ps.lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // "  pid  etime  command …" → [pid, etime, command]
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 3, let pid = Int(parts[0]) else { continue }
            guard let tool = matchTool(command: parts[2]), tool != "claude-code", tool != "codex" else { continue }
            guard let cwd = await cwd(of: pid), !cwd.isEmpty else { continue }
            // A live process is active by definition (ps only lists running ones).
            found.append(Session(
                id: "\(tool):\(pid)", pid: pid, tool: tool,
                cwd: AgentTranscriptProbe.normalizedPath(cwd), elapsed: humanize(parts[1]),
                lastActivity: now, state: .active
            ))
        }
        return found
    }

    /// Minimal `"key":"value"` extractor over a JSON text prefix (no full parse; these
    /// values never contain an unescaped quote). Pure + testable.
    static func extractJSONString(_ text: String, key: String) -> String? {
        AgentTranscriptProbe.jsonStringValues(in: text, key: key).first
    }

    /// Classify a process command line as a coding-agent CLI, or nil. Matches on the
    /// executable's BASENAME only — never a substring — and rejects `.app/` bundles,
    /// so "tail -f claude.log" (an arg), "~/claude-notes/x" (a path), and the
    /// Claude.app / Codex.app GUI helper processes are all correctly NOT flagged.
    static func matchTool(command: String) -> String? {
        let lower = command.lowercased()
        // GUI application bundles (Claude.app, Codex.app, "Codex Computer Use.app", …)
        // and our own app are never a terminal coding session. This single check is
        // what keeps the 35+ Electron helper processes from crying "live session".
        guard !lower.contains(".app/"), !lower.contains("vibedashboard") else { return nil }
        let exe = command.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? command
        switch ((exe as NSString).lastPathComponent).lowercased() {
        case "claude", "claude-code": return "claude-code"
        case "codex":                 return "codex"
        case "aider":                 return "aider"
        case "gemini":                return "gemini"
        case "opencode":              return "opencode"
        default:                      return nil
        }
    }

    /// Real uncommitted work for a live session: added/removed/changed-file counts
    /// from `git diff --numstat HEAD`, and the newest mtime among all touched files
    /// (incl. untracked) as an honest "last write". Runs only for detected sessions.
    static func workStat(cwd: String, now: Date) async -> WorkStat {
        var stat = WorkStat()

        // Line + file counts vs the last commit (staged + unstaged tracked changes).
        let numstat = await ProcessRunner.git(["diff", "--numstat", "HEAD"], cwd: cwd)
        if numstat.ok {
            stat.measured = true
            for row in numstat.lines {
                let cols = row.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                guard cols.count == 3, !cols[2].isEmpty else { continue }
                stat.filesTouched += 1
                stat.linesAdded += Int(cols[0]) ?? 0      // "-" for binary files → 0
                stat.linesRemoved += Int(cols[1]) ?? 0
            }
        }

        // Newest working-tree write among every touched path (incl. untracked).
        let status = await ProcessRunner.git(["status", "--porcelain"], cwd: cwd)
        if status.ok {
            var newest: Date? = nil
            for row in status.lines where row.count > 3 {
                // porcelain v1: "XY <path>" (2 status chars + space), rename "…old -> new".
                let payload = String(row.dropFirst(3))
                let path = (payload.components(separatedBy: " -> ").last ?? payload)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let abs = (cwd as NSString).appendingPathComponent(path)
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: abs),
                      let m = attrs[.modificationDate] as? Date else { continue }
                if newest == nil || m > newest! { newest = m }
            }
            stat.lastWrite = newest
        }
        return stat
    }

    /// Measure each distinct working directory once. A Codex parent and its
    /// subagents commonly share one checkout; probing per session made a busy
    /// workflow issue identical `git diff` / `git status` calls serially and held
    /// the live-refresh gate long enough to lose FSEvent updates.
    static func workStats(for sessions: [Session], now: Date) async -> [String: WorkStat] {
        let cwds = Array(Set(sessions.map { AgentTranscriptProbe.normalizedPath($0.cwd) }))
        guard !cwds.isEmpty else { return [:] }
        let byCwd = await withTaskGroup(of: (String, WorkStat).self,
                                        returning: [String: WorkStat].self) { group in
            var pending = cwds.makeIterator()
            for _ in 0..<min(4, cwds.count) {
                guard let cwd = pending.next() else { break }
                group.addTask { (cwd, await workStat(cwd: cwd, now: now)) }
            }
            var results: [String: WorkStat] = [:]
            while let (cwd, stat) = await group.next() {
                results[cwd] = stat
                if let next = pending.next() {
                    group.addTask { (next, await workStat(cwd: next, now: now)) }
                }
            }
            return results
        }
        return Dictionary(uniqueKeysWithValues: sessions.map {
            ($0.id, byCwd[AgentTranscriptProbe.normalizedPath($0.cwd)] ?? WorkStat())
        })
    }

    private static func cwd(of pid: Int) async -> String? {
        let r = await ProcessRunner.run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"])
        guard r.ok else { return nil }
        return r.lines.first { $0.hasPrefix("n/") }.map { String($0.dropFirst()) }
    }

    /// ps etime "[[DD-]HH:]MM:SS" → a composed, honest duration: "45m", "2h15m",
    /// "3d4h". Only a zero unit is dropped — a 45-minute session is "45m", never "0h".
    static func humanize(_ etime: String) -> String {
        // ps etime is only digits, ':' and a single '-'. Anything else → show raw
        // rather than fabricate a "0s"/"0h".
        guard !etime.isEmpty, etime.allSatisfy({ $0.isNumber || $0 == ":" || $0 == "-" }) else { return etime }
        var days = 0
        var rest = Substring(etime)
        if let dash = etime.firstIndex(of: "-") {
            days = Int(etime[..<dash]) ?? 0
            rest = etime[etime.index(after: dash)...]
        }
        let c = rest.split(separator: ":").map { Int($0) ?? 0 }
        let h: Int, m: Int, s: Int
        switch c.count {
        case 3: (h, m, s) = (c[0], c[1], c[2])
        case 2: (h, m, s) = (0, c[0], c[1])
        case 1: (h, m, s) = (0, 0, c[0])
        default: return etime   // unparseable — show the raw value, don't fabricate one
        }
        // Compose the two most-significant NON-zero units, largest first.
        if days > 0 { return h > 0 ? "\(days)d\(h)h" : "\(days)d" }
        if h > 0 { return m > 0 ? "\(h)h\(m)m" : "\(h)h" }
        if m > 0 { return s > 0 ? "\(m)m\(s)s" : "\(m)m" }
        return "\(s)s"
    }
}
