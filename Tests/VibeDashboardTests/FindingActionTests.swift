import Testing
@testable import VibeDashboard

// The finding-action layer is the app's second write surface (after git): it appends to
// a repo's .gitignore and hands AI-only fixes to a coding agent via the clipboard. The
// risky logic is PURE and pinned here without touching disk or SwiftUI — the .gitignore
// edit must be additive + idempotent (never a duplicate, never a rewrite), and every
// generated agent prompt must carry enough context (absolute repo path, the exact file,
// its size, the limit) to be pasted and acted on with zero back-reference.

// MARK: - .gitignore append (additive + idempotent)

@Suite("gitignore append is additive and idempotent")
struct GitignoreEditorTests {
    @Test("appending to an empty file adds the path on its own line")
    func appendToEmpty() {
        let (text, changed) = GitignoreEditor.append(to: "", path: "build/output.log")
        #expect(changed)
        #expect(text == "build/output.log\n")
    }

    @Test("adding the same path twice is a no-op the second time (idempotent)")
    func idempotent() {
        let (once, c1) = GitignoreEditor.append(to: "node_modules\n", path: "secrets/.env")
        #expect(c1)
        let (twice, c2) = GitignoreEditor.append(to: once, path: "secrets/.env")
        #expect(!c2)
        #expect(twice == once)                                   // returned unmodified
        #expect(twice.components(separatedBy: "secrets/.env").count - 1 == 1)   // exactly one entry
    }

    @Test("an already-present path is detected regardless of surrounding blank lines / CRLF spacing")
    func containsExactLine() {
        let body = "# deps\nnode_modules\n\n  dist/  \n"
        #expect(GitignoreEditor.contains(body, path: "node_modules"))
        #expect(GitignoreEditor.contains(body, path: "dist/"))          // trimmed match
        #expect(!GitignoreEditor.contains(body, path: "dist"))          // not a substring match
        #expect(!GitignoreEditor.contains(body, path: "node"))
    }

    @Test("existing content is preserved and a missing trailing newline is repaired before appending")
    func preservesAndRepairs() {
        let (text, changed) = GitignoreEditor.append(to: "a.txt\nb.txt", path: "c.txt")  // no trailing \n
        #expect(changed)
        #expect(text == "a.txt\nb.txt\nc.txt\n")                 // b.txt and c.txt never fused
    }

    @Test("a blank / whitespace-only path is refused (no change)")
    func blankRefused() {
        let (text, changed) = GitignoreEditor.append(to: "keep\n", path: "   ")
        #expect(!changed)
        #expect(text == "keep\n")
    }
}

// MARK: - Agent prompt templates (self-contained context)

@Suite("agent prompts carry full context")
struct FindingPromptTests {
    @Test("the split-file prompt names the repo path, the file, its size, the hard limit, and make validate")
    func splitFileContent() {
        let p = FindingPrompt.splitFile(repoPath: "/Users/x/Code/app", file: "Views/Big.swift", lines: 612)
        #expect(p.contains("/Users/x/Code/app"))    // absolute repo path
        #expect(p.contains("Views/Big.swift"))       // the exact file
        #expect(p.contains("612"))                   // its measured line count
        #expect(p.contains("400"))                   // the hard limit
        #expect(p.contains("make validate"))         // the closing verification step
    }

    @Test("a custom hard limit flows into the prompt text")
    func customLimit() {
        let p = FindingPrompt.splitFile(repoPath: "/r", file: "F.swift", lines: 900, hardLimit: 250)
        #expect(p.contains("250"))
        #expect(!p.contains("the 400-line"))
    }

    @Test("forFinding routes a Census (god-file) finding through the split template")
    func forFindingRoutesGodFile() {
        let f = Finding(severity: .med, pass: "Census", what: "god-file: A/Big.swift",
                        why: "612 lines — over hard 400. Split it.", fix: "split file")
        let p = FindingPrompt.forFinding(f, repoPath: "/Users/x/Code/app", file: "A/Big.swift", lines: 612)
        #expect(p.contains("A/Big.swift"))
        #expect(p.contains("612"))
        #expect(p.contains("400"))
        #expect(p.contains("make validate"))
    }

    @Test("forFinding builds a context-rich generic ask for a non-census finding")
    func forFindingGeneric() {
        let f = Finding(severity: .high, pass: "Hygiene", what: "merge markers in 1 file",
                        why: "Live merge markers in src/x.ts — a green build is lying.", fix: "open file")
        let p = FindingPrompt.forFinding(f, repoPath: "/Users/x/Code/app", file: "src/x.ts", lines: nil)
        #expect(p.contains("/Users/x/Code/app"))
        #expect(p.contains("src/x.ts"))
        #expect(p.contains("merge markers in 1 file"))   // the finding's `what`
        #expect(p.contains("make validate"))
    }
}

// MARK: - FindingTarget mapping (finding → on-disk file(s) + applicable actions)

@Suite("a finding maps to the right on-disk target and action set")
struct FindingTargetTests {
    private func repo(census: Census = Census(), hygiene: Hygiene = Hygiene(),
                      vibePresent: Bool = true) -> Repo {
        var r = Repo(id: "app", name: "app", path: "~/Code/app", absolutePath: "/tmp/app")
        r.census = census; r.hygiene = hygiene; r.vibePresent = vibePresent
        return r
    }

    @Test("embeddedPath pulls a god-file path out of the finding text, and a doc filename")
    func embeddedPath() {
        #expect(FindingTarget.embeddedPath(pass: "Census", what: "god-file: Sources/Big.swift") == "Sources/Big.swift")
        #expect(FindingTarget.embeddedPath(pass: "Docs", what: "TASK_STATE.md 812 lines") == "TASK_STATE.md")
        #expect(FindingTarget.embeddedPath(pass: "Docs", what: "CHANGELOG.md 3 behind") == "CHANGELOG.md")
        #expect(FindingTarget.embeddedPath(pass: "Hygiene", what: "3 uncommitted changes") == nil)
    }

    @Test("a god-file resolves to its file + line count, and offers exclude + prompt, not gitignore")
    func godFile() throws {
        var c = Census()
        c.godFiles = [FileLines(path: "A/Big.swift", lines: 612)]
        let f = Finding(severity: .med, pass: "Census", what: "god-file: A/Big.swift",
                        why: "612 lines", fix: "split file")
        let t = try #require(FindingTarget.resolve(f, repo: repo(census: c)))
        #expect(t.kind == .godFile)
        #expect(t.relPath == "A/Big.swift")
        #expect(t.lines == 612)                                  // pulled from census, not parsed
        #expect(t.absPath == "/tmp/app/A/Big.swift")
        #expect(t.canExclude && t.canPrompt && t.canViewFile)
        #expect(!t.canGitignore)
    }

    @Test("junk + secret findings resolve to their file and offer gitignore, not exclude")
    func junkAndSecret() throws {
        var hj = Hygiene(); hj.junkFiles = ["notes copy.swift"]
        let junk = Finding(severity: .low, pass: "Hygiene", what: "1 stray backup/dupe file", why: "cruft")
        let jt = try #require(FindingTarget.resolve(junk, repo: repo(hygiene: hj)))
        #expect(jt.kind == .junk)
        #expect(jt.relPath == "notes copy.swift")
        #expect(jt.canGitignore && jt.canViewFile && !jt.canExclude)

        var hs = Hygiene(); hs.secretFiles = ["config/.env"]
        let secret = Finding(severity: .high, pass: "Hygiene", what: "secret tracked in git: .env", why: "leak")
        let st = try #require(FindingTarget.resolve(secret, repo: repo(hygiene: hs)))
        #expect(st.kind == .secret)
        #expect(st.relPath == "config/.env")
        #expect(st.canGitignore)
    }

    @Test("a dirty-tree finding resolves to a git-status view with no file path")
    func dirtyTree() throws {
        let f = Finding(severity: .high, pass: "Worktree", what: "3 uncommitted changes", why: "…", fix: "commit…")
        let t = try #require(FindingTarget.resolve(f, repo: repo()))
        #expect(t.kind == .dirtyTree)
        #expect(t.isGitStatus)
        #expect(t.relPath == nil)
        #expect(!t.canViewFile && !t.isFileScoped)
    }

    @Test("a finding with no actionable file target resolves to nil (no menu shown)")
    func noTarget() {
        let f = Finding(severity: .high, pass: "Managed", what: "UNMANAGED — no VIBE.yaml", why: "…", fix: "open file")
        #expect(FindingTarget.resolve(f, repo: repo()) == nil)
        #expect(FindingTarget.resolve(f, repo: nil) == nil)
    }
}
