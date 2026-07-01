// ConsoleView.swift — bottom drawer: validate output · shell · activity feed.

import SwiftUI

struct ConsoleView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    var height: CGFloat = 210

    var body: some View {
        @Bindable var app = app
        let tabs: [SegOption<ConsoleTab>] = [
            SegOption(value: .output, label: "output"),
            SegOption(value: .shell, label: "shell"),
            SegOption(value: .activity, label: "activity", count: store.fleet.activity.count),
        ]
        VStack(spacing: 0) {
            HStack {
                SegMac(selection: $app.consoleTab, options: tabs, small: true)
                Spacer()
                Button { app.toggleConsole() } label: { VibeIcon("x", size: 13, color: Theme.color.textMuted) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.space.x3).padding(.vertical, Theme.space.x1_5)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    switch app.consoleTab {
                    case .activity: activityFeed
                    case .shell: shellFeed
                    case .output: outputFeed
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.space.x3)
            }
        }
        .frame(height: height)
        .background(ColorPalette.ink1000)
        .overlay(alignment: .top) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }

    private var activityFeed: some View {
        ForEach(store.fleet.activity) { a in
            HStack(alignment: .top, spacing: Theme.space.x2) {
                Text(a.t).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint).frame(width: 34, alignment: .trailing)
                Circle().fill(Theme.color.tone(a.tone)).frame(width: 6, height: 6).padding(.top, 5)
                Text(a.kind).font(VibeFont.mono(VibeFont.size.xxs, .medium)).foregroundStyle(Theme.color.tone(a.tone)).frame(width: 66, alignment: .leading)
                if a.repo != "—" {
                    Text(a.repo).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textSecondary)
                }
                Text(a.msg).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
                Spacer(minLength: 0)
            }
        }
    }

    private var shellFeed: some View {
        Group {
            if store.fleet.leaves.isEmpty {
                Text("no repo focused").font(VibeFont.mono(VibeFont.size.xs)).foregroundStyle(Theme.color.textFaint)
            } else if app.shellLog.isEmpty {
                let r = store.fleet.repo(app.selectedId)
                HStack(spacing: 6) {
                    Text("\(store.fleet.scanner.host)").foregroundStyle(Theme.color.info)
                    Text(r?.path ?? store.fleet.scanner.root).foregroundStyle(Theme.color.textMuted)
                    Text("%").foregroundStyle(Theme.color.accent)
                    CursorBlink(width: 7, height: 13)
                }
                .font(VibeFont.mono(VibeFont.size.xs))
            } else {
                ForEach(app.shellLog) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.host).foregroundStyle(Theme.color.info)
                            Text(entry.repoName).foregroundStyle(Theme.color.textMuted)
                            Text("% \(entry.cmd)").foregroundStyle(Theme.color.textPrimary)
                        }.font(VibeFont.mono(VibeFont.size.xs))
                        ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, ln in
                            Text(ln.text).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.tone(ln.tone))
                        }
                    }
                }
            }
        }
    }

    private var outputFeed: some View {
        Group {
            let last = app.shellLog.last { $0.cmd.contains("validate") }
            if let last {
                ForEach(Array(last.lines.enumerated()), id: \.offset) { _, ln in
                    Text(ln.text).font(VibeFont.mono(VibeFont.size.xs)).foregroundStyle(Theme.color.tone(ln.tone))
                }
            } else {
                Text("run `make validate` to see gate output here")
                    .font(VibeFont.mono(VibeFont.size.xs)).foregroundStyle(Theme.color.textFaint)
            }
        }
    }
}
