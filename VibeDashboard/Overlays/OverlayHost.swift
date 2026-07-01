// OverlayHost.swift — the modal layer: ⌘K command palette + confirm-gated
// write sheets (commit / prune / reconcile / apply-skill / install-hooks /
// waiver / about), each over a flat dimmed backdrop. Mounted once at the app
// root (`MacRootView`). Dark, mono-dominant; terse lowercase-technical voice.
//
// The sheet views + shared shell live in OverlaySheets*.swift (same module).

import SwiftUI

/// Small layout constants shared across the overlay layer.
enum OverlayLayout {
    static let paletteW: CGFloat = 580
    static let sheetW: CGFloat = 560
    static let aboutW: CGFloat = 460
    static let topInset: CGFloat = 0.07     // fraction of window height
    static let listMax: CGFloat = 340
    static let bodyMax: CGFloat = 460
}

struct OverlayHost: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    var body: some View {
        if let sheet = app.sheet {
            GeometryReader { geo in
                ZStack(alignment: sheet == .about ? .center : .top) {
                    Theme.color.bgVoid.opacity(0.62)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { app.closeSheet() }

                    content(sheet)
                        .padding(.top, sheet == .about ? 0 : geo.size.height * OverlayLayout.topInset)
                        .frame(maxWidth: 0.92 * geo.size.width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private func content(_ sheet: SheetKind) -> some View {
        switch sheet {
        case .palette:
            CommandPalette()
        case .about:
            AboutSheet()
        case .commit:
            if let r = store.fleet.repo(app.selectedId) { CommitSheet(repo: r) }
        case .prune:
            if let r = store.fleet.repo(app.selectedId) { PruneSheet(repo: r) }
        case .reconcile:
            if let r = store.fleet.repo(app.selectedId) { ReconcileSheet(repo: r) }
        case .applySkill:
            if let r = store.fleet.repo(app.selectedId) { ApplySkillSheet(repo: r) }
        case .installHooks:
            if let r = store.fleet.repo(app.selectedId) { InstallHooksSheet(repo: r) }
        case .waiver:
            WaiverSheet(repo: store.fleet.repo(app.selectedId))
        case .excludeFile:
            if let req = app.pendingExclude, let r = store.fleet.repo(req.repoId) {
                ExcludeSheet(repo: r, path: req.path)
            }
        }
    }
}

// MARK: - Command palette (⌘K)

private struct PaletteItem: Identifiable {
    enum Kind { case repo, action }
    let id: String
    let kind: Kind
    let label: String
    let sub: String?
    let icon: String
    let health: Health?
    let run: () -> Void
}

private struct CommandPalette: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    @State private var query = ""
    @FocusState private var focused: Bool

    private var items: [PaletteItem] {
        let repos = store.fleet.leaves + store.fleet.workspaces
        let repoItems = repos.map { r in
            PaletteItem(id: "repo·" + r.id, kind: .repo, label: r.name, sub: r.path,
                        icon: "folder-git-2", health: r.health) {
                app.openRepo(r.id); app.closeSheet()
            }
        }
        func act(_ id: String, _ icon: String, _ label: String, _ run: @escaping () -> Void) -> PaletteItem {
            PaletteItem(id: "act·" + id, kind: .action, label: label, sub: nil, icon: icon, health: nil) {
                run(); app.closeSheet()
            }
        }
        let actions: [PaletteItem] = [
            act("rescan", "refresh-cw", "Re-scan ~/Code") { Task { await store.rescan() } },
            act("fleet", "folder-tree", "Go to Fleet") { app.goView(.fleet) },
            act("agents", "radar", "Go to Agents") { app.goView(.agents) },
            act("findings", "triangle-alert", "Go to Findings") { app.goView(.findings) },
            act("skills", "blocks", "Go to Skills") { app.goView(.skills) },
            act("autopilot", "gauge-circle", "Go to Autopilot") { app.goView(.autopilot) },
            act("console", "terminal", "Toggle console") { app.toggleConsole() },
            act("inspector", "panel-right", "Toggle inspector") { app.toggleInspector() },
        ]
        return repoItems + actions
    }

    private var filtered: [PaletteItem] {
        let q = query.lowercased()
        let base = q.isEmpty ? items : items.filter {
            $0.label.lowercased().contains(q) || ($0.sub?.lowercased().contains(q) ?? false)
        }
        return Array(base.prefix(9))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.space.x2_5) {
                VibeIcon("command", size: 16, color: Theme.color.accent)
                TextField("jump to a repo or run an action…", text: $query)
                    .textFieldStyle(.plain)
                    .font(VibeFont.mono(VibeFont.size.md))
                    .foregroundStyle(Theme.color.textBright)
                    .focused($focused)
                Kbd("esc")
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }

            if filtered.isEmpty {
                Text("no matches")
                    .font(VibeFont.mono(VibeFont.size.sm))
                    .foregroundStyle(Theme.color.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.space.x5)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered) { item in PaletteRow(item: item) }
                    }
                    .padding(Theme.space.x1_5)
                }
                .frame(maxHeight: OverlayLayout.listMax)
            }
        }
        .frame(width: OverlayLayout.paletteW)
        .background(Theme.color.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous)
            .strokeBorder(Theme.color.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 16)
        .onAppear { focused = true }
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    @State private var hover = false
    var body: some View {
        Button(action: item.run) {
            HStack(spacing: Theme.space.x2_5) {
                if item.kind == .repo, let h = item.health {
                    HealthDot(health: h, size: 8).frame(width: 14)
                } else {
                    VibeIcon(item.icon, size: 14, color: Theme.color.textMuted).frame(width: 14)
                }
                Text(item.label)
                    .font(VibeFont.mono(VibeFont.size.sm))
                    .foregroundStyle(Theme.color.textPrimary)
                    .lineLimit(1)
                if let sub = item.sub {
                    Text(sub)
                        .font(VibeFont.mono(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.space.x2)
                Text(item.kind == .repo ? "repo" : "action")
                    .font(VibeFont.mono(9, .medium))
                    .tracking(9 * VibeFont.track.label)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.color.textGhost)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? Theme.color.surfaceActive : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
