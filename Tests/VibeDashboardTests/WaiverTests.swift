import Testing
import Foundation
@testable import VibeDashboard

// The waiver ledger is the app's "I acknowledge this and choose to hide it for N days"
// store — a local, personal mute that must NEVER silently swallow a finding forever.
// The suppression math is PURE (no UserDefaults, no SwiftUI here), so it's pinned
// directly: an ACTIVE waiver hides its finding; an EXPIRED one no longer does (the
// finding returns on its own); re-waiving updates rather than stacks; and the JSON
// round-trip that backs @AppStorage is total (garbage in → empty ledger, never a crash).

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)   // fixed "now" for determinism

private func waiver(_ id: String, expires: Date?, reason: String = "") -> Waiver {
    Waiver(findingId: id, reason: reason, created: t0, expires: expires)
}

// MARK: - Waiver.isActive

@Suite("a waiver is active until its expiry passes")
struct WaiverActivityTests {
    @Test("a never-expiry waiver (nil) is always active")
    func neverExpires() {
        #expect(waiver("f", expires: nil).isActive(now: t0))
        #expect(waiver("f", expires: nil).isActive(now: t0.addingTimeInterval(10 * 365 * 86_400)))
    }

    @Test("a future expiry is active; a past expiry is not")
    func futureVsPast() {
        #expect(waiver("f", expires: t0.addingTimeInterval(3600)).isActive(now: t0))
        #expect(!waiver("f", expires: t0.addingTimeInterval(-3600)).isActive(now: t0))
    }

    @Test("expiry is exclusive — a waiver is no longer active at the exact instant it expires")
    func exactInstant() {
        #expect(!waiver("f", expires: t0).isActive(now: t0))
    }
}

// MARK: - suppression (the headline behavior the feed relies on)

@Suite("the ledger suppresses only findings with an active waiver")
struct WaiverSuppressionTests {
    @Test("an ACTIVE waiver suppresses its finding; an EXPIRED one no longer does")
    func activeVsExpired() {
        let active = WaiverLedger(waivers: [waiver("A", expires: t0.addingTimeInterval(86_400))])
        #expect(active.suppresses("A", now: t0))

        // Same waiver, evaluated a day and a second later — now expired, no longer hiding.
        let later = t0.addingTimeInterval(86_401)
        #expect(!active.suppresses("A", now: later))
    }

    @Test("a waiver only suppresses the finding it names")
    func onlyNamedFinding() {
        let ledger = WaiverLedger(waivers: [waiver("A", expires: nil)])
        #expect(ledger.suppresses("A", now: t0))
        #expect(!ledger.suppresses("B", now: t0))
    }

    @Test("activeIDs returns exactly the currently-hidden ids (expired excluded)")
    func activeIDsSet() {
        let ledger = WaiverLedger(waivers: [
            waiver("A", expires: t0.addingTimeInterval(86_400)),   // active
            waiver("B", expires: t0.addingTimeInterval(-1)),       // expired
            waiver("C", expires: nil),                             // never
        ])
        #expect(ledger.activeIDs(now: t0) == ["A", "C"])
    }
}

// MARK: - record / lift / purge

@Suite("recording, lifting, and purging keep the ledger honest")
struct WaiverMutationTests {
    @Test("re-waiving the same finding replaces its entry — no stacked duplicates")
    func recordReplaces() {
        var ledger = WaiverLedger()
        ledger.record(waiver("A", expires: nil, reason: "first"))
        ledger.record(waiver("A", expires: t0.addingTimeInterval(86_400), reason: "second"))
        #expect(ledger.waivers.count == 1)
        #expect(ledger.waivers.first?.reason == "second")
        #expect(ledger.waivers.first?.expires == t0.addingTimeInterval(86_400))
    }

    @Test("recording distinct findings accumulates them")
    func recordDistinct() {
        var ledger = WaiverLedger()
        ledger.record(waiver("A", expires: nil))
        ledger.record(waiver("B", expires: nil))
        #expect(ledger.waivers.count == 2)
    }

    @Test("lifting a waived finding removes it and reports the change; lifting an absent one is a no-op")
    func lift() {
        var ledger = WaiverLedger(waivers: [waiver("A", expires: nil)])
        let removed = ledger.lift("A")       // mutating — call outside #expect (macro captures immutably)
        #expect(removed)
        #expect(ledger.waivers.isEmpty)
        let again = ledger.lift("A")          // already gone
        #expect(!again)
        #expect(!ledger.suppresses("A", now: t0))
    }

    @Test("purge drops expired waivers but keeps active and never-expiry ones")
    func purge() {
        let ledger = WaiverLedger(waivers: [
            waiver("A", expires: t0.addingTimeInterval(86_400)),   // active
            waiver("B", expires: t0.addingTimeInterval(-1)),       // expired → dropped
            waiver("C", expires: nil),                             // never
        ])
        let kept = ledger.purged(now: t0).waivers.map(\.findingId)
        #expect(Set(kept) == ["A", "C"])
    }
}

// MARK: - expiry token → date

@Suite("expiry tokens map to concrete horizons")
struct WaiverExpiryTokenTests {
    @Test("7d / 30d / 90d resolve to the matching number of days from now")
    func dayTokens() {
        #expect(WaiverLedger.expiryDate(from: "7d", now: t0) == t0.addingTimeInterval(7 * 86_400))
        #expect(WaiverLedger.expiryDate(from: "30d", now: t0) == t0.addingTimeInterval(30 * 86_400))
        #expect(WaiverLedger.expiryDate(from: "90d", now: t0) == t0.addingTimeInterval(90 * 86_400))
    }

    @Test("'never' — and any unrecognized token — means no expiry (nil)")
    func neverAndUnknown() {
        #expect(WaiverLedger.expiryDate(from: "never", now: t0) == nil)
        #expect(WaiverLedger.expiryDate(from: "", now: t0) == nil)
        #expect(WaiverLedger.expiryDate(from: "banana", now: t0) == nil)
    }
}

// MARK: - persistence (the @AppStorage JSON channel)

@Suite("ledger JSON persistence round-trips and never throws")
struct WaiverPersistenceTests {
    @Test("encode → decode reproduces the ledger exactly")
    func roundTrip() {
        let ledger = WaiverLedger(waivers: [
            waiver("A", expires: t0.addingTimeInterval(86_400), reason: "legacy module"),
            waiver("B", expires: nil, reason: ""),
        ])
        #expect(WaiverLedger.decode(ledger.encoded()) == ledger)
    }

    @Test("decoding empty or garbage yields an empty ledger, not a crash")
    func totalDecode() {
        #expect(WaiverLedger.decode("") == WaiverLedger())
        #expect(WaiverLedger.decode("not json at all {[") == WaiverLedger())
        #expect(WaiverLedger.decode("").waivers.isEmpty)
    }

    @Test("a round-tripped active waiver still suppresses its finding")
    func suppressionSurvivesRoundTrip() {
        let ledger = WaiverLedger(waivers: [waiver("A", expires: t0.addingTimeInterval(86_400))])
        let restored = WaiverLedger.decode(ledger.encoded())
        #expect(restored.suppresses("A", now: t0))
        #expect(!restored.suppresses("A", now: t0.addingTimeInterval(86_401)))
    }
}
