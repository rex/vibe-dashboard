// AgentsViewProbe.swift — optional, read-only evidence from the AgentsView app's
// local session index (~/.agentsview/sessions.db). AgentsView continuously ingests
// Claude Code sessions, so its DB reaches months further back than the on-disk
// transcripts (which rotate away) and carries a real `cwd` column that maps to a
// repo exactly like the on-disk scan.
//
// This is a DEFENSIVE, best-effort source: if the app isn't installed or the DB is
// gone it silently yields nothing and the backfill falls back to on-disk
// transcripts. But a genuine QUERY error (schema drift, a locked/corrupt DB) is no
// longer masked as "empty" — `sqlite3 -json` prints "" (not "[]") for zero rows, so
// ok+empty is a TRUE empty while a non-zero exit surfaces its stderr as a
// diagnostic, making a break in this months-deep source detectable, not invisible.
// It NEVER writes — the query runs through the sqlite3 CLI with `-readonly`, which
// hard-rejects writes ("attempt to write a readonly database"), so it can't corrupt
// or lock AgentsView's live database.

import Foundation

enum AgentsViewProbe {
    /// Evidence plus an optional error string. A nil error with empty evidence is a
    /// genuine zero-row result; a non-nil error means the query/DB failed and the
    /// source should be reported unavailable, not silently treated as empty.
    struct ScanResult: Sendable {
        var evidence: [SkillEvidence] = []
        var error: String?
    }

    private static var dbPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".agentsview/sessions.db")
    }
    private static var sqlite3Path: String {
        ["/usr/bin/sqlite3", "/opt/homebrew/bin/sqlite3"].first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/usr/bin/sqlite3"
    }

    // The WHERE mirrors TranscriptProbe.isProvenanceSkill so both evidence sources
    // surface the same skeleton-adoption family (lang-*/tool-*/agentic-* + scaffold/
    // retrofit/sync-skills). The Swift predicate is still applied per row below as
    // the authoritative gate, so the two can't drift.
    private static let query = """
    SELECT s.cwd AS cwd, tc.skill_name AS skill, COUNT(*) AS n, substr(MAX(s.started_at),1,10) AS last
    FROM tool_calls tc JOIN sessions s ON s.id = tc.session_id
    WHERE tc.tool_name = 'Skill'
      AND (tc.skill_name LIKE 'lang-%' OR tc.skill_name LIKE 'tool-%'
           OR tc.skill_name LIKE 'agentic-%'
           OR tc.skill_name IN ('scaffold', 'retrofit', 'sync-skills'))
      AND s.cwd != ''
    GROUP BY s.cwd, tc.skill_name;
    """

    static func scan() async -> ScanResult {
        guard FileManager.default.fileExists(atPath: dbPath),
              FileManager.default.isExecutableFile(atPath: sqlite3Path) else { return ScanResult() }
        let r = await ProcessRunner.run(sqlite3Path, ["-readonly", "-json", dbPath, query], timeout: 30)
        let result = interpret(ok: r.ok, code: r.code, stdout: r.stdout, stderr: r.stderr)
        if let err = result.error {
            Log.scan.error("AgentsViewProbe query failed: \(err, privacy: .public)")
        }
        return result
    }

    /// Pure decision from a sqlite3 result — factored out so the crucial
    /// empty-vs-error branch is unit-testable without a live database. `sqlite3
    /// -json` prints "" (not "[]") for zero rows, so ok+empty is a TRUE empty; a
    /// non-zero exit is a real error whose stderr we surface.
    static func interpret(ok: Bool, code: Int32, stdout: String, stderr: String) -> ScanResult {
        guard ok else {
            let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return ScanResult(error: err.isEmpty ? "sqlite3 exited \(code)" : err)
        }
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return ScanResult() }   // ok + empty ⇒ genuinely zero rows
        guard let data = out.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ScanResult(error: "sqlite3 returned non-JSON output")
        }
        return ScanResult(evidence: rows.compactMap(parseRow))
    }

    private static func parseRow(_ row: [String: Any]) -> SkillEvidence? {
        guard let cwd = row["cwd"] as? String, !cwd.isEmpty,
              let skill = row["skill"] as? String,
              TranscriptProbe.isProvenanceSkill(skill) else { return nil }
        // NSNumber coerces Int/Double/boxed numerics uniformly — sqlite3 -json emits
        // COUNT(*) as a JSON number, so this can't silently zero-out a real count.
        let count = (row["n"] as? NSNumber)?.intValue ?? 0
        let last = (row["last"] as? String) ?? ""
        return SkillEvidence(repoPath: cwd, skillId: skill, count: count, lastSeen: last, source: "AgentsView")
    }
}
