// OverlaySheets.swift — the shared sheet shell + sub-elements used by every
// confirm-gated write sheet. The individual sheets live in their own files
// (CommitSheet / PruneSheet / ReconcileSheet / WaiverSheet, plus
// OverlaySheetsMore + OverlayBackfill). Module-internal so OverlayHost and each
// sheet file can reach them.

import SwiftUI

// MARK: - Sheet shell

/// The chrome shared by every confirm-gated write sheet: icon-title header,
/// scrollable body, footer bar with Cancel + primary confirm.
struct SheetShell<Body: View>: View {
    @Environment(AppState.self) private var app
    let title: String
    let icon: String
    var width: CGFloat = OverlayLayout.sheetW
    var confirm: String
    var confirmIcon: String
    var confirmVariant: VibeButtonVariant = .primary
    /// When true the primary confirm is blocked + dimmed (e.g. an empty commit
    /// message, or nothing to commit) — the sheet can't fire a no-op write.
    var confirmDisabled: Bool = false
    var onConfirm: () -> Void
    @ViewBuilder var content: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.space.x2_5) {
                VibeIcon(icon, size: 16, color: Theme.color.accent)
                Text(title)
                    .font(VibeFont.mono(VibeFont.size.md, .bold))
                    .foregroundStyle(Theme.color.textBright)
                    .lineLimit(1)
                Spacer(minLength: Theme.space.x2)
                Button { app.closeSheet() } label: {
                    VibeIcon("x", size: 15, color: Theme.color.textMuted)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.color.surface2)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }

            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.space.x4)
            }
            .frame(maxHeight: OverlayLayout.bodyMax)

            HStack(spacing: Theme.space.x2_5) {
                Spacer()
                VibeButton(title: "Cancel", variant: .ghost) { app.closeSheet() }
                VibeButton(title: confirm, icon: confirmIcon, variant: confirmVariant, action: onConfirm)
                    .disabled(confirmDisabled)
                    .opacity(confirmDisabled ? 0.45 : 1)
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.vertical, Theme.space.x3)
            .frame(maxWidth: .infinity)
            .background(Theme.color.surface2)
            .overlay(alignment: .top) { Rectangle().fill(Theme.color.border).frame(height: 1) }
        }
        .frame(width: width)
        .background(Theme.color.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous)
            .strokeBorder(Theme.color.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 16)
    }
}

// MARK: - Shared sheet sub-elements

struct SheetProse: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VibeFont.mono(VibeFont.size.sm))
            .foregroundStyle(Theme.color.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A bordered file-list card with an UPPERCASE section caption + rows.
struct FileCard<Rows: View>: View {
    let caption: String
    @ViewBuilder var rows: () -> Rows
    var body: some View {
        VStack(spacing: 0) {
            Text(caption)
                .vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, Theme.space.x2)
                .background(Theme.color.surface2)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
            rows()
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(Theme.color.border, lineWidth: 1))
    }
}

/// One file line inside a `FileCard`.
struct FileRow<Right: View>: View {
    let icon: String
    let path: String
    var tone: VibeTone = .neutral
    @ViewBuilder var right: () -> Right
    var body: some View {
        HStack(spacing: Theme.space.x2_5) {
            VibeIcon(icon, size: 13, color: tone == .neutral ? Theme.color.textMuted : Theme.color.tone(tone))
            Text(path)
                .font(VibeFont.mono(VibeFont.size.sm))
                .foregroundStyle(Theme.color.textPrimary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            right()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, Theme.space.x2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}
