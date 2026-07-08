// SidebarView.swift — the source list: nested workspace tree + scanner footer.

import SwiftUI
import AppKit

struct SidebarView: View {
    var width: CGFloat = Theme.layout.sidebar
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    @State private var collapsed: Set<String> = []

    /// Walk the pre-order `sidebarTree`, hiding the descendants of collapsed nodes.
    /// A collapsed node at depth `d` hides every following row with depth > d until
    /// the tree returns to depth <= d — so collapse composes at arbitrary depth.
    private var visibleRows: [SidebarNode] {
        var out: [SidebarNode] = []
        var hideBelow: Int? = nil
        for node in store.fleet.sidebarTree {
            if let hd = hideBelow {
                if node.depth > hd { continue }
                hideBelow = nil
            }
            out.append(node)
            if node.hasChildren && collapsed.contains(node.id) { hideBelow = node.depth }
        }
        return out
    }

    var body: some View {
        let s = store.fleet.scanner
        let lastSwept = s.lastSweepAt.map { RelTime.ago($0, now: Date()) } ?? "not yet"
        VStack(spacing: 0) {
            HStack(spacing: Theme.space.x2) {
                VibeIcon("hard-drive", size: 14, color: Theme.color.textMuted)
                Text(s.root).font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                // Honest state: lime "scanning" only while a scan runs; muted "idle"
                // otherwise. There is no live watcher, so nothing claims "live".
                HStack(spacing: 5) {
                    Circle().fill(store.isScanning ? Theme.color.ok : Theme.color.textGhost).frame(width: 6, height: 6)
                        .shadow(color: store.isScanning ? ColorPalette.lime400.opacity(0.3) : .clear, radius: 4)
                    Text(store.isScanning ? "scanning" : "idle")
                        .vibeMicroLabel(9, color: store.isScanning ? Theme.color.ok : Theme.color.textGhost)
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
                    ForEach(visibleRows) { node in
                        if node.kind == .group {
                            SidebarGroupRow(node: node, expanded: !collapsed.contains(node.id),
                                            onToggle: { toggle(node.id) })
                        } else if let repo = store.fleet.byId[node.repoId ?? ""] {
                            SidebarRow(repo: repo, depth: node.depth, hasChildren: node.hasChildren,
                                       expanded: !collapsed.contains(node.id),
                                       selected: app.selectedId == repo.id,
                                       onSelect: { app.openRepo(repo.id) },
                                       onToggle: { toggle(node.id) })
                        }
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
                    VibeIcon("radar", size: 13, color: store.isScanning ? Theme.color.ok : Theme.color.textMuted)
                    Text("manual scan · \(s.host)").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textSecondary)
                }
                // Real: last-swept relative time (ages via RelTime.ago) + measured duration.
                Text("last swept \(lastSwept) · \(s.swept)")
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
            // Re-probe just THIS repo's git state (worktree/build/scm) and re-grade it
            // in place — no full fleet sweep. store.rescan(repoId:) already scopes this.
            Button("Refresh this repo") { Task { await store.rescan(repoId: repo.id) } }
                .disabled(store.isScanning)
            Divider()
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

/// A structural directory in the sidebar — a plain grouping dir (`__APPS`, `macOS`,
/// `__INFRASTRUCTURE`) that contains codebases but is NOT itself a workspace. It is
/// deliberately inert: a folder glyph + muted name + a disclosure to fold the group,
/// and nothing else — no selection, no hover highlight, no navigation, no actions.
private struct SidebarGroupRow: View {
    let node: SidebarNode
    let expanded: Bool
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onToggle) { Disclosure(open: expanded) }.buttonStyle(.plain)
            VibeIcon(expanded ? "folder-open" : "folder", size: 13, color: Theme.color.textFaint)
            Text(node.name)
                .font(VibeFont.mono(VibeFont.size.sm, .medium))
                .foregroundStyle(Theme.color.textMuted)
                .lineLimit(1)
            Spacer(minLength: 0)
            if node.repoCount > 0 {
                Text("\(node.repoCount)")
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textGhost)
            }
        }
        .padding(.leading, 8 + CGFloat(node.depth) * 15).padding(.trailing, 9)
        .frame(height: Theme.layout.rowH)
        .contentShape(Rectangle())
        .help(node.absolutePath)
        // No onTapGesture / hover state / contextMenu: structural node, not clickable.
    }
}
