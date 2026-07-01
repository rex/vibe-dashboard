// FindingsView.swift — severity-filtered findings feed + reusable table.
//
// The realtime worker stream, distilled: every surprise the fleet turned up,
// sorted high→med→low, filterable by severity, each with a one-click fix-it.

import SwiftUI

/// Severity filter for the findings feed.
private enum FindingFilter: String, Hashable, CaseIterable {
    case all, high, med, low

    var label: String { self == .all ? "all" : self.rawValue.uppercased() }

    /// Match test against a finding (`.all` passes everything).
    func matches(_ f: Finding) -> Bool {
        switch self {
        case .all: return true
        case .high: return f.severity == .high
        case .med: return f.severity == .med
        case .low: return f.severity == .low
        }
    }
}

struct FindingsView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    @State private var filter: FindingFilter = .all

    private var all: [Finding] { store.fleet.findings }
    private var shown: [Finding] { all.filter { filter.matches($0) } }

    private func count(_ sev: Severity) -> Int { all.filter { $0.severity == sev }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Findings")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                headline

                filterBar

                VibePanel(flushBody: true) {
                    if shown.isEmpty {
                        EmptyState(
                            icon: all.isEmpty ? "check" : "search",
                            tone: all.isEmpty ? .ok : .neutral,
                            text: all.isEmpty
                                ? "all clear — no surprises across the fleet."
                                : "no \(filter.label.lowercased()) findings."
                        )
                    } else {
                        FindingsTable(findings: shown)
                    }
                }
            }
            .padding(Theme.space.x5)
        }
    }

    // The rollup line: N findings · h·m·l breakdown.
    private var headline: some View {
        Group {
            if all.isEmpty {
                Text("worker swept the fleet — ").foregroundStyle(Theme.color.textSecondary)
                    + Text("every repo in policy").foregroundStyle(Theme.color.ok)
            } else {
                Text("\(all.count) finding\(all.count == 1 ? "" : "s") open · ")
                    .foregroundStyle(Theme.color.textSecondary)
                    + Text("\(count(.high)) high").foregroundStyle(Theme.color.danger)
                    + Text(" · ").foregroundStyle(Theme.color.textSecondary)
                    + Text("\(count(.med)) med").foregroundStyle(Theme.color.warn)
                    + Text(" · ").foregroundStyle(Theme.color.textSecondary)
                    + Text("\(count(.low)) low").foregroundStyle(Theme.color.textMuted)
            }
        }
        .font(VibeFont.mono(VibeFont.size.sm))
    }

    private var filterBar: some View {
        SegMac(
            selection: $filter,
            options: [
                SegOption(value: .all, label: "all", count: all.count),
                SegOption(value: .high, label: "high", count: count(.high)),
                SegOption(value: .med, label: "med", count: count(.med)),
                SegOption(value: .low, label: "low", count: count(.low)),
            ]
        )
    }
}

// MARK: - FindingsTable

/// A reusable, edge-to-edge list of finding rows (drop into a flush `VibePanel`).
struct FindingsTable: View {
    let findings: [Finding]

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(findings) { f in
                FindingRow(finding: f)
            }
        }
    }
}

private struct FindingRow: View {
    let finding: Finding
    @Environment(AppState.self) private var app
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space.x3) {
            SeverityTag(severity: finding.severity)
                .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.space.x1_5) {
                HStack(spacing: Theme.space.x2) {
                    Pill(text: finding.pass)
                    if let name = finding.repoName {
                        HStack(spacing: 5) {
                            VibeIcon("folder-git-2", size: 11, color: Theme.color.textFaint)
                            Text(name)
                                .font(VibeFont.mono(VibeFont.size.xxs))
                                .foregroundStyle(Theme.color.textMuted)
                                .lineLimit(1)
                        }
                    }
                }
                Text(finding.what)
                    .font(VibeFont.mono(VibeFont.size.sm, .bold))
                    .foregroundStyle(Theme.color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.why)
                    .font(VibeFont.sans(VibeFont.size.xs))
                    .foregroundStyle(Theme.color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let fix = finding.fix {
                VibeButton(title: fix, icon: "wrench", variant: .accentGhost, size: .sm) {
                    app.runFix(finding)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hover ? Theme.color.surfaceRaised : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
