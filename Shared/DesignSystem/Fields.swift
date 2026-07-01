// Fields.swift — VibeTextField, VibeSwitch, Kbd.

import SwiftUI

/// Styled text field (.vibe-input) with an optional leading icon.
struct VibeTextField: View {
    var placeholder: String
    @Binding var text: String
    var leadingIcon: String? = nil
    var invalid: Bool = false
    var onSubmit: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.space.x2) {
            if let leadingIcon { VibeIcon(leadingIcon, size: 14, color: Theme.color.textMuted) }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(VibeFont.mono(VibeFont.size.sm))
                .foregroundStyle(Theme.color.textPrimary)
                .focused($focused)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.color.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
            .strokeBorder(borderColor, lineWidth: focused ? 1.5 : 1))
    }
    private var borderColor: Color {
        if invalid { return Theme.color.danger }
        return focused ? Theme.color.accent : Theme.color.border
    }
}

/// A toggle switch (.vibe-switch).
struct VibeSwitch: View {
    @Binding var isOn: Bool
    var disabled: Bool = false
    var body: some View {
        Button { if !disabled { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.color.accent : Theme.color.surfaceActive)
                    .overlay(Capsule().strokeBorder(isOn ? Theme.color.accent : Theme.color.borderStrong, lineWidth: 1))
                Circle()
                    .fill(isOn ? Theme.color.textOnAccent : ColorPalette.fg300)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .animation(Theme.motion.easeOut, value: isOn)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.5 : 1)
    }
}

/// A keycap for ⌘K hints / shortcuts.
struct Kbd: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(VibeFont.mono(VibeFont.size.xxs))
            .foregroundStyle(Theme.color.textFaint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.color.bgVoid)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous)
                .strokeBorder(Theme.color.borderStrong, lineWidth: 1))
    }
}
