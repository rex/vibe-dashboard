// HooksMcpProbe.swift — lifecycle hooks (.claude/.git/.cursor) + MCP servers.

import Foundation

enum HooksMcpProbe {
    static var fm: FileManager { .default }
    private static func join(_ a: String, _ b: String) -> String { (a as NSString).appendingPathComponent(b) }
    private static func jsonObject(_ path: String) -> [String: Any]? {
        guard let data = fm.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // ---- hooks ----
    static func hooks(_ abs: String) -> [Hook] {
        var out: [Hook] = []
        out += claudeHooks(abs)
        out += gitHooks(abs)
        out += cursorHooks(abs)
        return out
    }

    private static func claudeHooks(_ abs: String) -> [Hook] {
        guard let settings = jsonObject(join(abs, ".claude/settings.json")),
              let hooksDict = settings["hooks"] as? [String: Any] else { return [] }
        var out: [Hook] = []
        for (event, value) in hooksDict {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                let matcher = group["matcher"] as? String
                let inner = (group["hooks"] as? [[String: Any]]) ?? []
                for h in inner {
                    guard let cmd = h["command"] as? String else { continue }
                    out.append(Hook(src: "claude", event: event, matcher: matcher,
                                    command: cmd, status: classify(cmd, abs: abs)))
                }
            }
        }
        return out
    }

    private static func classify(_ cmd: String, abs: String) -> HookStatus {
        // Inline command (ruff / pre-commit / swiftformat …) — enforces something.
        guard let token = cmd.split(whereSeparator: { $0 == " " }).map(String.init).first(where: { $0.contains(".sh") }) else {
            return .active
        }
        // Resolve the script path: strip quotes, expand $CLAUDE_PROJECT_DIR / ~, make absolute.
        var p = token.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
        p = p.replacingOccurrences(of: "${CLAUDE_PROJECT_DIR}", with: abs)
             .replacingOccurrences(of: "$CLAUDE_PROJECT_DIR", with: abs)
        if p.hasPrefix("~") { p = (p as NSString).expandingTildeInPath }
        if !p.hasPrefix("/") { p = join(abs, p) }
        // An unexpanded variable we can't verify — don't cry wolf.
        if p.contains("$") { return .active }
        guard fm.fileExists(atPath: p) else { return .missing }
        if let data = fm.contents(atPath: p), data.count < 240 {
            let body = String(decoding: data, as: UTF8.self)
            let meaningful = body.split(separator: "\n").filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("#") && !t.hasPrefix("echo") && t != "exit 0" && !t.hasPrefix("set ")
            }
            if meaningful.isEmpty { return .nothing }   // stub: nothing but boilerplate/exit 0
        }
        return .active
    }

    private static func gitHooks(_ abs: String) -> [Hook] {
        var dir = join(abs, ".git/hooks")
        // honor core.hooksPath if configured
        if let cfg = try? String(contentsOfFile: join(abs, ".git/config"), encoding: .utf8),
           let hp = cfg.split(separator: "\n").first(where: { $0.contains("hooksPath") })?.split(separator: "=").last {
            dir = join(abs, hp.trimmingCharacters(in: .whitespaces))
        }
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [Hook] = []
        for name in items where !name.hasSuffix(".sample") {
            let path = join(dir, name)
            guard fm.isExecutableFile(atPath: path) else { continue }
            let body = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let cmd = body.split(separator: "\n").first(where: {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("#") && !t.hasPrefix("set ")
            }).map { String($0).trimmingCharacters(in: .whitespaces) } ?? name
            out.append(Hook(src: "git", event: name, matcher: nil, command: cmd, status: .active))
        }
        return out
    }

    private static func cursorHooks(_ abs: String) -> [Hook] {
        guard let obj = jsonObject(join(abs, ".cursor/hooks.json")) else { return [] }
        var out: [Hook] = []
        for (event, v) in obj {
            if let cmd = (v as? [String: Any])?["command"] as? String {
                out.append(Hook(src: "cursor", event: event, matcher: nil, command: cmd, status: .active, scope: "local"))
            } else if let s = v as? String {
                out.append(Hook(src: "cursor", event: event, matcher: nil, command: s, status: .active, scope: "local"))
            }
        }
        return out
    }

    // ---- MCP servers ----
    static func mcp(_ abs: String) -> [McpServer] {
        guard let obj = jsonObject(join(abs, ".mcp.json")),
              let servers = obj["mcpServers"] as? [String: Any] else { return [] }
        var out: [McpServer] = []
        for (name, v) in servers {
            guard let cfg = v as? [String: Any] else { continue }
            var transport = "stdio"
            var target = ""
            if let url = cfg["url"] as? String {
                transport = url.contains("/sse") ? "sse" : "http"
                target = url
            } else if let cmd = cfg["command"] as? String {
                let args = (cfg["args"] as? [String])?.joined(separator: " ") ?? ""
                target = ([cmd, args].filter { !$0.isEmpty }).joined(separator: " ")
                if let t = cfg["type"] as? String { transport = t }
            }
            out.append(McpServer(name: name, transport: transport, target: target,
                                 status: .configured, tools: [], broad: isBroadScope(target, abs: abs)))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// A filesystem MCP is "broad" only if it grants access to root, the home dir, or
    /// a path OUTSIDE the repo. A server correctly scoped to the repo (or a subdir)
    /// is NOT broad — the old `contains("server-filesystem /")` test flagged every
    /// absolute path, so a properly-scoped `… /Users/me/proj` cried wolf.
    private static func isBroadScope(_ target: String, abs: String) -> Bool {
        let fsServer = target.contains("filesystem")
        let toks = target.split(whereSeparator: { $0 == " " }).map(String.init)
        let home = NSHomeDirectory()
        let pathArgs = toks.filter { $0.hasPrefix("/") || $0.hasPrefix("~") || $0.contains("$HOME") }
        if !fsServer {
            // Non-filesystem server: only a bare-root grant reads as broad.
            return pathArgs.contains { $0 == "/" }
        }
        for raw in pathArgs {
            let p = (raw as NSString).expandingTildeInPath.replacingOccurrences(of: "$HOME", with: home)
            if p == "/" || p == home || p == home + "/" { return true }           // root / home
            if p != abs && !p.hasPrefix(abs + "/") { return true }                  // reaches outside the repo
        }
        return false
    }
}
