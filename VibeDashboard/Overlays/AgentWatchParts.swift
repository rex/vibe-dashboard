import SwiftUI

struct AgentWatchMarkdownBody: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        Text(attributed)
            .font(VibeFont.mono(fontSize))
            .foregroundStyle(Theme.color.textSecondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

struct WorkflowHopDivider: View {
    let phase: Int

    var body: some View {
        VStack(spacing: Theme.space.x2) {
            Rectangle().fill(Theme.color.border).frame(width: 1, height: 150)
            VibeIcon("corner-down-right", size: 16, color: Theme.color.accent)
            Text("hop\nphase \(phase)")
                .font(VibeFont.mono(VibeFont.size.xxs, .bold))
                .foregroundStyle(Theme.color.accent)
                .multilineTextAlignment(.center)
            Rectangle().fill(Theme.color.border).frame(width: 1, height: 150)
        }
        .frame(height: 430)
    }
}
