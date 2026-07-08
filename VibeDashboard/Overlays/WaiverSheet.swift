// WaiverSheet.swift — record a time-boxed waiver against an open finding, and the
// pure, persistent ledger that backs it.
//
// A waiver = "I acknowledge this finding and choose to hide it for N days." It
// suppresses that ONE finding from the feed until it expires, then the finding
// returns on its own. The ledger is a pure value type (unit-tested in WaiverTests)
// persisted to UserDefaults as JSON via @AppStorage. HONEST SCOPE: nothing is
// written to VIBE.yaml or to disk in the repo — a waiver is a local, personal mute,
// and the toast says exactly that (never a fabricated "logged to VIBE.yaml").
//
// Reached from a finding row's ⋯ / right-click "Waive" action (FindingsView), which
// stashes the target finding id and calls `openSheet(.waiver)`; module-internal,
// rendered by OverlayHost via the shared SheetShell.

import SwiftUI

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

// MARK: - Waiver sheet

struct WaiverSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    /// Kept for the OverlayHost(.waiver) construction path; only used as a fallback
    /// target when no explicit finding was stashed.
    var repo: Repo? = nil

    @AppStorage(WaiverStore.ledgerKey) private var ledgerJSON = ""
    @AppStorage(WaiverStore.pendingKey) private var pendingId = ""
    @State private var reason = ""
    @State private var expiry = "30d"

    private static let expiryOptions = ["7d", "30d", "90d", "never"]

    /// The specific finding to waive — resolved live by id from the fleet feed (the
    /// row's "Waive" action stashed it just before this sheet opened). Falls back to
    /// the selected repo's first surprise for the legacy repo-only construction path.
    private var target: Finding? {
        store.fleet.findings.first { $0.id == pendingId } ?? repo?.surprises.first
    }

    var body: some View {
        SheetShell(title: "Waive a finding", icon: "shield-check",
                   width: OverlayLayout.sheetW, confirm: "Record waiver",
                   confirmIcon: "shield-check", confirmDisabled: target == nil,
                   onConfirm: record) {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                if let f = target {
                    fieldLabel("finding")
                    HStack(spacing: Theme.space.x2) {
                        SeverityTag(severity: f.severity)
                        Text(f.what)
                            .font(VibeFont.mono(VibeFont.size.sm))
                            .foregroundStyle(Theme.color.textPrimary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    SheetProse(text: "hides this one finding from the feed until it expires — then it returns on its own. Recorded locally only; nothing is written to VIBE.yaml or the repo.")
                } else {
                    SheetProse(text: "no open finding is selected to waive.")
                }
                fieldLabel("reason — why this is acceptable for now")
                VibeTextField(placeholder: "e.g. legacy module, scheduled for the v2 rewrite…", text: $reason)
                fieldLabel("expires")
                expiryChips
            }
        }
    }

    private var expiryChips: some View {
        HStack(spacing: Theme.space.x1_5) {
            ForEach(Self.expiryOptions, id: \.self) { opt in
                Button { expiry = opt } label: {
                    Text(opt)
                        .font(VibeFont.mono(VibeFont.size.xs, .medium))
                        .foregroundStyle(expiry == opt ? Theme.color.textOnAccent : Theme.color.textSecondary)
                        .padding(.horizontal, Theme.space.x2_5).padding(.vertical, Theme.space.x1_5)
                        .background(expiry == opt ? Theme.color.accent : Theme.color.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                            .strokeBorder(expiry == opt ? Theme.color.accent : Theme.color.border, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }

    /// Record the waiver for real: append to the persisted ledger (replacing any
    /// prior waiver for the same finding), purge expired entries, and confirm HONESTLY
    /// — the finding is hidden locally, nothing was written to policy.
    private func record() {
        guard let f = target else { app.closeSheet(); return }
        let now = Date()
        var ledger = WaiverLedger.decode(ledgerJSON)
        ledger.record(Waiver(findingId: f.id,
                             reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                             created: now,
                             expires: WaiverLedger.expiryDate(from: expiry, now: now)))
        ledger = ledger.purged(now: now)
        ledgerJSON = ledger.encoded()
        pendingId = ""                       // consume the stashed target
        app.closeSheet()
        let n = ledger.waivers.count
        let horizon = expiry == "never" ? "hidden until you lift it" : "hidden for \(expiry)"
        app.toast("finding waived", "\(horizon) · \(n) active waiver\(n == 1 ? "" : "s")", .ok)
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
    }
}
