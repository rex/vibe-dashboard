// DeriveIntegrations.swift — Makefile / SCM / CI / containers / skills / build.

import Foundation
import Yams

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
            .sorted()
            .map { CiWorkflow(name: $0, trigger: workflowTrigger(join(dir, $0)), status: .skip, last: "—") }
        // Triggers are read straight from each workflow's `on:` block, but we never
        // query the provider for run results — so there is no pass/fail to grade and
        // no last-run to show. Report the configuration and leave both unassessed
        // rather than invent a grade or a green "ok".
        return CiInfo(provider: provider, configured: true, workflows: workflows, grade: "n/a",
                      notes: [Note(tone: .neutral, text: "\(provider) · \(workflows.count) workflow(s) · run status not checked")])
    }

    /// The real trigger string for one workflow file, parsed from its `on:` block.
    /// Honest by construction: any read/parse failure — or a missing `on:` — yields
    /// "—" (unknown), NEVER a fabricated default. Note the YAML 1.1 footgun: a bare
    /// `on:` key resolves to Bool(`true`), so we look it up under both spellings.
    static func workflowTrigger(_ path: String) -> String {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let raw = try? Yams.load(yaml: text),
              let top = raw as? [AnyHashable: Any] else { return "—" }
        let onValue = top.first { entry in
            if let k = entry.key.base as? String { return k == "on" }
            if let b = entry.key.base as? Bool { return b == true }
            return false
        }?.value
        let events = triggerEvents(from: onValue)
        return events.isEmpty ? "—" : events.joined(separator: " · ")
    }

    /// Event names from an `on:` value — scalar (`push`), sequence
    /// (`[push, pull_request]`), or mapping (`push: … / schedule: …`) — de-duped and
    /// sorted into a stable canonical order (map keys arrive unordered).
    static func triggerEvents(from value: Any?) -> [String] {
        guard let value else { return [] }
        var names: [String] = []
        if let s = value as? String {
            names = [s]
        } else if let arr = value as? [Any] {
            names = arr.compactMap { $0 as? String }
        } else if let map = value as? [AnyHashable: Any] {
            names = map.keys.compactMap { $0.base as? String }
        } else {
            return []
        }
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var seen = Set<String>()
        return cleaned.filter { seen.insert($0).inserted }.sorted(by: triggerBefore)
    }

    private static let triggerOrder = [
        "push", "pull_request", "pull_request_target", "workflow_dispatch",
        "schedule", "release", "workflow_call", "workflow_run", "merge_group",
    ]
    /// Known events sort by `triggerOrder`; unknowns follow, alphabetically.
    private static func triggerBefore(_ a: String, _ b: String) -> Bool {
        switch (triggerOrder.firstIndex(of: a), triggerOrder.firstIndex(of: b)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a < b
        }
    }

    static func containers(_ abs: String) -> Containers {
        let hasDockerfile = exists(join(abs, "Dockerfile"))
        let composePath = ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"]
            .map { join(abs, $0) }.first(where: exists)
        guard hasDockerfile || composePath != nil else {
            return Containers(configured: false, items: [], grade: "n/a",
                              notes: [Note(tone: .neutral, text: "no container build")])
        }
        var items: [ContainerItem] = []
        var notes: [Note] = []
        if hasDockerfile {
            let item = dockerfileItem(abs)
            items.append(item)
            notes += item.checks.filter { !$0.ok }.map { Note(tone: .warn, text: "Dockerfile: \($0.text)") }
        }
        if let composePath {
            let item = composeItem(composePath)
            items.append(item)
            notes += item.checks.filter { !$0.ok }.map { Note(tone: .warn, text: "compose: \($0.text)") }
            if item.grade == "n/a" { notes.append(Note(tone: .neutral, text: "compose: present · not assessed")) }
        }
        if notes.isEmpty {
            notes = [Note(tone: .ok, text: hasDockerfile ? "pinned, non-root, healthchecked" : "compose checks passed")]
        }
        return Containers(configured: true, items: items, grade: worstGrade(items.map(\.grade)), notes: notes)
    }

    /// Dockerfile checks — all read from the file, all real.
    private static func dockerfileItem(_ abs: String) -> ContainerItem {
        let body = (try? String(contentsOfFile: join(abs, "Dockerfile"), encoding: .utf8)) ?? ""
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
        return ContainerItem(kind: "dockerfile", path: "Dockerfile",
                             checks: checks, grade: letterGrade(fails: checks.filter { !$0.ok }.count))
    }

    /// Compose checks derived from the file's own `services:` — image-tag pinning,
    /// restart policy, healthcheck. Unparsable or service-less → an honest "n/a" item
    /// with no invented checks and no letter grade (never the old canned "B").
    static func composeItem(_ path: String) -> ContainerItem {
        let rel = (path as NSString).lastPathComponent
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let root = (try? Yams.load(yaml: text)) as? [AnyHashable: Any],
              let services = root["services"] as? [AnyHashable: Any], !services.isEmpty else {
            return ContainerItem(kind: "compose", path: rel, checks: [], grade: "n/a")
        }
        var images: [String] = []
        var anyRestart = false
        var anyHealthcheck = false
        for raw in services.values {
            guard let svc = raw as? [AnyHashable: Any] else { continue }
            if let image = svc["image"] as? String { images.append(image) }
            // `restart: "no"` (or unquoted `no` → YAML false) IS the no-restart
            // default, so a bare presence check would over-credit; require a real policy.
            if let restart = svc["restart"] as? String,
               !["", "no"].contains(restart.lowercased()) { anyRestart = true }
            // `healthcheck: {disable: true}` explicitly turns the check off — don't count it.
            if let hc = svc["healthcheck"] as? [AnyHashable: Any],
               (hc["disable"] as? Bool) != true { anyHealthcheck = true }
        }
        var checks: [CheckItem] = []
        if !images.isEmpty {           // only meaningful when a service pulls an image
            let unpinned = images.filter(imageIsUnpinned)
            checks.append(CheckItem(ok: unpinned.isEmpty,
                text: unpinned.isEmpty ? "image tags pinned" : "unpinned image: \(unpinned[0])"))
        }
        checks.append(CheckItem(ok: anyRestart, text: anyRestart ? "restart policy set" : "no restart policy"))
        checks.append(CheckItem(ok: anyHealthcheck, text: anyHealthcheck ? "healthcheck defined" : "no healthcheck"))
        return ContainerItem(kind: "compose", path: rel,
                             checks: checks, grade: letterGrade(fails: checks.filter { !$0.ok }.count))
    }

    /// An image ref is unpinned if it has no tag or an explicit `:latest`
    /// (`@sha256:…` digests count as pinned; a registry `host:port/` is not a tag).
    private static func imageIsUnpinned(_ image: String) -> Bool {
        if image.contains("@sha256:") { return false }
        let namePart = image.lastIndex(of: "/").map { String(image[image.index(after: $0)...]) } ?? image
        guard let colon = namePart.lastIndex(of: ":") else { return true }
        let tag = namePart[namePart.index(after: colon)...]
        return tag.isEmpty || tag == "latest"
    }

    private static func letterGrade(fails: Int) -> String {
        fails == 0 ? "A" : fails == 1 ? "B" : fails == 2 ? "C" : "D"
    }

    /// Worst (red-most) letter among gradable items; non-letters ("n/a") ignored.
    /// Lexically A<B<C<D<F, so `max` is the worst; nothing gradable → "n/a".
    private static func worstGrade(_ grades: [String]) -> String {
        grades.filter { ["A", "B", "C", "D", "F"].contains($0) }.max() ?? "n/a"
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
            let semverLine = v.split(separator: "\n").first {
                $0.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil
            }
            if let sem = semverLine {
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
