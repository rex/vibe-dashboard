// Updater.swift — Sparkle auto-update wiring.
//
// Auto-check + prompt is Sparkle's default and the chosen UX: it checks on a
// schedule in the background and presents release notes + an Install button when
// a newer build appears on the appcast. The `SPUStandardUpdaterController` itself
// is owned by the App (lives for the whole process); this file is just the
// "Check for Updates…" menu item and the small view model that disables it while
// a check is already running.
//
// Updates are gated twice: an EdDSA signature over the archive (SUPublicEDKey)
// AND the app's Developer ID + notarization — Sparkle refuses anything that
// fails either, so a compromised feed can't ship a malicious build.

import SwiftUI
import Combine
import Sparkle

/// Publishes whether a manual check is currently allowed, so the menu item can
/// disable itself while a check is in flight (Sparkle's `canCheckForUpdates` is
/// KVO-compliant; bridge it to `@Published` for SwiftUI).
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }
}

/// The "Check for Updates…" menu item. The intermediate view is what Sparkle's
/// docs prescribe so the disabled state resolves correctly in a `Commands` menu.
struct CheckForUpdatesView: View {
    @ObservedObject private var model: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.model = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!model.canCheckForUpdates)
    }
}
