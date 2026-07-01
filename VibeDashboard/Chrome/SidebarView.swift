// SidebarView.swift — the source list: nested workspace tree + scanner footer.

import SwiftUI
import AppKit

struct SidebarView: View {
    var width: CGFloat = Theme.layout.sidebar
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    @State private var collapsed: Set<String> = []

    private struct RowItem: Identifiable { let repo: Repo; let depth: Int; let hasChildren: Bool; var id: String { repo.id } }

    private var rows: [RowItem] {
        let f = store.fleet
        var out: [RowItem] = []
        for ws in f.workspaces {
            out.append(RowItem(repo: ws, depth: 0, hasChildren: true))
            if !collapsed.contains(ws.id) {
                let kids = ws.children.compactMap { f.byId[$0] }.sorted { $0.name.lowercased() < $1.name.lowercased() }
                for c in kids { out.append(RowItem(repo: c, depth: 1, hasChildren: false)) }
            }
        }
        for r in f.leaves where r.parentId == nil {
            out.append(RowItem(repo: r, depth: 0, hasChildren: false))
        }
        return out
    }

    var body: some View {
        let s = store.fleet.scanner
        VStack(spacing: 0) {
            HStack(spacing: Theme.space.x2) {
                VibeIcon("hard-drive", size: 14, color: Theme.color.textMuted)
                Text(s.root).font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Circle().fill(Theme.color.ok).frame(width: 6, height: 6)
                        .shadow(color: ColorPalette.lime400.opacity(0.3), radius: 4)
                    Text("live").vibeMicroLabel(9, color: Theme.color.ok)
                }
            }
            .padding(.horizontal, Theme.space.x3).padding(.top, 11).padding(.bottom, Theme.space.x2)

            HStack {
                Text("managed codebases").vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textFaint)
                Spacer()
                Text("\(store.fleet.totals.repos)").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textGhost)
            }
            .padding(.horizontal, 14).padding(.bottom, Theme.space.x1_5)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(rows) { item in
                        SidebarRow(repo: item.repo, depth: item.depth, hasChildren: item.hasChildren,
                                   expanded: !collapsed.contains(item.repo.id),
                                   selected: app.selectedId == item.repo.id,
                                   onSelect: { app.openRepo(item.repo.id) },
                                   onToggle: { toggle(item.repo.id) })
                    }
                }
                .padding(.horizontal, 9).padding(.bottom, Theme.space.x2_5)
            }

            Divider().overlay(Theme.color.border)
            if store.ignoredCount > 0 || store.showIgnored {
                Button { store.toggleShowIgnored() } label: {
                    HStack(spacing: Theme.space.x1_5) {
                        VibeIcon(store.showIgnored ? "eye" : "eye-off", size: 12, color: Theme.color.textMuted)
                        Text(store.showIgnored ? "hide ignored" : "show ignored · \(store.ignoredCount)")
                            .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 13).padding(.top, Theme.space.x2)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: Theme.space.x2) {
                    VibeIcon("radar", size: 13, color: Theme.color.ok)
                    Text("scanner online · \(s.host)").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textSecondary)
                }
                Text("fsevents watching · last sweep \(s.lastSweep) · \(s.swept)")
                    .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13).padding(.vertical, Theme.space.x2_5)
        }
        .frame(width: width)
        .background(ColorPalette.ink900)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.color.border).frame(width: 1) }
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }
}

private struct SidebarRow: View {
    let repo: Repo
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let selected: Bool
    var onSelect: () -> Void
    var onToggle: () -> Void
    @Environment(FleetStore.self) private var store
    @State private var hover = false

    var body: some View {
        HStack(spacing: 7) {
            if hasChildren {
                Button(action: onToggle) { Disclosure(open: expanded) }.buttonStyle(.plain)
            } else if depth > 0 {
                VibeIcon("corner-down-right", size: 11, color: Theme.color.textGhost).frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }
            Group {
                if repo.isWorkspace {
                    VibeIcon("folder-tree", size: 14, color: selected ? Theme.color.accent : Theme.color.textMuted)
                } else {
                    LangGlyph(stack: repo.stack, size: 18, health: repo.health)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Iconic management indicator: repos slipping out of skeleton governance.
                if !repo.isWorkspace && repo.management != .skeleton {
                    Circle().fill(Theme.color.tone(repo.management.tone))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(ColorPalette.ink900, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
            Text(repo.name)
                .font(VibeFont.mono(VibeFont.size.sm, repo.isWorkspace ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.color.textBright : repo.isWorkspace ? Theme.color.textPrimary : Theme.color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if repo.agentActive {
                AgentPulse(active: true, color: repo.health == .danger ? Theme.color.danger : Theme.color.warn, size: 11)
            } else if repo.isWorkspace {
                Text("ws").vibeMicroLabel(9, color: Theme.color.textGhost)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs).strokeBorder(Theme.color.border, lineWidth: 1))
            } else if !repo.surprises.isEmpty {
                Text("\(repo.surprises.count)").font(VibeFont.mono(VibeFont.size.xxs, .bold))
                    .foregroundStyle(repo.health == .danger ? Theme.color.danger : Theme.color.warn)
            } else {
                VibeIcon("check", size: 11, color: Theme.color.textGhost)
            }
        }
        .padding(.leading, 8 + CGFloat(depth) * 15).padding(.trailing, 9)
        .frame(height: Theme.layout.rowH)
        .background(selected ? Theme.color.surfaceActive : hover ? Theme.color.surfaceRaised : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm).strokeBorder(selected ? Theme.color.borderStrong : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .help(repo.isWorkspace || repo.management == .skeleton ? repo.name : "\(repo.name) · \(repo.management.label)")
        .opacity(store.isIgnored(repo.id) ? 0.45 : 1)
        .onHover { hover = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(store.isIgnored(repo.id) ? "Show in fleet" : "Ignore repo") { store.toggleIgnore(repo.id) }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: (repo.absolutePath as NSString).expandingTildeInPath)
            }
            Button("Open in editor") {
                NSWorkspace.shared.open(URL(fileURLWithPath: (repo.absolutePath as NSString).expandingTildeInPath))
            }
        }
    }
}
