// AgentsViewProbe.swift — optional, read-only evidence from the AgentsView app's
// local session index (~/.agentsview/sessions.db). AgentsView continuously ingests
// Claude Code sessions, so its DB reaches months further back than the on-disk
// transcripts (which rotate away) and carries a real `cwd` column that maps to a
// repo exactly like the on-disk scan.
//
// This is a DEFENSIVE, best-effort source: if the app isn't installed, the DB is
// gone, or the schema changed, it silently yields nothing and the backfill falls
// back to on-disk transcripts. It NEVER writes — the query runs through the
// sqlite3 CLI with `-readonly`, which hard-rejects writes ("attempt to write a
// readonly database"), so it cannot corrupt or lock AgentsView's live database.

import Foundation

enum AgentsViewProbe {
    private static var dbPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".agentsview/sessions.db")
    }
    private static var sqlite3Path: String {
        ["/usr/bin/sqlite3", "/opt/homebrew/bin/sqlite3"].first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/usr/bin/sqlite3"
    }

    private static let query = """
    SELECT s.cwd AS cwd, tc.skill_name AS skill, COUNT(*) AS n, substr(MAX(s.started_at),1,10) AS last
    FROM tool_calls tc JOIN sessions s ON s.id = tc.session_id
    WHERE tc.tool_name = 'Skill'
      AND (tc.skill_name LIKE 'lang-%' OR tc.skill_name LIKE 'tool-%')
      AND s.cwd != ''
    GROUP BY s.cwd, tc.skill_name;
    """

    static func scan() async -> [SkillEvidence] {
        guard FileManager.default.fileExists(atPath: dbPath),
              FileManager.default.isExecutableFile(atPath: sqlite3Path) else { return [] }
        let r = await ProcessRunner.run(sqlite3Path, ["-readonly", "-json", dbPath, query], timeout: 30)
        guard r.ok, let data = r.stdout.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let cwd = row["cwd"] as? String, !cwd.isEmpty,
                  let skill = row["skill"] as? String, !skill.isEmpty else { return nil }
            let count = (row["n"] as? Int) ?? Int("\(row["n"] ?? "")") ?? 0
            let last = (row["last"] as? String) ?? ""
            return SkillEvidence(repoPath: cwd, skillId: skill, count: count, lastSeen: last, source: "AgentsView")
        }
    }
}
