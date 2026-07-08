import Testing
import Foundation
@testable import VibeDashboard

/// BuildInfo is stamped at build time by Scripts/generate-build-info.sh from
/// VERSION (MAJOR.(MINOR_BASE + commits-since-VERSION)). These tests pin the
/// "MARKETING_VERSION stuck at 0.1" regression: the shipped marketing version
/// must be the real computed value, never the project.yml 0.1 placeholder.
@Suite("BuildInfo")
struct BuildInfoTests {
    @Test("marketing version is not the 0.1 placeholder")
    func notPlaceholder() {
        #expect(BuildInfo.marketingVersion != "0.1")
    }

    @Test("marketing version is a real dotted-numeric version")
    func dottedNumeric() {
        let v = BuildInfo.marketingVersion
        #expect(!v.isEmpty)
        let parts = v.split(separator: ".")
        #expect(parts.count >= 2)
        #expect(parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) })
    }
}
