// OverlaySheets.swift — the shared sheet shell + sub-elements, plus the
// commit / prune / reconcile / waiver write sheets. Rendered by OverlayHost.
// Module-internal (not private) so OverlayHost can dispatch to them.

import SwiftUI

// MARK: - Sheet shell

/// The chrome shared by every confirm-gated write sheet: icon-title header,
/// scrollable body, footer bar with Cancel + primary confirm.
struct SheetShell<Body: View>: View {
    @Environment(AppState.self) private var app
    let title: String
    let icon: String
    var width: CGFloat = OverlayLayout.sheetW
    var confirm: String
    var confirmIcon: String
    var confirmVariant: VibeButtonVariant = .primary
    var onConfirm: () -> Void
    @ViewBuilder var content: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.space.x2_5) {
                VibeIcon(icon, size: 16, color: Theme.color.accent)
                Text(title)
                    .font(VibeFont.mono(VibeFont.size.md, .bold))
                    .foregroundStyle(Theme.color.textBright)
                    .lineLimit(1)
                Spacer(minLength: Theme.space.x2)
                Button { app.closeSheet() } label: {
                    VibeIcon("x", size: 15, color: Theme.color.textMuted)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.color.surface2)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }

            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.space.x4)
            }
            .frame(maxHeight: OverlayLayout.bodyMax)

            HStack(spacing: Theme.space.x2_5) {
                Spacer()
                VibeButton(title: "Cancel", variant: .ghost) { app.closeSheet() }
                VibeButton(title: confirm, icon: confirmIcon, variant: confirmVariant, action: onConfirm)
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.vertical, Theme.space.x3)
            .frame(maxWidth: .infinity)
            .background(Theme.color.surface2)
            .overlay(alignment: .top) { Rectangle().fill(Theme.color.border).frame(height: 1) }
        }
        .frame(width: width)
        .background(Theme.color.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous)
            .strokeBorder(Theme.color.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 16)
    }
}

// MARK: - Shared sheet sub-elements

struct SheetProse: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VibeFont.mono(VibeFont.size.sm))
            .foregroundStyle(Theme.color.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A bordered file-list card with an UPPERCASE section caption + rows.
struct FileCard<Rows: View>: View {
    let caption: String
    @ViewBuilder var rows: () -> Rows
    var body: some View {
        VStack(spacing: 0) {
            Text(caption)
                .vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, Theme.space.x2)
                .background(Theme.color.surface2)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
            rows()
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(Theme.color.border, lineWidth: 1))
    }
}

/// One file line inside a `FileCard`.
struct FileRow<Right: View>: View {
    let icon: String
    let path: String
    var tone: VibeTone = .neutral
    @ViewBuilder var right: () -> Right
    var body: some View {
        HStack(spacing: Theme.space.x2_5) {
            VibeIcon(icon, size: 13, color: tone == .neutral ? Theme.color.textMuted : Theme.color.tone(tone))
            Text(path)
                .font(VibeFont.mono(VibeFont.size.sm))
                .foregroundStyle(Theme.color.textPrimary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            right()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, Theme.space.x2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

// MARK: - Commit sheet

struct CommitSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo
    @State private var sign = true
    @State private var message = ""

    private var branch: String { repo.agent?.branch ?? "main" }
    private var count: Int { max(1, repo.worktree.unstaged) }

    var body: some View {
        SheetShell(title: "Commit · \(repo.name)", icon: "git-commit-horizontal",
                   width: OverlayLayout.sheetW, confirm: "Commit & push", confirmIcon: "git-commit-horizontal") {
            app.closeSheet()
            if sign {
                app.toast("committed + pushed", "\(count) files → \(branch) · signed ✓", .ok)
            } else {
                app.toast("committed + pushed", "\(count) files → \(branch) · UNSIGNED", .warn)
            }
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                HStack(spacing: Theme.space.x2_5) {
                    VibeIcon("git-branch", size: 14, color: Theme.color.textMuted)
                    Text("on ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary)
                    + Text(branch).font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.textPrimary)
                    if !repo.worktree.signed { Pill(text: "commits unsigned", tone: .danger) }
                }
                FileCard(caption: "staged · \(count)") {
                    ForEach(0..<count, id: \.self) { i in
                        FileRow(icon: "file-pen", path: repo.path + "/…", tone: .warn) {
                            EmptyView()
                        }.opacity(i == 0 ? 1 : 0.85)
                    }
                }
                VibeTextField(placeholder: "commit message — one logical step…", text: $message)
                Button { sign.toggle() } label: {
                    HStack(spacing: Theme.space.x2_5) {
                        VibeSwitch(isOn: $sign)
                        Text("sign commit ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textPrimary)
                        + Text("· signed_commits_required is true")
                            .font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textMuted)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Prune sheet

struct PruneSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo
    private var stale: [Worktree] { repo.worktrees.filter { $0.state != .active } }

    var body: some View {
        SheetShell(title: "Prune worktrees · \(repo.name)", icon: "trash-2",
                   width: OverlayLayout.sheetW, confirm: "Prune \(stale.count)", confirmIcon: "trash-2",
                   confirmVariant: .danger) {
            app.closeSheet()
            app.toast("pruned \(stale.count) worktrees",
                      "git worktree remove × \(stale.count) · disk reclaimed", .ok)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                SheetProse(text: "these worktrees are stale or abandoned. git worktree remove deletes the working directory; branches and commits are kept.")
                if stale.isEmpty {
                    EmptyState(icon: "check", tone: .ok, text: "no non-active worktrees to prune")
                } else {
                    VStack(spacing: 0) {
                        ForEach(stale) { w in
                            HStack(spacing: Theme.space.x2_5) {
                                VibeIcon("git-branch", size: 13, color: Theme.color.tone(w.state.tone))
                                Text(w.branch)
                                    .font(VibeFont.mono(VibeFont.size.sm))
                                    .foregroundStyle(Theme.color.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: Theme.space.x2)
                                Text("\(w.created) · \(w.commits) commits")
                                    .font(VibeFont.mono(VibeFont.size.xxs))
                                    .foregroundStyle(Theme.color.textMuted)
                                StatusBadge(text: w.state.rawValue, tone: w.state.tone, small: true)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
                        .strokeBorder(Theme.color.border, lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Reconcile sheet

struct ReconcileSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo

    var body: some View {
        SheetShell(title: "Reconcile · \(repo.name)", icon: "git-merge",
                   width: OverlayLayout.sheetW, confirm: "Apply reconcile", confirmIcon: "git-merge") {
            app.closeSheet()
            app.toast("reconciled \(repo.name)",
                      "\(repo.drift.files) skeleton files pulled · skills bumped", .ok)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                if let behind = repo.drift.behind {
                    Text("this repo is ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary)
                    + Text(behind).font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.warn)
                    + Text(" behind the skeleton. these skeleton-owned files will be overwritten with the current version. your code is untouched.")
                        .font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary)
                } else {
                    SheetProse(text: "this repo is current with the skeleton.")
                }
                let skillBumps = repo.skills.filter { $0.status == .behind }
                if repo.drift.files > 0 {
                    FileCard(caption: "skeleton-owned files · \(repo.drift.files)") {
                        ForEach(0..<repo.drift.files, id: \.self) { _ in
                            FileRow(icon: "file-diff", path: ".claude/…", tone: .warn) { EmptyView() }
                        }
                    }
                }
                if !skillBumps.isEmpty {
                    FileCard(caption: "skills to bump · \(skillBumps.count)") {
                        ForEach(skillBumps) { s in
                            FileRow(icon: "blocks", path: s.skillId, tone: .info) {
                                Text("\(s.installed ?? "—") → latest")
                                    .font(VibeFont.mono(VibeFont.size.xxs))
                                    .foregroundStyle(Theme.color.textMuted)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Waiver sheet

struct WaiverSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    let repo: Repo?
    @State private var reason = ""
    @State private var expiry = "30d"

    private var findings: [Finding] { repo?.surprises ?? store.fleet.findings }

    var body: some View {
        SheetShell(title: "Record a waiver", icon: "shield-check",
                   width: OverlayLayout.sheetW, confirm: "Record waiver", confirmIcon: "shield-check") {
            app.closeSheet()
            app.toast("waiver recorded", "expires in \(expiry) · logged to VIBE.yaml waivers[]", .info)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                if let f = findings.first {
                    fieldLabel("finding")
                    HStack(spacing: Theme.space.x2) {
                        SeverityTag(severity: f.severity)
                        Text(f.what)
                            .font(VibeFont.mono(VibeFont.size.sm))
                            .foregroundStyle(Theme.color.textPrimary)
                            .lineLimit(1)
                    }
                } else {
                    SheetProse(text: "no open findings to waive.")
                }
                fieldLabel("reason — why this is acceptable for now")
                VibeTextField(placeholder: "e.g. legacy module, scheduled for the v2 rewrite…", text: $reason)
                fieldLabel("expires")
                HStack(spacing: Theme.space.x1_5) {
                    ForEach(["7d", "30d", "90d", "never"], id: \.self) { opt in
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
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
    }
}
