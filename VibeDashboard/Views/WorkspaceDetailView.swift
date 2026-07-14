// WorkspaceDetailView.swift — workspace rollup: emblem header, aggregate
// stat strip over resolved children, and a nested child-repo table.

import SwiftUI

private enum WsCol {
    static let stack: CGFloat = 132, agent: CGFloat = 158, policy: CGFloat = 66, state: CGFloat = 104
}

struct WorkspaceDetailView: View {
    let workspace: Repo
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    /// Resolved leaf children, in the workspace's declared order.
    private var children: [Repo] {
        workspace.children.compactMap { store.fleet.byId[$0] }
    }

    // ---- aggregates over children ----
    private var worstHealth: Health { children.map(\.health).max() ?? .idle }
    private var avgCompliance: Int {
        children.isEmpty ? 100 : children.reduce(0) { $0 + $1.compliance } / children.count
    }
    private var totalSurprises: Int { children.reduce(0) { $0 + $1.surprises.count } }
    // The workspace's OWN sessions count too — a multi-repo session runs AT the root.
    private var agentsActive: Int {
        workspace.agentSessions.count + children.reduce(0) { $0 + $1.agentSessions.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text(workspace.name)
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                header
                statStrip
                table
            }
            .padding(Theme.space.x5)
        }
    }

    // ---- header: folder-tree emblem + name + N managed repos ----
    private var header: some View {
        VibePanel(glow: worstHealth == .ok) {
            HStack(spacing: Theme.space.x3) {
                emblem
                VStack(alignment: .leading, spacing: Theme.space.x1) {
                    HStack(spacing: Theme.space.x2) {
                        Text(workspace.name)
                            .font(VibeFont.mono(VibeFont.size.lg, .semibold))
                            .foregroundStyle(Theme.color.textBright).lineLimit(1)
                        Text("workspace").vibeMicroLabel(9, color: Theme.color.textFaint)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs)
                                .strokeBorder(Theme.color.border, lineWidth: 1))
                    }
                    Text("\(children.count) managed repo\(children.count == 1 ? "" : "s")")
                        .font(VibeFont.mono(VibeFont.size.sm, .medium))
                        .foregroundStyle(Theme.color.textSecondary)
                    Text(workspace.path)
                        .font(VibeFont.mono(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textMuted).lineLimit(1)
                }
                Spacer(minLength: Theme.space.x4)
                StatusBadge(text: rollupLabel, tone: worstHealth.tone,
                            live: agentsActive > 0, solid: worstHealth == .ok)
            }
        }
    }

    private var emblem: some View {
        VibeIcon("folder-tree", size: 24, color: Theme.color.textSecondary)
            .frame(width: 48, height: 48)
            .background(
                LinearGradient(colors: [Theme.color.surfaceRaised, ColorPalette.ink850],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.color.borderStrong, lineWidth: 1))
    }

    private var rollupLabel: String {
        switch worstHealth {
        case .ok: return "all in policy"
        case .warn: return "\(children.filter { $0.health == .warn }.count) drifting"
        case .danger: return "\(children.filter { $0.health == .danger }.count) with surprises"
        case .idle: return "idle"
        }
    }

    // ---- aggregate stat strip ----
    private var statStrip: some View {
        VibePanel(glow: worstHealth == .ok, flushBody: true) {
            let cols = [GridItem(.adaptive(minimum: 150), spacing: 1)]
            LazyVGrid(columns: cols, spacing: 1) {
                StatTile(value: worstHealth.rawValue, label: "worst health",
                         tone: worstHealth.tone, icon: "activity")
                StatTile(value: "\(avgCompliance)", unit: "%", label: "avg compliance",
                         tone: complianceTone(avgCompliance), icon: "gauge")
                StatTile(value: "\(totalSurprises)", label: "surprises",
                         tone: totalSurprises > 0 ? .danger : .ok, icon: "triangle-alert") {
                    app.goView(.findings)
                }
                StatTile(value: "\(agentsActive)", label: "agents active",
                         tone: agentsActive > 0 ? .warn : .ok, icon: "bot") {
                    app.goView(.agents)
                }
            }
            .background(Theme.color.border)
        }
    }

    // ---- child-repo table ----
    private var table: some View {
        VibePanel(title: "managed repos", icon: "folder-tree", flushBody: true) {
            if children.isEmpty {
                EmptyState(icon: "folder-tree", tone: .neutral, text: "no repos under this workspace.")
            } else {
                VStack(spacing: 0) {
                    tableHeader
                    ForEach(children) { child in
                        WorkspaceChildRow(repo: child) { app.openRepo(child.id) }
                    }
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("repository").frame(maxWidth: .infinity, alignment: .leading)
            Text("stack").frame(width: WsCol.stack, alignment: .leading)
            Text("agent").frame(width: WsCol.agent, alignment: .leading)
            Text("policy").frame(width: WsCol.policy, alignment: .leading)
            Text("state").frame(width: WsCol.state, alignment: .trailing)
        }
        .vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
        .padding(.horizontal, Theme.space.x4).padding(.vertical, Theme.space.x2_5)
        .frame(maxWidth: .infinity)
        .background(Theme.color.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }
}

// ---- one child repo row ----
private struct WorkspaceChildRow: View {
    let repo: Repo
    var onTap: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                HealthDot(health: repo.health, size: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.name).font(VibeFont.mono(VibeFont.size.sm, .medium))
                        .foregroundStyle(Theme.color.textPrimary).lineLimit(1)
                    Text(repo.desc).font(VibeFont.sans(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textMuted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 7) {
                LangGlyph(stack: repo.stack, size: 18)
                Text(repo.lang.label).font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textSecondary).lineLimit(1)
            }.frame(width: WsCol.stack, alignment: .leading)

            AgentCell(repo: repo).frame(width: WsCol.agent, alignment: .leading)

            Text("\(repo.compliance)%").font(VibeFont.mono(VibeFont.size.md, .bold))
                .foregroundStyle(Theme.color.tone(complianceTone(repo.compliance)))
                .frame(width: WsCol.policy, alignment: .leading)

            HStack(spacing: 7) {
                if repo.surprises.isEmpty { StatusBadge(text: "clean", tone: .ok, small: true) }
                else { StatusBadge(text: "\(repo.surprises.count)", tone: repo.health.tone, small: true) }
                VibeIcon("chevron-right", size: 14, color: Theme.color.textGhost)
            }.frame(width: WsCol.state, alignment: .trailing)
        }
        .padding(.horizontal, Theme.space.x4)
        .frame(height: Theme.layout.rowHLg)
        .background(hover ? Theme.color.surfaceRaised : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
    }
}
