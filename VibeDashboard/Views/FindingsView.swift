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
    @State private var showWaived = false
    @AppStorage("vibe.findings.groupByRepo") private var groupByRepo = false
    @AppStorage("vibe.findings.type") private var typeFilter = ""   // "" = every type
    @AppStorage(WaiverStore.ledgerKey) private var ledgerJSON = ""

    /// Findings actively muted by a waiver vs. the still-open remainder. Counts, the
    /// headline, and the filter bar all reflect the OPEN set — a waived finding is
    /// genuinely off the board until it expires — but the hidden count is disclosed
    /// (never silently dropped) and can be revealed on demand.
    // Grading already split open vs waived (FleetScanner.gradeRepo) — the feed just
    // renders both sets; a waiver's weight is out of the score, not merely hidden.
    private var openFindings: [Finding] { store.fleet.findings }
    private var waived: [Finding] { store.fleet.waivedFindings }

    /// Distinct finding types (the `pass` label) on the visible board, for the type
    /// menu — the open set, plus the waived set when it's revealed.
    private var types: [String] {
        Array(Set((showWaived ? openFindings + waived : openFindings).map(\.pass))).sorted()
    }
    /// The active type filter, ignored when that type is no longer present (e.g. its
    /// last finding was just waived) so the feed can never strand itself empty.
    private var activeType: String { types.contains(typeFilter) ? typeFilter : "" }

    private func matches(_ f: Finding) -> Bool {
        filter.matches(f) && (activeType.isEmpty || f.pass == activeType)
    }

    /// The rows the feed renders: open findings for the active severity+type filter,
    /// plus the waived ones appended when the user chooses to reveal them.
    private var shownFindings: [Finding] {
        let openShown = openFindings.filter(matches)
        guard showWaived else { return openShown }
        return openShown + waived.filter(matches)
    }

    /// Findings grouped by codebase. Each group inherits `shownFindings`' severity
    /// order; groups are ordered worst-severity-first, then by volume, then name.
    private var groups: [(id: String, name: String, findings: [Finding])] {
        Dictionary(grouping: shownFindings) { $0.repoId ?? "" }
            .map { (id: $0.key, name: $0.value.first?.repoName ?? "—", findings: $0.value) }
            .sorted { a, b in
                let sa = a.findings.map(\.severity).min() ?? .low
                let sb = b.findings.map(\.severity).min() ?? .low
                if sa != sb { return sa < sb }
                if a.findings.count != b.findings.count { return a.findings.count > b.findings.count }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    /// Severity counts and the open total respect the active TYPE filter, so the
    /// segmented badges never promise more than the current type slice holds.
    private func count(_ sev: Severity) -> Int {
        openFindings.filter { $0.severity == sev && (activeType.isEmpty || $0.pass == activeType) }.count
    }
    private var typedOpenCount: Int {
        openFindings.filter { activeType.isEmpty || $0.pass == activeType }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Findings")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                headline
                controlsRow
                if !waived.isEmpty { waivedToggle }

                if groupByRepo {
                    groupedBoard
                } else {
                    VibePanel(flushBody: true) {
                        if shownFindings.isEmpty { emptyState }
                        else { FindingsTable(findings: shownFindings) }
                    }
                }
            }
            .padding(Theme.space.x5)
        }
    }

    // MARK: - Board (flat vs grouped by codebase)

    private var groupedBoard: some View {
        VStack(spacing: Theme.space.x4) {
            if groups.isEmpty {
                VibePanel(flushBody: true) { emptyState }
            } else {
                ForEach(groups, id: \.id) { g in
                    VibePanel(flushBody: true) {
                        VStack(spacing: 0) {
                            repoHeader(g)
                            FindingsTable(findings: g.findings)
                        }
                    }
                }
            }
        }
    }

    /// A tappable codebase header above its findings — jumps to the repo detail.
    private func repoHeader(_ g: (id: String, name: String, findings: [Finding])) -> some View {
        let worst = g.findings.map(\.severity).min() ?? .low
        return Button { app.openRepo(g.id) } label: {
            HStack(spacing: Theme.space.x2) {
                VibeIcon("folder-git-2", size: 13, color: Theme.color.textMuted)
                Text(g.name)
                    .font(VibeFont.mono(VibeFont.size.sm, .bold))
                    .foregroundStyle(Theme.color.textBright).lineLimit(1)
                SeverityTag(severity: worst)
                Text("\(g.findings.count) finding\(g.findings.count == 1 ? "" : "s")")
                    .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                Spacer(minLength: 0)
                VibeIcon("arrow-right", size: 12, color: Theme.color.textFaint)
            }
            .padding(.horizontal, Theme.space.x4).padding(.vertical, Theme.space.x2_5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.color.surface2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
        .help("Open \(g.name)")
    }

    @ViewBuilder private var emptyState: some View {
        let boardEmpty = openFindings.isEmpty && waived.isEmpty
        EmptyState(
            icon: boardEmpty ? "check" : "search",
            tone: boardEmpty ? .ok : .neutral,
            text: boardEmpty
                ? "all clear — no surprises across the fleet."
                : "no findings match \(filterSummary)."
        )
    }
    private var filterSummary: String {
        var parts: [String] = []
        if filter != .all { parts.append(filter.label.lowercased()) }
        if !activeType.isEmpty { parts.append("“\(activeType)”") }
        return parts.isEmpty ? "this view" : parts.joined(separator: " · ")
    }

    // MARK: - Headline

    // The rollup line: N findings · h·m·l breakdown (+ active type, + waived).
    private var headline: some View {
        Group {
            if typedOpenCount == 0 {
                let trulyClear = openFindings.isEmpty
                Text(trulyClear ? "worker swept the fleet — " : "this slice is clear — ")
                    .foregroundStyle(Theme.color.textSecondary)
                    + Text(trulyClear ? (waived.isEmpty ? "every repo in policy" : "open board clear")
                                      : "\(openFindings.count) open under other filters")
                        .foregroundStyle(trulyClear ? Theme.color.ok : Theme.color.textMuted)
                    + waivedTail
            } else {
                Text("\(typedOpenCount) finding\(typedOpenCount == 1 ? "" : "s") open")
                    .foregroundStyle(Theme.color.textSecondary)
                    + (activeType.isEmpty ? Text("")
                       : Text(" · \(activeType)").foregroundStyle(Theme.color.textMuted))
                    + Text(" · ").foregroundStyle(Theme.color.textSecondary)
                    + Text("\(count(.high)) high").foregroundStyle(Theme.color.danger)
                    + Text(" · ").foregroundStyle(Theme.color.textSecondary)
                    + Text("\(count(.med)) med").foregroundStyle(Theme.color.warn)
                    + Text(" · ").foregroundStyle(Theme.color.textSecondary)
                    + Text("\(count(.low)) low").foregroundStyle(Theme.color.textMuted)
                    + waivedTail
            }
        }
        .font(VibeFont.mono(VibeFont.size.sm))
    }

    /// Trailing " · N waived" so muted findings are disclosed, never silently dropped.
    private var waivedTail: Text {
        waived.isEmpty
            ? Text("")
            : Text(" · ").foregroundStyle(Theme.color.textSecondary)
                + Text("\(waived.count) waived").foregroundStyle(Theme.color.textFaint)
    }

    /// Reveal / hide the waived findings inline. Rendered only when at least one
    /// waiver is active, so the affordance stays invisible until it's relevant.
    private var waivedToggle: some View {
        Button { showWaived.toggle() } label: {
            HStack(spacing: Theme.space.x1_5) {
                VibeIcon(showWaived ? "eye-off" : "eye", size: 12, color: Theme.color.textMuted)
                Text("\(waived.count) waived finding\(waived.count == 1 ? "" : "s") — \(showWaived ? "hide" : "show")")
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showWaived ? "hide waived findings" : "show findings you've waived")
    }

    // MARK: - Controls (severity · type · grouping)

    private var controlsRow: some View {
        HStack(spacing: Theme.space.x3) {
            SegMac(
                selection: $filter,
                options: [
                    SegOption(value: .all, label: "all", count: typedOpenCount),
                    SegOption(value: .high, label: "high", count: count(.high)),
                    SegOption(value: .med, label: "med", count: count(.med)),
                    SegOption(value: .low, label: "low", count: count(.low)),
                ]
            )
            Spacer(minLength: Theme.space.x2)
            typeMenu
            groupToggle
        }
    }

    /// Filter the board to a single finding type (`pass`). Disabled until there's
    /// more than one type to choose between.
    private var typeMenu: some View {
        let on = !activeType.isEmpty
        return Menu {
            Button { typeFilter = "" } label: { Text((activeType.isEmpty ? "✓ " : "") + "All types") }
            Divider()
            ForEach(types, id: \.self) { t in
                Button { typeFilter = t } label: { Text((activeType == t ? "✓ " : "") + t) }
            }
        } label: {
            HStack(spacing: Theme.space.x1_5) {
                VibeIcon("layers", size: 12, color: on ? Theme.color.accent : Theme.color.textMuted)
                Text(on ? activeType : "all types")
                    .font(VibeFont.mono(VibeFont.size.xxs, .medium))
                    .foregroundStyle(on ? Theme.color.textBright : Theme.color.textMuted)
                    .lineLimit(1)
                VibeIcon("chevron-down", size: 10, color: Theme.color.textFaint)
            }
            .padding(.horizontal, Theme.space.x2_5).padding(.vertical, Theme.space.x1_5)
            .background(on ? Theme.color.accent.opacity(0.14) : Theme.color.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                .strokeBorder(on ? Theme.color.accent.opacity(0.5) : Theme.color.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .disabled(types.count < 2 && !on)
        .help("Filter the board to one finding type")
    }

    /// Toggle between one flat severity-sorted list and per-codebase sections.
    private var groupToggle: some View {
        Button { groupByRepo.toggle() } label: {
            HStack(spacing: Theme.space.x1_5) {
                VibeIcon(groupByRepo ? "folder-git-2" : "list", size: 12,
                         color: groupByRepo ? Theme.color.textOnAccent : Theme.color.textMuted)
                Text(groupByRepo ? "grouped" : "group by repo")
                    .font(VibeFont.mono(VibeFont.size.xxs, .medium))
                    .foregroundStyle(groupByRepo ? Theme.color.textOnAccent : Theme.color.textMuted)
            }
            .padding(.horizontal, Theme.space.x2_5).padding(.vertical, Theme.space.x1_5)
            .background(groupByRepo ? Theme.color.accent : Theme.color.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                .strokeBorder(groupByRepo ? Color.clear : Theme.color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(groupByRepo ? "Show one flat, severity-sorted list" : "Group findings by codebase")
    }
}
