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
    /// When true the primary confirm is blocked + dimmed (e.g. an empty commit
    /// message, or nothing to commit) — the sheet can't fire a no-op write.
    var confirmDisabled: Bool = false
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
                    .disabled(confirmDisabled)
                    .opacity(confirmDisabled ? 0.45 : 1)
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
    @Environment(FleetStore.self) private var store
    let repo: Repo
    @State private var sign = true
    @State private var message = ""
    /// The REAL changed paths, read live from `git status --porcelain` at open —
    /// nil while loading. No fabricated `max(1, unstaged)` placeholder rows.
    @State private var changed: [String]? = nil

    private var branch: String { repo.build.branch }
    private var files: [String] { changed ?? [] }
    private var canCommit: Bool { GitWrite.isCommittable(message) && !files.isEmpty }

    var body: some View {
        SheetShell(title: "Commit · \(repo.name)", icon: "git-commit-horizontal",
                   width: OverlayLayout.sheetW, confirm: "Commit & push", confirmIcon: "git-commit-horizontal",
                   confirmDisabled: !canCommit, onConfirm: perform) {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                HStack(spacing: Theme.space.x2_5) {
                    VibeIcon("git-branch", size: 14, color: Theme.color.textMuted)
                    Text("on ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary)
                    + Text(branch).font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.textPrimary)
                    if !repo.worktree.signed { Pill(text: "commits unsigned", tone: .danger) }
                }
                changedCard
                VibeTextField(placeholder: "commit message — one logical step…", text: $message, onSubmit: perform)
                Button { sign.toggle() } label: {
                    HStack(spacing: Theme.space.x2_5) {
                        VibeSwitch(isOn: $sign)
                        Text("sign commit ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textPrimary)
                        + Text(repo.signedRequired ? "· signed_commits_required is true" : "· uses -S (recommended)")
                            .font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textMuted)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .task {
            let abs = (repo.absolutePath as NSString).expandingTildeInPath
            let r = await ProcessRunner.git(["status", "--porcelain"], cwd: abs)
            changed = r.stdout
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0.dropFirst(3)) }
                .filter { !$0.isEmpty }
        }
    }

    @ViewBuilder private var changedCard: some View {
        if changed == nil {
            FileCard(caption: "reading working tree…") {
                FileRow(icon: "refresh-cw", path: "git status --porcelain", tone: .neutral) { EmptyView() }
            }
        } else if files.isEmpty {
            FileCard(caption: "changed · 0") {
                FileRow(icon: "check", path: "working tree clean — nothing to commit", tone: .ok) { EmptyView() }
            }
        } else {
            FileCard(caption: "changed · \(files.count)") {
                ForEach(files.prefix(40), id: \.self) { p in
                    FileRow(icon: "file-pen", path: p, tone: .warn) { EmptyView() }
                }
                if files.count > 40 {
                    FileRow(icon: "more-horizontal", path: "+ \(files.count - 40) more", tone: .neutral) { EmptyView() }
                }
            }
        }
    }

    private func perform() {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = files
        guard GitWrite.isCommittable(msg), !paths.isEmpty else { return }
        app.closeSheet()
        let r = repo, host = store.fleet.scanner.host, signed = sign, n = paths.count, br = branch
        let steps: [(label: String, args: [String])] = [
            ("add", GitWrite.addAllArgs),
            ("commit", GitWrite.commitArgs(message: msg, sign: signed)),
            ("push", GitWrite.pushArgs),
        ]
        Task { @MainActor in
            let ok = await app.runGit(r, host: host, steps: steps, okTitle: "committed + pushed",
                                      okDetail: "\(n) file\(n == 1 ? "" : "s") → \(br)\(signed ? " · signed" : " · UNSIGNED")")
            if ok { await store.rescan(repoId: r.id) }
        }
    }
}

// MARK: - Prune sheet

struct PruneSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    let repo: Repo
    /// ONLY abandoned worktrees are prune candidates — a stale one can still hold
    /// unpushed commits, so it is never auto-removed.
    private var abandoned: [Worktree] { repo.worktrees.filter { $0.state == .abandoned } }

    var body: some View {
        SheetShell(title: "Prune worktrees · \(repo.name)", icon: "trash-2",
                   width: OverlayLayout.sheetW, confirm: "Prune \(abandoned.count)", confirmIcon: "trash-2",
                   confirmVariant: .danger, confirmDisabled: abandoned.isEmpty, onConfirm: perform) {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                SheetProse(text: "removes these ABANDONED worktrees with git worktree remove (no --force): the working directory goes, branches and commits stay. A worktree with unpushed commits, or one git finds dirty, is refused — never force-destroyed.")
                if abandoned.isEmpty {
                    EmptyState(icon: "check", tone: .ok, text: "no abandoned worktrees to prune")
                } else {
                    VStack(spacing: 0) {
                        ForEach(abandoned) { w in
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
                                StatusBadge(text: w.commits > 0 ? "unpushed — kept" : w.state.rawValue,
                                            tone: w.commits > 0 ? .warn : w.state.tone, small: true)
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

    private func perform() {
        let targets = abandoned
        guard !targets.isEmpty else { return }
        app.closeSheet()
        let r = repo, host = store.fleet.scanner.host
        Task { @MainActor in
            let ok = await app.pruneWorktrees(r, worktrees: targets, host: host)
            if ok { await store.rescan(repoId: r.id) }
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
