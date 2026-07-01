// Tabs.swift — VibeTabs (underlined) + SegMac (segmented control).

import SwiftUI

struct SegOption<T: Hashable>: Identifiable {
    let value: T
    let label: String
    var icon: String? = nil
    var count: Int? = nil
    var id: T { value }
}

/// macOS segmented control (toolbar + sub-nav).
struct SegMac<T: Hashable>: View {
    @Binding var selection: T
    let options: [SegOption<T>]
    var small: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { o in
                let on = o.value == selection
                Button { selection = o.value } label: {
                    HStack(spacing: Theme.space.x1_5) {
                        if let icon = o.icon {
                            VibeIcon(icon, size: small ? 12 : 13, color: on ? Theme.color.accent : Theme.color.textFaint)
                        }
                        Text(o.label)
                        if let count = o.count {
                            Text("\(count)")
                                .font(VibeFont.mono((small ? VibeFont.size.xxs : VibeFont.size.xs) * 0.85, .bold))
                                .foregroundStyle(on ? Theme.color.textFaint : Theme.color.textGhost)
                        }
                    }
                    .font(VibeFont.mono(small ? VibeFont.size.xxs : VibeFont.size.xs, on ? .bold : .medium))
                    .foregroundStyle(on ? Theme.color.textPrimary : Theme.color.textMuted)
                    .padding(.horizontal, small ? 9 : 13)
                    .padding(.vertical, small ? 4 : 5)
                    .background(on ? Theme.color.surfaceRaised : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous)
                        .strokeBorder(on ? Theme.color.borderStrong : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.color.bgVoid)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
            .strokeBorder(Theme.color.border, lineWidth: 1))
    }
}

/// Underlined tab bar (.vibe-tabs) for repo detail.
struct VibeTabs<T: Hashable>: View {
    @Binding var selection: T
    let options: [SegOption<T>]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { o in
                let on = o.value == selection
                Button { selection = o.value } label: {
                    HStack(spacing: Theme.space.x1_5) {
                        if let icon = o.icon { VibeIcon(icon, size: 13, color: on ? Theme.color.textPrimary : Theme.color.textMuted) }
                        Text(o.label)
                        if let count = o.count {
                            Text("\(count)").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                        }
                    }
                    .font(VibeFont.mono(VibeFont.size.sm, .medium))
                    .foregroundStyle(on ? Theme.color.textPrimary : Theme.color.textMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Theme.space.x2_5)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(on ? Theme.color.accent : .clear)
                            .frame(height: 2)
                            .shadow(color: on ? ColorPalette.lime400.opacity(0.3) : .clear, radius: 4)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }
}
