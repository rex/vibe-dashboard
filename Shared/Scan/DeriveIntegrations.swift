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
        // Dirty/unpushed trees are problems fleet-wide, so grade them red here too
        // (single letters A<B<C<D<F sort lexically; keep the worse of the two).
        func worse(_ a: String, _ b: String) -> String { a > b ? a : b }
        if worktree.unpushed > 0 {
            grade = worse(grade, "D")
            notes.append(Note(tone: .danger, text: "\(worktree.unpushed) commit(s) ahead — not pushed"))
        } else if remotes.isEmpty {
            notes.append(Note(tone: .warn, text: "no remote configured"))
            if grade == "A" { grade = "B" }
        } else {
            notes.append(Note(tone: .ok, text: "in sync with remote"))
        }
        if !worktree.clean {
            grade = worse(grade, "F")
            notes.append(Note(tone: .danger, text: "\(worktree.unstaged) uncommitted change(s)"))
        }
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

    // Skills are reported ONLY from real provenance — NEVER inferred from code.
    // Capability-driven detection ("has .swift → lang-swift-apple is applied") is a
    // lie: it claims a skill governs a repo that may never have adopted it, which is
    // worse than no detection. The authoritative record is a `skills:` block in
    // VIBE.yaml (id + version + when-applied) that the skeleton must write on apply.
    // Until a repo records that, its lang/tool skills are simply UNKNOWN — and the
    // app says so rather than guess. The only other honest signal is the on-disk
    // skeleton stamp (.claude/skeleton-version), which is a real artifact, not a guess.
    static func skills(_ abs: String, vibe: [String: Any]?, stack: String) -> [SkillUse] {
        var out: [SkillUse] = []
        var seen = Set<String>()
        func emit(_ id: String, version: String?, status: SkillState, note: String? = nil) {
            guard !seen.contains(id) else { return }
            seen.insert(id)
            out.append(SkillUse(skillId: id, installed: version, status: status, note: note))
        }
        // 1) Authoritative: skills the repo RECORDS in its VIBE.yaml.
        if let recorded = vibe?["skills"] as? [[String: Any]] {
            for entry in recorded {
                guard let id = entry["id"] as? String else { continue }
                emit(id, version: entry["version"].map { "\($0)" }, status: .ok)
            }
        } else if let ids = vibe?["skills"] as? [String] {
            for id in ids { emit(id, version: nil, status: .ok) }
        }
        // 2) Real on-disk artifact (not inference): the skeleton stamp.
        if exists(join(abs, ".claude/skeleton-version")) || exists(join(abs, "VIBE.yaml")) {
            let v = (try? String(contentsOfFile: join(abs, ".claude/skeleton-version"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stamped = (v?.isEmpty == false)
            emit("agentic-skeleton", version: stamped ? v : nil, status: stamped ? .ok : .drift,
                 note: stamped ? nil : "not stamped — no .claude/skeleton-version")
        }
        return out
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
