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

        var lines = original.components(separatedBy: "\n")
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

        let newText = lines.joined(separator: "\n")
        // VERIFY: the result must parse AND now contain the glob under architecture.exclude_globs.
        guard let re = (try? Yams.load(yaml: newText)) as? [String: Any],
              let reArch = re["architecture"] as? [String: Any],
              let reGlobs = reArch["exclude_globs"] as? [String],
              reGlobs.contains(glob) else {
            return .unsafe("edit did not validate — VIBE.yaml left untouched")
        }
        // Backup (best-effort) then atomic write.
        try? original.write(toFile: vibePath + ".bak", atomically: true, encoding: .utf8)
        do { try newText.write(toFile: vibePath, atomically: true, encoding: .utf8) } catch {
            return .unsafe("write failed: \(error.localizedDescription)")
        }
        return .added(glob: glob)
    }

    /// The globs currently excluded (for showing the user before/after).
    static func currentExcludes(vibePath: String) -> [String] {
        guard let text = try? String(contentsOfFile: vibePath, encoding: .utf8),
              let dict = (try? Yams.load(yaml: text)) as? [String: Any],
              let arch = dict["architecture"] as? [String: Any],
              let globs = arch["exclude_globs"] as? [String] else { return [] }
        return globs
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
