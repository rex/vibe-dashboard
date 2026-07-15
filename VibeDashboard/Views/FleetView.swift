// FleetView.swift — agent-aware mission control: stat strip + nested repo table.

import SwiftUI

private enum Col {
    static let stack: CGFloat = 116, agent: CGFloat = 150, gates: CGFloat = 118
    static let docs: CGFloat = 96, policy: CGFloat = 64, state: CGFloat = 104
}

// Aligned with Derive.healthBand: ≥95 clean, 60–94 drifting, <60 in trouble.
func complianceTone(_ c: Int) -> VibeTone { c >= 95 ? .ok : c >= 60 ? .warn : .danger }

struct FleetView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    var body: some View {
        let t = store.fleet.totals
        let agentSessions = store.liveAgentSessions
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                VStack(alignment: .leading, spacing: Theme.space.x1_5) {
                    Text("Fleet").font(VibeFont.sans(VibeFont.size.xxl, .semibold)).tracking(VibeFont.size.xxl * -0.02).foregroundStyle(Theme.color.textBright)
                    headline(t, sessions: agentSessions)
                }

                VibePanel(glow: t.danger == 0, flushBody: true) {
                    // One row, equal widths, filling the panel — no dead space, no
                    // second-row wrap, centered numbers.
                    HStack(spacing: 1) {
                        StatTile(value: "\(t.repos)", label: "repos", tone: .neutral, icon: "folder-git-2",
                                 help: "Managed repos in view (workspaces not counted)")
                        StatTile(value: "\(t.compliance)", unit: "%", label: "compliance", tone: complianceTone(t.compliance), icon: "gauge",
                                 help: "Average compliance score across visible repos — 100 minus each repo's deductions")
                        StatTile(value: "\(agentSessions.count)", label: "working", tone: agentSessions.isEmpty ? .ok : .warn, icon: "bot",
                                 help: "Live agent sessions detected right now — click for the Agents module") { app.goView(.agents) }
                        StatTile(value: "\(t.abandonedWorktrees)", label: "abandoned", tone: t.abandonedWorktrees > 0 ? .danger : .ok, icon: "git-branch",
                                 help: "Worktrees with no commit in 30+ days — click to review sprawl") { app.goView(.agents) }
                        StatTile(value: "\(t.bloatedDocs)", label: "doc bloat", tone: t.bloatedDocs > 0 ? .danger : .ok, icon: "file-warning",
                                 help: "Repos whose TASK_STATE/AGENTS docs exceed the hard line limit") { app.goView(.agents) }
                        StatTile(value: "\(t.surprises)", label: "surprises", tone: t.surprises > 0 ? .danger : .ok, icon: "triangle-alert",
                                 help: "Open findings across the visible fleet (waived excluded) — click for the feed") { app.goView(.findings) }
                        StatTile(value: "\(t.godFiles)", label: "god files", tone: t.godFiles > 0 ? .danger : .ok, icon: "file-code-2",
                                 help: "Files over the hard line limit and in scope (exclude_globs respected)")
                        StatTile(value: "\(t.dirty)", label: "dirty trees", tone: t.dirty > 0 ? .warn : .ok, icon: "git-commit-horizontal",
                                 help: "Repos with uncommitted changes in the working tree")
                        StatTile(value: "\(t.mcpFailed)", label: "mcp failed", tone: t.mcpFailed > 0 ? .danger : .ok, icon: "waypoints",
                                 help: "Configured MCP servers whose recent calls failed")
                    }
                    .background(Theme.color.border)
                }

                VibePanel(flushBody: true) {
                    // Same filesystem shape as the sidebar: structural group dirs are
                    // inert header rows; repos/workspaces indent to their real depth.
                    VStack(spacing: 0) {
                        headerRow
                        ForEach(store.fleet.sidebarTree) { node in
                            if node.kind == .group {
                                GroupTableRow(node: node)
                            } else if let r = store.fleet.byId[node.repoId ?? ""] {
                                if r.isWorkspace {
                                    WorkspaceTableRow(ws: r, depth: node.depth) { app.openRepo(r.id) }
                                } else {
                                    RepoTableRow(repo: r, depth: node.depth) { app.openRepo(r.id) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.space.x5)
        }
    }

    @ViewBuilder private func headline(_ t: FleetTotals, sessions: [FleetAgentSession]) -> some View {
        Group {
            if let s = sessions.first {
                Text("\(sessions.count) agent\(sessions.count > 1 ? "s" : "") working").foregroundStyle(Theme.color.warn)
                + Text(" · \(t.abandonedWorktrees) abandoned worktrees · \(s.repo.name) is being edited live.")
                    .foregroundStyle(Theme.color.textSecondary)
            } else {
                Text("worker swept \(store.fleet.scanner.lastSweep). ").foregroundStyle(Theme.color.textSecondary)
                + Text("\(t.healthy) in policy").foregroundStyle(Theme.color.ok)
                + Text(" · ").foregroundStyle(Theme.color.textSecondary)
                + Text("\(t.warn) drifting").foregroundStyle(Theme.color.warn)
                + Text(" · ").foregroundStyle(Theme.color.textSecondary)
                + Text("\(t.danger) with surprises").foregroundStyle(Theme.color.danger)
            }
        }
        .font(VibeFont.mono(VibeFont.size.sm))
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("repository").frame(maxWidth: .infinity, alignment: .leading)
            Text("stack").frame(width: Col.stack, alignment: .leading)
            Text("agent").frame(width: Col.agent, alignment: .leading)
            Text("gates").frame(width: Col.gates, alignment: .leading)
            Text("docs").frame(width: Col.docs, alignment: .leading)
            Text("policy").frame(width: Col.policy, alignment: .leading)
            Text("state").frame(width: Col.state, alignment: .trailing)
        }
        .vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
        .padding(.horizontal, Theme.space.x4).padding(.vertical, Theme.space.x2_5)
        .frame(maxWidth: .infinity)
        .background(Theme.color.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }
}

private struct RepoTableRow: View {
    let repo: Repo
    let depth: Int
    var onTap: () -> Void
    @Environment(FleetStore.self) private var store
    @State private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                if depth > 0 { VibeIcon("corner-down-right", size: 13, color: Theme.color.textGhost) }
                HealthDot(health: repo.health, size: 9)
                RepoLogoThumb(repo: repo, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.space.x1_5) {
                        Text(repo.name).font(VibeFont.mono(VibeFont.size.sm, .medium)).foregroundStyle(Theme.color.textPrimary).lineLimit(1)
                        RepoBadges(repo: repo, size: 14)
                    }
                    // Full ~-collapsed path — how same-named repos are told apart.
                    Text(repo.path).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.leading, CGFloat(depth) * 18)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 7) {
                LangGlyph(stack: repo.stack, size: 18)
                Text(repo.lang.label).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textSecondary).lineLimit(1)
            }.frame(width: Col.stack, alignment: .leading)

            AgentCell(repo: repo).frame(width: Col.agent, alignment: .leading)
            GateStrip(gates: repo.gates).frame(width: Col.gates, alignment: .leading)
            DocsCell(repo: repo).frame(width: Col.docs, alignment: .leading)
            Text("\(repo.compliance)%").font(VibeFont.mono(VibeFont.size.md, .bold))
                .foregroundStyle(Theme.color.tone(complianceTone(repo.compliance)))
                .frame(width: Col.policy, alignment: .leading)
                // Hover = the top of the "why this grade" breakdown.
                .help(repo.gradeFactors.isEmpty ? "no deductions"
                      : repo.gradeFactors.sorted { $0.delta < $1.delta }.prefix(4)
                          .map { "\($0.delta) \($0.label)" }.joined(separator: "\n"))
            HStack(spacing: 7) {
                if repo.surprises.isEmpty { StatusBadge(text: "clean", tone: .ok, small: true) }
                else { StatusBadge(text: "\(repo.surprises.count)", tone: repo.health.tone, small: true) }
                VibeIcon("chevron-right", size: 14, color: Theme.color.textGhost)
            }.frame(width: Col.state, alignment: .trailing)
        }
        .padding(.horizontal, Theme.space.x4)
        .frame(height: Theme.layout.rowHLg)
        .background(hover ? Theme.color.surfaceRaised : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        .contentShape(Rectangle())
        .help("\(repo.name) · \(repo.absolutePath)" + (repo.desc.isEmpty ? "" : "\n\(repo.desc)"))
        .opacity(store.isIgnored(repo.id) ? 0.45 : 1)
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(store.isIgnored(repo.id) ? "Show in fleet" : "Ignore repo") { store.toggleIgnore(repo.id) }
            Button("Open detail") { onTap() }
        }
    }
}

/// A plain grouping directory (`__APPS`, `macOS`) — structure, not a destination.
/// Mirrors the sidebar's inert group rows: no hover, no navigation.
private struct GroupTableRow: View {
    let node: SidebarNode
    var body: some View {
        HStack(spacing: 8) {
            VibeIcon("folder", size: 12, color: Theme.color.textFaint)
            Text(node.name)
                .font(VibeFont.mono(VibeFont.size.xs, .medium))
                .foregroundStyle(Theme.color.textMuted)
            Spacer()
            Text("\(node.repoCount)")
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textGhost)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.leading, CGFloat(node.depth) * 18)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Theme.color.surfaceSunken.opacity(0.55))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        .help(node.absolutePath)
    }
}

private struct WorkspaceTableRow: View {
    let ws: Repo
    var depth: Int = 0
    var onTap: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            VibeIcon("folder-tree", size: 14, color: Theme.color.textSecondary)
            Text(ws.name).font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.textPrimary)
            Text("workspace").vibeMicroLabel(9, color: Theme.color.textFaint)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs).strokeBorder(Theme.color.border, lineWidth: 1))
            Text(ws.path).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
            Spacer()
            Text("\(ws.children.count) repos").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
            VibeIcon("chevron-right", size: 13, color: Theme.color.textGhost)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.leading, CGFloat(depth) * 18)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(hover ? Theme.color.surfaceRaised : Theme.color.surface2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
    }
}

// ---- shared cells ----
struct GateStrip: View {
    let gates: [Gate]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(gates) { g in
                Image(systemName: g.status.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.color.tone(g.status.tone))
                    .frame(width: 17, height: 17)
                    .background(g.status == .fail ? Theme.color.dangerSurface : g.status == .warn ? Theme.color.warnSurface : Theme.color.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs).strokeBorder(g.status == .fail ? Theme.color.dangerLine : g.status == .warn ? Theme.color.warnLine : Theme.color.border, lineWidth: 1))
                    .help("\(g.name) · \(g.command)\n\(g.detail)")
            }
        }
    }
}

struct AgentCell: View {
    let repo: Repo
    var body: some View {
        if let a = repo.agent, a.active {
            HStack(spacing: 7) {
                AgentPulse(active: a.state == .active, color: repo.health == .danger ? Theme.color.danger : Theme.color.warn, size: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.tool ?? "agent").font(VibeFont.mono(VibeFont.size.xs, .bold)).foregroundStyle(repo.health == .danger ? Theme.color.danger : Theme.color.warn)
                    Text("\(a.elapsed ?? "—") · \(a.filesTouched)f").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
                }
            }
            .help("\(a.tool ?? "agent") session · \(a.state.rawValue) · \(a.filesTouched) files changed"
                  + (a.model.map { " · \($0)" } ?? "") + " · last activity \(a.lastActivity)")
        } else if repo.serena?.active == true {
            HStack(spacing: 6) { VibeIcon("waypoints", size: 12, color: Theme.color.info); Text("serena").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textSecondary) }
                .help("Serena project active — LSP index available to agents")
        } else {
            Text("idle · \(repo.agent?.lastActivity ?? "—")").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint).lineLimit(1)
                .help("No live agent session detected in this repo")
        }
    }
}

struct DocsCell: View {
    let repo: Repo
    private func k(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }
    var body: some View {
        let ts = repo.docs.taskState
        let cl = repo.docs.changelog
        let worst: VibeTone = [ts.status, repo.docs.agentsMd.status, cl.status].contains(.fail) ? .danger
            : [ts.status, repo.docs.agentsMd.status, cl.status].contains(.warn) ? .warn : .ok
        HStack(spacing: 7) {
            VibeIcon("file-text", size: 13, color: worst == .ok ? Theme.color.textFaint : Theme.color.tone(worst))
            Text("\(k(ts.lines)) ln").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(ts.status == .ok ? Theme.color.textMuted : Theme.color.tone(ts.status.tone))
            if cl.status != .ok { VibeIcon("history", size: 12, color: Theme.color.tone(cl.status.tone)) }
        }
        .help("TASK_STATE.md: \(ts.lines) lines"
              + (cl.status == .ok ? " · changelog current" : " · CHANGELOG \(cl.behind) commits behind"))
    }
}
