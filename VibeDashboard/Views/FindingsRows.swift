// FindingsRows.swift — the reusable findings table + one finding row (severity
// tag, repo pill, why/what, fix-it button, waive/un-waive). Split out of
// FindingsView so the feed view has room for grouping + type filtering.

import SwiftUI

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
