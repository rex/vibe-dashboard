// WaiverLedger.swift — the pure, persistent waiver ledger (moved out of the
// sheet so GRADING can honor waivers: a waived finding leaves the feed AND its
// weight leaves the score — see Derive.factors(waived:)). A waiver remains a
// local, time-boxed, personal mute; nothing is written into the repo.

import Foundation

extension WaiverLedger {
    /// The actively-waived finding ids straight from UserDefaults — the single load
    /// path grading uses (full scan, targeted rescan, and waiver-change regrade).
    static func activeIDsFromDefaults(now: Date = Date()) -> Set<String> {
        decode(UserDefaults.standard.string(forKey: WaiverStore.ledgerKey) ?? "")
            .activeIDs(now: now)
    }
}

// MARK: - Waiver ledger (pure, persistent)

/// UserDefaults keys shared by the finding feed (suppress + un-waive) and this sheet
/// (record). Centralized so the producer and consumer can never drift on the string.
enum WaiverStore {
    static let ledgerKey = "vibe.mac.waivers"          // JSON-encoded WaiverLedger
    static let pendingKey = "vibe.mac.waiver.target"   // finding id awaiting the open sheet
}

/// One recorded waiver: a single finding hidden until `expires` (nil = never). Pure
/// value type — no IO, no SwiftUI — so the suppression math is unit-testable.
struct Waiver: Codable, Hashable, Sendable {
    var findingId: String
    var reason: String
    var created: Date
    var expires: Date?          // nil = never expires

    /// Still hiding its finding? Active until its expiry passes; a never-expiry
    /// (nil) waiver is always active.
    func isActive(now: Date) -> Bool {
        guard let expires else { return true }
        return now < expires
    }
}

/// The full set of recorded waivers + the pure suppression logic the feed applies.
/// Persisted as JSON; `decode` is total — a garbage or empty blob yields an empty
/// ledger rather than throwing.
struct WaiverLedger: Codable, Hashable, Sendable {
    var waivers: [Waiver] = []

    /// Is this finding currently suppressed? True iff an ACTIVE waiver names it — an
    /// expired waiver never suppresses, so the finding comes back on its own.
    func suppresses(_ findingId: String, now: Date) -> Bool {
        waivers.contains { $0.findingId == findingId && $0.isActive(now: now) }
    }

    /// The finding ids actively hidden right now — the feed filters against this set
    /// in a single pass.
    func activeIDs(now: Date) -> Set<String> {
        Set(waivers.lazy.filter { $0.isActive(now: now) }.map(\.findingId))
    }

    /// Record a waiver, replacing any prior one for the SAME finding — re-waiving a
    /// finding updates its reason/expiry instead of stacking duplicates.
    mutating func record(_ w: Waiver) {
        waivers.removeAll { $0.findingId == w.findingId }
        waivers.append(w)
    }

    /// Remove every waiver naming `findingId` (the un-waive path). Returns whether
    /// anything was actually lifted.
    @discardableResult
    mutating func lift(_ findingId: String) -> Bool {
        let before = waivers.count
        waivers.removeAll { $0.findingId == findingId }
        return waivers.count != before
    }

    /// Drop waivers that have expired as of `now` — housekeeping so the stored blob
    /// doesn't grow without bound. Suppression already ignores expired entries, so
    /// purging changes on-disk size only, never behavior.
    func purged(now: Date) -> WaiverLedger {
        WaiverLedger(waivers: waivers.filter { $0.isActive(now: now) })
    }

    // ---- persistence (JSON string <-> ledger), total + side-effect free ----

    static func decode(_ json: String) -> WaiverLedger {
        guard let data = json.data(using: .utf8),
              let ledger = try? JSONDecoder().decode(WaiverLedger.self, from: data)
        else { return WaiverLedger() }
        return ledger
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    // ---- expiry token -> concrete date ----

    /// Map an expiry token from the sheet ("7d" / "30d" / "90d" / "never") to a
    /// concrete expiry relative to `now`. "never" — and any unrecognized token —
    /// yields nil (no expiry). Pure: the single source of truth shared by the sheet
    /// and the tests.
    static func expiryDate(from token: String, now: Date) -> Date? {
        let days: Int
        switch token {
        case "7d": days = 7
        case "30d": days = 30
        case "90d": days = 90
        default: return nil            // "never" (and any unknown token) → never expires
        }
        return now.addingTimeInterval(TimeInterval(days) * 86_400)
    }
}

