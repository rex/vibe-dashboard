// VibeDashboardApp.swift — @main entry.

import SwiftUI
import AppKit
import Sparkle

@main
struct VibeDashboardApp: App {
    @State private var store: FleetStore
    @State private var app: AppState
    // Owned for the app's lifetime. Start the scheduled background checks only
    // when there's a real signing key AND we're not the unit-test host — a live
    // updater in the headless test host blocks the runner (first-run prompt / XPC
    // startup) and times it out. The "Check for Updates…" item stays present
    // either way; it's simply disabled until the updater is running.
    private let updater: SPUStandardUpdaterController

    init() {
        FontRegistration.registerBundledFonts()
        _store = State(initialValue: FleetStore())
        _app = State(initialValue: AppState())
        updater = SPUStandardUpdaterController(
            startingUpdater: Self.shouldStartUpdater,
            updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// Auto-updates run only in a real, shipped app: not under XCTest/Swift Testing,
    /// and not until `SUPublicEDKey` is a real key (the repo ships a placeholder).
    private static var shouldStartUpdater: Bool {
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let keyConfigured = !key.isEmpty && !key.hasPrefix("REPLACE_")
        return !underTest && keyConfigured
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
                // what kept the monitor from ever starting when a scan hung. FSEvents
                // makes agent cards + per-repo re-scores push-based; the 30s poll
                // stays as the safety net.
                .task {
                    store.startAgentMonitor()
                    store.startFsMonitors()
                    await store.rescan()
                }
                // Cmd-tabbing back in refreshes the live-agent list immediately —
                // the 30s cadence covers the background; activation covers "I'm looking".
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await store.refreshAgents() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { VibeCommands(app: app, store: store, updater: updater.updater) }

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
