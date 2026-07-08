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
                            soft: DocLimit.taskSoft, hard: DocLimit.taskHard)
                DocBloatRow(label: "AGENTS.md", lines: repo.docs.agentsMd.lines,
                            soft: DocLimit.mdSoft, hard: DocLimit.mdHard)
                DocBloatRow(label: "CLAUDE.md", lines: repo.docs.claudeMd.lines,
                            soft: DocLimit.mdSoft, hard: DocLimit.mdHard)
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

    private var accent: Color { repo.health == .danger ? Theme.color.danger : Theme.color.warn }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x3) {
            // identity: tool tile · tool/branch/elapsed · pulse
            HStack(spacing: Theme.space.x2_5) {
                VibeIcon(agentToolIcon(agent.tool), size: 17, color: accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.color.toneSurface(repo.health == .danger ? .danger : .warn))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                        .strokeBorder(Theme.color.toneLine(repo.health == .danger ? .danger : .warn), lineWidth: 1))

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

                AgentPulse(active: true, color: accent, size: 14)
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
                Text(" · last write \(agent.lastActivity)").foregroundStyle(Theme.color.textMuted)
            }
            .font(VibeFont.mono(VibeFont.size.xxs))
            .lineLimit(1)
        }
        .padding(Theme.space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.warnSurfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(Theme.color.warnLine, lineWidth: 1))
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
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1) {
            HStack {
                Text(label)
                    .font(VibeFont.mono(VibeFont.size.xs, .medium))
                    .foregroundStyle(Theme.color.textPrimary)
                Spacer(minLength: Theme.space.x2)
                Text("soft \(Int(soft)) · hard \(Int(hard))")
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textGhost)
            }
            LimitBar(value: Double(lines), soft: soft, hard: hard, unit: " ln")
        }
    }
}

// MARK: - TASK_STATE.md markdown

/// A tiny, terse markdown renderer for TASK_STATE.md — headings, checkboxes,
/// bullets, blockquotes, body text, and inline `code` spans. Line-based, no
/// dependencies; everything mono except the top-level `#` heading (Grotesk).
struct TaskMarkdownView: View {
    let text: String

    private enum Block {
        case h1(String), h2(String), h3(String)
        case check(Bool, String)
        case bullet(String)
        case quote(String)
        case body(String)
        case spacer
    }

    // Parsed lines keyed by their original index (stable identity for ForEach).
    private var blocks: [(Int, Block)] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .enumerated()
            .map { ($0.offset, Self.parse($0.element)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
            ForEach(blocks, id: \.0) { _, block in
                row(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ---- parse ----

    private static func parse(_ raw: String) -> Block {
        let line = raw
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .spacer }
        if line.hasPrefix("### ") { return .h3(String(line.dropFirst(4))) }
        if line.hasPrefix("## ")  { return .h2(String(line.dropFirst(3))) }
        if line.hasPrefix("# ")   { return .h1(String(line.dropFirst(2))) }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return .check(true, String(trimmed.dropFirst(6)))
        }
        if trimmed.hasPrefix("- [ ] ") { return .check(false, String(trimmed.dropFirst(6))) }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return .bullet(String(trimmed.dropFirst(2))) }
        if trimmed.hasPrefix("> ") { return .quote(String(trimmed.dropFirst(2))) }
        return .body(line)
    }

    // ---- render ----

    @ViewBuilder private func row(for block: Block) -> some View {
        switch block {
        case .h1(let s):
            Text(s)
                .font(VibeFont.sans(VibeFont.size.lg, .semibold))
                .tracking(VibeFont.size.lg * VibeFont.track.snug)
                .foregroundStyle(Theme.color.textBright)
                .padding(.top, Theme.space.x1)
        case .h2(let s):
            Text(s)
                .font(VibeFont.mono(VibeFont.size.md, .bold))
                .foregroundStyle(Theme.color.textPrimary)
                .padding(.top, Theme.space.x1)
        case .h3(let s):
            Text(s.uppercased())
                .font(VibeFont.mono(VibeFont.size.xs, .bold))
                .tracking(VibeFont.size.xs * VibeFont.track.label)
                .foregroundStyle(Theme.color.textSecondary)
        case .check(let done, let s):
            HStack(alignment: .firstTextBaseline, spacing: Theme.space.x2) {
                VibeIcon(done ? "check-circle-2" : "square-dashed", size: 13,
                         color: done ? Theme.color.ok : Theme.color.textFaint)
                inline(s)
                    .strikethrough(done, color: Theme.color.textGhost)
                    .foregroundStyle(done ? Theme.color.textMuted : Theme.color.textPrimary)
            }
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: Theme.space.x2) {
                Text("·").font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.textFaint)
                inline(s).foregroundStyle(Theme.color.textSecondary)
            }
            .padding(.leading, Theme.space.x1)
        case .quote(let s):
            HStack(spacing: Theme.space.x2_5) {
                Rectangle().fill(Theme.color.accent).frame(width: 2)
                inline(s).foregroundStyle(Theme.color.textMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .body(let s):
            inline(s).foregroundStyle(Theme.color.textSecondary)
        case .spacer:
            Spacer().frame(height: Theme.space.x1)
        }
    }

    // ---- inline `code` spans ----

    /// Render a line as mono body text, styling backtick-delimited spans as code.
    private func inline(_ s: String) -> Text {
        guard s.contains("`") else {
            return Text(s).font(VibeFont.mono(VibeFont.size.sm))
        }
        var out = Text("")
        var isCode = false
        for segment in s.components(separatedBy: "`") {
            let piece = isCode
                ? Text(segment).font(VibeFont.mono(VibeFont.size.sm, .medium)).foregroundColor(Theme.color.accent)
                : Text(segment).font(VibeFont.mono(VibeFont.size.sm))
            out = out + piece
            isCode.toggle()
        }
        return out
    }
}
