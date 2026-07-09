// VibeDashboardApp.swift — @main entry.

import SwiftUI
import AppKit

@main
struct VibeDashboardApp: App {
    @State private var store: FleetStore
    @State private var app: AppState

    init() {
        FontRegistration.registerBundledFonts()
        _store = State(initialValue: FleetStore())
        _app = State(initialValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environment(store)
                .environment(app)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
                // Monitor FIRST, then the fleet scan: agent detection must never be
                // held hostage by a slow (or wedged) rescan — that ordering is exactly
                // what kept the monitor from ever starting when a scan hung.
                .task { store.startAgentMonitor(); await store.rescan() }
                // Cmd-tabbing back in refreshes the live-agent list immediately —
                // the 30s cadence covers the background; activation covers "I'm looking".
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await store.refreshAgents() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { VibeCommands(app: app, store: store) }

        // Agent transcript watching gets a real, resizable window per target —
        // a monitoring surface, not a modal sheet.
        WindowGroup(id: "agent-watch", for: AgentWatchTarget.self) { $target in
            if let target {
                AgentWatchWindow(target: target)
                    .environment(store)
                    .environment(app)
                    .frame(minWidth: 900, minHeight: 620)
                    .preferredColorScheme(.dark)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1520, height: 960)

        MenuBarExtra("Vibe", systemImage: "chevron.left.forwardslash.chevron.right") {
            MenuBarContent().environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
