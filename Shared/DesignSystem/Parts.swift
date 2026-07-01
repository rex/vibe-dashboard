// Parts.swift — HealthDot, AgentPulse, Disclosure, MetaRow, StatTile,
// TrafficLights, CursorBlink, Empty.

import SwiftUI

/// The blinking brand cursor block `▮` (respects reduce-motion).
struct CursorBlink: View {
    var width: CGFloat
    var height: CGFloat
    var color: Color = Theme.color.accent
    var glow: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            let visible = reduceMotion ? true : (Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0)
            Rectangle()
                .fill(color)
                .frame(width: width, height: height)
                .opacity(visible ? 1 : 0)
                .shadow(color: glow ? ColorPalette.lime400.opacity(0.3) : .clear, radius: glow ? 4 : 0)
        }
    }
}

/// A status dot. Pulses only for a violation (danger); glows when ok.
struct HealthDot: View {
    var health: Health = .ok
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(Theme.color.health(health))
            .frame(width: size, height: size)
            .modifier(PulseModifier(active: health == .danger))
            .shadow(color: glowColor, radius: health == .ok ? 4 : (health == .danger ? 5 : 0))
    }
    private var glowColor: Color {
        switch health {
        case .ok: return ColorPalette.lime400.opacity(0.3)
        case .danger: return ColorPalette.red400.opacity(0.6)
        default: return .clear
        }
    }
}

/// Live agent equalizer — 3 bars, only animates when active.
struct AgentPulse: View {
    var active: Bool = true
    var color: Color = Theme.color.warn
    var size: CGFloat = 13
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !active || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = active && !reduceMotion ? (sin(t * 3.2 + Double(i) * 1.1) * 0.325 + 0.675) : 0.4
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2.5, height: size * CGFloat(phase))
                        .opacity(active ? 1 : 0.4)
                }
            }
            .frame(height: size)
        }
    }
}

/// Disclosure triangle.
struct Disclosure: View {
    var open: Bool
    var body: some View {
        VibeIcon("chevron-right", size: 12, color: Theme.color.textMuted)
            .rotationEffect(.degrees(open ? 90 : 0))
            .animation(Theme.motion.easeOut, value: open)
            .frame(width: 14, height: 14)
    }
}

/// A label : value row with a bottom hairline.
struct MetaRow<Value: View>: View {
    let key: String
    @ViewBuilder var value: () -> Value
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(key).vibeMicroLabel(VibeFont.size.xxs).lineLimit(1)
            Spacer(minLength: Theme.space.x2)
            value()
                .font(VibeFont.mono(VibeFont.size.sm))
                .foregroundStyle(Theme.color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

/// A big metric tile for the fleet stat strip.
struct StatTile: View {
    let value: String
    var unit: String? = nil
    let label: String
    var tone: VibeTone = .neutral
    var icon: String? = nil
    var numberSize: CGFloat = 38
    var action: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x2) {
            HStack(spacing: 7) {
                if let icon { VibeIcon(icon, size: 12, color: Theme.color.textMuted) }
                Text(label).vibeMicroLabel(VibeFont.size.xxs)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(VibeFont.mono(numberSize, .black))
                    .tracking(numberSize * VibeFont.track.tight)
                    .foregroundStyle(tone == .neutral ? Theme.color.textBright : Theme.color.tone(tone))
                    .shadow(color: tone == .ok ? ColorPalette.lime400.opacity(0.45) : .clear, radius: tone == .ok ? 8 : 0)
                if let unit {
                    Text(unit).font(VibeFont.mono(numberSize * 0.5, .medium)).foregroundStyle(Theme.color.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, Theme.space.x4)
        .background(hover && action != nil ? Theme.color.surfaceRaised : Theme.color.surface1)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { action?() }
    }
}

/// macOS window traffic lights.
struct TrafficLights: View {
    var onClose: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 8) {
            dot(Color(hex: 0xFF5F57)).onTapGesture { onClose?() }
            dot(Color(hex: 0xFEBC2E))
            dot(Color(hex: 0x28C840))
        }
    }
    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
    }
}

/// Empty / all-clear state.
struct EmptyState: View {
    var icon: String = "check"
    var tone: VibeTone = .ok
    let text: String
    var body: some View {
        VStack(spacing: Theme.space.x2_5) {
            VibeIcon(icon, size: 22, color: Theme.color.tone(tone))
            Text(text).font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, Theme.space.x5)
    }
}
