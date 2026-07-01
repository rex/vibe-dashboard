// AgentsView.swift — fleet agent oversight: the "rein them in" screen.
//
// Four panels: who is working now (SessionCards), worktree sprawl, the
// TASK_STATE.md doc-bloat leaderboard, and changelog staleness. Every value
// flows through Theme / VibeFont / the design-system components.

import SwiftUI

// MARK: - Agent tool identity (icon + label per agent id)

private struct AgentTool { let icon: String; let label: String }

private func agentTool(_ id: String?) -> AgentTool {
    switch id {
    case "codex":  return AgentTool(icon: "square-terminal", label: "codex")
    case "serena": return AgentTool(icon: "waypoints", label: "serena")
    case "claude-code", "claude": return AgentTool(icon: "bot", label: "claude-code")
    case let t?:   return AgentTool(icon: "bot", label: t)
    case nil:      return AgentTool(icon: "bot", label: "agent")
    }
}

/// active=lime, stale=amber, abandoned=red.
private extension WorktreeLife {
    var badgeLabel: String { rawValue }
}

private let taskStateSoft: Double = 400
private let taskStateHard: Double = 800

/// 14pt sits between Theme.space.x3 (12) and .x4 (16); the spec calls for it
/// on the session grid gap and SessionCard padding. Named, not magic.
private enum AgentsLayout { static let gap14: CGFloat = 14 }

// MARK: - Screen

struct AgentsView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    private var sessions: [Repo] { store.fleet.sessions }
    private var sprawl: [(repo: Repo, worktree: Worktree)] {
        store.fleet.worktreeSprawl.sorted { a, b in
            rank(a.worktree.state) < rank(b.worktree.state)
        }
    }
    private var bloat: [Repo] {
        store.fleet.leaves.sorted { $0.docs.taskState.lines > $1.docs.taskState.lines }
    }
    private var stale: [Repo] {
        store.fleet.leaves
            .filter { $0.docs.changelog.status != .ok }
            .sorted { $0.docs.changelog.behind > $1.docs.changelog.behind }
    }
    private func rank(_ s: WorktreeLife) -> Int {
        switch s { case .abandoned: return 0; case .stale: return 1; case .active: return 2 }
    }

    var body: some View {
        let t = store.fleet.totals
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                header(t)
                WorkingNowSection(sessions: sessions)
                HStack(alignment: .top, spacing: Theme.space.x4) {
                    DocBloatPanel(repos: bloat).frame(maxWidth: .infinity, alignment: .top)
                    ChangelogStalenessPanel(repos: stale).frame(maxWidth: .infinity, alignment: .top)
                }
                WorktreeSprawlPanel(sprawl: sprawl, abandoned: t.abandonedWorktrees)
            }
            .padding(Theme.space.x5)
        }
    }

    @ViewBuilder private func header(_ t: FleetTotals) -> some View {
        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
            Text("Agents")
                .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                .tracking(VibeFont.size.xxl * -0.02)
                .foregroundStyle(Theme.color.textBright)
            (
                Text("\(t.agentsActive) working now")
                    .foregroundStyle(t.agentsActive > 0 ? Theme.color.warn : Theme.color.ok)
                + Text(" · \(t.abandonedWorktrees) abandoned worktrees · \(t.bloatedDocs) bloated docs · \(t.staleChangelogs) stale changelogs. rein them in.")
                    .foregroundStyle(Theme.color.textSecondary)
            )
            .font(VibeFont.mono(VibeFont.size.sm))
            .monospacedDigit()
        }
    }
}

// MARK: - Working now

private struct WorkingNowSection: View {
    let sessions: [Repo]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x2) {
            Text("working now · \(sessions.count)")
                .vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textFaint)
            if sessions.isEmpty {
                VibePanel(flushBody: true) {
                    EmptyState(icon: "moon", tone: .ok, text: "no agents working. the fleet is quiet.")
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: AgentsLayout.gap14)],
                          spacing: AgentsLayout.gap14) {
                    ForEach(sessions) { SessionCard(repo: $0) }
                }
            }
        }
    }
}

private struct SessionCard: View {
    let repo: Repo
    @Environment(AppState.self) private var app

    private var agent: AgentInfo { repo.agent ?? AgentInfo() }
    private var tool: AgentTool { agentTool(agent.tool) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x3) {
            identityRow
            Text(agent.note)
                .font(VibeFont.mono(VibeFont.size.xs))
                .foregroundStyle(Theme.color.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            diffMeta
            actionRow
        }
        .padding(AgentsLayout.gap14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.warnSurfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(Theme.color.warnLine, lineWidth: 1))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.03)).frame(height: 1).padding(.horizontal, 1)
        }
    }

    private var identityRow: some View {
        HStack(alignment: .center, spacing: Theme.space.x2_5) {
            VibeIcon(tool.icon, size: 17, color: Theme.color.warn)
                .frame(width: 34, height: 34)
                .background(Theme.color.warnSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                    .strokeBorder(Theme.color.warnLine, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Button { app.openRepo(repo.id) } label: {
                    HStack(spacing: 7) {
                        HealthDot(health: repo.health, size: 8)
                        Text(repo.name)
                            .font(VibeFont.mono(VibeFont.size.md, .bold))
                            .foregroundStyle(Theme.color.textBright)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                Text("\(tool.label) · \(agent.branch ?? "—") · \(agent.elapsed ?? "—")")
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AgentPulse(active: true, color: Theme.color.warn, size: 14)
        }
    }

    private var diffMeta: some View {
        HStack(alignment: .center, spacing: AgentsLayout.gap14) {
            Text("\(agent.filesTouched) files").foregroundStyle(Theme.color.textMuted)
            if let added = agent.linesAdded {
                HStack(spacing: 0) {
                    Text("+\(added.formatted())").foregroundStyle(Theme.color.ok)
                    Text("\u{2212}\((agent.linesRemoved ?? 0).formatted())").foregroundStyle(Theme.color.danger)
                }
            }
            Text("· last write \(agent.lastActivity)").foregroundStyle(Theme.color.textMuted)
        }
        .font(VibeFont.mono(VibeFont.size.xxs))
        .monospacedDigit()
    }

    private var actionRow: some View {
        HStack(spacing: Theme.space.x2) {
            VibeButton(title: "Watch", icon: "terminal", variant: .secondary, size: .sm, block: true) {
                app.openRepo(repo.id); app.openConsole(.output)
            }
            VibeButton(title: "Pause", icon: "pause", variant: .danger, size: .sm, block: true) {
                app.toast("paused \(tool.label)", "\(repo.name) · held for review", .warn)
            }
        }
    }
}

// MARK: - Worktree sprawl

private struct WorktreeSprawlPanel: View {
    let sprawl: [(repo: Repo, worktree: Worktree)]
    let abandoned: Int
    @Environment(AppState.self) private var app

    var body: some View {
        VibePanel(flushBody: true) {
            VStack(spacing: 0) {
                headerRow
                if sprawl.isEmpty {
                    EmptyState(icon: "git-branch", tone: .ok, text: "no extra worktrees across the fleet.")
                } else {
                    ForEach(Array(sprawl.enumerated()), id: \.element.worktree.id) { idx, item in
                        SprawlRow(repo: item.repo, wt: item.worktree, last: idx == sprawl.count - 1)
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: Theme.space.x2) {
            PanelTitle(text: "worktree sprawl")
            Spacer()
            if abandoned > 0 {
                Button { app.openSheet(.prune) } label: {
                    HStack(spacing: Theme.space.x1_5) {
                        VibeIcon("trash-2", size: 11, color: Theme.color.danger)
                        Text("Prune all \(abandoned)")
                            .font(VibeFont.mono(VibeFont.size.xxs, .medium))
                            .foregroundStyle(Theme.color.danger)
                    }
                    .padding(.horizontal, Theme.space.x2_5)
                    .padding(.vertical, Theme.space.x1)
                    .background(Theme.color.dangerSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous)
                        .strokeBorder(Theme.color.dangerLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                StatusBadge(text: "tidy", tone: .ok, small: true)
            }
        }
        .padding(.horizontal, Theme.space.x4)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }
}

private struct SprawlRow: View {
    let repo: Repo
    let wt: Worktree
    let last: Bool
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(alignment: .center, spacing: Theme.space.x2_5) {
            VibeIcon("git-branch", size: 14, color: Theme.color.tone(wt.state.tone))
            VStack(alignment: .leading, spacing: 1) {
                Text(wt.branch)
                    .font(VibeFont.mono(VibeFont.size.sm))
                    .foregroundStyle(Theme.color.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Button { app.openRepo(repo.id) } label: {
                    Text("\(repo.name) · \(wt.created) · \(wt.commits) commits")
                        .font(VibeFont.mono(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textMuted)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(text: wt.state.badgeLabel, tone: wt.state.tone, small: true)
            if wt.state != .active {
                Button {
                    app.toast("pruned", "git worktree remove \(wt.branch) · \(repo.name)", .ok)
                } label: {
                    VibeIcon("trash-2", size: 12, color: Theme.color.textMuted)
                        .frame(width: 26, height: 26)
                        .background(Theme.color.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous)
                            .strokeBorder(Theme.color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x2_5)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        }
    }
}

// MARK: - Doc bloat leaderboard

private struct DocBloatPanel: View {
    let repos: [Repo]
    @Environment(AppState.self) private var app

    var body: some View {
        VibePanel(header: {
            HStack(spacing: Theme.space.x2) {
                PanelTitle(text: "doc bloat · TASK_STATE.md")
                Spacer()
                Text("soft \(Int(taskStateSoft)) · hard \(Int(taskStateHard))")
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .monospacedDigit()
            }
        }, content: {
            if repos.isEmpty {
                EmptyState(icon: "file-text", tone: .ok, text: "no TASK_STATE.md to weigh yet.")
            } else {
                VStack(alignment: .leading, spacing: Theme.space.x3) {
                    ForEach(repos.prefix(5)) { r in
                        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
                            Button { app.openRepo(r.id) } label: {
                                HStack(spacing: 7) {
                                    HealthDot(health: r.health, size: 7)
                                    Text(r.name)
                                        .font(VibeFont.mono(VibeFont.size.xs, .medium))
                                        .foregroundStyle(Theme.color.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            LimitBar(value: Double(r.docs.taskState.lines), soft: taskStateSoft, hard: taskStateHard)
                        }
                    }
                }
            }
        })
    }
}

// MARK: - Changelog staleness

private struct ChangelogStalenessPanel: View {
    let repos: [Repo]
    @Environment(AppState.self) private var app

    var body: some View {
        VibePanel(title: "changelog staleness", flushBody: true) {
            if repos.isEmpty {
                EmptyState(icon: "history", tone: .ok, text: "every CHANGELOG is current.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(repos.enumerated()), id: \.element.id) { idx, r in
                        let tone = r.docs.changelog.status.tone
                        Button { app.openRepo(r.id) } label: {
                            HStack(spacing: Theme.space.x2_5) {
                                VibeIcon("history", size: 14, color: Theme.color.tone(tone))
                                Text(r.name)
                                    .font(VibeFont.mono(VibeFont.size.sm))
                                    .foregroundStyle(Theme.color.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: Theme.space.x2)
                                Text("\(r.docs.changelog.behind) behind · \(r.docs.changelog.lastUpdated)")
                                    .font(VibeFont.mono(VibeFont.size.xxs))
                                    .foregroundStyle(Theme.color.tone(tone))
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, Theme.space.x4)
                            .padding(.vertical, Theme.space.x2_5)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if idx != repos.count - 1 {
                                Rectangle().fill(Theme.color.borderSubtle).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }
}
