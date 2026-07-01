// DeriveIntegrations.swift — Makefile / SCM / CI / containers / skills / build.

import Foundation

enum DeriveIntegrations {
    static var fm: FileManager { .default }
    private static func join(_ a: String, _ b: String) -> String { (a as NSString).appendingPathComponent(b) }
    private static func exists(_ p: String) -> Bool { fm.fileExists(atPath: p) }

    private static let targetDesc: [String: String] = [
        "help": "list every target", "install": "resolve + install deps", "lint": "ruff / eslint / swiftlint",
        "format": "format the tree", "typecheck": "mypy / tsc / build-for-testing", "test": "run the test suite",
        "validate": "lint · type · arch · tests — the gate", "check-architecture": "file-size + module-fanout audit",
        "check-skeleton": "diff skeleton-owned files", "check-docs": "doc-size + freshness audit",
        "build": "production build", "build-mac": "build the macOS app", "regenerate": "xcodegen generate",
        "docker-build": "build the container image", "compose-up": "docker compose up -d",
        "coverage": "coverage report", "clean": "remove caches + artifacts", "run": "launch the app",
    ]
    private static let targetKind: [String: TargetKind] = [
        "help": .util, "install": .util, "format": .util, "clean": .util, "regenerate": .util,
        "build": .run, "build-mac": .run, "run": .run, "dev": .run, "docker-build": .run, "compose-up": .run, "coverage": .run,
    ]

    static func makefile(_ abs: String) -> MakefileInfo {
        guard let text = try? String(contentsOfFile: join(abs, "Makefile"), encoding: .utf8) else {
            return MakefileInfo(count: 0, note: "no Makefile", targets: [])
        }
        var names: [String] = []
        for line in text.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon])
            guard name.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil else { continue }
            if !names.contains(name) { names.append(name) }
        }
        let targets = names.map { MakeTarget(name: $0, desc: targetDesc[$0] ?? $0, kind: targetKind[$0] ?? .gate) }
        return MakefileInfo(count: targets.count, note: nil, targets: targets)
    }

    static func scm(branch: String, remotes: [Remote], worktree: WorktreeState, signedRequired: Bool) -> Scm {
        var grade = "A"
        var notes: [Note] = []
        if !worktree.signed {
            if signedRequired { grade = "F"; notes.append(Note(tone: .danger, text: "commits are not signed — signed_commits_required is true")) }
            else { notes.append(Note(tone: .warn, text: "commits are not GPG-signed")) }
        } else {
            notes.append(Note(tone: .ok, text: "commit signature verified"))
        }
        if worktree.unpushed > 0 {
            if grade == "A" { grade = worktree.unpushed > 3 ? "C" : "B" }
            notes.append(Note(tone: .warn, text: "\(worktree.unpushed) commit(s) ahead — not pushed"))
        } else if remotes.isEmpty {
            notes.append(Note(tone: .warn, text: "no remote configured"))
            if grade == "A" { grade = "B" }
        } else {
            notes.append(Note(tone: .ok, text: "in sync with remote"))
        }
        if !worktree.clean { notes.append(Note(tone: .warn, text: "\(worktree.unstaged) uncommitted change(s)")) }
        return Scm(branch: branch, remotes: remotes, grade: grade, notes: notes, signed: worktree.signed)
    }

    static func ci(_ abs: String, stack: String) -> CiInfo {
        let gh = join(abs, ".github/workflows")
        let gitea = join(abs, ".gitea/workflows")
        let dir = exists(gh) ? gh : (exists(gitea) ? gitea : nil)
        guard let dir, let files = try? fm.contentsOfDirectory(atPath: dir) else {
            let ships = stack.contains("fastapi") || stack.contains("fastmcp") || stack.contains("swift") || stack.contains("react")
            return CiInfo(provider: "none", configured: false, workflows: [], grade: ships ? "D" : "C",
                          notes: [Note(tone: ships ? .warn : .neutral, text: "no CI workflow — gates run locally only")])
        }
        let provider = dir == gh ? "github-actions" : "gitea-actions"
        let workflows = files.filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }
            .map { CiWorkflow(name: $0, trigger: "push · pull_request", status: .skip, last: "—") }
        return CiInfo(provider: provider, configured: true, workflows: workflows, grade: "B",
                      notes: [Note(tone: .ok, text: "\(provider) · \(workflows.count) workflow(s)")])
    }

    static func containers(_ abs: String) -> Containers {
        let dockerfile = join(abs, "Dockerfile")
        guard exists(dockerfile) else {
            return Containers(configured: false, items: [], grade: "n/a",
                              notes: [Note(tone: .neutral, text: "no container build")])
        }
        let body = (try? String(contentsOfFile: dockerfile, encoding: .utf8)) ?? ""
        let pinned = !body.contains(":latest") && body.contains("FROM")
        let nonroot = body.contains("USER ")
        let health = body.contains("HEALTHCHECK")
        let ignore = exists(join(abs, ".dockerignore"))
        let checks = [
            CheckItem(ok: pinned, text: pinned ? "base image pinned" : "base image is :latest — not pinned"),
            CheckItem(ok: nonroot, text: nonroot ? "runs as non-root USER" : "runs as root — no USER directive"),
            CheckItem(ok: ignore, text: ignore ? ".dockerignore present" : "no .dockerignore"),
            CheckItem(ok: health, text: health ? "HEALTHCHECK defined" : "no HEALTHCHECK"),
        ]
        let fails = checks.filter { !$0.ok }.count
        let grade = fails == 0 ? "A" : fails == 1 ? "B" : fails == 2 ? "C" : "D"
        let item = ContainerItem(kind: "dockerfile", path: "Dockerfile", checks: checks, grade: grade)
        var items = [item]
        if exists(join(abs, "docker-compose.yml")) || exists(join(abs, "compose.yml")) {
            items.append(ContainerItem(kind: "compose", path: "docker-compose.yml",
                checks: [CheckItem(ok: true, text: "compose file present")], grade: "B"))
        }
        let notes = checks.filter { !$0.ok }.map { Note(tone: .warn, text: "Dockerfile: \($0.text)") }
        return Containers(configured: true, items: items, grade: grade,
                          notes: notes.isEmpty ? [Note(tone: .ok, text: "pinned, non-root, healthchecked")] : notes)
    }

    // Skill usage is INFERRED from tech, because the skeleton records no per-repo
    // skill manifest (a real hole — see SkeletonProbe). project.stack is free-form
    // ("swift-apple" / "swift-macos" / "swift-ios-watchos"), so we detect by the
    // actual stack family + files on disk rather than an exact string match — that
    // brittle `== "swift-apple"` is why lang-swift-apple used to show "used by 1".
    static func skills(_ abs: String, vibe: [String: Any]?, stack: String) -> [SkillUse] {
        var out: [SkillUse] = []
        let s = stack.lowercased()
        func has(_ f: String) -> Bool { exists(join(abs, f)) }
        func hasNs(_ k: String) -> Bool { vibe?[k] != nil }

        if exists(join(abs, "AGENTS.md")) || exists(join(abs, "VIBE.yaml")) {
            var v: String? = nil
            if let sv = try? String(contentsOfFile: join(abs, ".claude/skeleton-version"), encoding: .utf8) {
                v = sv.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            out.append(SkillUse(skillId: "agentic-skeleton", installed: v, status: v == nil ? .drift : .ok,
                                note: v == nil ? "not stamped — no .claude/skeleton-version" : nil))
        }
        // Any Apple/Swift repo, however its stack string is spelled.
        let isSwift = ["swift", "apple", "ios", "macos", "watchos", "tvos", "xcode"].contains { s.contains($0) }
            || has("Package.swift") || has("project.yml") || dirHasXcodeproj(abs)
        if isSwift {
            out.append(SkillUse(skillId: "lang-swift-apple", installed: nil, status: .ok,
                                note: hasNs("apple") ? nil : "inferred from stack — no apple: namespace in VIBE.yaml"))
        }
        if s.contains("python") || s.contains("ansible") || has("pyproject.toml") || has("requirements.txt") {
            out.append(SkillUse(skillId: "lang-python", installed: nil, status: .ok,
                                note: hasNs("python") ? nil : "inferred from stack"))
        }
        if s.contains("mcp") { out.append(SkillUse(skillId: "lang-mcp", installed: nil, status: .ok)) }
        if s.contains("react") || s.contains("next") || s.contains("vite") || s.contains("spa") {
            out.append(SkillUse(skillId: "lang-react-spa", installed: nil, status: .ok))
        }
        if s == "go" || s.hasPrefix("go-") || s.contains("golang") || has("go.mod") {
            out.append(SkillUse(skillId: "lang-go", installed: nil, status: .ok))
        }
        if has("Dockerfile") { out.append(SkillUse(skillId: "lang-docker", installed: nil, status: .ok,
                                                   note: hasNs("docker") ? nil : "Dockerfile present — no docker: namespace")) }
        if exists(join(abs, ".github/workflows")) || exists(join(abs, ".gitea/workflows")) {
            out.append(SkillUse(skillId: "tool-ci", installed: nil, status: hasNs("ci") ? .ok : .drift,
                                note: hasNs("ci") ? nil : "no ci: namespace in VIBE.yaml"))
        }
        return out
    }
    private static func dirHasXcodeproj(_ abs: String) -> Bool {
        (try? fm.contentsOfDirectory(atPath: abs))?.contains { $0.hasSuffix(".xcodeproj") } ?? false
    }

    static func build(_ abs: String, git: GitFacts) -> RepoBuild {
        var version = "v0.1.0"
        if let v = try? String(contentsOfFile: join(abs, "VERSION"), encoding: .utf8) {
            if let sem = v.split(separator: "\n").first(where: { $0.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil }) {
                version = "v" + sem.trimmingCharacters(in: .whitespaces)
            } else if let major = value(in: v, key: "MAJOR"), let minor = value(in: v, key: "MINOR_BASE") {
                version = "v\(major).\(minor).0"
            }
        }
        return RepoBuild(version: version, commit: git.commitShort, date: git.commitDateRel,
                         dirty: !git.worktree.clean, branch: git.branch)
    }
    private static func value(in text: String, key: String) -> String? {
        text.split(separator: "\n").first { $0.hasPrefix("\(key)=") }?
            .split(separator: "=").last.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
