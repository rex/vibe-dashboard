// PruneSheet.swift — the worktree-prune write sheet. Lists only ABANDONED
// worktrees and removes them with `git worktree remove` (no --force) through
// AppState.pruneWorktrees. Split out of OverlaySheets.swift; module-internal,
// rendered by OverlayHost via the shared SheetShell.

import SwiftUI

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
                SheetProse(text: "removes these ABANDONED worktrees with git worktree remove (no --force): "
                    + "the working directory goes, branches and commits stay. A worktree with unpushed "
                    + "commits, or one git finds dirty, is refused — never force-destroyed.")
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
