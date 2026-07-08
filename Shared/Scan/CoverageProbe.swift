// CoverageProbe.swift — read a line-coverage percent from a coverage artifact
// that is ALREADY ON DISK. This probe NEVER runs tests or executes anything: it is
// cheap, Sendable-clean file IO meant to run off the main actor inside probeRepo.
//
// The honest contract: return a real percent ONLY when an artifact exists and parses;
// return nil otherwise. A repo without a coverage report shows no number (the gate,
// penalty, and finding all no-op on nil) rather than a fabricated one.

import Foundation

enum CoverageProbe {
    private static var fm: FileManager { .default }
    private static func join(_ base: String, _ c: String) -> String {
        (base as NSString).appendingPathComponent(c)
    }

    /// Line-coverage percent (0…100) parsed from the first coverage artifact on disk
    /// that yields a value, or nil when none is found or parseable. Formats are tried
    /// in order and the first successful parse wins; a present-but-malformed artifact
    /// falls through to the next candidate rather than masking a valid one. Pure file
    /// IO — nothing is executed.
    static func coverage(_ abs: String) -> Int? {
        // LCOV tracefile → sum(LH)/sum(LF).
        for name in ["coverage/lcov.info", "lcov.info"] {
            if let text = readText(join(abs, name)), let p = parseLcov(text) { return p }
        }
        // Istanbul JSON summary → total.lines.pct.
        if let data = readData(join(abs, "coverage/coverage-summary.json")),
           let p = parseIstanbul(data) { return p }
        // Cobertura XML → root line-rate × 100.
        if let text = readText(join(abs, "coverage.xml")), let p = parseCobertura(text) { return p }
        // Plain-text summary → first "NN%".
        for name in [".coverage", "coverage.txt"] {
            if let text = readText(join(abs, name)), let p = parsePercentText(text) { return p }
        }
        return nil
    }

    // ---- IO ----
    // Reading a binary artifact (e.g. coverage.py's SQLite `.coverage`) as UTF-8 simply
    // throws and yields nil — the honest "can't parse" outcome, never a crash.
    private static func readText(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }
    private static func readData(_ path: String) -> Data? {
        fm.fileExists(atPath: path) ? fm.contents(atPath: path) : nil
    }

    // ---- LCOV ----
    /// Sum every record's LH (lines hit) and LF (lines found) and turn the ratio into a
    /// percent. LCOV emits one LF/LH pair per source file, so the fleet-wide percent is
    /// sum(LH)/sum(LF). nil when no LF is found (nothing measurable).
    private static func parseLcov(_ text: String) -> Int? {
        var hit = 0, found = 0
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("LH:"), let n = Int(line.dropFirst(3)) { hit += n }
            else if line.hasPrefix("LF:"), let n = Int(line.dropFirst(3)) { found += n }
        }
        guard found > 0 else { return nil }
        return pct(Double(hit) / Double(found) * 100)
    }

    // ---- Istanbul ----
    /// Read `.total.lines.pct` — already a percent — from an Istanbul coverage-summary.
    private static func parseIstanbul(_ data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let total = root["total"] as? [String: Any],
              let lines = total["lines"] as? [String: Any],
              let n = lines["pct"] as? NSNumber else { return nil }
        return pct(n.doubleValue)
    }

    // ---- Cobertura ----
    /// The root `<coverage line-rate="0.83" …>` attribute is a 0…1 fraction; its first
    /// occurrence in the file is the overall rate (nested package/class rates follow it).
    private static func parseCobertura(_ text: String) -> Int? {
        guard let m = firstMatch(#"line-rate="([0-9]*\.?[0-9]+)""#, in: text),
              let rate = Double(m) else { return nil }
        return pct(rate * 100)
    }

    // ---- plain-text "NN%" ----
    /// Best-effort: the first "NN%" (or "NN.N%") in a saved text summary.
    private static func parsePercentText(_ text: String) -> Int? {
        guard let m = firstMatch(#"([0-9]+(?:\.[0-9]+)?)\s*%"#, in: text),
              let v = Double(m) else { return nil }
        return pct(v)
    }

    // ---- helpers ----
    /// Clamp to 0…100 and round to the nearest integer percent.
    private static func pct(_ v: Double) -> Int {
        Int(min(100, max(0, v)).rounded())
    }
    /// First capture group of `pattern` in `text`, or nil.
    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = re.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
