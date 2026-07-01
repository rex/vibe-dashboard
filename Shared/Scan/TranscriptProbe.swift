// TranscriptProbe.swift — best-effort skill-application EVIDENCE from Claude Code
// transcripts, for the human-gated backfill. This is NOT a source of truth: it
// only finds where a `/lang-*` or `/tool-*` skill was actually EXECUTED (a real
// `Skill` tool-use event, not a mention), which is incomplete (misses /scaffold-
// applied, other-agent, other-machine, older sessions) and sometimes imprecise
// (cwd can be a workspace root). It exists to help you RECORD provenance into
// VIBE.yaml — the permanent record — with your confirmation, never automatically.

import Foundation

struct SkillEvidence: Sendable, Hashable, Identifiable {
    var repoPath: String   // the transcript's cwd (absolute)
    var skillId: String
    var count: Int
    var lastSeen: String   // YYYY-MM-DD
    var id: String { repoPath + "·" + skillId }
}

enum TranscriptProbe {
    private static var fm: FileManager { .default }
    private static var projectsDir: String { (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects") }

    /// The currently-installed version of a skill (best-known "applied" version
    /// for a backfilled entry — the exact apply-time version isn't in transcripts).
    static func installedVersion(_ skillId: String) -> String? {
        let p = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/skills/\(skillId)/VERSION")
        guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { return nil }
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    static func scan() async -> [SkillEvidence] {
        await withCheckedContinuation { (cont: CheckedContinuation<[SkillEvidence], Never>) in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: scanSync()) }
        }
    }

    private static func scanSync() -> [SkillEvidence] {
        guard let dirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return [] }
        var agg: [String: SkillEvidence] = [:]   // key: cwd|skill
        for dir in dirs {
            let dpath = (projectsDir as NSString).appendingPathComponent(dir)
            guard let files = try? fm.contentsOfDirectory(atPath: dpath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let fpath = (dpath as NSString).appendingPathComponent(file)
                guard let content = try? String(contentsOfFile: fpath, encoding: .utf8) else { continue }
                for line in content.split(separator: "\n") where line.contains("\"name\":\"Skill\"") {
                    ingest(String(line), into: &agg)
                }
            }
        }
        return Array(agg.values)
    }

    private static func ingest(_ line: String, into agg: inout [String: SkillEvidence]) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cwd = obj["cwd"] as? String, !cwd.isEmpty,
              let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]] else { return }
        let ts = (obj["timestamp"] as? String).map { String($0.prefix(10)) } ?? ""
        for block in content
            where (block["type"] as? String) == "tool_use" && (block["name"] as? String) == "Skill" {
            guard let input = block["input"] as? [String: Any],
                  let skill = input["skill"] as? String,
                  skill.hasPrefix("lang-") || skill.hasPrefix("tool-") else { continue }
            let key = cwd + "|" + skill
            var e = agg[key] ?? SkillEvidence(repoPath: cwd, skillId: skill, count: 0, lastSeen: "")
            e.count += 1
            if ts > e.lastSeen { e.lastSeen = ts }
            agg[key] = e
        }
    }
}
