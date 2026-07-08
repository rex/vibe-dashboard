// TranscriptProbe.swift — best-effort skill-application EVIDENCE from Claude Code
// transcripts, for the human-gated backfill. This is NOT a source of truth: it
// only finds where a skeleton-family skill (`/lang-*`, `/tool-*`, `/agentic-*`,
// `/scaffold`, `/retrofit`, `/sync-skills`) was actually EXECUTED (a real `Skill`
// tool-use event, not a mention), which is incomplete (misses other-agent,
// other-machine, older rotated-away sessions) and sometimes imprecise (cwd can be
// a workspace root). It exists to help you RECORD provenance into VIBE.yaml — the
// permanent record — with your confirmation, never automatically.

import Foundation

struct SkillEvidence: Sendable, Hashable, Identifiable {
    var repoPath: String   // the transcript's cwd (absolute)
    var skillId: String
    var count: Int
    var lastSeen: String   // YYYY-MM-DD
    var source: String = "transcript"   // "transcript" | "AgentsView" | both
    var id: String { repoPath + "·" + skillId }
}

enum TranscriptProbe {
    private static var fm: FileManager { .default }
    private static var projectsDir: String { (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects") }

    /// Aggregated evidence plus honest diagnostics: how many transcript lines
    /// matched the Skill substring but couldn't be parsed (a schema-drift signal),
    /// and whether the AgentsView source errored — so silent drops stay VISIBLE.
    struct ScanResult: Sendable {
        var evidence: [SkillEvidence] = []
        var unparsedSkillLines: Int = 0
        var agentsViewError: String?
    }

    /// Skill ids whose EXECUTION is strong provenance that a repo adopted the
    /// skeleton. Deliberately wider than lang-*/tool-*: running agentic-config,
    /// scaffold, retrofit, or sync-skills in a repo is itself an adoption signal
    /// (real transcripts show `retrofit`/`scaffold`/`agentic-*` runs the old
    /// filter discarded). This is the DISPLAY allowlist; the human Record click is
    /// the write gate, so widening here never writes anything on its own.
    static func isProvenanceSkill(_ id: String) -> Bool {
        id.hasPrefix("lang-") || id.hasPrefix("tool-") || id.hasPrefix("agentic-")
            || id == "scaffold" || id == "retrofit" || id == "sync-skills"
    }

    /// Canonical path form for comparing a session cwd to a repo's absolutePath:
    /// tilde-expanded, symlink-resolved, trailing slash stripped. BOTH sides MUST
    /// go through this or a format mismatch drops real evidence as "non-managed".
    static func normalizedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        var resolved = (expanded as NSString).resolvingSymlinksInPath
        while resolved.count > 1 && resolved.hasSuffix("/") { resolved.removeLast() }
        return resolved
    }

    /// The currently-installed version of a skill (best-known "applied" version
    /// for a backfilled entry — the exact apply-time version isn't in transcripts).
    static func installedVersion(_ skillId: String) -> String? {
        let p = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/skills/\(skillId)/VERSION")
        guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { return nil }
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// Union of on-disk transcripts + the AgentsView index (which reaches months
    /// further back and catches repos whose on-disk transcripts were rotated away).
    static func scan() async -> ScanResult {
        async let disk = diskScan()
        async let agents = AgentsViewProbe.scan()
        let d = await disk
        let a = await agents
        if d.unparsed > 0 {
            Log.scan.debug("TranscriptProbe: \(d.unparsed) Skill line(s) matched substring but failed to parse")
        }
        return ScanResult(evidence: merge(d.events + a.evidence),
                          unparsedSkillLines: d.unparsed, agentsViewError: a.error)
    }

    private static func diskScan() async -> (events: [SkillEvidence], unparsed: Int) {
        await withCheckedContinuation { (cont: CheckedContinuation<(events: [SkillEvidence], unparsed: Int), Never>) in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: scanSync()) }
        }
    }

    /// Fold duplicate (cwd, skill) evidence from both sources into one row.
    private static func merge(_ all: [SkillEvidence]) -> [SkillEvidence] {
        var agg: [String: SkillEvidence] = [:]
        for e in all {
            guard var x = agg[e.id] else { agg[e.id] = e; continue }
            x.count += e.count
            if e.lastSeen > x.lastSeen { x.lastSeen = e.lastSeen }
            if !x.source.contains(e.source) { x.source += " + " + e.source }
            agg[e.id] = x
        }
        return Array(agg.values)
    }

    private static func scanSync() -> (events: [SkillEvidence], unparsed: Int) {
        guard let dirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return ([], 0) }
        var all: [SkillEvidence] = []
        var unparsed = 0
        for dir in dirs {
            let dpath = (projectsDir as NSString).appendingPathComponent(dir)
            guard let files = try? fm.contentsOfDirectory(atPath: dpath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let fpath = (dpath as NSString).appendingPathComponent(file)
                guard let content = try? String(contentsOfFile: fpath, encoding: .utf8) else { continue }
                for line in content.split(separator: "\n") where line.contains("\"name\":\"Skill\"") {
                    let (events, dropped) = parseLine(String(line))
                    if dropped { unparsed += 1 }
                    all.append(contentsOf: events)
                }
            }
        }
        return (all, unparsed)
    }

    /// Parse ONE JSONL line for Skill tool-use evidence. Returns any events found,
    /// and `dropped == true` ONLY when the line is a top-level assistant record
    /// whose content shape is unrecognized (or the line won't JSON-decode) — the
    /// schema-drift case worth counting. A String content, an absent content, or a
    /// non-assistant record that merely quotes the tool name is a CLEAN skip
    /// (`dropped == false`) and is never counted, so the diagnostic can't cry wolf.
    static func parseLine(_ line: String) -> (events: [SkillEvidence], dropped: Bool) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], true)   // matched the substring but not decodable → a real drop
        }
        // Only assistant turns carry tool_use — filter on the top-level type first.
        guard (obj["type"] as? String) == "assistant" else { return ([], false) }
        guard let cwd = obj["cwd"] as? String, !cwd.isEmpty,
              let msg = obj["message"] as? [String: Any],
              let content = msg["content"] else { return ([], false) }
        if content is String { return ([], false) }             // string content → mention/meta, skip
        guard let blocks = content as? [[String: Any]] else { return ([], true) }  // assistant + odd shape → drift
        let ts = (obj["timestamp"] as? String).map { String($0.prefix(10)) } ?? ""
        var events: [SkillEvidence] = []
        for block in blocks
            where (block["type"] as? String) == "tool_use" && (block["name"] as? String) == "Skill" {
            guard let input = block["input"] as? [String: Any],
                  let skill = input["skill"] as? String,
                  isProvenanceSkill(skill) else { continue }
            events.append(SkillEvidence(repoPath: cwd, skillId: skill, count: 1, lastSeen: ts))
        }
        return (events, false)
    }
}
