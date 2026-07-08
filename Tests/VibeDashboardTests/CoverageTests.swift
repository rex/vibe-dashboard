import Testing
import Foundation
@testable import VibeDashboard

/// CoverageProbe turns an on-disk coverage artifact into a real line-coverage percent
/// — and returns nil (honest absence) when there is no artifact, so a repo without a
/// report shows no number rather than a fabricated one. Every case writes a throwaway
/// repo tree into a temp dir and drives the full disk→parse path.
@Suite("Coverage probe")
struct CoverageTests {
    /// Writes `files` (relative path → contents) into a fresh temp repo, returns its path.
    private func tempRepo(_ files: [String: String]) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coverage-test-" + UUID().uuidString)
        for (rel, body) in files {
            let url = dir.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
        return dir.path
    }

    @Test("lcov.info with LH:80 / LF:100 → 80")
    func lcovSingleRecord() {
        let lcov = "TN:\nSF:/a/b/File.swift\nDA:1,1\nDA:2,0\nLF:100\nLH:80\nend_of_record\n"
        let repo = tempRepo(["lcov.info": lcov])
        #expect(CoverageProbe.coverage(repo) == 80)
    }

    @Test("lcov sums LH/LF across records: (80+40)/(100+100) → 60")
    func lcovMultiRecordSum() {
        let lcov = """
        SF:/a.swift
        LF:100
        LH:80
        end_of_record
        SF:/b.swift
        LF:100
        LH:40
        end_of_record
        """
        let repo = tempRepo(["coverage/lcov.info": lcov])
        #expect(CoverageProbe.coverage(repo) == 60)
    }

    @Test("istanbul coverage-summary.json total.lines.pct=73 → 73")
    func istanbulSummary() {
        let json = #"{"total":{"lines":{"total":200,"covered":146,"skipped":0,"pct":73}}}"#
        let repo = tempRepo(["coverage/coverage-summary.json": json])
        #expect(CoverageProbe.coverage(repo) == 73)
    }

    @Test("cobertura coverage.xml line-rate=0.8 → 80, nested rate ignored")
    func coberturaLineRate() {
        let xml = #"""
        <?xml version="1.0" ?>
        <coverage line-rate="0.8" branch-rate="0.5">
          <packages><package line-rate="0.3"></package></packages>
        </coverage>
        """#
        let repo = tempRepo(["coverage.xml": xml])
        #expect(CoverageProbe.coverage(repo) == 80)
    }

    @Test("plain-text coverage.txt with a NN% → 84 (best-effort)")
    func plainTextPercent() {
        let repo = tempRepo(["coverage.txt": "TOTAL coverage: 84% of statements\n"])
        #expect(CoverageProbe.coverage(repo) == 84)
    }

    @Test("format precedence: lcov.info wins over coverage.xml when both exist")
    func lcovBeatsCobertura() {
        let repo = tempRepo([
            "lcov.info": "LF:100\nLH:80\nend_of_record\n",   // 80
            "coverage.xml": #"<coverage line-rate="0.3"></coverage>"#,   // 30
        ])
        #expect(CoverageProbe.coverage(repo) == 80)
    }

    @Test("a repo with no coverage artifact → nil (honest absence)")
    func noArtifactIsNil() {
        let repo = tempRepo(["README.md": "# no coverage here\n"])
        #expect(CoverageProbe.coverage(repo) == nil)
    }

    @Test("an empty / unparseable lcov (no LF) → nil, never a fake 0/100")
    func unparseableLcovIsNil() {
        let repo = tempRepo(["lcov.info": "TN:\nSF:/only/headers.swift\nend_of_record\n"])
        #expect(CoverageProbe.coverage(repo) == nil)
    }
}
