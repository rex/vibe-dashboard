// AgentWatchSheet.swift - focused transcript/workflow monitor for a selected live agent.

import SwiftUI

struct AgentWatchSheet: View {
    @Environment(AppState.self) private var app
    let target: AgentWatchTarget
    @State private var panes: [TranscriptPane] = []
    @State private var expanded: Set<String> = []
    @State private var fontSize: CGFloat = 12

    var body: some View {
        SheetShell(title: title, icon: "terminal", width: 1120,
                   confirm: "Close", confirmIcon: "x", confirmVariant: .secondary) {
            app.closeSheet()
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                toolbar
                if panes.isEmpty {
                    EmptyState(icon: "file-warning", tone: .warn, text: "no transcript events loaded yet.")
                } else {
                    paneScroller
                }
            }
        }
        .task(id: target.transcriptPath) {
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var title: String {
        if let workflowId = target.workflowId { return "Watch workflow · \(workflowId)" }
        return "Watch agent · \(target.repoName)"
    }

    private var toolbar: some View {
        HStack(spacing: Theme.space.x2) {
            Pill(text: target.tool, tone: .neutral, icon: providerIcon)
            Pill(text: target.kind.rawValue, tone: kindTone, icon: kindIcon)
            Text(target.repoName)
                .font(VibeFont.mono(VibeFont.size.xs))
                .foregroundStyle(Theme.color.textMuted)
                .lineLimit(1)
            Spacer()
            VibeButton(title: "-", icon: "minus", variant: .secondary, size: .sm) {
                fontSize = Swift.max(10, fontSize - 1)
            }
            Text("\(Int(fontSize))")
                .font(VibeFont.mono(VibeFont.size.xs, .medium))
                .foregroundStyle(Theme.color.textSecondary)
                .monospacedDigit()
                .frame(width: 28)
            VibeButton(title: "+", icon: "plus", variant: .secondary, size: .sm) {
                fontSize = Swift.min(18, fontSize + 1)
            }
        }
    }

    private var paneScroller: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: Theme.space.x3) {
                ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                    if target.kind == .workflow, index > 0, panes[index - 1].phaseIndex != pane.phaseIndex {
                        WorkflowHopDivider(phase: pane.phaseIndex)
                    }
                    TranscriptPaneView(pane: pane, fontSize: fontSize, expanded: $expanded)
                }
            }
            .padding(.bottom, Theme.space.x1)
        }
    }

    private var providerIcon: String {
        switch target.tool {
        case "codex": return "square-terminal"
        case "claude-code", "claude": return "bot"
        default: return "bot"
        }
    }
    private var kindIcon: String {
        switch target.kind {
        case .standard: return "terminal"
        case .subagent: return "corner-down-right"
        case .workflow: return "git-merge"
        }
    }
    private var kindTone: VibeTone {
        switch target.kind {
        case .standard: return .neutral
        case .subagent: return .info
        case .workflow: return .policy
        }
    }

    private func reload() async {
        let path = target.transcriptPath
        let kind = target.kind
        let loaded = await Task.detached {
            AgentTranscriptWatchProbe.panes(path: path, kind: kind)
        }.value
        panes = loaded
    }
}

private struct TranscriptPaneView: View {
    let pane: TranscriptPane
    let fontSize: CGFloat
    @Binding var expanded: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.space.x2) {
                    ForEach(pane.events) { event in
                        TranscriptEventRow(event: event, fontSize: fontSize, expanded: $expanded)
                    }
                }
                .padding(Theme.space.x3)
            }
        }
        .frame(width: 360, height: 430)
        .background(Theme.color.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(Theme.color.border, lineWidth: 1))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1) {
            HStack(spacing: Theme.space.x2) {
                if let phaseLabel = pane.phaseLabel {
                    StatusBadge(text: phaseLabel, tone: .info, small: true)
                }
                Text(pane.title)
                    .font(VibeFont.mono(VibeFont.size.sm, .bold))
                    .foregroundStyle(Theme.color.textBright)
                    .lineLimit(1)
            }
            Text(pane.subtitle)
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textFaint)
                .lineLimit(1)
        }
        .padding(Theme.space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }
}

private struct TranscriptEventRow: View {
    let event: TranscriptEvent
    let fontSize: CGFloat
    @Binding var expanded: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1) {
            HStack(spacing: Theme.space.x2) {
                VibeIcon(icon, size: 12, color: toneColor)
                Text(event.title)
                    .font(VibeFont.mono(fontSize * 0.9, .medium))
                    .foregroundStyle(toneColor)
                    .lineLimit(1)
                Spacer()
                Text(event.timestamp.map { RelTime.ago($0, now: Date()) } ?? "—")
                    .font(VibeFont.mono(fontSize * 0.82))
                    .foregroundStyle(Theme.color.textFaint)
            }
            if event.kind == .toolUse || event.kind == .toolResult {
                DisclosureGroup(isExpanded: binding) {
                    codeBody(event.body)
                } label: {
                    Text(event.kind == .toolUse ? "tool call" : "tool result")
                        .font(VibeFont.mono(fontSize * 0.9))
                        .foregroundStyle(Theme.color.textMuted)
                }
            } else {
                AgentWatchMarkdownBody(text: event.body, fontSize: fontSize)
            }
        }
        .padding(Theme.space.x2)
        .background(Theme.color.surface1.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
            .strokeBorder(Theme.color.borderSubtle, lineWidth: 1))
    }

    private var binding: Binding<Bool> {
        Binding {
            expanded.contains(event.id)
        } set: { isExpanded in
            if isExpanded { expanded.insert(event.id) } else { expanded.remove(event.id) }
        }
    }

    private var icon: String {
        switch event.kind {
        case .text: return event.role == "user" ? "user" : "bot"
        case .toolUse: return "wrench"
        case .toolResult: return event.isError ? "triangle-alert" : "check-circle"
        case .meta: return "info"
        }
    }
    private var toneColor: Color {
        if event.isError { return Theme.color.danger }
        switch event.kind {
        case .toolUse: return Theme.color.warn
        case .toolResult: return Theme.color.info
        default: return Theme.color.textSecondary
        }
    }

    private func codeBody(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text.isEmpty ? " " : text)
                .font(VibeFont.mono(fontSize))
                .foregroundStyle(Theme.color.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(Theme.space.x2)
        }
        .background(Theme.color.bgVoid)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous))
    }
}
