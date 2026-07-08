// VibeDashboardApp.swift — @main entry.

import SwiftUI

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
                .task { await store.rescan(); store.startAgentMonitor() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { VibeCommands(app: app, store: store) }

        MenuBarExtra("Vibe", systemImage: "chevron.left.forwardslash.chevron.right") {
            MenuBarContent().environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
