import Testing
import Foundation
@testable import VibeDashboard

/// The evidence/backfill pipeline is the app's provenance thesis: real skill runs
/// must surface (nothing dropped by a path-format mismatch), a broken source must
/// announce itself (never masquerade as "empty"), and the one repo-mutating writer
/// must stay bullet-proof. These tests pin the pure, reachable logic behind that.
@Suite("Evidence / backfill")
struct EvidenceTests {
    private func tempVibe(_ body: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("evidence-vibe-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("VIBE.yaml").path
        try? body.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    // MARK: (a) cwd normalization

    @Test("cwd normalization matches trailing-slash / tilde / symlinked forms to the resolved repo path")
    func cwdNormalization() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("evidence-norm-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let real = base.appendingPathComponent("real-repo")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("linked-repo")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        // Canonical = the resolved real path. Every alternate spelling must collapse to it.
        let canonical = TranscriptProbe.normalizedPath(real.path)
        #expect(TranscriptProbe.normalizedPath(real.path + "/") == canonical)   // trailing slash
        #expect(TranscriptProbe.normalizedPath(real.path + "//") == canonical)  // doubled slash
        #expect(TranscriptProbe.normalizedPath(link.path) == canonical)         // symlink → real
        #expect(TranscriptProbe.normalizedPath(canonical) == canonical)         // idempotent
        // Tilde expansion: "~" resolves to the same canonical form as $HOME.
        #expect(TranscriptProbe.normalizedPath("~") == TranscriptProbe.normalizedPath(NSHomeDirectory()))
        // Never reduces the root to an empty string.
        #expect(TranscriptProbe.normalizedPath("/") == "/")
    }

    // MARK: (b) AgentsViewProbe empty-vs-error branching

    @Test("AgentsViewProbe distinguishes a true-empty result from a query/DB error")
    func agentsViewEmptyVsError() {
        // ok + empty stdout ⇒ genuine zero rows (sqlite3 -json prints "" for none): [] and NO error.
        let empty = AgentsViewProbe.interpret(ok: true, code: 0, stdout: "", stderr: "")
        #expect(empty.evidence.isEmpty)
        #expect(empty.error == nil)

        // non-zero exit ⇒ error surfaced (a schema break is detectable, not invisible), evidence empty.
        let broken = AgentsViewProbe.interpret(ok: false, code: 1, stdout: "",
                                               stderr: "Error: no such table: tool_calls")
        #expect(broken.evidence.isEmpty)
        #expect(broken.error?.contains("no such table") == true)

        // ok + JSON rows ⇒ parsed; the count comes through NSNumber coercion, not zeroed.
        let rows = AgentsViewProbe.interpret(ok: true, code: 0,
            stdout: #"[{"cwd":"/Users/x/Code/foo","skill":"lang-go","n":5,"last":"2026-01-02"}]"#, stderr: "")
        #expect(rows.error == nil)
        #expect(rows.evidence.count == 1)
        #expect(rows.evidence.first?.count == 5)          // NSNumber → Int, not silently 0
        #expect(rows.evidence.first?.skillId == "lang-go")

        // widened allowlist: an agentic-* skill now surfaces instead of being dropped at the source.
        let widened = AgentsViewProbe.interpret(ok: true, code: 0,
            stdout: #"[{"cwd":"/Users/x/Code/foo","skill":"agentic-config","n":2,"last":"2026-01-03"}]"#, stderr: "")
        #expect(widened.evidence.first?.skillId == "agentic-config")

        // a non-provenance skill is still filtered out (near-zero false positives).
        let filtered = AgentsViewProbe.interpret(ok: true, code: 0,
            stdout: #"[{"cwd":"/Users/x/Code/foo","skill":"anchor","n":9,"last":"2026-01-03"}]"#, stderr: "")
        #expect(filtered.evidence.isEmpty)
    }

    // MARK: (c) backupPath collision-free filenames

    @Test("backupPath produces distinct filenames for distinct-but-slug-similar repo paths")
    func backupPathNoCollision() {
        // Under the old '/'→'_', ' '→'_' slug these two collided onto one file.
        let a = VibeYamlEditor.backupPath(for: "/Users/dev/Code/a b/VIBE.yaml")
        let b = VibeYamlEditor.backupPath(for: "/Users/dev/Code/a_b/VIBE.yaml")
        #expect(a != b)
        // Deterministic: the same path always maps to the same backup (the write/verify contract relies on it).
        #expect(VibeYamlEditor.backupPath(for: "/Users/dev/Code/a b/VIBE.yaml") == a)
        // Lives in the app backups dir, never next to the repo, and doesn't leak the raw path.
        #expect(a.contains("Library/Application Support/VibeDashboard/backups"))
        #expect(!a.contains("/Code/a b/"))
    }

    // MARK: Task 1 — content shape handling + drift counting (pure parseLine)

    @Test("parseLine iterates array content, skips String/other-type content, and flags only real drift")
    func transcriptParseLineShapes() {
        // assistant + array content with a real Skill tool_use ⇒ one event, not dropped.
        let arr = #"{"type":"assistant","cwd":"/Users/x/Code/foo","timestamp":"2026-01-02T10:00:00Z","#
            + #""message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"lang-swift-apple"}}]}}"#
        let a = TranscriptProbe.parseLine(arr)
        #expect(a.dropped == false)
        #expect(a.events.count == 1)
        #expect(a.events.first?.skillId == "lang-swift-apple")
        #expect(a.events.first?.repoPath == "/Users/x/Code/foo")
        #expect(a.events.first?.lastSeen == "2026-01-02")

        // assistant + String content (a mention/meta record) ⇒ skipped cleanly, NOT counted.
        let str = #"{"type":"assistant","cwd":"/Users/x/Code/foo","message":{"content":"I ran the \"name\":\"Skill\" tool"}}"#
        let s = TranscriptProbe.parseLine(str)
        #expect(s.events.isEmpty)
        #expect(s.dropped == false)

        // assistant + unexpected content shape (a dict) ⇒ dropped (a schema-drift signal worth counting).
        let weird = #"{"type":"assistant","cwd":"/Users/x/Code/foo","message":{"content":{"name":"Skill"}}}"#
        let w = TranscriptProbe.parseLine(weird)
        #expect(w.events.isEmpty)
        #expect(w.dropped == true)

        // non-assistant record that merely quotes the tool name ⇒ clean skip, not a drop.
        let user = #"{"type":"user","cwd":"/Users/x/Code/foo","message":{"content":"see \"name\":\"Skill\""}}"#
        let u = TranscriptProbe.parseLine(user)
        #expect(u.events.isEmpty)
        #expect(u.dropped == false)

        // a Skill run whose skill is NOT provenance-family ⇒ no event, and NOT a drop.
        let offlist = #"{"type":"assistant","cwd":"/Users/x/Code/foo","message":{"content":"#
            + #"[{"type":"tool_use","name":"Skill","input":{"skill":"anchor"}}]}}"#
        let o = TranscriptProbe.parseLine(offlist)
        #expect(o.events.isEmpty)
        #expect(o.dropped == false)
    }

    // MARK: Task 7 — widened provenance allowlist

    @Test("isProvenanceSkill widens to the agentic-*/scaffold/retrofit/sync-skills family but excludes personal skills")
    func provenanceAllowlist() {
        for id in ["lang-swift-apple", "tool-ci", "agentic-skeleton", "agentic-config",
                   "agentic-workspace", "scaffold", "retrofit", "sync-skills"] {
            #expect(TranscriptProbe.isProvenanceSkill(id), "expected \(id) to be provenance")
        }
        for id in ["anchor", "serena", "plan", "prompt-builder", "side-project", "budget", ""] {
            #expect(!TranscriptProbe.isProvenanceSkill(id), "expected \(id) to be excluded")
        }
    }

    // MARK: Task 5/6 — recordSkill quoting + last-block insert placement (via public entry)

    @Test("recordSkill quotes every string scalar so odd inputs can't mis-parse")
    func recordSkillQuotesScalars() {
        let path = tempVibe("architecture:\n  max_lines_per_file:\n    hard: 400\n")
        let r = VibeYamlEditor.recordSkill(vibePath: path, id: "lang-go", version: "1.2.0", applied: "2026-07-01")
        #expect(r == .skillRecorded(id: "lang-go"))
        let after = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        #expect(after.contains("id: \"lang-go\""))
        #expect(after.contains("applied: \"2026-07-01\""))            // date-like value quoted, not left bare
        #expect(after.contains("source: \"transcript-backfill\""))
        #expect(VibeYamlEditor.currentSkillIds(vibePath: path) == ["lang-go"])
    }

    @Test("recordSkill inserts inside the skills list, above a trailing comment, when skills: is the last block")
    func recordSkillLastBlockTrailingComment() {
        let src = """
        architecture:
          max_lines_per_file:
            hard: 400
        skills:
          - id: tool-ci
            version: "0.1.0"
            applied: "2026-06-01"
          # keep agentic-* provenance below
        """
        let path = tempVibe(src)
        let r = VibeYamlEditor.recordSkill(vibePath: path, id: "lang-go", version: "0.2.0", applied: "2026-07-01")
        #expect(r == .skillRecorded(id: "lang-go"))
        #expect(Set(VibeYamlEditor.currentSkillIds(vibePath: path)) == ["tool-ci", "lang-go"])
        let after = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard let entryRange = after.range(of: "id: \"lang-go\""),
              let commentRange = after.range(of: "# keep agentic-* provenance") else {
            Issue.record("new entry or trailing comment missing from output"); return
        }
        // The new entry must sit INSIDE the list, ABOVE the footer comment — not after it.
        #expect(entryRange.lowerBound < commentRange.lowerBound)
    }
}
