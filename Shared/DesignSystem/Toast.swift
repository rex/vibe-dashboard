// Toast.swift — transient notifications (.vibe-toast).

import SwiftUI

struct ToastData: Identifiable, Equatable {
    let id: Int
    let title: String
    let message: String
    var tone: VibeTone = .info
}

struct ToastView: View {
    let toast: ToastData
    var onDismiss: () -> Void

    private var icon: String {
        switch toast.tone {
        case .ok: return "check-circle"
        case .warn: return "triangle-alert"
        case .danger: return "x-circle"
        default: return "info"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space.x3) {
            VibeIcon(icon, size: 16, color: Theme.color.tone(toast.tone == .neutral ? .info : toast.tone))
            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title)
                    .font(VibeFont.mono(VibeFont.size.sm, .bold))
                    .foregroundStyle(Theme.color.textPrimary)
                if !toast.message.isEmpty {
                    Text(toast.message)
                        .font(VibeFont.mono(VibeFont.size.xs))
                        .foregroundStyle(Theme.color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) { VibeIcon("x", size: 14, color: Theme.color.textMuted) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(width: 360, alignment: .leading)
        .background(Theme.color.surfaceRaised)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.color.tone(toast.tone == .neutral ? .info : toast.tone)).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(Theme.color.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 15, y: 8)
    }
}

struct ToastStack: View {
    let toasts: [ToastData]
    var onDismiss: (Int) -> Void
    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.space.x2) {
            ForEach(toasts) { t in
                ToastView(toast: t) { onDismiss(t.id) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(Theme.space.x5)
        .animation(Theme.motion.easeOutBase, value: toasts)
    }
}
