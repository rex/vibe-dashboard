// Buttons.swift — VibeButton (.vibe-btn) with variants + sizes.

import SwiftUI

enum VibeButtonVariant { case primary, secondary, ghost, danger, accentGhost }
enum VibeButtonSize { case sm, md, lg
    var padH: CGFloat { self == .sm ? 10 : self == .lg ? 20 : 14 }
    var padV: CGFloat { self == .sm ? 5 : self == .lg ? 11 : 8 }
    var font: CGFloat { self == .sm ? VibeFont.size.xs : self == .lg ? VibeFont.size.base : VibeFont.size.sm }
}

struct VibeButtonStyle: ButtonStyle {
    var variant: VibeButtonVariant = .secondary
    var size: VibeButtonSize = .md
    var block: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(VibeFont.mono(size.font, variant == .primary ? .bold : .medium))
            .tracking(size.font * 0.01)
            .foregroundStyle(fg)
            .padding(.horizontal, size.padH)
            .padding(.vertical, size.padV)
            .frame(maxWidth: block ? .infinity : nil)
            .background(bg(pressed))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .offset(y: pressed ? 0.5 : 0)
            .animation(Theme.motion.easeOut, value: pressed)
    }

    private var fg: Color {
        switch variant {
        case .primary: return Theme.color.textOnAccent
        case .secondary: return Theme.color.textPrimary
        case .ghost: return Theme.color.textSecondary
        case .danger: return Theme.color.danger
        case .accentGhost: return Theme.color.accent
        }
    }
    private func bg(_ pressed: Bool) -> Color {
        switch variant {
        case .primary: return pressed ? Theme.color.accentPress : Theme.color.accent
        case .secondary: return pressed ? Theme.color.surfaceActive : Theme.color.surfaceRaised
        case .ghost: return pressed ? Theme.color.surfaceRaised : .clear
        case .danger: return pressed ? Theme.color.dangerSurface : .clear
        case .accentGhost: return pressed ? Theme.color.okSurface : .clear
        }
    }
    private var border: Color {
        switch variant {
        case .primary: return Theme.color.accent
        case .secondary: return Theme.color.borderStrong
        case .ghost: return .clear
        case .danger: return Theme.color.dangerLine
        case .accentGhost: return Theme.color.okLine
        }
    }
}

/// Convenience button with an optional leading icon.
struct VibeButton: View {
    let title: String
    var icon: String? = nil
    var variant: VibeButtonVariant = .secondary
    var size: VibeButtonSize = .md
    var block: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space.x2) {
                if let icon { VibeIcon(icon, size: 14, color: nil) }
                Text(title)
            }
        }
        .buttonStyle(VibeButtonStyle(variant: variant, size: size, block: block))
    }
}
