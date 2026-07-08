import Testing
import Foundation
@testable import VibeDashboard

/// The glob matcher backs exclude_globs grading — a file wrongly matched (or
/// wrongly missed) means the census grades the wrong set of files, so the
/// semantics are pinned down here: rooted, `**` crosses separators, `*`/`?` don't.
@Suite("Glob")
struct GlobTests {
    @Test("an exact relative path matches only itself")
    func exactPath() {
        #expect(Glob.matches(path: "Sources/Big.swift", pattern: "Sources/Big.swift"))
        #expect(!Glob.matches(path: "Sources/Other.swift", pattern: "Sources/Big.swift"))
        #expect(!Glob.matches(path: "Sources/Big.swift.bak", pattern: "Sources/Big.swift"))
    }

    @Test("**/ matches zero or more leading segments")
    func globstarLeading() {
        let p = "**/Generated/**"
        #expect(Glob.matches(path: "Generated/Api.swift", pattern: p))          // zero segments before
        #expect(Glob.matches(path: "Sources/Generated/Api.swift", pattern: p))
        #expect(Glob.matches(path: "a/b/c/Generated/deep/Api.swift", pattern: p))
        #expect(!Glob.matches(path: "Sources/Api.swift", pattern: p))
    }

    @Test("Sources/**/*.swift matches at any depth under Sources, only .swift")
    func scopeStyle() {
        let p = "Sources/**/*.swift"
        #expect(Glob.matches(path: "Sources/Big.swift", pattern: p))
        #expect(Glob.matches(path: "Sources/a/b/C.swift", pattern: p))
        #expect(!Glob.matches(path: "Tests/X.swift", pattern: p))
        #expect(!Glob.matches(path: "Sources/readme.md", pattern: p))
    }

    @Test("* does not cross a path separator; ? is a single char")
    func singleSegment() {
        #expect(Glob.matches(path: "App.swift", pattern: "*.swift"))
        #expect(!Glob.matches(path: "sub/App.swift", pattern: "*.swift"))
        #expect(Glob.matches(path: "file1.txt", pattern: "file?.txt"))
        #expect(!Glob.matches(path: "file10.txt", pattern: "file?.txt"))
    }

    @Test("literal dots are escaped, not wildcards")
    func escaping() {
        #expect(Glob.matches(path: "a.b", pattern: "a.b"))
        #expect(!Glob.matches(path: "axb", pattern: "a.b"))
    }

    @Test("matchesAny is true if any pattern matches")
    func any() {
        let pats = ["**/Generated/**", "vendor/**"]
        #expect(Glob.matchesAny(path: "vendor/lib.swift", patterns: pats))
        #expect(!Glob.matchesAny(path: "src/main.swift", patterns: pats))
        #expect(!Glob.matchesAny(path: "src/main.swift", patterns: []))   // no patterns → nothing excluded
    }
}

/// The whole point of the exclude work: an over-hard file matched by exclude_globs
/// must NOT land in `godFiles` (graded) — it goes to `excludedGodFiles` (shown).
@Suite("Census exclude_globs")
struct CensusExcludeTests {
    /// Writes a throwaway repo tree under /var (a symlink to /private/var) and
    /// returns the un-canonicalized path — `walk` must canonicalize it internally.
    private func tempRepo(_ files: [String: Int]) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("census-test-" + UUID().uuidString)
        for (rel, lines) in files {
            let url = dir.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let body = Array(repeating: "let x = 0", count: lines).joined(separator: "\n")
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
        return dir.path
    }

    @Test("an excluded over-hard file is separated out of grading")
    func excludedNotGraded() {
        let repo = tempRepo(["Sources/Big.swift": 500, "Sources/Generated/Huge.swift": 600])
        let w = FileProbes.walk(repo, soft: 250, hard: 400, ansible: false, excludes: ["**/Generated/**"])
        let god = w.census.godFiles.map(\.path)
        let excl = w.census.excludedGodFiles.map(\.path)
        #expect(god.contains("Sources/Big.swift"))
        #expect(!god.contains("Sources/Generated/Huge.swift"))   // excluded — not graded
        #expect(excl.contains("Sources/Generated/Huge.swift"))
        #expect(w.census.excludedGodFiles.first?.excluded == true)
    }

    @Test("with no excludes, every over-hard file is graded")
    func noExcludes() {
        let repo = tempRepo(["Big.swift": 500, "Also.swift": 450])
        let w = FileProbes.walk(repo, soft: 250, hard: 400, ansible: false, excludes: [])
        #expect(w.census.godFiles.count == 2)
        #expect(w.census.excludedGodFiles.isEmpty)
    }

    @Test("an exact-path exclude (what the exclude sheet writes) grades nothing else")
    func exactPathExclude() {
        let repo = tempRepo(["Sources/Big.swift": 500, "Sources/Small.swift": 100])
        let w = FileProbes.walk(repo, soft: 250, hard: 400, ansible: false, excludes: ["Sources/Big.swift"])
        #expect(w.census.godFiles.isEmpty)                       // the only god-file was excluded
        #expect(w.census.excludedGodFiles.map(\.path) == ["Sources/Big.swift"])
    }
}
