// WatchEventRows.swift — per-event rendering for a watch pane. Prose respects
// block markdown; tool calls collapse to one scannable line (name + salient arg +
// live status) and expand to their input/result; thinking is present but ghosted.

import SwiftUI

struct WatchEventRow: View {
    let event: WatchEvent
    let rowId: String
    let fontSize: Double
    @Binding var expanded: Set<String>

    var body: some View {
        switch event.kind {
        case .user: userRow
        case .assistant: assistantRow
        case .thinking: WatchFoldRow(rowId: rowId, fontSize: fontSize, expanded: $expanded,
                                     icon: "brain", label: "thinking",
                                     preview: event.body, tone: .ghost) {
            Text(WatchInline.render(event.body, fontSize: fontSize))
                .font(VibeFont.mono(fontSize).italic())
                .foregroundStyle(Theme.color.textFaint)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        case .tool: toolRow
        case .meta: metaRow
        case .outcome: EmptyView()   // outcomes render via WatchOutcomeRow
        }
    }

    // MARK: - Prose

    private var userRow: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
            HStack(spacing: Theme.space.x1_5) {
                VibeIcon("user", size: 10, color: Theme.color.accent)
                Text("you").vibeMicroLabel(9, color: Theme.color.accent)
                Spacer(minLength: 0)
                stamp
            }
            WatchMarkdownView(text: event.body, fontSize: fontSize)
        }
        .padding(Theme.space.x2_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.radius.sm,
                                   bottomLeadingRadius: Theme.radius.sm)
                .fill(Theme.color.accent)
                .frame(width: 2)
        }
    }

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1) {
            HStack(spacing: Theme.space.x1_5) {
                VibeIcon("bot", size: 10, color: Theme.color.textMuted)
                Text("assistant").vibeMicroLabel(9, color: Theme.color.textMuted)
                Spacer(minLength: 0)
                stamp
            }
            WatchMarkdownView(text: event.body, fontSize: fontSize)
        }
        .padding(.vertical, Theme.space.x1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tool call (collapsed line ↔ expanded input/result)

    private var isOpen: Bool { expanded.contains(rowId) }

    private var toolRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen { expanded.remove(rowId) } else { expanded.insert(rowId) }
            } label: {
                HStack(spacing: Theme.space.x1_5) {
                    VibeIcon(isOpen ? "chevron-down" : "chevron-right", size: 10,
                             color: Theme.color.textGhost)
                    toolStatusIcon
                    Text(event.title)
                        .font(VibeFont.mono(fontSize * 0.92, .medium))
                        .foregroundStyle(event.isError ? Theme.color.danger : Theme.color.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if !event.summary.isEmpty {
                        Text(event.summary)
                            .font(VibeFont.mono(fontSize * 0.88))
                            .foregroundStyle(Theme.color.textFaint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Theme.space.x1)
                    stamp
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.space.x2).padding(.vertical, Theme.space.x1_5)

            if isOpen {
                VStack(alignment: .leading, spacing: Theme.space.x2) {
                    if !event.body.isEmpty {
                        WatchCodePane(label: "input", text: event.body,
                                      lang: event.inputIsJSON ? "json" : nil, fontSize: fontSize)
                    }
                    if let output = event.output {
                        WatchCodePane(label: event.isError ? "result · error" : "result",
                                      text: output.isEmpty ? "(empty)" : output,
                                      lang: nil, fontSize: fontSize,
                                      tone: event.isError ? .danger : nil)
                    } else {
                        HStack(spacing: Theme.space.x1_5) {
                            AgentPulse(active: true, color: Theme.color.warn, size: 9)
                            Text("running — no result yet")
                                .font(VibeFont.mono(VibeFont.size.xxs))
                                .foregroundStyle(Theme.color.warn)
                        }
                    }
                }
                .padding(.horizontal, Theme.space.x2).padding(.bottom, Theme.space.x2)
            }
        }
        .background(Theme.color.surface1.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
            .strokeBorder(event.isError ? Theme.color.dangerLine : Theme.color.borderSubtle,
                          lineWidth: 1))
    }

    @ViewBuilder private var toolStatusIcon: some View {
        if event.isError {
            VibeIcon("x-circle", size: 11, color: Theme.color.danger)
        } else if event.output != nil {
            VibeIcon("check", size: 11, color: Theme.color.ok)
        } else if event.title == "tool result" {
            VibeIcon("corner-down-right", size: 11, color: Theme.color.info)
        } else {
            VibeIcon("circle-dot-dashed", size: 11, color: Theme.color.warn)
        }
    }

    // MARK: - Meta

    private var metaRow: some View {
        HStack(spacing: Theme.space.x2) {
            Rectangle().fill(Theme.color.borderSubtle).frame(height: 1)
            Text(event.body.isEmpty ? event.title : "\(event.title) · \(event.body)")
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textGhost)
                .lineLimit(1)
                .fixedSize()
            Rectangle().fill(Theme.color.borderSubtle).frame(height: 1)
        }
        .padding(.vertical, Theme.space.x1)
    }

    @ViewBuilder private var stamp: some View {
        if let ts = event.timestamp {
            Text(WatchClock.hms(ts))
                .font(VibeFont.mono(fontSize * 0.78))
                .foregroundStyle(Theme.color.textGhost)
                .monospacedDigit()
        }
    }
}

// MARK: - Shared folding row (thinking / outcome)

enum WatchFoldTone { case ghost, policy }

struct WatchFoldRow<Content: View>: View {
    let rowId: String
    let fontSize: Double
    @Binding var expanded: Set<String>
    let icon: String
    let label: String
    let preview: String
    let tone: WatchFoldTone
    @ViewBuilder let content: () -> Content

    private var isOpen: Bool { expanded.contains(rowId) }
    private var color: Color { tone == .policy ? Theme.color.policy : Theme.color.textGhost }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
            Button {
                if isOpen { expanded.remove(rowId) } else { expanded.insert(rowId) }
            } label: {
                HStack(spacing: Theme.space.x1_5) {
                    VibeIcon(isOpen ? "chevron-down" : "chevron-right", size: 10, color: color)
                    VibeIcon(icon, size: 11, color: color)
                    Text(label).vibeMicroLabel(9, color: color)
                    if !isOpen {
                        Text(WatchTranscriptParser.oneLine(preview, cap: 90))
                            .font(VibeFont.mono(fontSize * 0.85).italic())
                            .foregroundStyle(Theme.color.textGhost)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen { content().padding(.leading, Theme.space.x4) }
        }
        .padding(.vertical, Theme.space.x0_5)
    }
}

/// The journal-recorded return value of a finished workflow agent — the honest
/// "what this agent handed back" marker at the foot of its pane.
struct WatchOutcomeRow: View {
    let body_: String
    let rowId: String
    let fontSize: Double
    @Binding var expanded: Set<String>

    init(body: String, rowId: String, fontSize: Double, expanded: Binding<Set<String>>) {
        self.body_ = body
        self.rowId = rowId
        self.fontSize = fontSize
        self._expanded = expanded
    }

    var body: some View {
        WatchFoldRow(rowId: rowId, fontSize: fontSize, expanded: $expanded,
                     icon: "git-merge", label: "returned", preview: body_, tone: .policy) {
            WatchCodePane(label: "result", text: body_, lang: "json", fontSize: fontSize)
        }
        .padding(Theme.space.x2)
        .background(Theme.color.violetSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
            .strokeBorder(Theme.color.violetLine, lineWidth: 1))
    }
}

/// Mono code well used for tool inputs/results — horizontal scroll keeps long
/// lines from wrapping into soup; text stays selectable.
struct WatchCodePane: View {
    let label: String
    let text: String
    let lang: String?
    let fontSize: Double
    var tone: VibeTone? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1) {
            HStack {
                Text(label).vibeMicroLabel(8, color: tone.map { Theme.color.tone($0) }
                    ?? Theme.color.textGhost)
                Spacer()
                if let lang {
                    Text(lang).vibeMicroLabel(8, color: Theme.color.textGhost)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(VibeFont.mono(fontSize * 0.92))
                    .foregroundStyle(tone == .danger ? Theme.color.danger : Theme.color.textSecondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(Theme.space.x2)
            }
            .background(Theme.color.bgVoid)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous)
                .strokeBorder(tone == .danger ? Theme.color.dangerLine : Theme.color.borderSubtle,
                              lineWidth: 1))
        }
    }
}
