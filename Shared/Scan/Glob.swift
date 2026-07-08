// Glob.swift — minimatch-style glob matching for VIBE.yaml `exclude_globs`
// (and, when we wire it, `scope_globs`).
//
// Patterns are ROOTED at the repo root — the same coordinate space the census
// uses for a file's relative path (e.g. `Sources/Big.swift`). `**` crosses path
// separators; `*` and `?` do not. Depth is opt-in via `**`, never implicit —
// this mirrors how the skeleton writes globs (`Sources/**/*.swift`,
// `**/Generated/**`) and how VibeYamlEditor records an exact excluded path.

import Foundation

enum Glob {
    /// Compile a glob into an anchored regex. `nil` means "matches nothing".
    static func compile(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: translate(pattern))
    }

    static func matches(path: String, pattern: String) -> Bool {
        guard let re = compile(pattern) else { return false }
        return matches(path: path, regex: re)
    }

    /// Convenience for one-off checks. Hot loops should `compile` once and reuse.
    static func matchesAny(path: String, patterns: [String]) -> Bool {
        patterns.contains { matches(path: path, pattern: $0) }
    }

    static func matches(path: String, regex: NSRegularExpression) -> Bool {
        let r = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, options: [], range: r) != nil
    }

    /// Glob → anchored regex source. `**/` matches zero or more path segments so
    /// `**/Generated/**` also catches a top-level `Generated/…`.
    static func translate(_ glob: String) -> String {
        var out = "^"
        let chars = Array(glob)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "*" {
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    var j = i
                    while j < chars.count && chars[j] == "*" { j += 1 }
                    if j < chars.count && chars[j] == "/" {
                        out += "(?:.*/)?"   // **/  → zero or more leading segments
                        j += 1
                    } else {
                        out += ".*"          // **   → anything, crossing separators
                    }
                    i = j
                    continue
                }
                out += "[^/]*"               // *    → within one path segment
            } else if c == "?" {
                out += "[^/]"                // ?    → one non-separator char
            } else {
                out += NSRegularExpression.escapedPattern(for: String(c))
            }
            i += 1
        }
        return out + "$"
    }
}
