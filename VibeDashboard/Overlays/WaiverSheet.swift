// WaiverSheet.swift — record a time-boxed waiver against an open finding. Split
// out of OverlaySheets.swift; module-internal, rendered by OverlayHost via the
// shared SheetShell.

import SwiftUI

struct WaiverSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    let repo: Repo?
    @State private var reason = ""
    @State private var expiry = "30d"

    private var findings: [Finding] { repo?.surprises ?? store.fleet.findings }

    var body: some View {
        SheetShell(title: "Record a waiver", icon: "shield-check",
                   width: OverlayLayout.sheetW, confirm: "Record waiver", confirmIcon: "shield-check") {
            app.closeSheet()
            app.toast("waiver recorded", "expires in \(expiry) · logged to VIBE.yaml waivers[]", .info)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                if let f = findings.first {
                    fieldLabel("finding")
                    HStack(spacing: Theme.space.x2) {
                        SeverityTag(severity: f.severity)
                        Text(f.what)
                            .font(VibeFont.mono(VibeFont.size.sm))
                            .foregroundStyle(Theme.color.textPrimary)
                            .lineLimit(1)
                    }
                } else {
                    SheetProse(text: "no open findings to waive.")
                }
                fieldLabel("reason — why this is acceptable for now")
                VibeTextField(placeholder: "e.g. legacy module, scheduled for the v2 rewrite…", text: $reason)
                fieldLabel("expires")
                HStack(spacing: Theme.space.x1_5) {
                    ForEach(["7d", "30d", "90d", "never"], id: \.self) { opt in
                        Button { expiry = opt } label: {
                            Text(opt)
                                .font(VibeFont.mono(VibeFont.size.xs, .medium))
                                .foregroundStyle(expiry == opt ? Theme.color.textOnAccent : Theme.color.textSecondary)
                                .padding(.horizontal, Theme.space.x2_5).padding(.vertical, Theme.space.x1_5)
                                .background(expiry == opt ? Theme.color.accent : Theme.color.surfaceSunken)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                                    .strokeBorder(expiry == opt ? Theme.color.accent : Theme.color.border, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
    }
}
