import Testing
import Foundation
@testable import VibeDashboard

/// Two pure pieces behind the Overview slice: `AssetProbe` icon-path resolution
/// (which on-disk file becomes a repo's logo) and `GitStatus.group` (porcelain →
/// readable buckets). Both must be deterministic and honest — a wrong icon path or a
/// mis-bucketed change would show the user something that isn't true.
@Suite("Overview")
struct OverviewTests {

    // MARK: helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-overview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0, count: bytes).write(to: url)
    }

    // MARK: - AssetProbe.resolveIconPath

    @Test("app icon: the largest PNG under AppIcon.appiconset wins")
    func appIconLargest() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = root.appendingPathComponent("MyApp/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        try writeFile(set.appendingPathComponent("icon-40.png"), bytes: 100)
        try writeFile(set.appendingPathComponent("icon-1024.png"), bytes: 5_000)
        try writeFile(set.appendingPathComponent("Contents.json"), bytes: 20)   // not a png → ignored

        let path = AssetProbe.resolveIconPath(repoDir: root.path)
        #expect(path?.hasSuffix("AppIcon.appiconset/icon-1024.png") == true)
    }

    @Test("app icon is found a few dirs deep")
    func appIconNested() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = root.appendingPathComponent("Sources/App/Resources/Media.xcassets/AppIcon.appiconset",
                                              isDirectory: true)
        try writeFile(set.appendingPathComponent("only.png"), bytes: 700)

        let path = AssetProbe.resolveIconPath(repoDir: root.path)
        #expect(path?.hasSuffix("Media.xcassets/AppIcon.appiconset/only.png") == true)
    }

    @Test("web: a public favicon resolves when there is no app icon")
    func webFavicon() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("public/favicon.ico"), bytes: 200)

        let path = AssetProbe.resolveIconPath(repoDir: root.path)
        #expect(path?.hasSuffix("public/favicon.ico") == true)
    }

    @Test("a native app icon beats a web favicon when both exist")
    func appIconBeatsWeb() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        try writeFile(set.appendingPathComponent("m.png"), bytes: 300)
        try writeFile(root.appendingPathComponent("public/favicon.png"), bytes: 9_999)

        let path = AssetProbe.resolveIconPath(repoDir: root.path)
        #expect(path?.hasSuffix("AppIcon.appiconset/m.png") == true)
    }

    @Test("no icon on disk → nil (the UI honestly falls back to the stack emblem)")
    func noIcon() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("README.md"), bytes: 10)

        #expect(AssetProbe.resolveIconPath(repoDir: root.path) == nil)
    }

    @Test("an AppIcon.appiconset buried in node_modules is skipped, not resolved")
    func skipsHeavyDirs() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let buried = root.appendingPathComponent("node_modules/dep/App.xcassets/AppIcon.appiconset",
                                                 isDirectory: true)
        try writeFile(buried.appendingPathComponent("icon.png"), bytes: 400)

        #expect(AssetProbe.resolveIconPath(repoDir: root.path) == nil)
    }

    // MARK: - GitStatus.group (porcelain → buckets)

    @Test("porcelain lines bucket into staged / modified / untracked / renamed / deleted / conflicted")
    func porcelainGrouping() {
        let groups = GitStatus.group([
            "M  Shared/Staged.swift",      // staged (index modified)
            "A  New.swift",                // staged (added)
            " M Shared/Mod.swift",         // modified (worktree)
            "?? notes.txt",                // untracked
            "R  old.swift -> new.swift",   // renamed
            " D gone.swift",               // deleted
            "UU conflict.swift",           // conflicted
        ])
        func g(_ k: GitStatusKind) -> GitStatusGroup? { groups.first { $0.kind == k } }

        #expect(g(.staged)?.entries.count == 2)
        #expect(g(.modified)?.entries.count == 1)
        #expect(g(.untracked)?.entries.count == 1)
        #expect(g(.renamed)?.entries.count == 1)
        #expect(g(.deleted)?.entries.count == 1)
        #expect(g(.conflicted)?.entries.count == 1)

        // a rename renders with an arrow, old + new both visible
        #expect(g(.renamed)?.entries.first?.path == "old.swift → new.swift")
        // the porcelain "XY " prefix is stripped from the path
        #expect(g(.untracked)?.entries.first?.path == "notes.txt")
        #expect(g(.modified)?.entries.first?.path == "Shared/Mod.swift")
    }

    @Test("a clean tree yields no groups → the panel shows an honest clean state")
    func cleanTree() {
        #expect(GitStatus.group([]).isEmpty)
        #expect(GitStatus.group(["", "   "]).isEmpty)   // blank / separator-only lines ignored
    }

    @Test("groups come back in loudest-first declaration order")
    func groupOrder() {
        let groups = GitStatus.group([" M a.swift", "UU b.swift", "?? c.txt"])
        #expect(groups.map(\.kind) == [.conflicted, .modified, .untracked])
    }

    @Test("a staged delete is a deletion; an unstaged delete is too")
    func deletesBucketTogether() {
        let groups = GitStatus.group(["D  staged-del.swift", " D worktree-del.swift"])
        #expect(groups.first { $0.kind == .deleted }?.entries.count == 2)
        #expect(groups.contains { $0.kind == .staged } == false)
    }
}
