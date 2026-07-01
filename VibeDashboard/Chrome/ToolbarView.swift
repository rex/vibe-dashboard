// ToolbarView.swift — the unified toolbar (52pt) under the hidden title bar.

import SwiftUI

struct ToolbarView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    private let nav: [SegOption<AppView>] = [
        SegOption(value: .fleet, label: "Fleet", icon: "folder-tree"),
        SegOption(value: .agents, label: "Agents", icon: "radar"),
        SegOption(value: .findings, label: "Findings", icon: "triangle-alert"),
        SegOption(value: .skills, label: "Skills", icon: "blocks"),
        SegOption(value: .autopilot, label: "Autopilot", icon: "gauge-circle"),
    ]

    var body: some View {
        @Bindable var app = app
        let t = store.fleet.totals
        let repo = store.fleet.repo(app.selectedId)
        let inRepo = app.view == .repo && repo != nil
        let navBinding = Binding<AppView>(get: { app.view }, set: { app.goView($0) })

        HStack(spacing: Theme.space.x3) {
            Color.clear.frame(width: 72)   // native traffic lights

            HStack(spacing: 2) {
                toolIcon("chevron-left", enabled: inRepo) { app.back() }
                toolIcon("chevron-right", enabled: false) {}
            }

            if inRepo, let r = repo {
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.name).font(VibeFont.mono(VibeFont.size.md, .bold)).foregroundStyle(Theme.color.textBright).lineLimit(1)
                    Text(r.path).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted).lineLimit(1)
                }
                .frame(maxWidth: 220, alignment: .leading)
            }

            Spacer(minLength: Theme.space.x2)
            SegMac(selection: navBinding, options: navWithCounts(t))
            Spacer(minLength: Theme.space.x2)

            searchButton
            rescanButton
            HStack(spacing: 2) {
                toggle("panel-right", on: app.inspectorOpen) { app.toggleInspector() }
                toggle("panel-bottom", on: app.consoleOpen) { app.toggleConsole() }
            }
        }
        .padding(.horizontal, Theme.space.x3_5safe)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(ColorPalette.ink850)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }

    private func navWithCounts(_ t: FleetTotals) -> [SegOption<AppView>] {
        nav.map { o in
            var o = o
            if o.value == .agents { o.count = t.agentsActive > 0 ? t.agentsActive : nil }
            if o.value == .findings { o.count = t.surprises > 0 ? t.surprises : nil }
            return o
        }
    }

    private var searchButton: some View {
        Button { app.togglePalette() } label: {
            HStack(spacing: Theme.space.x2) {
                VibeIcon("search", size: 14, color: Theme.color.textMuted)
                Text("search fleet…").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textFaint)
                Spacer(minLength: 0)
                Kbd("⌘K")
            }
            .padding(.horizontal, 9)
            .frame(width: 200, height: 30)
            .background(Theme.color.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm).strokeBorder(Theme.color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var rescanButton: some View {
        Button { Task { await store.rescan() } } label: {
            HStack(spacing: 7) {
                VibeIcon("refresh-cw", size: 14, color: Theme.color.accent)
                    .rotationEffect(.degrees(store.isScanning ? 360 : 0))
                    .animation(store.isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isScanning)
                Text("Re-scan").font(VibeFont.mono(VibeFont.size.sm, .medium)).foregroundStyle(Theme.color.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Theme.color.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm).strokeBorder(Theme.color.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func toolIcon(_ name: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VibeIcon(name, size: 16, color: enabled ? Theme.color.textSecondary : Theme.color.textGhost)
                .frame(width: 26, height: 28)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
    private func toggle(_ name: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VibeIcon(name, size: 15, color: on ? Theme.color.accent : Theme.color.textMuted)
                .frame(width: 30, height: 30)
                .background(on ? Theme.color.surfaceActive : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm).strokeBorder(on ? Theme.color.borderStrong : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

extension Theme.space { static let x3_5safe: CGFloat = 14 }
