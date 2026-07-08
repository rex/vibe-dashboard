// Badges.swift — Tag, StatusBadge, SeverityTag, Pill, GradeChip.

import SwiftUI

/// Neutral metadata pill (.vibe-tag) — stack=python, lifecycle=brownfield.
struct VibeTag: View {
    let text: String
    var keyText: String? = nil
    var tone: VibeTone = .neutral
    var uppercase: Bool = false
    var icon: String? = nil
    var dot: Bool = false

    var body: some View {
        HStack(spacing: Theme.space.x1_5) {
            if dot { Circle().fill(fg).frame(width: 6, height: 6) }
            if let icon { VibeIcon(icon, size: 11, color: fg) }
            if let keyText {
                Text(keyText).foregroundStyle(Theme.color.textMuted)
                Text("=").foregroundStyle(Theme.color.textGhost)
            }
            Text(text).foregroundStyle(fg)
        }
        .font(VibeFont.mono(uppercase ? VibeFont.size.xxs : VibeFont.size.xs, .medium))
        .tracking(uppercase ? VibeFont.size.xxs * VibeFont.track.label : 0)
        .textCase(uppercase ? .uppercase : nil)
        .lineLimit(1)
        .padding(.horizontal, Theme.space.x2)
        .padding(.vertical, Theme.space.x1)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
            .strokeBorder(line, lineWidth: 1))
    }
    private var fg: Color { tone == .neutral ? Theme.color.textSecondary : Theme.color.tone(tone) }
    private var bg: Color {
        switch tone {
        case .neutral: return Theme.color.surface2
        case .ok: return Theme.color.okSurfaceSoft
        case .info: return Theme.color.infoSurfaceSoft
        case .policy: return Theme.color.violetSurface
        default: return Theme.color.toneSurface(tone)
        }
    }
    private var line: Color { tone == .neutral ? Theme.color.border : Theme.color.toneLine(tone) }
}

/// The core signal element (.vibe-status).
struct StatusBadge: View {
    let text: String
    var tone: VibeTone = .neutral
    var small: Bool = false
    var live: Bool = false
    var solid: Bool = false
    var showDot: Bool = true

    var body: some View {
        HStack(spacing: small ? 5 : 7) {
            if showDot {
                Circle().fill(dotColor)
                    .frame(width: small ? 6 : 7, height: small ? 6 : 7)
                    .shadow(color: live ? ColorPalette.lime400.opacity(0.5) : .clear, radius: live ? 4 : 0)
            }
            Text(text).tracking(0.02 * fontSize)
        }
        .font(VibeFont.mono(fontSize, solid ? .bold : .medium))
        .foregroundStyle(fg)
        .lineLimit(1)
        .padding(.leading, small ? 6 : 9)
        .padding(.trailing, small ? 7 : 10)
        .padding(.vertical, small ? 3 : 5)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
            .strokeBorder(line, lineWidth: 1))
    }
    private var fontSize: CGFloat { small ? VibeFont.size.xxs : VibeFont.size.xs }
    private var fg: Color {
        if solid { return tone == .danger ? ColorPalette.redInk : ColorPalette.limeInk }
        return tone == .neutral ? Theme.color.textSecondary : Theme.color.tone(tone)
    }
    private var dotColor: Color { solid ? fg : (tone == .neutral ? Theme.color.textSecondary : Theme.color.tone(tone)) }
    private var bg: Color { solid ? Theme.color.tone(tone) : (tone == .neutral ? Theme.color.surface2 : Theme.color.toneSurface(tone)) }
    private var line: Color { solid ? Theme.color.tone(tone) : (tone == .neutral ? Theme.color.border : Theme.color.toneLine(tone)) }
}

/// HIGH / MED / LOW (.vibe-sev).
struct SeverityTag: View {
    let severity: Severity
    var body: some View {
        Text(severity.label)
            .font(VibeFont.mono(VibeFont.size.xxs, .bold))
            .tracking(VibeFont.size.xxs * VibeFont.track.label)
            .foregroundStyle(severity == .low ? Theme.color.textMuted : Theme.color.tone(severity.tone))
            .padding(.horizontal, Theme.space.x1_5)
            .padding(.vertical, 3)
            .background(severity == .low ? Theme.color.surface2 : Theme.color.toneSurface(severity.tone))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous)
                .strokeBorder(severity == .low ? Theme.color.border : Theme.color.toneLine(severity.tone), lineWidth: 1))
    }
}

/// Tiny pill (mac-parts Pill).
struct Pill: View {
    let text: String
    var tone: VibeTone = .neutral
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let icon { VibeIcon(icon, size: 11, color: fg) }
            Text(text).foregroundStyle(fg)
        }
        .font(VibeFont.mono(VibeFont.size.xxs, .regular))
        .lineLimit(1)
        .padding(.horizontal, Theme.space.x1_5)
        .padding(.vertical, Theme.space.x0_5)
        .background(tone == .neutral ? Theme.color.surface2 : Theme.color.toneSurface(tone))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous)
            .strokeBorder(tone == .neutral ? Theme.color.border : Theme.color.toneLine(tone), lineWidth: 1))
    }
    private var fg: Color { tone == .neutral ? Theme.color.textSecondary : Theme.color.tone(tone) }
}

/// Grade chip A–F for audited objects (brand GradeChip).
struct GradeChip: View {
    let grade: String
    var size: CGFloat = 24
    private var tone: VibeTone {
        switch grade { case "A", "B": return .ok; case "C": return .warn
        case "D", "F": return .danger; default: return .neutral }
    }
    var body: some View {
        Text(grade)
            .font(VibeFont.mono(size * 0.5, .black))
            .foregroundStyle(tone == .neutral ? Theme.color.textMuted : Theme.color.tone(tone))
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, size * 0.18)
            .background(tone == .neutral ? Theme.color.surface2 : Theme.color.toneSurface(tone))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                .strokeBorder(tone == .neutral ? Theme.color.border : Theme.color.toneLine(tone), lineWidth: 1))
    }
}

/// Deprecated no-op. The live/danger signal is carried by the dot's glow, not a
/// pulse loop (a continuous per-dot animation across dozens of rows pegs the
/// main thread). The `StatusBadge` call site is gone; this type survives only
/// because `HealthDot` (Shared/DesignSystem/Parts.swift) still references it.
/// Delete this type and that call site together to finish the removal.
struct PulseModifier: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View { content }
}
