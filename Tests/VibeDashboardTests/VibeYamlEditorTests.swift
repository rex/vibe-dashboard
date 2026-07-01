import Testing
import Foundation
@testable import VibeDashboard

/// The exclude-file writer is the one thing in this app that mutates a repo's
/// VIBE.yaml, so it's tested hard: it must add correctly, stay idempotent, and —
/// above all — REFUSE to write anything it can't verify, leaving the file intact.
@Suite("VibeYamlEditor")
struct VibeYamlEditorTests {
    private func tempVibe(_ body: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-test-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("VIBE.yaml").path
        try? body.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private let blockStyle = """
    kind: vibe-policy
    project:
      name: sample
    architecture:
      check_command: make check-architecture
      scope_globs:
        - "Sources/**/*.swift"
      exclude_globs:
        - "**/Generated/**"
      max_lines_per_file:
        soft: 250
        hard: 400
    workflow:
      signed_commits_required: true
    """

    @Test("adds a glob to an existing exclude_globs and re-parses")
    func addsToExisting() {
        let path = tempVibe(blockStyle)
        let result = VibeYamlEditor.addExcludeGlob(vibePath: path, glob: "Sources/Big.swift")
        #expect(result == .added(glob: "Sources/Big.swift"))
        let globs = VibeYamlEditor.currentExcludes(vibePath: path)
        #expect(globs.contains("**/Generated/**"))   // original preserved
        #expect(globs.contains("Sources/Big.swift"))  // new one added
        #expect(FileManager.default.fileExists(atPath: path + ".bak"))  // backup written
    }

    @Test("is idempotent — a second add reports alreadyExcluded")
    func idempotent() {
        let path = tempVibe(blockStyle)
        _ = VibeYamlEditor.addExcludeGlob(vibePath: path, glob: "Sources/Big.swift")
        let again = VibeYamlEditor.addExcludeGlob(vibePath: path, glob: "Sources/Big.swift")
        #expect(again == .alreadyExcluded)
    }

    @Test("creates exclude_globs when architecture has none")
    func createsBlock() {
        let path = tempVibe("""
        architecture:
          check_command: make check-architecture
          scope_globs:
            - "Sources/**/*.swift"
        workflow:
          signed_commits_required: true
        """)
        let result = VibeYamlEditor.addExcludeGlob(vibePath: path, glob: "Sources/Big.swift")
        #expect(result == .added(glob: "Sources/Big.swift"))
        #expect(VibeYamlEditor.currentExcludes(vibePath: path) == ["Sources/Big.swift"])
    }

    @Test("converts an inline empty list")
    func inlineEmpty() {
        let path = tempVibe("""
        architecture:
          exclude_globs: []
          max_lines_per_file:
            hard: 400
        """)
        let result = VibeYamlEditor.addExcludeGlob(vibePath: path, glob: "a/b.swift")
        #expect(result == .added(glob: "a/b.swift"))
        #expect(VibeYamlEditor.currentExcludes(vibePath: path) == ["a/b.swift"])
    }

    @Test("refuses to write a file that doesn't already parse")
    func refusesMalformed() {
        let broken = "architecture:\n  exclude_globs:\n    - \"unterminated\n"
        let path = tempVibe(broken)
        let result = VibeYamlEditor.addExcludeGlob(vibePath: path, glob: "x.swift")
        #expect(result == .parseError)
        let after = try? String(contentsOfFile: path, encoding: .utf8)
        #expect(after == broken)   // left byte-for-byte untouched
    }

    @Test("refuses when there is no architecture section")
    func refusesNoArchitecture() {
        let src = "project:\n  name: x\nworkflow:\n  signed_commits_required: true\n"
        let path = tempVibe(src)
        let result = VibeYamlEditor.addExcludeGlob(vibePath: path, glob: "x.swift")
        if case .unsafe = result {} else { Issue.record("expected .unsafe, got \(result)") }
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == src)
    }
}
