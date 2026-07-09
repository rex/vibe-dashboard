// AgentWatchWindow.swift — the dedicated agent-watch window: a resizable,
// full-height mission console tailing every transcript a session/workflow owns.
// Replaces the old fixed 360×430 sheet. One window per watch target
// (WindowGroup(for: AgentWatchTarget.self)).

import SwiftUI
import AppKit

struct AgentWatchWindow: View {
    let target: AgentWatchTarget
    @State private var model: AgentWatchModel
    @AppStorage("vibe.watch.fontSize") private var fontSize: Double = 12.5
    @State private var expanded: Set<String> = []    // "<panePath>·<eventId>" rows open
    @State private var followSignal = 0              // bump → every pane snaps to its tail

    private static let minFont = 10.0, maxFont = 19.0

    init(target: AgentWatchTarget) {
        self.target = target
        _model = State(initialValue: AgentWatchModel(target: target))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Theme.color.border).frame(height: 1)
            panesArea
        }
        .background(Theme.color.bgVoid)
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: - Toolbar

    private var anyStreaming: Bool { model.panes.contains { $0.isStreaming(now: model.now) } }

    private var toolbar: some View {
        HStack(spacing: Theme.space.x3) {
            // Leading inset clears the traffic lights under .hiddenTitleBar.
            Color.clear.frame(width: 64, height: 1)
            AgentPulse(active: anyStreaming,
                       color: anyStreaming ? Theme.color.ok : Theme.color.textFaint, size: 12)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.space.x2) {
                    Text(target.repoName)
                        .font(VibeFont.mono(VibeFont.size.md, .bold))
                        .foregroundStyle(Theme.color.textBright)
                        .lineLimit(1)
                    Pill(text: kindLabel, tone: kindTone, icon: kindIcon)
                    if let wf = target.workflowId {
                        Text(wf).font(VibeFont.mono(VibeFont.size.xxs))
                            .foregroundStyle(Theme.color.textFaint).lineLimit(1)
                    }
                }
                Text(WatchTranscriptParser.abbreviateHome(target.repoPath))
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textFaint)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Theme.space.x2)

            Text("\(model.panes.count) pane\(model.panes.count == 1 ? "" : "s")")
                .vibeMicroLabel(9, color: Theme.color.textGhost)

            toolbarButton("arrow-down", help: "Follow all panes (snap to the live tail)") {
                followSignal += 1
            }
            toolbarButton("chevron-down", help: "Expand every tool call") {
                expanded = allToolRowIds()
            }
            toolbarButton("chevron-up", help: "Collapse every tool call") {
                expanded = []
            }

            HStack(spacing: Theme.space.x1) {
                toolbarButton("minus", help: "Smaller text (⌘−)") {
                    fontSize = max(Self.minFont, fontSize - 1)
                }
                .keyboardShortcut("-", modifiers: .command)
                Text("\(Int(fontSize))")
                    .font(VibeFont.mono(VibeFont.size.xs, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.color.textSecondary)
                    .frame(width: 22)
                    .help("Text size — ⌘0 resets")
                toolbarButton("plus", help: "Larger text (⌘+)") {
                    fontSize = min(Self.maxFont, fontSize + 1)
                }
                .keyboardShortcut("=", modifiers: .command)
            }
            Button("") { fontSize = 12.5 }
                .keyboardShortcut("0", modifiers: .command)
                .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0)
        }
        .padding(.horizontal, Theme.space.x3)
        .frame(height: 46)
        .background(ColorPalette.ink900)
    }

    private func toolbarButton(_ icon: String, help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VibeIcon(icon, size: 13, color: Theme.color.textSecondary)
                .frame(width: 26, height: 24)
                .background(Theme.color.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                    .strokeBorder(Theme.color.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func allToolRowIds() -> Set<String> {
        var ids: Set<String> = []
        for pane in model.panes {
            for e in pane.tail.events where e.kind == .tool || e.kind == .thinking {
                ids.insert(pane.id + "·" + e.id)
            }
            if pane.outcome != nil { ids.insert(pane.id + "·outcome") }
        }
        return ids
    }

    // MARK: - Panes

    private var panesArea: some View {
        GeometryReader { geo in
            if model.panes.isEmpty {
                EmptyState(icon: "radar", tone: .neutral,
                           text: "waiting for transcript events…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let pad = Theme.space.x3
                let gap = Theme.space.x2_5
                let hops = CGFloat(hopCount())
                let n = CGFloat(model.panes.count)
                let avail = geo.size.width - pad * 2 - gap * (n - 1) - hops * (34 + gap)
                let paneW = max(440, avail / n)
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(Array(model.panes.enumerated()), id: \.element.id) { idx, pane in
                            if idx > 0, pane.phase != model.panes[idx - 1].phase {
                                WatchHopDivider(phase: pane.phase)
                            }
                            WatchPaneView(pane: pane, fontSize: fontSize,
                                          expanded: $expanded, followSignal: followSignal,
                                          now: model.now)
                                .frame(width: paneW)
                        }
                    }
                    .padding(pad)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
            }
        }
    }

    private func hopCount() -> Int {
        guard model.panes.count > 1 else { return 0 }
        return zip(model.panes, model.panes.dropFirst()).filter { $0.phase != $1.phase }.count
    }

    private var kindLabel: String {
        switch target.kind {
        case .workflow: return "workflow"
        case .subagent: return "subagent"
        case .standard: return target.tool
        }
    }
    private var kindIcon: String {
        switch target.kind {
        case .workflow: return "git-merge"
        case .subagent: return "corner-down-right"
        case .standard: return target.tool == "codex" ? "square-terminal" : "bot"
        }
    }
    private var kindTone: VibeTone {
        switch target.kind {
        case .workflow: return .policy
        case .subagent: return .info
        case .standard: return .neutral
        }
    }
}

/// The between-pane "hop" marker: the workflow moved to its next phase — a new
/// agent (or wave) picked up where the previous one returned.
struct WatchHopDivider: View {
    let phase: Int

    var body: some View {
        VStack(spacing: Theme.space.x2) {
            Rectangle().fill(Theme.color.borderStrong).frame(width: 1)
                .frame(maxHeight: .infinity)
            VibeIcon("corner-down-right", size: 15, color: Theme.color.accent)
            Text("hop")
                .vibeMicroLabel(9, color: Theme.color.accent)
            Text("\(phase)")
                .font(VibeFont.mono(VibeFont.size.sm, .bold))
                .foregroundStyle(Theme.color.accent)
                .monospacedDigit()
            Rectangle().fill(Theme.color.borderStrong).frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 34)
        .frame(maxHeight: .infinity)
    }
}
