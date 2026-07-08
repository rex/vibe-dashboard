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
    private var isIdle: Bool { agent.state == .idle }
    // ACTIVE keeps the live amber treatment; IDLE goes muted + labeled, never bright-live.
    private var cardBg: Color { isIdle ? Theme.color.surfaceSunken : Theme.color.warnSurfaceSoft }
    private var cardLine: Color { isIdle ? Theme.color.border : Theme.color.warnLine }

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
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(cardLine, lineWidth: 1))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.03)).frame(height: 1).padding(.horizontal, 1)
        }
    }

    private var identityRow: some View {
        HStack(alignment: .center, spacing: Theme.space.x2_5) {
            VibeIcon(tool.icon, size: 17, color: isIdle ? Theme.color.textMuted : Theme.color.warn)
                .frame(width: 34, height: 34)
                .background(isIdle ? Theme.color.surfaceSunken : Theme.color.warnSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                    .strokeBorder(cardLine, lineWidth: 1))
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
            AgentPulse(active: !isIdle, color: isIdle ? Theme.color.textFaint : Theme.color.warn, size: 14)
        }
    }

    private var diffMeta: some View {
        HStack(alignment: .center, spacing: AgentsLayout.gap14) {
            Text("\(agent.filesTouched) file\(agent.filesTouched == 1 ? "" : "s")").foregroundStyle(Theme.color.textMuted)
            // Only render +/− when the diff was actually measured — never a fake "+0 −0".
            if let added = agent.linesAdded, let removed = agent.linesRemoved {
                HStack(spacing: 0) {
                    Text("+\(added.formatted())").foregroundStyle(Theme.color.ok)
                    Text("\u{2212}\(removed.formatted())").foregroundStyle(Theme.color.danger)
                }
            }
            // IDLE shows the honest "idle · last write 22m ago"; amber "idle" is the one warm note.
            Text(isIdle ? "idle " : "").foregroundColor(Theme.color.warn) +
                Text("· last write \(agent.lastActivity)").foregroundColor(Theme.color.textMuted)
        }
        .font(VibeFont.mono(VibeFont.size.xxs))
        .monospacedDigit()
    }

    private var actionRow: some View {
        HStack(spacing: Theme.space.x2) {
            VibeButton(title: "Watch", icon: "terminal", variant: .secondary, size: .sm, block: true) {
                app.openRepo(repo.id); app.openConsole(.output)
            }
            // Agents can't be paused (ps/lsof is read-only) — reveal the tree instead.
            VibeButton(title: "Reveal", icon: "folder-open", variant: .secondary, size: .sm, block: true) {
                app.reveal(path: repo.absolutePath)
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
    @Environment(FleetStore.self) private var store

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
            StatusBadge(text: wt.state.rawValue, tone: wt.state.tone, small: true)
            // Per-row prune is gated to ABANDONED only (a stale one may be unpushed).
            if wt.state == .abandoned {
                Button {
                    let r = repo, w = wt, host = store.fleet.scanner.host
                    Task { @MainActor in
                        let ok = await app.pruneWorktrees(r, worktrees: [w], host: host)
                        if ok { await store.rescan(repoId: r.id) }
                    }
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

// Doc-bloat + changelog-staleness leaderboards live in AgentsPanels.swift (kept out of
// this file for the 400-line hard gate).
