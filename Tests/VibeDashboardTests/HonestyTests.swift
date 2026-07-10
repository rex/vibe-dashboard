import Testing
import Foundation
@testable import VibeDashboard

/// Pins the pure logic behind two "honest disposition" surfaces:
///  - "Open in editor" must pick a *real, installed* editor by priority
///    (never silently open Finder when an editor exists), and
///  - the ⌘K palette's filter/cap must surface how many matches it hid so a
///    silent 9-item cap can't swallow results.
@Suite("Honesty")
struct HonestyTests {

    // MARK: - Open-in-editor detection

    @Test("editor picker honors priority — first installed candidate wins")
    func editorPriority() {
        let bothInstalled: Set<EditorApp> = [.vscode, .xcode]
        #expect(EditorApp.pick(from: EditorApp.priority) { bothInstalled.contains($0) } == .vscode)

        let onlyXcode: Set<EditorApp> = [.xcode]
        #expect(EditorApp.pick(from: EditorApp.priority) { onlyXcode.contains($0) } == .xcode)

        let cursorAndXcode: Set<EditorApp> = [.cursor, .xcode]
        #expect(EditorApp.pick(from: EditorApp.priority) { cursorAndXcode.contains($0) } == .cursor)
    }

    @Test("editor picker returns nil when nothing is installed (→ honest Finder fallback)")
    func editorNoneInstalled() {
        #expect(EditorApp.pick(from: EditorApp.priority) { _ in false } == nil)
    }

    @Test("every editor maps to a non-empty bundle id")
    func editorBundleIds() {
        for e in EditorApp.allCases { #expect(!e.bundleId.isEmpty) }
        // The priority list only references real cases.
        for e in EditorApp.priority { #expect(EditorApp.allCases.contains(e)) }
    }

    // MARK: - Command-palette filtering + cap

    private var sample: [(label: String, sub: String?)] {
        [("Re-scan root", nil),
         ("Go to Fleet", nil),
         ("Go to Agents", nil),
         ("vibe-dashboard", "~/Code/apps/vibe-dashboard"),
         ("example-svc", "~/dev/example-svc")]
    }

    @Test("empty query returns everything, capped, with the remainder counted")
    func paletteEmptyQueryCap() {
        let r = PaletteMatch.run(labels: sample, query: "", cap: 3)
        #expect(r.visible.count == 3)
        #expect(r.hidden == sample.count - 3)   // 2 hidden → shows "2 more…"
    }

    @Test("no cap pressure means zero hidden")
    func paletteUnderCap() {
        let r = PaletteMatch.run(labels: sample, query: "", cap: 99)
        #expect(r.visible.count == sample.count)
        #expect(r.hidden == 0)
    }

    @Test("query matches labels case-insensitively, one hit per item")
    func paletteMatchLabel() {
        let r = PaletteMatch.run(labels: sample, query: "GO TO", cap: 9)
        #expect(r.visible.count == 2)   // Fleet + Agents
        #expect(r.hidden == 0)
    }

    @Test("query matches the sub/path, not just the label")
    func paletteMatchSub() {
        let r = PaletteMatch.run(labels: sample, query: "code", cap: 9)
        #expect(r.visible.count == 1)   // only the vibe-dashboard path contains "Code"
    }

    @Test("no matches → empty visible, zero hidden (so 'no matches' shows, not a phantom count)")
    func paletteNoMatch() {
        let r = PaletteMatch.run(labels: sample, query: "zzz-nonexistent", cap: 9)
        #expect(r.visible.isEmpty)
        #expect(r.hidden == 0)
    }

    @Test("the visible indices are valid positions into the input")
    func paletteIndicesValid() {
        let r = PaletteMatch.run(labels: sample, query: "", cap: 2)
        #expect(r.visible == [0, 1])
        for i in r.visible { #expect(sample.indices.contains(i)) }
    }
}
