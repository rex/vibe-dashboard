// AgentsPanels.swift — doc-bloat + changelog-staleness leaderboards for the Agents
// screen. Split out of AgentsView.swift to keep that file under the 400-line hard gate.

import SwiftUI

private let taskStateSoft: Double = 400
private let taskStateHard: Double = 800

// MARK: - Doc bloat leaderboard

struct DocBloatPanel: View {
    let repos: [Repo]
    @Environment(AppState.self) private var app

    var body: some View {
        VibePanel(header: {
            HStack(spacing: Theme.space.x2) {
                PanelTitle(text: "doc bloat · TASK_STATE.md")
                Spacer()
                Text("soft \(Int(taskStateSoft)) · hard \(Int(taskStateHard))")
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .monospacedDigit()
            }
        }, content: {
            if repos.isEmpty {
                EmptyState(icon: "file-text", tone: .ok, text: "no TASK_STATE.md to weigh yet.")
            } else {
                VStack(alignment: .leading, spacing: Theme.space.x3) {
                    ForEach(repos.prefix(5)) { r in
                        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
                            Button { app.openRepo(r.id) } label: {
                                HStack(spacing: 7) {
                                    HealthDot(health: r.health, size: 7)
                                    Text(r.name)
                                        .font(VibeFont.mono(VibeFont.size.xs, .medium))
                                        .foregroundStyle(Theme.color.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            LimitBar(value: Double(r.docs.taskState.lines), soft: taskStateSoft, hard: taskStateHard)
                        }
                    }
                }
            }
        })
    }
}

// MARK: - Changelog staleness

struct ChangelogStalenessPanel: View {
    let repos: [Repo]
    @Environment(AppState.self) private var app

    var body: some View {
        VibePanel(title: "changelog staleness", flushBody: true) {
            if repos.isEmpty {
                EmptyState(icon: "history", tone: .ok, text: "every CHANGELOG is current.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(repos.enumerated()), id: \.element.id) { idx, r in
                        let tone = r.docs.changelog.status.tone
                        Button { app.openRepo(r.id) } label: {
                            HStack(spacing: Theme.space.x2_5) {
                                VibeIcon("history", size: 14, color: Theme.color.tone(tone))
                                Text(r.name)
                                    .font(VibeFont.mono(VibeFont.size.sm))
                                    .foregroundStyle(Theme.color.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: Theme.space.x2)
                                Text("\(r.docs.changelog.behind) behind · \(r.docs.changelog.lastUpdated)")
                                    .font(VibeFont.mono(VibeFont.size.xxs))
                                    .foregroundStyle(Theme.color.tone(tone))
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, Theme.space.x4)
                            .padding(.vertical, Theme.space.x2_5)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if idx != repos.count - 1 {
                                Rectangle().fill(Theme.color.borderSubtle).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }
}
