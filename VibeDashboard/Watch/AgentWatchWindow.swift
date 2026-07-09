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

    private var anyStreaming: Bool { model.lanes.contains { $0.isStreaming(now: model.now) } }

    /// Workflow windows are NAMED from the plan the orchestrator persisted
    /// (workflows/scripts/<name>-<wfId>.js); everything else uses the repo.
    private var headline: String { model.workflowMeta.name ?? target.repoName }
    private var subline: String {
        model.workflowMeta.description ?? WatchTranscriptParser.abbreviateHome(target.repoPath)
    }

    private var toolbar: some View {
        HStack(spacing: Theme.space.x3) {
            // Leading inset clears the traffic lights under .hiddenTitleBar.
            Color.clear.frame(width: 64, height: 1)
            AgentPulse(active: anyStreaming,
                       color: anyStreaming ? Theme.color.ok : Theme.color.textFaint, size: 12)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.space.x2) {
                    Text(headline)
                        .font(VibeFont.mono(VibeFont.size.md, .bold))
                        .foregroundStyle(Theme.color.textBright)
                        .lineLimit(1)
                    Pill(text: kindLabel, tone: kindTone, icon: kindIcon)
                    if target.kind == .workflow {
                        progressBadge
                    }
                }
                Text(subline)
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textFaint)
                    .lineLimit(1).truncationMode(.middle)
                    .help(subline)
            }
            Spacer(minLength: Theme.space.x2)

            phaseStrip

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
        for lane in model.lanes {
            for seg in lane.segments {
                for e in seg.tail.events where e.kind == .tool || e.kind == .thinking {
                    ids.insert(seg.id + "·" + e.id)
                }
                if seg.outcome != nil { ids.insert(seg.id + "·outcome") }
            }
        }
        return ids
    }

    /// Real progress: journal results over agents known so far — never a guess.
    @ViewBuilder private var progressBadge: some View {
        if model.agentTotal > 0 {
            let done = model.returnedCount == model.agentTotal
            Text("\(model.returnedCount)/\(model.agentTotal) returned")
                .font(VibeFont.mono(VibeFont.size.xxs, .medium))
                .foregroundStyle(done ? Theme.color.ok : Theme.color.textMuted)
                .monospacedDigit()
            if model.workflowMeta.status == "completed", let ms = model.workflowMeta.durationMs {
                StatusBadge(text: "completed · \(RelTime.compact(Double(ms) / 1000))",
                            tone: .ok, small: true)
            }
        }
    }

    /// The PLAN's phase titles from the persisted script meta — shown as the
    /// workflow's intent, not asserted live state (loops/dynamic scripts may
    /// diverge; the lanes' hop dividers carry the real transitions).
    @ViewBuilder private var phaseStrip: some View {
        if !model.workflowMeta.phases.isEmpty {
            HStack(spacing: Theme.space.x1) {
                Text("plan").vibeMicroLabel(8, color: Theme.color.textGhost)
                ForEach(Array(model.workflowMeta.phases.enumerated()), id: \.offset) { idx, title in
                    if idx > 0 {
                        VibeIcon("chevron-right", size: 9, color: Theme.color.textGhost)
                    }
                    Text(title)
                        .font(VibeFont.mono(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textMuted)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Lanes

    private var panesArea: some View {
        GeometryReader { geo in
            if model.lanes.isEmpty {
                EmptyState(icon: "radar", tone: .neutral,
                           text: "waiting for transcript events…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let pad = Theme.space.x3
                let gap = Theme.space.x2_5
                let n = CGFloat(model.lanes.count)
                let avail = geo.size.width - pad * 2 - gap * (n - 1)
                let laneW = max(440, avail / n)
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(model.lanes) { lane in
                            WatchLaneView(lane: lane, fontSize: fontSize,
                                          expanded: $expanded, followSignal: followSignal,
                                          now: model.now)
                                .frame(width: laneW)
                        }
                    }
                    .padding(pad)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
            }
        }
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

