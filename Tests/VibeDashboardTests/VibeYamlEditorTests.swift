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
        #expect(!FileManager.default.fileExists(atPath: path + ".bak"))  // NEVER drops a .bak in the repo
        #expect(FileManager.default.fileExists(atPath: VibeYamlEditor.backupPath(for: path)))  // backup lives in app dir
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

    @Test("handles CRLF line endings without mixing them")
    func crlf() {
        let src = "architecture:\r\n  exclude_globs: []\r\n  max_lines_per_file:\r\n    hard: 400\r\n"
        let path = tempVibe(src)
        let result = VibeYamlEditor.addExcludeGlob(vibePath: path, glob: "a/b.swift")
        #expect(result == .added(glob: "a/b.swift"))
        #expect(VibeYamlEditor.currentExcludes(vibePath: path) == ["a/b.swift"])
        let after = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lfs = after.components(separatedBy: "\n").count - 1
        let crlfs = after.components(separatedBy: "\r\n").count - 1
        #expect(lfs == crlfs)   // every LF is part of a CRLF — no mixed endings
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

    @Test("records a skill by creating a top-level skills: block")
    func recordSkillNew() {
        let path = tempVibe(blockStyle)
        let result = VibeYamlEditor.recordSkill(vibePath: path, id: "lang-swift-apple", version: "0.3.0", applied: "2026-07-01")
        #expect(result == .skillRecorded(id: "lang-swift-apple"))
        #expect(VibeYamlEditor.currentSkillIds(vibePath: path) == ["lang-swift-apple"])
    }

    @Test("appends to an existing skills: block and stays idempotent")
    func recordSkillAppend() {
        let path = tempVibe(blockStyle + "\nskills:\n  - id: tool-ci\n    version: \"0.1.0\"\n    applied: 2026-06-01\n")
        let first = VibeYamlEditor.recordSkill(vibePath: path, id: "lang-python", version: "0.1.0", applied: "2026-07-01")
        #expect(first == .skillRecorded(id: "lang-python"))
        #expect(Set(VibeYamlEditor.currentSkillIds(vibePath: path)) == ["tool-ci", "lang-python"])
        let again = VibeYamlEditor.recordSkill(vibePath: path, id: "tool-ci", version: "0.1.0", applied: "2026-07-01")
        #expect(again == .alreadyRecorded)
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
