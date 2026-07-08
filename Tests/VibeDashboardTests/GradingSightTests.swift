import Testing
import Foundation
@testable import VibeDashboard

/// GRADING SIGHT — the surprises the probe layer used to MISS (false-negatives) and
/// the false-positives that manufactured noise. Each test pins the pure, reachable
/// logic behind a Tier-1 fix so the tool never shows something fake as real: a real
/// god-file isn't invented from a trailing newline, a real secret isn't overlooked, a
/// healthy changelog isn't failed by ordinary commit volume, stranded detached
/// worktrees aren't dropped, and a policy-less VIBE.yaml can't launder itself managed.
@Suite("Grading sight")
struct GradingSightTests {
    private func tempRepo(_ files: [String: String]) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gsight-" + UUID().uuidString)
        for (rel, body) in files {
            let url = dir.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
        return dir.path
    }
    private func swiftBody(lines n: Int, trailingNewline: Bool) -> String {
        let content = Array(repeating: "let x = 0", count: n).joined(separator: "\n")
        return trailingNewline ? content + "\n" : content
    }

    // MARK: (a) census off-by-one / CRLF — a trailing newline is a terminator, not a line

    @Test("lineCount uses one convention: a trailing newline terminates, CR is ignored")
    func lineCountConvention() {
        #expect(FileProbes.lineCount(Data("a\nb\nc\n".utf8)) == 3)   // trailing nl terminates the 3rd line
        #expect(FileProbes.lineCount(Data("a\nb\nc".utf8)) == 3)     // an unterminated last line still counts
        #expect(FileProbes.lineCount(Data("a\r\nb\r\n".utf8)) == 2)  // CRLF counts the same as LF
        #expect(FileProbes.lineCount(Data()) == 0)                    // empty file → 0
        #expect(FileProbes.lineCount(Data("\n".utf8)) == 1)           // a lone newline is one (empty) line
    }

    @Test("a file with exactly `hard` content lines + a trailing newline is NOT a god-file")
    func exactHardNotGodFile() {
        let repo = tempRepo([
            "Exact.swift":     swiftBody(lines: 400, trailingNewline: true),   // exactly hard, terminated
            "ExactNoNL.swift": swiftBody(lines: 400, trailingNewline: false),  // exactly hard, unterminated
            "Over.swift":      swiftBody(lines: 401, trailingNewline: true),   // hard + 1
        ])
        let god = Set(FileProbes.walk(repo, soft: 250, hard: 400, ansible: false).census.godFiles.map(\.path))
        #expect(!god.contains("Exact.swift"))       // exactly hard → in policy, never flagged
        #expect(!god.contains("ExactNoNL.swift"))   // same without the trailing newline
        #expect(god.contains("Over.swift"))         // hard + 1 → still correctly flagged
    }

    // MARK: (b) secret globs — catch modern keys, never a .env.example or a source file

    @Test("isTrackedSecret catches modern key material yet excludes .env.example and source files")
    func secretClassification() {
        // Modern keys the old spec silently missed.
        #expect(HygieneProbe.isTrackedSecret("id_ed25519"))
        #expect(HygieneProbe.isTrackedSecret("deploy/id_ecdsa"))
        #expect(HygieneProbe.isTrackedSecret("certs/server.key"))
        #expect(HygieneProbe.isTrackedSecret(".netrc"))
        #expect(HygieneProbe.isTrackedSecret(".npmrc"))
        #expect(HygieneProbe.isTrackedSecret(".aws/credentials"))
        #expect(HygieneProbe.isTrackedSecret("gcp-credentials.json"))
        #expect(HygieneProbe.isTrackedSecret("serviceAccount.json"))
        // Pre-existing coverage preserved.
        #expect(HygieneProbe.isTrackedSecret(".env"))
        #expect(HygieneProbe.isTrackedSecret(".env.local"))
        #expect(HygieneProbe.isTrackedSecret("config/id_rsa"))
        #expect(HygieneProbe.isTrackedSecret("cert.pem"))
        // The .env safe-exclusion still holds (v0.22 — must not regress).
        #expect(!HygieneProbe.isTrackedSecret(".env.example"))
        #expect(!HygieneProbe.isTrackedSecret(".env.sample"))
        // Near-zero false positives: source / docs / example config that merely mention credentials.
        #expect(!HygieneProbe.isTrackedSecret("Sources/CredentialsManager.swift"))
        #expect(!HygieneProbe.isTrackedSecret("credentials.example.json"))
        #expect(!HygieneProbe.isTrackedSecret("README.md"))
        #expect(!HygieneProbe.isTrackedSecret("main.swift"))
    }

    // MARK: (c) changelog staleness by version delta — commit count is no longer an input

    @Test("changelog staleness is a version delta — a header matching VERSION never fails")
    func changelogVersionDelta() {
        // The signature takes NO commit count — that IS the anti-alert-fatigue fix: a
        // repo whose changelog header matches VERSION is in-sync no matter how many
        // commits (each auto-bumping VERSION) have landed since.
        let match = FileProbes.changelogStaleness(current: "0.24.1", documented: "0.24.1")
        #expect(match.status == .ok)
        #expect(match.behind == 0)

        // A few undocumented PATCH bumps (ordinary per-commit volume) stay non-fatal.
        #expect(FileProbes.changelogStaleness(current: "0.24.5", documented: "0.24.0").status == .ok)
        // A whole minor undocumented ⇒ warn; several ⇒ fail; a major behind ⇒ fail.
        #expect(FileProbes.changelogStaleness(current: "0.25.0", documented: "0.24.0").status == .warn)
        #expect(FileProbes.changelogStaleness(current: "0.27.0", documented: "0.24.0").status == .fail)
        #expect(FileProbes.changelogStaleness(current: "1.0.0",  documented: "0.9.0").status == .fail)
        // Changelog AHEAD of VERSION (an unreleased entry staged) is fine, not "behind".
        #expect(FileProbes.changelogStaleness(current: "0.24.0", documented: "0.24.1").status == .ok)
        // Indeterminate (missing VERSION or unparseable header) ⇒ never a manufactured fail.
        #expect(FileProbes.changelogStaleness(current: nil, documented: "0.1.0").status == .ok)
        #expect(FileProbes.changelogStaleness(current: "0.1.0", documented: nil).status == .ok)

        // Header extraction skips `## [Unreleased]` and lands on the first versioned entry.
        let text = "# Changelog\n\n## [Unreleased]\n\n## [0.24.1] — 2026-07-08\n- fix\n\n## [0.24.0]\n"
        #expect(FileProbes.firstSemVerHeader(text) == "0.24.1")
        #expect(FileProbes.firstSemVerHeader("# Changelog\n\nno versions here\n") == nil)
    }

    // MARK: Task 1 — detached-HEAD worktrees are recorded, not dropped

    @Test("parseWorktrees records a detached worktree under a synthetic label; drops the main worktree")
    func worktreeDetached() {
        let porcelain = """
        worktree /repo/main
        HEAD aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        branch refs/heads/main

        worktree /repo/feat
        HEAD bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
        branch refs/heads/feature

        worktree /repo/det
        HEAD cccccccc11112222333344445555666677778888
        detached

        """
        let pairs = GitProbe.parseWorktrees(porcelain, repoAbs: "/repo/main")
        let byPath = Dictionary(uniqueKeysWithValues: pairs.map { ($0.path, $0.branch) })
        #expect(pairs.count == 2)
        #expect(byPath["/repo/main"] == nil)                 // the main worktree is excluded
        #expect(byPath["/repo/feat"] == "feature")           // refs/heads/ stripped
        #expect(byPath["/repo/det"] == "detached@cccccccc")  // detached recorded (was silently dropped)
    }

    // MARK: Task 2 — signature detected by PRESENCE (raw gpgsig header), gpg never run

    @Test("isSignedCommitObject: a gpgsig header ⇒ signed; message mentions don't false-positive")
    func signaturePresence() {
        let signed = "tree a\nparent b\nauthor X 1 +0\ncommitter X 1 +0\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n\nmsg"
        let ssh = "tree a\nauthor X 1 +0\ncommitter X 1 +0\ngpgsig-sha256 -----BEGIN SSH SIGNATURE-----\n \n\nmsg"
        let unsigned = "tree a\nparent b\nauthor X 1 +0\ncommitter X 1 +0\n\nmsg"
        let mentionsInBody = "tree a\nauthor X 1 +0\ncommitter X 1 +0\n\nrefactor gpgsig parsing"  // in the MESSAGE only
        #expect(GitProbe.isSignedCommitObject(signed))
        #expect(GitProbe.isSignedCommitObject(ssh))
        #expect(!GitProbe.isSignedCommitObject(unsigned))
        #expect(!GitProbe.isSignedCommitObject(mentionsInBody))   // header block only — no cry-wolf
        #expect(!GitProbe.isSignedCommitObject(""))               // no object ⇒ not detectable here (caller keeps default)
    }

    // MARK: Task 6 — git hooks get stub/missing classification + absolute hooksPath

    @Test("classifyGitHook mirrors the claude-hook stub/missing logic")
    func gitHookClassification() {
        let abs = "/nonexistent-\(UUID().uuidString)"
        #expect(HooksMcpProbe.classifyGitHook(body: "#!/bin/sh\nexit 0\n", data: Data("x".utf8), abs: abs) == .nothing)
        #expect(HooksMcpProbe.classifyGitHook(body: "#!/bin/sh\nexec ./missing.sh \"$@\"\n", data: Data("x".utf8), abs: abs) == .missing)
        #expect(HooksMcpProbe.classifyGitHook(body: "#!/bin/sh\ngit diff --check\n", data: Data("x".utf8), abs: abs) == .active)
        // Command-substitution / unexpanded var ⇒ unverifiable ⇒ don't cry wolf (.active).
        #expect(HooksMcpProbe.classifyGitHook(body: "#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\"\n", data: Data("x".utf8), abs: abs) == .active)
        // Empty file ⇒ nothing; binary/compiled hook ⇒ active (doing work we can't introspect).
        #expect(HooksMcpProbe.classifyGitHook(body: "", data: Data(), abs: abs) == .nothing)
        #expect(HooksMcpProbe.classifyGitHook(body: "", data: Data([0xFF, 0xD8]), abs: abs) == .active)
    }

    @Test("gitHooksDir honors an ABSOLUTE core.hooksPath instead of mis-joining it onto the repo")
    func hooksPathAbsolute() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("gsight-hp-" + UUID().uuidString)
        let git = base.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let cfg = git.appendingPathComponent("config")

        try? "[core]\n\thooksPath = /opt/team/githooks\n".write(to: cfg, atomically: true, encoding: .utf8)
        #expect(HooksMcpProbe.gitHooksDir(base.path) == "/opt/team/githooks")   // absolute stands alone
        try? "[core]\n\thooksPath = .githooks\n".write(to: cfg, atomically: true, encoding: .utf8)
        #expect(HooksMcpProbe.gitHooksDir(base.path) == base.path + "/.githooks")  // relative joins onto repo
        try? "[core]\n\tbare = false\n".write(to: cfg, atomically: true, encoding: .utf8)
        #expect(HooksMcpProbe.gitHooksDir(base.path) == base.path + "/.git/hooks") // no override ⇒ default
    }

    // MARK: Task 7 — an empty/stub VIBE.yaml can't launder a repo into "managed"

    @Test("a parsed VIBE.yaml with no enforceable section is detected as a stub and surfaced")
    func policyStub() {
        // Pure PolicyProbe detection over the built policy sections.
        func section(_ name: String) -> PolicySection { PolicySection(section: name, rows: [PolicyRow(k: "k", v: "v")]) }
        #expect(PolicyProbe.declaresNoEnforceablePolicy(sections: []))                      // empty doc
        #expect(PolicyProbe.declaresNoEnforceablePolicy(sections: [section("project")]))    // project-only stub
        #expect(PolicyProbe.declaresNoEnforceablePolicy(sections: [section("project"), section("stack")]))
        #expect(!PolicyProbe.declaresNoEnforceablePolicy(sections: [section("architecture")]))  // real policy
        #expect(!PolicyProbe.declaresNoEnforceablePolicy(sections: [section("project"), section("workflow")]))

        // Derive detection from the built sections, plus the surfaced finding + honest health.
        var stub = Repo(id: "x", name: "x", path: "~/x", absolutePath: "/x")
        stub.vibePresent = true
        stub.policy = [PolicySection(section: "project", rows: [PolicyRow(k: "stack", v: "go")])]
        #expect(Derive.isPolicyStub(stub))
        #expect(Derive.health(stub, signedRequired: false) == .danger)   // no longer laundered green
        #expect(Derive.surprises(stub, signedRequired: false, hardLimit: 400).contains { $0.what.contains("no enforceable policy") })

        // A repo with a real architecture section is NOT a stub.
        var governed = Repo(id: "y", name: "y", path: "~/y", absolutePath: "/y")
        governed.vibePresent = true
        governed.policy = [PolicySection(section: "architecture", rows: [PolicyRow(k: "hard", v: "400")])]
        #expect(!Derive.isPolicyStub(governed))
        #expect(!Derive.surprises(governed, signedRequired: false, hardLimit: 400).contains { $0.what.contains("no enforceable policy") })

        // A malformed VIBE (didn't parse) is handled by its own path, not the stub finding.
        var malformed = Repo(id: "z", name: "z", path: "~/z", absolutePath: "/z")
        malformed.vibePresent = true
        malformed.vibeMalformed = true
        #expect(!Derive.isPolicyStub(malformed))
    }
}
