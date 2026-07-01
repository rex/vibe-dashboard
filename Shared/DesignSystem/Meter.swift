// Meter.swift — Meter (coverage/compliance) + LimitBar (lines vs soft/hard).

import SwiftUI

/// Coverage / compliance bar with an optional threshold marker (.vibe-meter).
struct Meter: View {
    let label: String
    let value: Double            // 0…max
    var max: Double = 100
    var floor: Double? = nil     // threshold marker
    var tone: VibeTone = .ok
    var unit: String = "%"
    var valueText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).vibeMicroLabel(VibeFont.size.xxs)
                Spacer(minLength: Theme.space.x2)
                Text(valueText ?? "\(Int(value))\(unit)")
                    .font(VibeFont.mono(VibeFont.size.sm, .bold))
                    .foregroundStyle(Theme.color.textPrimary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.color.surfaceActive)
                    Capsule().fill(Theme.color.tone(tone))
                        .frame(width: max > 0 ? w * CGFloat(min(1, value / max)) : 0)
                        .shadow(color: tone == .ok ? ColorPalette.lime400.opacity(0.3) : .clear, radius: tone == .ok ? 5 : 0)
                    if let floor {
                        Rectangle().fill(Theme.color.textSecondary)
                            .frame(width: 2)
                            .offset(x: w * CGFloat(min(1, floor / max)) - 1)
                    }
                }
            }
            .frame(height: 8)
        }
    }
}

/// A limit bar (lines vs soft/hard), used for census + doc bloat.
struct LimitBar: View {
    let value: Double
    var soft: Double? = nil
    var hard: Double? = nil
    var unit: String = ""
    var maxOverride: Double? = nil

    private var tone: VibeTone {
        if let hard, value > hard { return .danger }
        if let soft, value > soft { return .warn }
        return .ok
    }
    private var cap: Double {
        if let m = maxOverride { return m }
        let h = hard ?? value
        return Swift.max(h * 1.15, value * 1.05, 1)
    }

    var body: some View {
        HStack(spacing: Theme.space.x2_5) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.color.surfaceActive)
                    Capsule().fill(Theme.color.tone(tone))
                        .frame(width: w * CGFloat(min(1, value / cap)))
                        .shadow(color: tone == .ok ? ColorPalette.lime400.opacity(0.3) : .clear, radius: tone == .ok ? 4 : 0)
                    ForEach([soft, hard].compactMap { $0 }, id: \.self) { mark in
                        Rectangle().fill(Theme.color.textFaint).frame(width: 1)
                            .offset(x: w * CGFloat(min(1, mark / cap)))
                    }
                }
            }
            .frame(height: 6)
            Text("\(Int(value).formatted())\(unit)")
                .font(VibeFont.mono(VibeFont.size.xs, .bold))
                .foregroundStyle(Theme.color.tone(tone))
                .frame(minWidth: 46, alignment: .trailing)
        }
    }
}
