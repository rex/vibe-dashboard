// RepoAgentTab.swift — the repo-detail Agent tab + a terse TASK_STATE renderer.
//
// The local-only face of a repo: who's editing it right now (live session),
// the git worktrees agents leave behind, the docs they bloat, the CHANGELOG
// they forget, the Serena project state — and the raw TASK_STATE.md rendered
// in a sunken well by a tiny hand-rolled markdown view (TaskMarkdownView).
//
// Mono-dominant, dark, terse. All values flow through Theme / VibeFont / DS.

import SwiftUI

// Doc-bloat thresholds (soft / hard) per file class.
private enum DocLimit {
    static let taskSoft: Double = 400,  taskHard: Double = 800
    static let mdSoft: Double = 300,    mdHard: Double = 500
}

// MARK: - Agent tab

struct RepoAgentTab: View {
    let repo: Repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Agent")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                liveSessionPanel
                worktreesPanel
                docBloatPanel
                changelogPanel
                serenaPanel
                taskStatePanel
            }
            .padding(Theme.space.x5)
        }
    }

    // ---- 1. live session ----

    @ViewBuilder private var liveSessionPanel: some View {
        VibePanel(title: "live session", icon: "bot", glow: false) {
            if let a = repo.agent, a.active {
                LiveSessionCard(repo: repo, agent: a)
            } else {
                HStack(spacing: Theme.space.x2) {
                    VibeIcon("circle-slash", size: 13, color: Theme.color.textFaint)
                    Text("idle · no agent editing · last write \(repo.agent?.lastActivity ?? "—")")
                        .font(VibeFont.mono(VibeFont.size.sm))
                        .foregroundStyle(Theme.color.textMuted)
                        .lineLimit(1)
                }
            }
        }
    }

    // ---- 2. worktrees ----

    @ViewBuilder private var worktreesPanel: some View {
        VibePanel(title: "worktrees", icon: "git-branch", flushBody: !repo.worktrees.isEmpty) {
            if repo.worktrees.isEmpty {
                EmptyState(icon: "git-branch", tone: .ok, text: "one worktree. no branch sprawl here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(repo.worktrees) { WorktreeRow(wt: $0) }
                }
            }
        }
    }

    // ---- 3. doc bloat ----

    @ViewBuilder private var docBloatPanel: some View {
        VibePanel(title: "doc bloat", icon: "file-warning") {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                DocBloatRow(label: "TASK_STATE.md", lines: repo.docs.taskState.lines,
                            soft: DocLimit.taskSoft, hard: DocLimit.taskHard,
                            present: repo.docs.taskState.present)
                DocBloatRow(label: "AGENTS.md", lines: repo.docs.agentsMd.lines,
                            soft: DocLimit.mdSoft, hard: DocLimit.mdHard,
                            present: repo.docs.agentsMd.present)
                DocBloatRow(label: "CLAUDE.md", lines: repo.docs.claudeMd.lines,
                            soft: DocLimit.mdSoft, hard: DocLimit.mdHard,
                            present: repo.docs.claudeMd.present)
            }
        }
    }

    // ---- 4. changelog ----

    @ViewBuilder private var changelogPanel: some View {
        let cl = repo.docs.changelog
        VibePanel(title: "changelog", icon: "history", flushBody: true) {
            VStack(spacing: 0) {
                MetaRow(key: "last updated") {
                    Text(cl.lastUpdated)
                        .foregroundStyle(cl.status == .ok ? Theme.color.textPrimary : Theme.color.tone(cl.status.tone))
                }
                MetaRow(key: "behind") {
                    Text("\(cl.behind) commit\(cl.behind == 1 ? "" : "s")")
                        .foregroundStyle(cl.behind == 0 ? Theme.color.textPrimary : Theme.color.tone(cl.status.tone))
                }
                MetaRow(key: "status") {
                    StatusBadge(text: cl.status.rawValue, tone: cl.status.tone, small: true)
                }
            }
            .padding(.horizontal, Theme.space.x4)
        }
    }

    // ---- 5. serena ----

    @ViewBuilder private var serenaPanel: some View {
        VibePanel(title: "serena", icon: "waypoints", flushBody: repo.serena?.present == true) {
            if let s = repo.serena, s.present {
                VStack(spacing: 0) {
                    MetaRow(key: "project") { Text(s.project.isEmpty ? "—" : s.project) }
                    MetaRow(key: "state") {
                        StatusBadge(text: s.active ? "active" : "indexed",
                                    tone: s.active ? .ok : .neutral, small: true, live: s.active)
                    }
                    MetaRow(key: "memories") { Text("\(s.memories)") }
                    MetaRow(key: "last session") { Text(s.lastSession) }
                }
                .padding(.horizontal, Theme.space.x4)
            } else {
                EmptyState(icon: "circle-slash", tone: .neutral, text: "no Serena project")
            }
        }
    }

    // ---- 6. TASK_STATE.md ----

    @ViewBuilder private var taskStatePanel: some View {
        VibePanel(title: "TASK_STATE.md", icon: "file-text") {
            VibePanel(surface: .sunken) {
                if repo.docs.taskStateMarkdown.isEmpty {
                    EmptyState(icon: "file-text", tone: .neutral, text: "no TASK_STATE.md on disk")
                } else {
                    TaskMarkdownView(text: repo.docs.taskStateMarkdown)
                }
            }
        }
    }
}

// MARK: - Live session card

private func agentToolIcon(_ tool: String?) -> String {
    switch tool {
    case "codex": return "square-terminal"
    case "serena": return "waypoints"
    case "claude-code", "claude": return "bot"
    default: return "bot"
    }
}

private struct LiveSessionCard: View {
    let repo: Repo
    let agent: AgentInfo

    private var isIdle: Bool { agent.state == .idle }
    private var liveTone: VibeTone { repo.health == .danger ? .danger : .warn }
    // ACTIVE keeps the live amber (or danger) treatment; IDLE reads muted so a quiet
    // 15–60m session never masquerades as bright-live (that would be fake liveness).
    private var accent: Color { isIdle ? Theme.color.textMuted : Theme.color.tone(liveTone) }
    private var cardBg: Color { isIdle ? Theme.color.surfaceSunken : Theme.color.warnSurfaceSoft }
    private var cardLine: Color { isIdle ? Theme.color.border : Theme.color.warnLine }
    private var tileBg: Color { isIdle ? Theme.color.surfaceSunken : Theme.color.toneSurface(liveTone) }
    private var tileLine: Color { isIdle ? Theme.color.border : Theme.color.toneLine(liveTone) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x3) {
            // identity: tool tile · tool/branch/elapsed · pulse
            HStack(spacing: Theme.space.x2_5) {
                VibeIcon(agentToolIcon(agent.tool), size: 17, color: accent)
                    .frame(width: 34, height: 34)
                    .background(tileBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                        .strokeBorder(tileLine, lineWidth: 1))

                VStack(alignment: .leading, spacing: Theme.space.x0_5) {
                    HStack(spacing: Theme.space.x1_5) {
                        HealthDot(health: repo.health, size: 8)
                        Text(agent.tool ?? "agent")
                            .font(VibeFont.mono(VibeFont.size.md, .bold))
                            .foregroundStyle(Theme.color.textBright)
                    }
                    Text("\(agent.branch ?? "—") · \(agent.elapsed ?? "—")")
                        .font(VibeFont.mono(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AgentPulse(active: !isIdle, color: isIdle ? Theme.color.textFaint : accent, size: 14)
            }

            // note
            Text(agent.note)
                .font(VibeFont.mono(VibeFont.size.xs))
                .foregroundStyle(Theme.color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // diff meta — +/− only when the diff was actually measured (no fake "+0 −0")
            HStack(spacing: Theme.space.x1) {
                Text("\(agent.filesTouched) file\(agent.filesTouched == 1 ? "" : "s")").foregroundStyle(Theme.color.textMuted)
                if let added = agent.linesAdded, let removed = agent.linesRemoved {
                    Text(" · ").foregroundStyle(Theme.color.textGhost)
                    Text("+\(added.formatted())").foregroundStyle(Theme.color.ok)
                    Text("\u{2212}\(removed.formatted())").foregroundStyle(Theme.color.danger)
                }
                // IDLE surfaces the honest "idle · last write 22m ago"; amber "idle"
                // is the one warm note on an otherwise muted card.
                if isIdle {
                    Text(" · ").foregroundStyle(Theme.color.textGhost)
                    Text("idle").foregroundStyle(Theme.color.warn)
                }
                Text(" · last write \(agent.lastActivity)").foregroundStyle(Theme.color.textMuted)
            }
            .font(VibeFont.mono(VibeFont.size.xxs))
            .lineLimit(1)
        }
        .padding(Theme.space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(cardLine, lineWidth: 1))
    }
}

// MARK: - Rows

private struct WorktreeRow: View {
    let wt: Worktree
    var body: some View {
        HStack(spacing: Theme.space.x3) {
            VibeIcon("git-branch", size: 13, color: Theme.color.tone(wt.state.tone))
            Text(wt.branch)
                .font(VibeFont.mono(VibeFont.size.sm, .medium))
                .foregroundStyle(Theme.color.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // A LINKED worktree sitting on uncommitted work is a real surprise — flag it.
            if wt.dirty { Pill(text: "dirty", tone: .warn) }
            StatusBadge(text: wt.state.rawValue, tone: wt.state.tone, small: true)
            Text(wt.created)
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textFaint)
                .fixedSize()
            Text("\(wt.commits) commits")
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textMuted)
                .fixedSize()
        }
        .padding(.horizontal, Theme.space.x4)
        .frame(minHeight: Theme.layout.rowH)
        .padding(.vertical, Theme.space.x1_5)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

private struct DocBloatRow: View {
    let label: String
    let lines: Int
    let soft: Double
    let hard: Double
    var present: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1) {
            HStack {
                Text(label)
                    .font(VibeFont.mono(VibeFont.size.xs, .medium))
                    .foregroundStyle(Theme.color.textPrimary)
                Spacer(minLength: Theme.space.x2)
                if present {
                    Text("soft \(Int(soft)) · hard \(Int(hard))")
                        .font(VibeFont.mono(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textGhost)
                } else {
                    StatusBadge(text: "missing", tone: .warn, small: true, showDot: false)
                }
            }
            if present {
                LimitBar(value: Double(lines), soft: soft, hard: hard, unit: " ln")
            } else {
                // A MISSING required doc is NOT a 0-line doc — render an explicit hollow
                // track, never a healthy-looking empty bar that reads identical to one.
                HStack(spacing: Theme.space.x2_5) {
                    Capsule().fill(Theme.color.surfaceActive)
                        .frame(height: 6)
                        .overlay(Capsule().strokeBorder(Theme.color.warnLine, lineWidth: 1))
                    Text("absent")
                        .font(VibeFont.mono(VibeFont.size.xs, .bold))
                        .foregroundStyle(Theme.color.warn)
                        .frame(minWidth: 46, alignment: .trailing)
                }
            }
        }
    }
}
