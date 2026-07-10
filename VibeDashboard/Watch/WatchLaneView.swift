// WatchLaneView.swift — one full-height LANE in the watch window: a continuous
// stream that follows an agent through phase handoffs. Segments stack vertically
// with an unmissable hop divider between them, so "agent 1 returned → agent 2
// picked up" reads in-place — no pane switching. Follow is sticky: the lane tails
// its stream until the user scrolls up, then a "↓ n new" chip offers the way back.

import SwiftUI
import AppKit

struct WatchLaneView: View {
    // The lane arrives as an OBSERVABLE BOX: this view registers on box.lane /
    // box.now during body, so a content tick re-renders only this lane — never
    // its 7 siblings. (Passing plain values from the window re-rendered all of
    // them per tick; that was the main-thread layout storm.)
    let box: WatchLaneBox
    let fontSize: Double
    @Binding var expanded: Set<String>
    let followSignal: Int

    private var lane: WatchLane { box.lane }
    private var now: Date { box.now }

    @State private var follow = true
    @State private var unfollowedAt = 0          // lane event total when the user scrolled away
    @State private var lastAutoScroll = Date.distantPast

    private static let bottomId = "lane-bottom"

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

    // MARK: - Header (describes the CURRENT segment + the lane's journey)

    private var current: WatchPane? { lane.current }
    private var streaming: Bool { lane.isStreaming(now: now) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.space.x2) {
                if lane.segments.count > 1 {
                    StatusBadge(text: "stage \(lane.segments.count)", tone: .info, small: true)
                }
                Text(current?.title ?? "—")
                    .font(VibeFont.mono(VibeFont.size.sm, .bold))
                    .foregroundStyle(Theme.color.textBright)
                    .lineLimit(1)
                    .help(journeyHelp)
                Spacer(minLength: Theme.space.x2)
                status
            }
            HStack(spacing: Theme.space.x1_5) {
                if let badge = current?.badge {
                    Text(badge).vibeMicroLabel(9, color: Theme.color.textMuted)
                }
                if lane.segments.count > 1 {
                    Text("\(lane.segments.count) agents")
                        .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                }
                Text("· \(lane.eventTotal) events")
                    .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                if let last = lane.segments.compactMap(\.lastEventAt).max() {
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
            ForEach(lane.segments) { seg in
                Button("Reveal \((seg.path as NSString).lastPathComponent) in Finder") {
                    NSWorkspace.shared.selectFile(seg.path, inFileViewerRootedAtPath: "")
                }
            }
            Button("Copy current transcript path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(current?.path ?? "", forType: .string)
            }
        }
    }

    private var journeyHelp: String {
        lane.segments.enumerated()
            .map { "stage \($0.offset + 1): \($0.element.title)" }
            .joined(separator: "\n")
    }

    @ViewBuilder private var status: some View {
        if lane.done {
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

    // MARK: - Continuous stream (segments + hop dividers), sticky follow

    private var events: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.space.x2) {
                    ForEach(Array(lane.segments.enumerated()), id: \.element.id) { idx, seg in
                        if idx > 0 {
                            WatchHopRow(stage: idx + 1, title: seg.title,
                                        startedAt: seg.firstEventAt)
                        }
                        if seg.tail.bootstrapped || seg.tail.trimmed > 0 {
                            trimNote(seg)
                        }
                        ForEach(seg.tail.events) { event in
                            WatchEventRow(event: event, rowId: seg.id + "·" + event.id,
                                          fontSize: fontSize, expanded: $expanded)
                        }
                        if let outcome = seg.outcome {
                            WatchOutcomeRow(body: outcome, rowId: seg.id + "·outcome",
                                            fontSize: fontSize, expanded: $expanded)
                        }
                    }
                    bottomSentinel
                }
                .padding(Theme.space.x3)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: lane.eventTotal) {
                if follow { autoScroll(proxy) }
            }
            .onChange(of: lane.segments.count) {   // a hop landed — keep following into it
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
                    unfollowedAt = lane.eventTotal
                }
            }
    }

    private func autoScroll(_ proxy: ScrollViewProxy) {
        lastAutoScroll = Date()
        proxy.scrollTo(Self.bottomId, anchor: .bottom)
    }

    private func newEventsChip(_ proxy: ScrollViewProxy) -> some View {
        let fresh = max(0, lane.eventTotal - unfollowedAt)
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

    /// Honest disclosure that a segment starts mid-stream (huge transcript) or that
    /// the retention cap dropped early rows — never silently pretend completeness.
    private func trimNote(_ seg: WatchPane) -> some View {
        HStack(spacing: Theme.space.x1_5) {
            VibeIcon("history", size: 10, color: Theme.color.textGhost)
            Text(seg.tail.trimmed > 0
                 ? "showing the latest \(seg.tail.events.count) events · \(seg.tail.trimmed) earlier trimmed"
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
