// SessionTelemetry.swift — model / effort / context-window facts for a live
// session, read from the transcript tail the probe already holds. Claude records
// the model + token usage on every assistant line; Codex records model+effort in
// `turn_context` and running totals in `event_msg:token_count`. Anything absent
// stays nil — the UI hides it rather than inventing it.

import Foundation

struct SessionTelemetry: Sendable, Hashable {
    var model: String?
    var effort: String?          // Codex records reasoning effort; Claude doesn't
    var contextTokens: Int?      // tokens in the context window as of the last turn

    /// Scan the tail newest-first; stop as soon as both facts are found.
    static func read(tail: String, tool: String) -> SessionTelemetry {
        var t = SessionTelemetry()
        for line in tail.split(separator: "\n").reversed() {
            guard let obj = WatchTranscriptParser.object(String(line)) else { continue }
            if tool == "codex" { scanCodex(obj, into: &t) } else { scanClaude(obj, into: &t) }
            if t.model != nil && t.contextTokens != nil { break }
        }
        return t
    }

    private static func scanClaude(_ obj: [String: Any], into t: inout SessionTelemetry) {
        guard obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any] else { return }
        if t.model == nil { t.model = message["model"] as? String }
        if t.contextTokens == nil, let usage = message["usage"] as? [String: Any] {
            let total = ["input_tokens", "cache_read_input_tokens",
                         "cache_creation_input_tokens", "output_tokens"]
                .compactMap { usage[$0] as? Int }.reduce(0, +)
            if total > 0 { t.contextTokens = total }
        }
    }

    private static func scanCodex(_ obj: [String: Any], into t: inout SessionTelemetry) {
        guard let payload = obj["payload"] as? [String: Any] else { return }
        switch obj["type"] as? String {
        case "turn_context":
            if t.model == nil {
                t.model = payload["model"] as? String
                t.effort = payload["effort"] as? String
            }
        case "event_msg" where payload["type"] as? String == "token_count":
            guard t.contextTokens == nil,
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any] else { return }
            let total = ["input_tokens", "cached_input_tokens", "output_tokens"]
                .compactMap { last[$0] as? Int }.reduce(0, +)
            if total > 0 { t.contextTokens = total }
        default: break
        }
    }

    /// "418k" — the compact token form the cards render.
    static func kTokens(_ n: Int) -> String {
        n >= 10_000 ? "\(n / 1000)k" : n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}
