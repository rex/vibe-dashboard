// WatchPaneView.swift — one full-height transcript column in the watch window:
// header (who/what/status) + auto-following event scroll. Follow is sticky: the
// pane tails its transcript until the user scrolls up, then a "↓ n new" chip
// offers the way back down. No timers here — new events arrive via the model.

import SwiftUI
import AppKit

struct WatchPaneView: View {
    let pane: WatchPane
    let fontSize: Double
    @Binding var expanded: Set<String>
    let followSignal: Int
    let now: Date

    @State private var follow = true
    @State private var unfollowedAt = 0          // event count when the user scrolled away
    @State private var lastAutoScroll = Date.distantPast

    private static let bottomId = "pane-bottom"

    var body: some View {
        VStack(spacing: 0) {
            header
            events
        }
        .background(ColorPalette.ink900)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(Theme.color.border, lineWidth: 1))
        .frame(maxHeight: .infinity)
    }

    // MARK: - Header

    private var streaming: Bool { pane.isStreaming(now: now) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.space.x2) {
                if pane.phase > 0 {
                    StatusBadge(text: "phase \(pane.phase)", tone: .info, small: true)
                }
                Text(pane.title)
                    .font(VibeFont.mono(VibeFont.size.sm, .bold))
                    .foregroundStyle(Theme.color.textBright)
                    .lineLimit(1)
                    .help(pane.title)
                Spacer(minLength: Theme.space.x2)
                status
            }
            HStack(spacing: Theme.space.x1_5) {
                if let badge = pane.badge {
                    Text(badge).vibeMicroLabel(9, color: Theme.color.textMuted)
                }
                Text("\(pane.tail.events.count) events")
                    .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                if let last = pane.lastEventAt {
                    Text("· \(WatchClock.hms(last))")
                        .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Theme.space.x3).padding(.vertical, Theme.space.x2_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
        .contextMenu {
            Button("Reveal transcript in Finder") {
                NSWorkspace.shared.selectFile(pane.path, inFileViewerRootedAtPath: "")
            }
            Button("Copy transcript path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pane.path, forType: .string)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if pane.done {
            HStack(spacing: Theme.space.x1) {
                VibeIcon("check-circle", size: 11, color: Theme.color.ok)
                Text("returned").vibeMicroLabel(9, color: Theme.color.ok)
            }
        } else if streaming {
            HStack(spacing: Theme.space.x1_5) {
                AgentPulse(active: true, color: Theme.color.ok, size: 10)
                Text("streaming").vibeMicroLabel(9, color: Theme.color.ok)
            }
        } else {
            Text("quiet").vibeMicroLabel(9, color: Theme.color.textGhost)
        }
    }

    // MARK: - Event scroll (sticky follow)

    private var events: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.space.x2) {
                    if pane.tail.bootstrapped || pane.tail.trimmed > 0 {
                        trimNote
                    }
                    ForEach(pane.tail.events) { event in
                        WatchEventRow(event: event, rowId: pane.id + "·" + event.id,
                                      fontSize: fontSize, expanded: $expanded)
                    }
                    if let outcome = pane.outcome {
                        WatchOutcomeRow(body: outcome, rowId: pane.id + "·outcome",
                                        fontSize: fontSize, expanded: $expanded)
                    }
                    bottomSentinel
                }
                .padding(Theme.space.x3)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: pane.tail.seq) {
                if follow { autoScroll(proxy) }
            }
            .onChange(of: followSignal) {
                follow = true
                autoScroll(proxy)
            }
            .overlay(alignment: .bottom) {
                if !follow { newEventsChip(proxy) }
            }
        }
    }

    /// A 1-pt marker after the last row. Visible ⇒ the user is reading the tail
    /// (follow on). It vanishing without a recent programmatic scroll ⇒ the user
    /// scrolled up ⇒ follow off, and the chip starts counting new arrivals.
    private var bottomSentinel: some View {
        Color.clear.frame(height: 1).id(Self.bottomId)
            .onAppear {
                follow = true
                unfollowedAt = 0
            }
            .onDisappear {
                if Date().timeIntervalSince(lastAutoScroll) > 0.6 {
                    follow = false
                    unfollowedAt = pane.tail.seq
                }
            }
    }

    private func autoScroll(_ proxy: ScrollViewProxy) {
        lastAutoScroll = Date()
        proxy.scrollTo(Self.bottomId, anchor: .bottom)
    }

    private func newEventsChip(_ proxy: ScrollViewProxy) -> some View {
        let fresh = max(0, pane.tail.seq - unfollowedAt)
        return Button {
            follow = true
            autoScroll(proxy)
        } label: {
            HStack(spacing: Theme.space.x1_5) {
                VibeIcon("arrow-down", size: 11, color: Theme.color.textOnAccent)
                Text(fresh > 0 ? "\(fresh) new" : "latest")
                    .font(VibeFont.mono(VibeFont.size.xxs, .bold))
                    .foregroundStyle(Theme.color.textOnAccent)
                    .monospacedDigit()
            }
            .padding(.horizontal, Theme.space.x2_5).padding(.vertical, Theme.space.x1)
            .background(Theme.color.accent)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, Theme.space.x2_5)
    }

    /// Honest disclosure that the pane starts mid-stream (huge transcript) or that
    /// the retention cap dropped early rows — never silently pretend completeness.
    private var trimNote: some View {
        HStack(spacing: Theme.space.x1_5) {
            VibeIcon("history", size: 10, color: Theme.color.textGhost)
            Text(pane.tail.trimmed > 0
                 ? "showing the latest \(pane.tail.events.count) events · \(pane.tail.trimmed) earlier trimmed"
                 : "tailing from the last \(WatchTailer.bootstrapBytes / 1024) KB of a large transcript")
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textGhost)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.space.x1)
    }
}

/// Absolute wall-clock stamps for log rows — relative strings go stale in a live
/// tail; "14:32:05" never lies.
enum WatchClock {
    nonisolated(unsafe) private static let hmsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    static func hms(_ date: Date) -> String { hmsFormatter.string(from: date) }
}
