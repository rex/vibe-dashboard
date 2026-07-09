// WatchTranscript.swift — rich transcript event model + per-line parsers for the
// agent watch window. Understands both Claude Code session/agent JSONLs and Codex
// rollout JSONLs, and pairs tool calls with their results (the tailer applies the
// pairing across lines). Pure parsing — no IO, no clocks — so every shape is
// unit-testable against real captured lines.

import Foundation

enum WatchEventKind: String, Sendable, Hashable {
    case user, assistant, thinking, tool, meta, outcome
}

/// One rendered row in a watch pane. `output` is nil on a tool event until its
/// result line arrives; the UI shows an honest "running…" only while nil.
struct WatchEvent: Identifiable, Sendable, Hashable {
    var id: String = ""
    var kind: WatchEventKind
    var title: String            // "you" / "assistant" / "thinking" / tool name / meta label
    var body: String             // markdown (prose kinds) or the tool's input
    var summary: String = ""     // tool rows: one-line salient input ("make test", "GitProbe.swift")
    var inputIsJSON: Bool = true // tool rows: body is pretty JSON (vs a raw patch/string)
    var output: String? = nil    // paired tool result body (nil = no result yet)
    var isError: Bool = false
    var timestamp: Date?
}

/// What one JSONL line contributes: zero or more events, plus tool-result payloads
/// that attach to a PREVIOUS event (matched on the tool key by the tailer).
enum WatchLineItem: Sendable {
    case event(WatchEvent, toolKey: String?)
    case result(key: String, body: String, isError: Bool)
}

enum WatchTranscriptParser {
    static let bodyCap = 24_000

    static func items(line: String) -> [WatchLineItem] {
        guard let obj = object(line) else { return [] }
        let ts = (obj["timestamp"] as? String).flatMap(AgentTranscriptProbe.parseTimestamp)
        switch obj["type"] as? String {
        case "response_item":
            guard let payload = obj["payload"] as? [String: Any] else { return [] }
            return codexItems(payload: payload, ts: ts)
        case "session_meta":
            let cwd = (obj["payload"] as? [String: Any])?["cwd"] as? String ?? ""
            return metaItem("session started", detail: abbreviateHome(cwd), ts: ts)
        case "compacted":
            return metaItem("context compacted", detail: "", ts: ts)
        case "user", "assistant":
            return claudeItems(obj, ts: ts)
        case "system":
            if obj["subtype"] as? String == "compact_boundary" {
                return metaItem("context compacted", detail: "", ts: ts)
            }
            if let content = obj["content"] as? String, !content.isEmpty, content.count < 400 {
                return metaItem("system", detail: content, ts: ts)
            }
            return []
        default:
            return []   // attachment / progress / summary / turn_context / event_msg / …
        }
    }

    // MARK: - Claude Code lines

    private static func claudeItems(_ obj: [String: Any], ts: Date?) -> [WatchLineItem] {
        guard let message = obj["message"] as? [String: Any] else { return [] }
        let role = message["role"] as? String ?? obj["type"] as? String ?? "user"
        if let text = message["content"] as? String {
            return proseItem(role: role, text: text, ts: ts)
        }
        guard let blocks = message["content"] as? [[String: Any]] else { return [] }
        var out: [WatchLineItem] = []
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                out += proseItem(role: role, text: block["text"] as? String ?? "", ts: ts)
            case "thinking":
                let t = block["thinking"] as? String ?? ""
                if !clean(t).isEmpty {
                    out.append(.event(WatchEvent(kind: .thinking, title: "thinking",
                                                 body: clip(clean(t)), timestamp: ts), toolKey: nil))
                }
            case "redacted_thinking":
                out.append(.event(WatchEvent(kind: .thinking, title: "thinking",
                                             body: "[redacted]", timestamp: ts), toolKey: nil))
            case "tool_use":
                let name = block["name"] as? String ?? "tool"
                let input = block["input"]
                out.append(.event(WatchEvent(kind: .tool, title: name,
                                             body: clip(pretty(input)),
                                             summary: toolSummary(name: name, input: input),
                                             timestamp: ts),
                                  toolKey: block["id"] as? String))
            case "tool_result":
                guard let key = block["tool_use_id"] as? String else { continue }
                out.append(.result(key: key,
                                   body: clip(contentString(block["content"])),
                                   isError: block["is_error"] as? Bool ?? false))
            default:
                break
            }
        }
        return out
    }

    // MARK: - Codex rollout lines (response_item payloads)

    private static func codexItems(payload: [String: Any], ts: Date?) -> [WatchLineItem] {
        let key = (payload["call_id"] as? String) ?? (payload["id"] as? String)
        switch payload["type"] as? String {
        case "message":
            let role = payload["role"] as? String ?? "assistant"
            guard role != "developer", role != "system" else { return [] }   // instruction dumps
            return proseItem(role: role, text: contentString(payload["content"]), ts: ts)
        case "reasoning":
            let text = reasoningText(payload)
            guard !text.isEmpty else { return [] }
            return [.event(WatchEvent(kind: .thinking, title: "thinking",
                                      body: clip(text), timestamp: ts), toolKey: nil)]
        case "function_call", "tool_search_call", "web_search_call":
            let name = payload["name"] as? String
                ?? (payload["type"] as? String ?? "tool").replacingOccurrences(of: "_", with: " ")
            let input = jsonValue(payload["arguments"] ?? payload["input"] ?? payload["action"])
            return [.event(WatchEvent(kind: .tool, title: name,
                                      body: clip(pretty(input)),
                                      summary: toolSummary(name: name, input: input),
                                      timestamp: ts), toolKey: key)]
        case "custom_tool_call":
            let name = payload["name"] as? String ?? "tool"
            let raw = (payload["input"] as? String) ?? contentString(payload["input"])
            return [.event(WatchEvent(kind: .tool, title: name,
                                      body: clip(raw), summary: toolSummary(name: name, input: raw),
                                      inputIsJSON: false, timestamp: ts), toolKey: key)]
        case "function_call_output", "custom_tool_call_output", "tool_search_output":
            guard let key else { return [] }
            let (body, exitError) = codexOutput(payload["output"] ?? payload["tools"])
            let failed = payload["status"] as? String == "failed"
            return [.result(key: key, body: clip(body), isError: failed || exitError)]
        default:
            return []
        }
    }

    /// Codex wraps shell output in a JSON string: `{"output": "...", "metadata":
    /// {"exit_code": N}}`. Unwrap it and surface a non-zero exit as an error.
    static func codexOutput(_ value: Any?) -> (body: String, isError: Bool) {
        if let s = value as? String, let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let exit = ((obj["metadata"] as? [String: Any])?["exit_code"] as? Int) ?? 0
            if let inner = obj["output"] as? String { return (inner, exit != 0) }
            return (pretty(obj), exit != 0)
        }
        return (contentString(value), false)
    }

    private static func reasoningText(_ payload: [String: Any]) -> String {
        var parts: [String] = []
        for blockKey in ["summary", "content"] {
            for block in payload[blockKey] as? [[String: Any]] ?? [] {
                if let t = block["text"] as? String, !clean(t).isEmpty { parts.append(clean(t)) }
            }
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Shared helpers

    private static func proseItem(role: String, text: String, ts: Date?) -> [WatchLineItem] {
        let body = clean(text)
        guard !body.isEmpty else { return [] }
        let kind: WatchEventKind = role == "user" ? .user : .assistant
        return [.event(WatchEvent(kind: kind, title: role == "user" ? "you" : "assistant",
                                  body: clip(body), timestamp: ts), toolKey: nil)]
    }

    private static func metaItem(_ label: String, detail: String, ts: Date?) -> [WatchLineItem] {
        [.event(WatchEvent(kind: .meta, title: label, body: clean(detail), timestamp: ts), toolKey: nil)]
    }

    /// One-line salient input for a collapsed tool row — the argument a human would
    /// scan for ("make test", "GitProbe.swift", a pattern, a URL). Pure + testable.
    static func toolSummary(name: String, input: Any?) -> String {
        if let s = input as? String {   // raw payloads (apply_patch, …): first meaningful line
            let first = s.split(separator: "\n").map(String.init)
                .first { !clean($0).isEmpty && !$0.hasPrefix("*** Begin") } ?? ""
            return oneLine(first)
        }
        guard let dict = input as? [String: Any] else { return "" }
        if name == "TodoWrite", let todos = dict["todos"] as? [Any] { return "\(todos.count) todos" }
        let preferred = ["command", "cmd", "file_path", "path", "pattern", "query", "url",
                         "description", "prompt", "skill", "title", "name", "target", "message"]
        for key in preferred {
            if let v = dict[key] as? String, !clean(v).isEmpty { return oneLine(v) }
        }
        if let first = dict.values.compactMap({ $0 as? String }).first(where: { !clean($0).isEmpty }) {
            return oneLine(first)
        }
        return ""
    }

    static func oneLine(_ s: String, cap: Int = 110) -> String {
        let flat = abbreviateHome(s).split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }.joined(separator: " · ")
        return flat.count > cap ? String(flat.prefix(cap)) + "…" : flat
    }

    static func abbreviateHome(_ s: String) -> String {
        let home = NSHomeDirectory()
        return s.hasPrefix(home) ? "~" + s.dropFirst(home.count) : s
    }

    static func contentString(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let blocks = value as? [[String: Any]] {
            return blocks.map { block -> String in
                switch block["type"] as? String {
                case "text", "input_text", "output_text": return block["text"] as? String ?? ""
                case "image": return "[image]"
                default: return pretty(block)
                }
            }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return value == nil ? "" : pretty(value)
    }

    static func pretty(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return String(describing: value) }
        return String(decoding: data, as: UTF8.self)
    }

    /// A JSON-encoded string argument ("{\"cmd\":…}") → its object, else passthrough.
    static func jsonValue(_ value: Any?) -> Any? {
        guard let s = value as? String else { return value }
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return s }
        return obj
    }

    static func clip(_ text: String, limit: Int = bodyCap) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n\n[clipped \(text.count - limit) chars]"
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Workflow sidecars (journal.jsonl + agent meta.json)

/// The `agent-<id>.meta.json` sidecar next to each workflow/subagent transcript —
/// carries the human-readable task description used as the pane title.
struct WatchAgentMeta: Sendable {
    var agentType: String?
    var description: String?

    static func read(transcriptPath: String) -> WatchAgentMeta {
        let metaPath = (transcriptPath as NSString).deletingPathExtension + ".meta.json"
        guard let data = FileManager.default.contents(atPath: metaPath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return WatchAgentMeta() }
        return WatchAgentMeta(agentType: obj["agentType"] as? String,
                              description: obj["description"] as? String)
    }
}

/// A workflow dir's `journal.jsonl`: `started` order + per-agent `result` payloads.
/// Gives the watch window honest lifecycle (running vs returned) and spawn order.
struct WatchJournal: Sendable {
    var startOrder: [String] = []           // agentIds in spawn order
    var results: [String: String] = [:]     // agentId → pretty result payload

    static func read(dir: String) -> WatchJournal {
        let path = (dir as NSString).appendingPathComponent("journal.jsonl")
        guard let data = FileManager.default.contents(atPath: path) else { return WatchJournal() }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ text: String) -> WatchJournal {
        var j = WatchJournal()
        for line in text.split(separator: "\n") {
            guard let obj = WatchTranscriptParser.object(String(line)),
                  let agentId = obj["agentId"] as? String else { continue }
            switch obj["type"] as? String {
            case "started":
                if !j.startOrder.contains(agentId) { j.startOrder.append(agentId) }
            case "result":
                j.results[agentId] = WatchTranscriptParser.clip(
                    WatchTranscriptParser.pretty(obj["result"]), limit: 4000)
            default: break
            }
        }
        return j
    }
}
