// GateRow.swift — a single quality-gate result line (.vibe-gate).

import SwiftUI

struct GateRow: View {
    let name: String
    var command: String? = nil
    let status: GateStatus
    var detail: String? = nil
    var bare: Bool = false

    var body: some View {
        HStack(spacing: Theme.space.x3) {
            Image(systemName: status.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.color.tone(status.tone))
                .frame(width: 15, height: 15)
            Text(name)
                .font(VibeFont.mono(VibeFont.size.sm, .medium))
                .foregroundStyle(Theme.color.textPrimary)
            if let command {
                Text(command)
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.space.x2)
            if let detail {
                Text(detail)
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(status == .fail ? Theme.color.danger : Theme.color.textFaint)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, bare ? Theme.space.x1 : Theme.space.x3)
        .padding(.vertical, bare ? 9 : 10)
        .frame(minHeight: bare ? 0 : 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: bare ? 0 : Theme.radius.sm, style: .continuous))
        .overlay(alignment: bare ? .bottom : .center) {
            if bare {
                Rectangle().fill(Theme.color.borderSubtle).frame(height: 1)
            } else {
                RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                    .strokeBorder(status == .fail ? Theme.color.dangerLine : Theme.color.border, lineWidth: 1)
            }
        }
    }
    private var background: Color {
        if bare { return .clear }
        return status == .fail ? Theme.color.dangerSurfaceSoft : Theme.color.surfaceSunken
    }
}
