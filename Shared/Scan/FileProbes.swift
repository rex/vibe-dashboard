// FileProbes.swift — stack inference, line census, doc bloat, Serena state.

import Foundation

enum FileProbes {
    static var fm: FileManager { .default }
    static let skipDirs: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", ".venv", "venv",
        "dist", "build", "Pods", "Carthage", ".next", "__pycache__", ".serena",
        ".mypy_cache", ".ruff_cache", "vendor", ".idea", "target",
    ]

    static func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }
    static func join(_ base: String, _ c: String) -> String { (base as NSString).appendingPathComponent(c) }

    /// Fully-resolved canonical path. The file enumerator yields canonical URLs
    /// (e.g. /private/var/… for a /var/… input), so we canonicalize the repo root
    /// the same way before stripping it — otherwise a repo behind a symlink (or a
    /// /var temp dir) leaves a mangled relative path. Returns the input unchanged
    /// if it can't be resolved.
    static func canonical(_ path: String) -> String {
        guard let r = realpath(path, nil) else { return path }
        defer { free(r) }
        return String(cString: r)
    }

    // ---- stack / identity ----
    struct Identity: Sendable { var stack = "unknown"; var framework = "—"; var pm = "—"; var lifecycle = "brownfield" }

    static func identity(_ abs: String, vibe: [String: Any]?) -> Identity {
        var id = Identity()
        if let proj = vibe?["project"] as? [String: Any] {
            if let s = proj["stack"] as? String { id.stack = s }
            if let l = proj["lifecycle"] as? String { id.lifecycle = l }
        }
        if let stack = vibe?["stack"] as? [String: Any] {
            if let pm = stack["package_manager"] as? String { id.pm = pm }
            if let fw = stack["framework"] as? String { id.framework = fw }
        }
        if id.stack != "unknown" { return id }   // VIBE.yaml is authoritative

        // Infer from files.
        func has(_ f: String) -> Bool { exists(join(abs, f)) }
        if has("Package.swift") || hasSuffix(abs, ".xcodeproj") || has("project.yml") && has("Info.plist") {
            id.stack = "swift-apple"; id.framework = "swiftui"; id.pm = "spm"
        } else if has("pyproject.toml") || has("requirements.txt") || has("setup.py") {
            let py = (try? String(contentsOfFile: join(abs, "pyproject.toml"), encoding: .utf8)) ?? ""
            if py.contains("fastmcp") || py.contains("\"mcp\"") || py.contains("mcp[") { id.stack = "python-fastmcp"; id.framework = "fastmcp" }
            else if py.contains("fastapi") { id.stack = "python-fastapi"; id.framework = "fastapi" }
            else if has("ansible.cfg") || exists(join(abs, "roles")) { id.stack = "ansible-python"; id.framework = "ansible" }
            else { id.stack = "python-stdlib"; id.framework = "none" }
            id.pm = has("uv.lock") ? "uv" : "pip"
        } else if has("ansible.cfg") || exists(join(abs, "roles")) {
            id.stack = "ansible-python"; id.framework = "ansible"; id.pm = "uv"
        } else if has("package.json") {
            let pkg = (try? String(contentsOfFile: join(abs, "package.json"), encoding: .utf8)) ?? ""
            id.stack = pkg.contains("react") ? "react-spa-ts" : "node-ts"
            id.framework = pkg.contains("wxt") ? "wxt-react" : (pkg.contains("vite") ? "vite" : "node")
            id.pm = has("pnpm-lock.yaml") ? "pnpm" : (has("yarn.lock") ? "yarn" : "npm")
        } else if has("go.mod") {
            id.stack = "go"; id.framework = "stdlib"; id.pm = "go"
        }
        return id
    }
    private static func hasSuffix(_ abs: String, _ ext: String) -> Bool {
        (try? fm.contentsOfDirectory(atPath: abs))?.contains { $0.hasSuffix(ext) } ?? false
    }

    // ---- line census + free hygiene facts (one walk, one read per file) ----
    struct WalkResult: Sendable { var census = Census(); var conflicts: [String] = []; var junk: [String] = [] }

    static func walk(_ abs: String, soft: Int, hard: Int, ansible: Bool, excludes: [String] = []) -> WalkResult {
        var w = WalkResult()
        var c = Census()
        var files: [FileLines] = []
        let exts = ansible ? Reference.codeExtensions.union(Reference.ansibleExtensions) : Reference.codeExtensions
        // Compile the repo's exclude_globs ONCE (not per-file) — a file matching any
        // of them is out of architecture scope: shown for visibility, never graded.
        let excludeMatchers = excludes.compactMap { Glob.compile($0) }
        let base = canonical(abs)
        guard let en = fm.enumerator(at: URL(fileURLWithPath: base),
                                     includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles]) else { w.census = c; return w }
        for case let url as URL in en {
            let name = url.lastPathComponent
            if skipDirs.contains(name) { en.skipDescendants(); continue }
            let rel = url.path.replacingOccurrences(of: base + "/", with: "")
            if HygieneProbe.isJunkFile(name) { w.junk.append(rel) }
            guard exts.contains(url.pathExtension.lowercased()) else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let lines = data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 } + 1
            c.scanned += 1
            let excluded = excludeMatchers.contains { Glob.matches(path: rel, regex: $0) }
            if lines > soft && !excluded { c.softCount += 1 }
            if lines > hard {
                let fl = FileLines(path: rel, lines: lines, excluded: excluded)
                if excluded { c.excludedGodFiles.append(fl) } else { c.godFiles.append(fl) }
            }
            if HygieneProbe.hasConflictMarkers(data) { w.conflicts.append(rel) }
            files.append(FileLines(path: rel, lines: lines, excluded: excluded))
            if c.scanned > 5000 { break }   // safety cap
        }
        c.godFiles.sort { $0.lines > $1.lines }
        c.excludedGodFiles.sort { $0.lines > $1.lines }
        c.largest = Array(files.sorted { $0.lines > $1.lines }.prefix(8))
        w.census = c
        return w
    }

    // ---- doc bloat ----
    static func docs(_ abs: String, now: Date) async -> Docs {
        var d = Docs()
        d.taskState = docFile(abs, "TASK_STATE.md", limit: "taskState")
        d.agentsMd = docFile(abs, "AGENTS.md", limit: "agentsMd")
        d.claudeMd = docFile(abs, "CLAUDE.md", limit: "agentsMd")
        if let md = try? String(contentsOfFile: join(abs, "TASK_STATE.md"), encoding: .utf8) {
            d.taskStateMarkdown = md.count > 6000 ? String(md.prefix(6000)) + "\n\n_…elided._" : md
        }
        d.changelog = await changelog(abs, now: now)
        return d
    }
    private static func docFile(_ abs: String, _ name: String, limit: String) -> DocFile {
        let path = join(abs, name)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return DocFile(lines: 0, bytes: 0, status: .skip, present: false)
        }
        let lines = data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        let (soft, hard) = Reference.docLimits[limit] ?? (300, 500)
        let status: GateStatus = lines > hard ? .fail : (lines > soft ? .warn : .ok)
        return DocFile(lines: lines, bytes: data.count, status: status, present: true)
    }
    private static func changelog(_ abs: String, now: Date) async -> ChangelogInfo {
        guard exists(join(abs, "CHANGELOG.md")) else { return ChangelogInfo(lastUpdated: "—", behind: 0, status: .ok, present: false) }
        var info = ChangelogInfo(present: true)
        let last = await ProcessRunner.git(["log", "-1", "--format=%cI", "--", "CHANGELOG.md"], cwd: abs)
        if let d = ISO8601DateFormatter().date(from: last.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
            info.lastUpdated = RelTime.ago(d, now: now)
        }
        let hashR = await ProcessRunner.git(["log", "-1", "--format=%H", "--", "CHANGELOG.md"], cwd: abs)
        let hash = hashR.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hash.isEmpty {
            let cnt = await ProcessRunner.git(["rev-list", "--count", "\(hash)..HEAD"], cwd: abs)
            info.behind = Int(cnt.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        info.status = info.behind > 8 ? .fail : (info.behind > 3 ? .warn : .ok)
        return info
    }

    // ---- Serena ----
    static func serena(_ abs: String, now: Date) -> SerenaState? {
        let dir = join(abs, ".serena")
        guard exists(dir) else { return nil }
        var s = SerenaState(present: true)
        let memDir = join(dir, "memories")
        if let mems = try? fm.contentsOfDirectory(atPath: memDir) {
            s.memories = mems.filter { $0.hasSuffix(".md") }.count
        }
        if let proj = try? String(contentsOfFile: join(dir, "project.yml"), encoding: .utf8),
           let nameLine = proj.split(separator: "\n").first(where: { $0.contains("project_name") || $0.hasPrefix("name") }) {
            s.project = nameLine.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "") } ?? (abs as NSString).lastPathComponent
        } else { s.project = (abs as NSString).lastPathComponent }
        if let attrs = try? fm.attributesOfItem(atPath: dir), let mod = attrs[.modificationDate] as? Date {
            s.lastSession = RelTime.ago(mod, now: now)
            s.active = now.timeIntervalSince(mod) < 900   // touched in last 15 min
        }
        return s
    }
}
