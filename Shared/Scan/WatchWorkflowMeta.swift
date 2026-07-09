// WatchWorkflowMeta.swift — recover a workflow's PLAN and terminal state from disk.
//
// The orchestrator persists two sidecars outside the wf transcript dir, both under
// the owning session directory:
//   workflows/scripts/<meta.name>-<wfId>.js   — from LAUNCH: the actual script; its
//                                               `export const meta = {…}` literal
//                                               carries name/description/phases.
//   workflows/<wfId>.json                     — on COMPLETION: workflowName, status,
//                                               summary, durationMs, agentCount, logs.
// Reading these turns a detected workflow into a NAMED, plan-aware watch target.
// The meta literal is extracted textually (never executed).

import Foundation

struct WatchWorkflowMeta: Sendable, Hashable {
    var name: String?
    var description: String?
    var phases: [String] = []       // planned phase titles, in order
    var status: String?             // terminal only: "completed" / "failed" / …
    var summary: String?            // terminal only
    var durationMs: Int?            // terminal only
    var agentCount: Int?            // terminal only
    var logs: [String] = []         // terminal only: the script's log() narration

    var isTerminal: Bool { status != nil }

    /// Load for a workflow transcript dir `…/<session>/subagents/workflows/<wfId>`.
    /// Live: plan from the persisted script. Terminal: state JSON layered on top.
    static func load(workflowDir: String) -> WatchWorkflowMeta {
        let wfId = (workflowDir as NSString).lastPathComponent
        let sessionDir = ((workflowDir as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent                       // strip wfId + "workflows"
        let base = (sessionDir as NSString).deletingLastPathComponent  // strip "subagents"

        var meta = WatchWorkflowMeta()
        if let script = scriptText(base: base, wfId: wfId) {
            meta = parseScriptMeta(script)
        }
        applyTerminal(base: base, wfId: wfId, to: &meta)
        return meta
    }

    private static func scriptText(base: String, wfId: String) -> String? {
        let dir = (base as NSString).appendingPathComponent("workflows/scripts")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        guard let name = names.first(where: { $0.hasSuffix("-\(wfId).js") }) else { return nil }
        let path = (dir as NSString).appendingPathComponent(name)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        // The meta literal sits at the top; 16 KB is plenty and bounds the parse.
        return String(decoding: data.prefix(16 * 1024), as: UTF8.self)
    }

    private static func applyTerminal(base: String, wfId: String, to meta: inout WatchWorkflowMeta) {
        let path = (base as NSString).appendingPathComponent("workflows/\(wfId).json")
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        meta.name = (obj["workflowName"] as? String) ?? meta.name
        meta.status = obj["status"] as? String
        meta.summary = obj["summary"] as? String
        meta.durationMs = (obj["durationMs"] as? Int)
            ?? (obj["durationMs"] as? String).flatMap(Int.init)
        meta.agentCount = (obj["agentCount"] as? Int)
            ?? (obj["agentCount"] as? String).flatMap(Int.init)
        meta.logs = (obj["logs"] as? [String]) ?? []
        if let phases = obj["phases"] as? [[String: Any]] {
            let titles = phases.compactMap { $0["title"] as? String }
            if !titles.isEmpty { meta.phases = titles }
        }
    }

    // MARK: - Script meta extraction (textual, never executed)

    /// Pull name/description/phase-titles out of the `export const meta = {…}`
    /// literal. The block is model-authored plain JS with quoted string values, so
    /// quoted-string extraction per key is robust; a script whose meta we cannot
    /// read simply yields an empty plan (honest fallback), never a guess.
    static func parseScriptMeta(_ script: String) -> WatchWorkflowMeta {
        guard let start = script.range(of: "export const meta") else { return WatchWorkflowMeta() }
        guard let block = balancedBraceBlock(in: script[start.upperBound...]) else {
            return WatchWorkflowMeta()
        }
        var meta = WatchWorkflowMeta()
        meta.name = firstString(after: "name", in: block)
        meta.description = firstString(after: "description", in: block)
        if let phasesRange = block.range(of: "phases") {
            let tail = String(block[phasesRange.upperBound...])
            meta.phases = allStrings(after: "title", in: tail)
        }
        return meta
    }

    /// The `{…}` block following the current position, brace-balanced and
    /// string-aware (braces inside quoted values don't count).
    static func balancedBraceBlock(in text: Substring) -> String? {
        guard let open = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var quote: Character?
        var escaped = false
        var i = open
        while i < text.endIndex {
            let ch = text[i]
            if escaped { escaped = false }
            else if ch == "\\" { escaped = true }
            else if let q = quote { if ch == q { quote = nil } }
            else if ch == "'" || ch == "\"" || ch == "`" { quote = ch }
            else if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return String(text[open...i]) }
            }
            i = text.index(after: i)
        }
        return nil
    }

    static func firstString(after key: String, in block: String) -> String? {
        allStrings(after: key, in: block).first
    }

    /// Every `key: '<value>'` (or double-quoted) occurrence, unescaped, in order.
    static func allStrings(after key: String, in block: String) -> [String] {
        var values: [String] = []
        var search = block.startIndex
        while let keyRange = block.range(of: key + ":", range: search..<block.endIndex) {
            var i = keyRange.upperBound
            while i < block.endIndex, block[i] == " " || block[i] == "\t" { i = block.index(after: i) }
            guard i < block.endIndex, block[i] == "'" || block[i] == "\"" else {
                search = keyRange.upperBound; continue
            }
            let quote = block[i]
            i = block.index(after: i)
            var value = ""
            var escaped = false
            while i < block.endIndex {
                let ch = block[i]
                if escaped { value.append(ch); escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == quote { break }
                else { value.append(ch) }
                i = block.index(after: i)
            }
            values.append(value)
            search = i < block.endIndex ? block.index(after: i) : block.endIndex
        }
        return values
    }
}
