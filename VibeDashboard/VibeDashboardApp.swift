// VibeDashboardApp.swift — @main entry.

import SwiftUI

@main
struct VibeDashboardApp: App {
    @State private var store: FleetStore

    init() {
        FontRegistration.registerBundledFonts()
        _store = State(initialValue: FleetStore())
    }

    var body: some Scene {
        WindowGroup {
            RootScaffold()
                .environment(store)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
                .task { await store.rescan() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

/// Temporary validation root — replaced by the Mac chrome next.
private struct RootScaffold: View {
    @Environment(FleetStore.self) private var store
    var body: some View {
        ZStack {
            Theme.color.bgVoid.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.space.x5) {
                HStack {
                    VibeLogo(size: 40, sub: "mission control", mark: true)
                    Spacer()
                    if store.isScanning { ProgressView().controlSize(.small) }
                    Text("\(store.fleet.totals.repos) repos · \(store.fleet.totals.compliance)% in policy")
                        .font(VibeFont.mono(VibeFont.size.sm, .medium))
                        .foregroundStyle(Theme.color.textSecondary)
                }
                ScrollView {
                    VStack(spacing: Theme.space.x1) {
                        ForEach(store.fleet.tree) { node in
                            if let r = store.fleet.byId[node.repoId] {
                                HStack(spacing: Theme.space.x3) {
                                    Color.clear.frame(width: CGFloat(node.depth) * 18)
                                    LangGlyph(stack: r.stack, size: 18, health: r.health)
                                    Text(r.name).font(VibeFont.mono(VibeFont.size.sm, .medium)).foregroundStyle(Theme.color.textPrimary)
                                    if r.agentActive { AgentPulse(active: true, size: 12) }
                                    Spacer()
                                    if !r.isWorkspace { StatusBadge(text: "\(r.compliance)%", tone: r.health.tone, small: true) }
                                    HealthDot(health: r.health)
                                }
                                .padding(.horizontal, Theme.space.x3)
                                .frame(height: 32)
                            }
                        }
                    }
                    .padding(Theme.space.x3)
                    .background(Theme.color.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius.md).strokeBorder(Theme.color.border, lineWidth: 1))
                }
            }
            .padding(Theme.space.x8)
        }
    }
}
