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

/// Live-agent equalizer — 3 bars, drawn in a Canvas on a slow periodic timeline.
///
/// THE RULE (learned three times over): this indicator must never touch the
/// layout system while animating. Animating bar HEIGHT re-ran layout per frame;
/// even an ANIMATED scaleEffect (GeometryEffect) dirtied its node at display
/// rate and made every ancestor re-run sizeThatFits (sampled: 22k layout
/// frames/5s across all views). A Canvas inside a FIXED frame swaps pure
/// drawing on each 0.45s tick — zero layout, zero .animation, a few µs of fill.
struct AgentPulse: View {
    var active: Bool = true
    var color: Color = Theme.color.warn
    var size: CGFloat = 13

    private static let step: TimeInterval = 0.45
    private static let patterns: [[CGFloat]] = [
        [0.50, 1.00, 0.68], [0.85, 0.55, 0.95], [0.60, 0.90, 0.45], [1.00, 0.65, 0.80],
    ]
    private var barsWidth: CGFloat { 3 * 2.5 + 2 * 2 }

    var body: some View {
        Group {
            if active {
                TimelineView(.periodic(from: .now, by: Self.step)) { ctx in
                    bars(tick: Int(ctx.date.timeIntervalSinceReferenceDate / Self.step))
                }
            } else {
                bars(tick: 0).opacity(0.4)
            }
        }
        .frame(width: barsWidth, height: size)   // layout size is CONSTANT, forever
    }

    private func bars(tick: Int) -> some View {
        let pattern = Self.patterns[((tick % Self.patterns.count) + Self.patterns.count) % Self.patterns.count]
        return Canvas { g, sz in
            for i in 0..<3 {
                let h = size * pattern[i]
                let rect = CGRect(x: CGFloat(i) * 4.5, y: (sz.height - h) / 2,
                                  width: 2.5, height: h)
                g.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
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
    // 26pt + tight padding: nine tiles fit one row at normal window widths — the
    // old 38pt/18pt tiles forced the window comically wide for the same numbers.
    var numberSize: CGFloat = 26
    var help: String? = nil
    var action: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        VStack(alignment: .center, spacing: Theme.space.x1_5) {
            HStack(spacing: 6) {
                if let icon { VibeIcon(icon, size: 11, color: Theme.color.textMuted) }
                Text(label).vibeMicroLabel(9)
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
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.space.x3)
        .padding(.vertical, Theme.space.x2_5)
        .background(hover && action != nil ? Theme.color.surfaceRaised : Theme.color.surface1)
        .contentShape(Rectangle())
        .help(help ?? label)
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
