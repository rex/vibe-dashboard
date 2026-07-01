// MenuCommands.swift — native menu bar (Commands) + menu-bar-extra popover.

import SwiftUI

struct VibeCommands: Commands {
    var app: AppState
    var store: FleetStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Vibe") { app.openSheet(.about) }
        }
        CommandGroup(after: .newItem) {
            Button("Re-scan ~/Code") { Task { await store.rescan() } }.keyboardShortcut("r")
            Button("Change scan root…") { pickRoot() }.keyboardShortcut("o")
        }
        CommandMenu("Repo") {
            let r = store.fleet.repo(app.selectedId)
            Button("Reveal in Finder") { reveal(r) }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(r == nil)
            Button("Open in editor") { openEditor(r) }.keyboardShortcut("e").disabled(r == nil)
            Divider()
            Button("Reconcile with skeleton…") { app.openSheet(.reconcile) }.disabled(r == nil)
            Button("Commit & push…") { app.openSheet(.commit) }.disabled(r?.worktree.clean ?? true)
        }
        CommandMenu("Agent") {
            Button("Open activity console") { app.openConsole(.activity) }.keyboardShortcut("j")
            Button("Review running agents") { app.goView(.agents) }
        }
        CommandGroup(after: .toolbar) {
            Button("Toggle inspector") { app.toggleInspector() }.keyboardShortcut("0", modifiers: [.command, .option])
            Button("Toggle console") { app.toggleConsole() }.keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Command palette…") { app.togglePalette() }.keyboardShortcut("k")
            Divider()
            ForEach(AppView.allCases.filter { $0 != .repo }, id: \.self) { v in
                Button(v.rawValue.capitalized) { app.goView(v) }
            }
        }
    }

    private func reveal(_ r: Repo?) {
        guard let r else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: (r.absolutePath as NSString).expandingTildeInPath)
    }
    private func openEditor(_ r: Repo?) {
        guard let r else { return }
        let p = (r.absolutePath as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
    }
    private func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: ((store.roots.first ?? "~/Code") as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            store.setRoots(panel.urls.map(\.path))
            Task { await store.rescan() }
        }
    }
}

/// The menu-bar-extra fleet popover content.
struct MenuBarContent: View {
    @Environment(FleetStore.self) private var store
    var body: some View {
        let t = store.fleet.totals
        VStack(alignment: .leading, spacing: Theme.space.x2) {
            HStack {
                Wordmark(size: 15)
                Spacer()
                Text(store.fleet.scanner.root).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
            }
            Divider()
            HStack(spacing: 4) {
                Text("\(t.healthy) in policy").foregroundStyle(Theme.color.ok)
                Text("·").foregroundStyle(Theme.color.textFaint)
                Text("\(t.warn) drift").foregroundStyle(Theme.color.warn)
                Text("·").foregroundStyle(Theme.color.textFaint)
                Text("\(t.danger) surprises").foregroundStyle(Theme.color.danger)
            }
            .font(VibeFont.mono(VibeFont.size.xs))
            Text("agents working now · \(t.agentsActive)").vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textFaint)
            if store.fleet.sessions.isEmpty {
                Text("none — fleet is quiet").font(VibeFont.mono(VibeFont.size.xs)).foregroundStyle(Theme.color.textMuted)
            } else {
                ForEach(store.fleet.sessions) { s in
                    HStack(spacing: Theme.space.x2) {
                        AgentPulse(active: true, color: s.health == .danger ? Theme.color.danger : Theme.color.warn, size: 11)
                        Text(s.name).font(VibeFont.mono(VibeFont.size.xs)).foregroundStyle(Theme.color.textPrimary)
                        Spacer()
                        Text("\(s.agent?.tool ?? "agent") · \(s.agent?.elapsed ?? "—")").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
                    }
                }
            }
            Divider()
            Button("Re-scan") { Task { await store.rescan() } }
        }
        .padding(Theme.space.x3)
        .frame(width: 320)
    }
}
