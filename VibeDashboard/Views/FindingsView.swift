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
    @AppStorage(WaiverStore.ledgerKey) private var ledgerJSON = ""

    /// Findings actively muted by a waiver vs. the still-open remainder. Counts, the
    /// headline, and the filter bar all reflect the OPEN set — a waived finding is
    /// genuinely off the board until it expires — but the hidden count is disclosed
    /// (never silently dropped) and can be revealed on demand.
    // Grading already split open vs waived (FleetScanner.gradeRepo) — the feed just
    // renders both sets; a waiver's weight is out of the score, not merely hidden.
    private var openFindings: [Finding] { store.fleet.findings }
    private var waived: [Finding] { store.fleet.waivedFindings }

    /// The rows the table renders: open findings for the active filter, plus the
    /// waived ones appended when the user chooses to reveal them.
    private var tableFindings: [Finding] {
        let openShown = openFindings.filter { filter.matches($0) }
        guard showWaived else { return openShown }
        return openShown + waived.filter { filter.matches($0) }
    }

    private func count(_ sev: Severity) -> Int { openFindings.filter { $0.severity == sev }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Findings")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                headline

                filterBar

                if !waived.isEmpty { waivedToggle }

                VibePanel(flushBody: true) {
                    if tableFindings.isEmpty {
                        EmptyState(
                            icon: openFindings.isEmpty && waived.isEmpty ? "check" : "search",
                            tone: openFindings.isEmpty && waived.isEmpty ? .ok : .neutral,
                            text: openFindings.isEmpty && waived.isEmpty
                                ? "all clear — no surprises across the fleet."
                                : "no \(filter.label.lowercased()) findings."
                        )
                    } else {
                        FindingsTable(findings: tableFindings)
                    }
                }
            }
            .padding(Theme.space.x5)
        }
    }

    // The rollup line: N findings · h·m·l breakdown (+ waived disclosure).
    private var headline: some View {
        Group {
            if openFindings.isEmpty {
                Text("worker swept the fleet — ").foregroundStyle(Theme.color.textSecondary)
                    + Text(waived.isEmpty ? "every repo in policy" : "open board clear")
                        .foregroundStyle(Theme.color.ok)
                    + waivedTail
            } else {
                Text("\(openFindings.count) finding\(openFindings.count == 1 ? "" : "s") open · ")
                    .foregroundStyle(Theme.color.textSecondary)
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

    private var filterBar: some View {
        SegMac(
            selection: $filter,
            options: [
                SegOption(value: .all, label: "all", count: openFindings.count),
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
    @Environment(FleetStore.self) private var store
    @State private var hover = false
    @State private var viewTarget: FindingTarget?
    @AppStorage(WaiverStore.ledgerKey) private var ledgerJSON = ""
    @AppStorage(WaiverStore.pendingKey) private var pendingWaiverId = ""

    private var repo: Repo? { store.fleet.repo(finding.repoId) }
    /// The file(s) this finding points at — drives which actions the row offers.
    private var target: FindingTarget? { FindingTarget.resolve(finding, repo: repo) }
    /// Is this finding currently muted by an active waiver? Only ever true for rows
    /// surfaced by the feed's "show waived" reveal.
    private var waived: Bool { WaiverLedger.decode(ledgerJSON).suppresses(finding.id, now: Date()) }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space.x3) {
            SeverityTag(severity: finding.severity)
                .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.space.x1_5) {
                HStack(spacing: Theme.space.x2) {
                    Pill(text: finding.pass)
                    if waived { Pill(text: "waived", icon: "shield-check") }
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
            .opacity(waived ? 0.5 : 1)          // a muted finding reads as backgrounded

            HStack(spacing: Theme.space.x2) {
                if !waived, let fix = finding.fix {
                    VibeButton(title: fix, icon: "wrench", variant: .accentGhost, size: .sm) {
                        app.runFix(finding)
                    }
                }
                moreMenu()          // always present — at minimum offers Waive / Un-waive
            }
            .fixedSize()
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hover ? Theme.color.surfaceRaised : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu { actionItems(target) }
        .sheet(item: $viewTarget) { FileViewerSheet(app: app, target: $0) }
    }

    /// The visible ⋯ affordance — a bordered square that opens the same action set as
    /// the row's right-click menu. Always present: even a finding with no file target
    /// can still be waived.
    private func moreMenu() -> some View {
        Menu { actionItems(target) } label: {
            VibeIcon("more-horizontal", size: 15, color: Theme.color.textMuted)
                .frame(width: 30, height: 26)
                .background(Theme.color.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                    .strokeBorder(Theme.color.borderStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("more actions")
    }

    /// The applicable secondary actions for a finding — shared by the ⋯ menu and the
    /// right-click context menu. Target-scoped actions (view/git-status, AI-prompt,
    /// exclude, gitignore, copy path/name) appear only when a file target fits; the
    /// Waive / Un-waive action is offered on EVERY finding.
    @ViewBuilder private func actionItems(_ t: FindingTarget?) -> some View {
        if let t {
            if t.isGitStatus {
                Button("View git status") { viewTarget = t }
            } else if t.canViewFile {
                Button("View file") { viewTarget = t }
            }
            if t.canPrompt {
                Button("Copy agent prompt") { app.copyAgentPrompt(for: finding) }
            }
            if t.canExclude, let rel = t.relPath, repo?.vibePresent == true {
                Button("Exclude from architecture scope") { app.requestExclude(repoId: t.repoId, path: rel) }
            }
            if t.canGitignore, let rel = t.relPath {
                Button("Add to .gitignore") {
                    app.addToGitignore(repoId: t.repoId, repoAbsPath: t.repoAbsPath, relPath: rel)
                }
            }
            if t.isFileScoped, let abs = t.absPath, let rel = t.relPath {
                Divider()
                Button("Copy full file path") { app.copy(abs, as: "file path") }
                Button("Copy file name") { app.copy((rel as NSString).lastPathComponent, as: "file name") }
            }
            Divider()
        }
        if waived {
            Button("Un-waive — show this finding again") { unwaive() }
        } else {
            Button("Waive this finding…") { requestWaive() }
        }
    }

    /// Stash this finding as the waiver target and open the waiver sheet (which
    /// resolves the target by id). Opens UI only — the finding isn't hidden until the
    /// user confirms an expiry in the sheet.
    private func requestWaive() {
        pendingWaiverId = finding.id
        app.openSheet(.waiver)
    }

    /// Lift every waiver on this finding immediately — it returns to the open feed.
    private func unwaive() {
        var ledger = WaiverLedger.decode(ledgerJSON)
        guard ledger.lift(finding.id) else { return }
        ledgerJSON = ledger.encoded()
        store.applyWaivers()   // the finding + its grade weight return instantly
        app.toast("waiver lifted", finding.what, .info)
    }
}
