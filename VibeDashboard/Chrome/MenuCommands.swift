// MenuCommands.swift — native menu bar (Commands) + menu-bar-extra popover.

import SwiftUI
import Sparkle

struct VibeCommands: Commands {
    var app: AppState
    var store: FleetStore
    var updater: SPUUpdater

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Vibe") { app.openSheet(.about) }
            CheckForUpdatesView(updater: updater)
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
        let dir = URL(fileURLWithPath: (r.absolutePath as NSString).expandingTildeInPath,
                      isDirectory: true)
        let installed: (EditorApp) -> Bool = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) != nil
        }
        guard let editor = EditorApp.pick(from: EditorApp.priority, installed: installed),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleId)
        else {
            // No known editor installed — degrade to the OS default (Finder)
            // rather than pretending an editor opened.
            NSWorkspace.shared.open(dir)
            return
        }
        NSWorkspace.shared.open([dir], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
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

/// A code editor the "Open in editor" command can launch, in priority order.
/// Installation is detected by bundle identifier via `NSWorkspace`; the
/// *selection* (`pick`) is pure so it is unit-tested without the workspace.
enum EditorApp: String, CaseIterable, Sendable {
    case vscode, cursor, xcode

    /// A general-purpose editor first, then Swift-native Xcode as the fallback.
    static let priority: [EditorApp] = [.vscode, .cursor, .xcode]

    var bundleId: String {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .xcode:  return "com.apple.dt.Xcode"
        }
    }

    /// The first candidate the `installed` predicate accepts, or nil if none are.
    static func pick(from candidates: [EditorApp], installed: (EditorApp) -> Bool) -> EditorApp? {
        candidates.first(where: installed)
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
                        AgentPulse(active: true, color: s.repo.health == .danger ? Theme.color.danger : Theme.color.warn, size: 11)
                        Text(s.repo.name).font(VibeFont.mono(VibeFont.size.xs)).foregroundStyle(Theme.color.textPrimary)
                        Spacer()
                        Text("\(s.agent.tool ?? "agent") · \(s.agent.elapsed ?? "—")")
                            .font(VibeFont.mono(VibeFont.size.xxs))
                            .foregroundStyle(Theme.color.textMuted)
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
