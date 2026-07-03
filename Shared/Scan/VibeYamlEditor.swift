// VibeYamlEditor.swift — the ONLY writer that touches a repo's VIBE.yaml.
//
// A mangled VIBE.yaml bricks a repo's whole policy, so this is deliberately
// paranoid: it parses the original, does a SURGICAL text insert (comments and
// formatting are preserved — no Yams round-trip re-dump), then RE-PARSES the
// result and refuses to write unless the edit both parses AND actually contains
// the intended change. A timestamped byte-for-byte backup is written first, and
// the final write is atomic. If anything is off, the original is left untouched.

import Foundation
import Yams

enum VibeYamlEditor {
    enum Result: Equatable {
        case added(glob: String)
        case alreadyExcluded
        case skillRecorded(id: String)
        case alreadyRecorded
        case noVibe
        case parseError
        case unsafe(String)   // couldn't edit safely — original untouched
    }

    /// Add `glob` to `architecture.exclude_globs` in the repo's VIBE.yaml.
    static func addExcludeGlob(vibePath: String, glob: String) -> Result {
        guard let original = try? String(contentsOfFile: vibePath, encoding: .utf8) else { return .noVibe }
        guard let parsed = (try? Yams.load(yaml: original)) as? [String: Any] else { return .parseError }

        let arch = parsed["architecture"] as? [String: Any]
        let existing = (arch?["exclude_globs"] as? [String]) ?? []
        if existing.contains(glob) { return .alreadyExcluded }

        // Normalize line endings for analysis (a stray \r survives .whitespaces
        // trimming and breaks inline-value detection); re-emit in the original style.
        let usesCRLF = original.contains("\r\n")
        let normalized = usesCRLF ? original.replacingOccurrences(of: "\r\n", with: "\n") : original
        var lines = normalized.components(separatedBy: "\n")
        guard let archIdx = lines.firstIndex(where: { isTopKey($0, "architecture") }) else {
            return .unsafe("no architecture: section to add exclude_globs to")
        }
        var blockEnd = lines.count
        for i in (archIdx + 1)..<lines.count where isTopKeyLine(lines[i]) { blockEnd = i; break }

        let quoted = "\"\(glob)\""
        if let exIdx = (archIdx + 1..<blockEnd).first(where: { trimmedKey(lines[$0]) == "exclude_globs" }) {
            // Inline forms: `exclude_globs: []` we can convert; any other inline array we won't risk.
            let after = inlineValue(lines[exIdx])
            if after == "[]" {
                lines[exIdx] = String(repeating: " ", count: indentOf(lines[exIdx])) + "exclude_globs:"
            } else if !after.isEmpty {
                return .unsafe("exclude_globs is inline — edit it by hand")
            }
            let itemIndent = firstItemIndent(lines, after: exIdx, blockEnd: blockEnd) ?? (indentOf(lines[exIdx]) + 2)
            var insertAt = exIdx + 1
            while insertAt < blockEnd, isListItemLine(lines[insertAt]) { insertAt += 1 }
            lines.insert(String(repeating: " ", count: itemIndent) + "- " + quoted, at: insertAt)
        } else {
            // No exclude_globs yet — add it, matching the indent of architecture's other keys.
            let keyIndent = firstChildKeyIndent(lines, archIdx: archIdx, blockEnd: blockEnd) ?? (indentOf(lines[archIdx]) + 2)
            lines.insert(contentsOf: [
                String(repeating: " ", count: keyIndent) + "exclude_globs:",
                String(repeating: " ", count: keyIndent + 2) + "- " + quoted,
            ], at: archIdx + 1)
        }

        var newText = lines.joined(separator: "\n")
        if usesCRLF { newText = newText.replacingOccurrences(of: "\n", with: "\r\n") }
        // VERIFY: the result must parse AND now contain the glob under architecture.exclude_globs.
        guard let re = (try? Yams.load(yaml: newText)) as? [String: Any],
              let reArch = re["architecture"] as? [String: Any],
              let reGlobs = reArch["exclude_globs"] as? [String],
              reGlobs.contains(glob) else {
            return .unsafe("edit did not validate — VIBE.yaml left untouched")
        }
        // Backup (best-effort) then atomic write.
        try? original.write(toFile: backupPath(for: vibePath), atomically: true, encoding: .utf8)
        do { try newText.write(toFile: vibePath, atomically: true, encoding: .utf8) } catch {
            return .unsafe("write failed: \(error.localizedDescription)")
        }
        return .added(glob: glob)
    }

    /// Record an applied skill into VIBE.yaml's top-level `skills:` block. Same
    /// paranoid contract as addExcludeGlob — verified, backed-up, atomic, and it
    /// refuses to write anything it can't re-parse.
    static func recordSkill(vibePath: String, id: String, version: String?, applied: String) -> Result {
        guard let original = try? String(contentsOfFile: vibePath, encoding: .utf8) else { return .noVibe }
        guard let parsed = (try? Yams.load(yaml: original)) as? [String: Any] else { return .parseError }
        if recordedSkillIds(parsed).contains(id) { return .alreadyRecorded }

        let usesCRLF = original.contains("\r\n")
        let normalized = usesCRLF ? original.replacingOccurrences(of: "\r\n", with: "\n") : original
        var lines = normalized.components(separatedBy: "\n")

        var entry = ["  - id: \(id)"]
        if let version { entry.append("    version: \"\(version)\"") }
        entry.append("    applied: \(applied)")
        entry.append("    source: transcript-backfill")

        if let skIdx = lines.firstIndex(where: { isTopKey($0, "skills") }) {
            let after = inlineValue(lines[skIdx])
            if after == "[]" { lines[skIdx] = "skills:" } else if !after.isEmpty {
                return .unsafe("skills is inline — edit it by hand")
            }
            var blockEnd = lines.count
            for i in (skIdx + 1)..<lines.count where isTopKeyLine(lines[i]) { blockEnd = i; break }
            var insertAt = skIdx + 1
            for i in (skIdx + 1)..<blockEnd where isListItemLine(lines[i]) || indentOf(lines[i]) > 0 { insertAt = i + 1 }
            lines.insert(contentsOf: entry, at: insertAt)
        } else {
            while lines.last?.isEmpty == true { lines.removeLast() }
            lines.append("skills:")
            lines.append(contentsOf: entry)
        }

        var newText = lines.joined(separator: "\n")
        if !newText.hasSuffix("\n") { newText += "\n" }
        if usesCRLF { newText = newText.replacingOccurrences(of: "\n", with: "\r\n") }
        // VERIFY: parses AND now records this skill id.
        guard let re = (try? Yams.load(yaml: newText)) as? [String: Any],
              recordedSkillIds(re).contains(id) else {
            return .unsafe("edit did not validate — VIBE.yaml left untouched")
        }
        try? original.write(toFile: backupPath(for: vibePath), atomically: true, encoding: .utf8)
        do { try newText.write(toFile: vibePath, atomically: true, encoding: .utf8) } catch {
            return .unsafe("write failed: \(error.localizedDescription)")
        }
        return .skillRecorded(id: id)
    }

    private static func recordedSkillIds(_ dict: [String: Any]) -> [String] {
        if let maps = dict["skills"] as? [[String: Any]] { return maps.compactMap { $0["id"] as? String } }
        if let ids = dict["skills"] as? [String] { return ids }
        return []
    }

    /// Backups go to the app's own directory, NEVER next to the file — dropping a
    /// `.bak` into a scanned repo is exactly the committed-junk this app flags.
    static func backupPath(for vibePath: String) -> String {
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/VibeDashboard/backups")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let slug = vibePath.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_")
        return (dir as NSString).appendingPathComponent(slug + ".bak")
    }

    /// The globs currently excluded (for showing the user before/after).
    static func currentExcludes(vibePath: String) -> [String] {
        guard let text = try? String(contentsOfFile: vibePath, encoding: .utf8),
              let dict = (try? Yams.load(yaml: text)) as? [String: Any],
              let arch = dict["architecture"] as? [String: Any],
              let globs = arch["exclude_globs"] as? [String] else { return [] }
        return globs
    }

    /// The skill ids a repo currently records in VIBE.yaml.
    static func currentSkillIds(vibePath: String) -> [String] {
        guard let text = try? String(contentsOfFile: vibePath, encoding: .utf8),
              let dict = (try? Yams.load(yaml: text)) as? [String: Any] else { return [] }
        return recordedSkillIds(dict)
    }

    // ---- line helpers (indentation-aware, comment/format preserving) ----
    private static func indentOf(_ line: String) -> Int { line.prefix { $0 == " " }.count }

    private static func isTopKey(_ line: String, _ name: String) -> Bool {
        line.range(of: "^\(name)[ \\t]*:", options: .regularExpression) != nil
    }
    private static func isTopKeyLine(_ line: String) -> Bool {
        guard let f = line.first, f != " ", f != "\t", f != "#", f != "-" else { return false }
        return line.range(of: "^[A-Za-z_][A-Za-z0-9_]*[ \\t]*:", options: .regularExpression) != nil
    }
    private static func trimmedKey(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("#"), !t.hasPrefix("-"), let colon = t.firstIndex(of: ":") else { return nil }
        let key = String(t[t.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        return key.range(of: "^[A-Za-z_][A-Za-z0-9_-]*$", options: .regularExpression) != nil ? key : nil
    }
    private static func inlineValue(_ line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }
    private static func isListItemLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("-")
    }
    private static func firstItemIndent(_ lines: [String], after idx: Int, blockEnd: Int) -> Int? {
        for i in (idx + 1)..<blockEnd where isListItemLine(lines[i]) { return indentOf(lines[i]) }
        return nil
    }
    private static func firstChildKeyIndent(_ lines: [String], archIdx: Int, blockEnd: Int) -> Int? {
        for i in (archIdx + 1)..<blockEnd where trimmedKey(lines[i]) != nil && indentOf(lines[i]) > 0 {
            return indentOf(lines[i])
        }
        return nil
    }
}
