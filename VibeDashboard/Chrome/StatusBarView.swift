// StatusBarView.swift — the bottom status bar (24pt).

import SwiftUI

struct StatusBarView: View {
    @Environment(FleetStore.self) private var store

    var body: some View {
        let t = store.fleet.totals
        let agentCount = store.liveAgentSessionCount
        let s = store.fleet.scanner
        let b = store.fleet.appBuild
        let lastSwept = s.lastSweepAt.map { RelTime.ago($0, now: Date()) } ?? "—"
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                HealthDot(health: .ok, size: 6)
                // Real state — scans are manual; nothing "watches" continuously.
                Text("\(store.isScanning ? "scanning" : "idle") \(s.root)")
            }
            dot
            Text("\(t.repos) repos · \(t.workspaces) workspaces")
            dot
            // Real last-swept relative time (ages) + measured scan duration.
            Text("swept \(lastSwept) · \(s.swept)")
            if store.isScanning {
                ScanBar()
            }
            Spacer(minLength: Theme.space.x2)
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.color.accent).frame(width: 6, height: 6)
                    .shadow(color: ColorPalette.lime400.opacity(0.3), radius: 3)
                Text("vibe \(b.version) · ").foregroundStyle(Theme.color.textFaint)
                + Text(b.commit).foregroundStyle(Theme.color.info)
                + Text(" · \(b.date) · \(b.channel)").foregroundStyle(Theme.color.textFaint)
            }
            Spacer(minLength: Theme.space.x2)
            if agentCount > 0 {
                HStack(spacing: 6) {
                    AgentPulse(active: true, color: Theme.color.warn, size: 9)
                    Text("\(agentCount) agent\(agentCount > 1 ? "s" : "") working").foregroundStyle(Theme.color.warn)
                }
            } else {
                Text("no agents working").foregroundStyle(Theme.color.textFaint)
            }
            dot
            HStack(spacing: 4) {
                Text("compliance")
                Text("\(t.compliance)%").font(VibeFont.mono(VibeFont.size.xxs, .bold))
                    .foregroundStyle(t.compliance >= 95 ? Theme.color.ok : t.compliance >= 80 ? Theme.color.warn : Theme.color.danger)
            }
        }
        .font(VibeFont.mono(VibeFont.size.xxs))
        .foregroundStyle(Theme.color.textMuted)
        .lineLimit(1)
        .padding(.horizontal, Theme.space.x3)
        .frame(height: 24)
        .background(ColorPalette.ink1000)
        .overlay(alignment: .top) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }
    private var dot: some View { Text("·").foregroundStyle(Theme.color.textFaint) }
}

/// Scan-progress sweep, drawn in a Canvas at ~15fps inside a FIXED frame — the
/// old repeatForever offset animation was an animated GeometryEffect running at
/// display rate for the entire scan. Pure drawing; the layout system never hears
/// about it.
private struct ScanBar: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { ctx in
            Canvas { g, sz in
                let phase = CGFloat(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9)) / 0.9
                let w = sz.width * 0.3
                let x = (sz.width + w) * phase - w
                g.fill(Path(roundedRect: CGRect(x: x, y: 0, width: w, height: sz.height),
                            cornerRadius: sz.height / 2),
                       with: .color(Theme.color.accent))
            }
        }
        .frame(width: 64, height: 3)
        .background(Theme.color.surfaceActive)
        .clipShape(Capsule())
    }
}
