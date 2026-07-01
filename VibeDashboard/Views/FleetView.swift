// FleetView.swift — agent-aware mission control: stat strip + nested repo table.

import SwiftUI

private enum Col {
    static let stack: CGFloat = 116, agent: CGFloat = 150, gates: CGFloat = 118
    static let docs: CGFloat = 96, policy: CGFloat = 64, state: CGFloat = 104
}

func complianceTone(_ c: Int) -> VibeTone { c >= 95 ? .ok : c >= 80 ? .warn : .danger }

struct FleetView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    var body: some View {
        let t = store.fleet.totals
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                VStack(alignment: .leading, spacing: Theme.space.x1_5) {
                    Text("Fleet").font(VibeFont.sans(VibeFont.size.xxl, .semibold)).tracking(VibeFont.size.xxl * -0.02).foregroundStyle(Theme.color.textBright)
                    headline(t)
                }

                VibePanel(glow: t.danger == 0, flushBody: true) {
                    let cols = [GridItem(.adaptive(minimum: 150), spacing: 1)]
                    LazyVGrid(columns: cols, spacing: 1) {
                        StatTile(value: "\(t.repos)", label: "repos", tone: .neutral, icon: "folder-git-2")
                        StatTile(value: "\(t.compliance)", unit: "%", label: "compliance", tone: complianceTone(t.compliance), icon: "gauge")
                        StatTile(value: "\(t.agentsActive)", label: "working", tone: t.agentsActive > 0 ? .warn : .ok, icon: "bot") { app.goView(.agents) }
                        StatTile(value: "\(t.abandonedWorktrees)", label: "abandoned", tone: t.abandonedWorktrees > 0 ? .danger : .ok, icon: "git-branch") { app.goView(.agents) }
                        StatTile(value: "\(t.bloatedDocs)", label: "doc bloat", tone: t.bloatedDocs > 0 ? .danger : .ok, icon: "file-warning") { app.goView(.agents) }
                        StatTile(value: "\(t.surprises)", label: "surprises", tone: t.surprises > 0 ? .danger : .ok, icon: "triangle-alert") { app.goView(.findings) }
                    }
                    .background(Theme.color.border)
                }

                VibePanel(flushBody: true) {
                    VStack(spacing: 0) {
                        headerRow
                        ForEach(store.fleet.tree) { node in
                            if let r = store.fleet.byId[node.repoId] {
                                if r.isWorkspace {
                                    WorkspaceTableRow(ws: r) { app.openRepo(r.id) }
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

    @ViewBuilder private func headline(_ t: FleetTotals) -> some View {
        Group {
            if t.agentsActive > 0, let s = store.fleet.sessions.first {
                Text("\(t.agentsActive) agent\(t.agentsActive > 1 ? "s" : "") working").foregroundStyle(Theme.color.warn)
                + Text(" · \(t.abandonedWorktrees) abandoned worktrees · \(s.name) is being edited live.").foregroundStyle(Theme.color.textSecondary)
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.name).font(VibeFont.mono(VibeFont.size.sm, .medium)).foregroundStyle(Theme.color.textPrimary).lineLimit(1)
                    Text(repo.desc).font(VibeFont.sans(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted).lineLimit(1)
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
        .help("\(repo.name) · \(repo.path)")
        .opacity(store.isIgnored(repo.id) ? 0.45 : 1)
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(store.isIgnored(repo.id) ? "Show in fleet" : "Ignore repo") { store.toggleIgnore(repo.id) }
            Button("Open detail") { onTap() }
        }
    }
}

private struct WorkspaceTableRow: View {
    let ws: Repo
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
            }
        }
    }
}

struct AgentCell: View {
    let repo: Repo
    var body: some View {
        if let a = repo.agent, a.active {
            HStack(spacing: 7) {
                AgentPulse(active: true, color: repo.health == .danger ? Theme.color.danger : Theme.color.warn, size: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.tool ?? "agent").font(VibeFont.mono(VibeFont.size.xs, .bold)).foregroundStyle(repo.health == .danger ? Theme.color.danger : Theme.color.warn)
                    Text("\(a.elapsed ?? "—") · \(a.filesTouched)f").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
                }
            }
        } else if repo.serena?.active == true {
            HStack(spacing: 6) { VibeIcon("waypoints", size: 12, color: Theme.color.info); Text("serena").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textSecondary) }
        } else {
            Text("idle · \(repo.agent?.lastActivity ?? "—")").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint).lineLimit(1)
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
    }
}
