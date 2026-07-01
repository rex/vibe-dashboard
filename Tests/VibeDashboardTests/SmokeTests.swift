import Testing
@testable import VibeDashboard

@Suite("smoke")
struct SmokeTests {
    @Test("scaffold builds and links")
    func scaffoldLinks() {
        #expect(Bool(true))
    }
}
