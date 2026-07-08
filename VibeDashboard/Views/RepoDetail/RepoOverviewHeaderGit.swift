// RepoOverviewHeaderGit.swift — the repo Overview's identity header (logo, full
// path, glanceable badges) and the GIT STATUS panel (the real porcelain change-set,
// grouped). Split out of RepoTabsCore to keep every file under the 400-line gate.

import SwiftUI

/// Overview identity lockup: the repo's own logo (or emblem fallback), its name, the
/// FULL ~-collapsed path (the disambiguator for same-named repos — prominent and
/// selectable, with the absolute path on hover), the description, and the glanceable
/// identity cluster (stack · remote hosts · CI).
struct RepoOverviewHeader: View {
    let repo: Repo

    var body: some View {
        HStack(alignment: .center, spacing: Theme.space.x3) {
            RepoLogoThumb(repo: repo, size: 46, live: repo.agentActive)

            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(VibeFont.mono(VibeFont.size.lg, .semibold))
                    .foregroundStyle(Theme.color.textBright)
                    .lineLimit(1)

                HStack(spacing: Theme.space.x1_5) {
                    VibeIcon("folder", size: 11, color: Theme.color.textFaint)
                    Text(repo.path)
                        .font(VibeFont.mono(VibeFont.size.xs))
                        .foregroundStyle(Theme.color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(repo.absolutePath)
                }

                if !repo.desc.isEmpty {
                    Text(repo.desc)
                        .font(VibeFont.sans(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.space.x3)
            RepoBadges(repo: repo, size: 22, showStack: true)
        }
    }
}

/// The real `git status` for the repo, grouped into readable buckets. Branch +
/// unpushed on top; a clean tree renders an honest "working tree clean" state rather
/// than an empty box. Nothing here is inferred — it's the porcelain change-set.
struct GitStatusPanel: View {
    let repo: Repo

    private var groups: [GitStatusGroup] { GitStatus.group(repo.worktree.statusLines) }
    private var shown: Int { repo.worktree.statusLines.count }   // capped in GitProbe
    private var total: Int { repo.worktree.unstaged }            // true change count

    var body: some View {
        VibePanel(title: "GIT STATUS", flushBody: true) {
            VStack(spacing: 0) {
                branchLine
                if groups.isEmpty {
                    EmptyState(icon: "check", tone: .ok, text: "working tree clean")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { GitStatusGroupView(group: $0) }
                        if total > shown {
                            Text("+ \(total - shown) more change\(total - shown == 1 ? "" : "s") not shown")
                                .font(VibeFont.mono(VibeFont.size.xxs))
                                .foregroundStyle(Theme.color.textFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.space.x4)
                                .padding(.vertical, Theme.space.x2_5)
                        }
                    }
                }
            }
        }
    }

    private var branchLine: some View {
        HStack(spacing: Theme.space.x2) {
            VibeIcon("git-branch", size: 13, color: Theme.color.textSecondary)
            Text(repo.scm.branch)
                .font(VibeFont.mono(VibeFont.size.sm, .medium))
                .foregroundStyle(Theme.color.textPrimary)
                .lineLimit(1)
            if repo.worktree.unpushed > 0 {
                Pill(text: "\(repo.worktree.unpushed) unpushed", tone: .warn, icon: "arrow-up")
            }
            Spacer(minLength: Theme.space.x2)
            if groups.isEmpty {
                StatusBadge(text: "clean", tone: .ok, small: true)
            } else {
                Text("\(total) change\(total == 1 ? "" : "s")")
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
            }
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x2_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }
}

/// One bucket (staged / modified / untracked / renamed / deleted / conflicted): a
/// toned header with a count, then the changed paths (capped, with a "+N more" tail).
private struct GitStatusGroupView: View {
    let group: GitStatusGroup
    private let cap = 12
    private var tone: VibeTone { group.kind.tone }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.space.x2) {
                VibeIcon(group.kind.icon, size: 12, color: Theme.color.tone(tone))
                Text(group.kind.label).vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.tone(tone))
                Text("\(group.entries.count)")
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textFaint)
                Spacer()
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.top, Theme.space.x3)
            .padding(.bottom, Theme.space.x1_5)

            VStack(alignment: .leading, spacing: Theme.space.x1) {
                ForEach(group.entries.prefix(cap)) { entry in
                    Text(entry.path)
                        .font(VibeFont.mono(VibeFont.size.xs))
                        .foregroundStyle(Theme.color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if group.entries.count > cap {
                    Text("+ \(group.entries.count - cap) more")
                        .font(VibeFont.mono(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textFaint)
                }
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.bottom, Theme.space.x2)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}
