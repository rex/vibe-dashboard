// Placeholders.swift — temporary stubs, replaced by real screens next.

import SwiftUI

private struct ScreenStub: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: Theme.space.x3) {
            Text(title).font(VibeFont.sans(VibeFont.size.xxl, .semibold)).foregroundStyle(Theme.color.textBright)
            EmptyState(icon: icon, tone: .neutral, text: "\(title) — assembling…")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentsView: View { var body: some View { ScreenStub(title: "Agents", icon: "radar") } }
struct FindingsView: View { var body: some View { ScreenStub(title: "Findings", icon: "triangle-alert") } }
struct SkillsView: View { var body: some View { ScreenStub(title: "Skills", icon: "blocks") } }
struct AutopilotView: View { var body: some View { ScreenStub(title: "Autopilot", icon: "gauge-circle") } }

struct RepoDetailView: View {
    let repo: Repo
    var body: some View { ScreenStub(title: repo.name, icon: "folder-git-2") }
}
struct WorkspaceDetailView: View {
    let workspace: Repo
    var body: some View { ScreenStub(title: workspace.name, icon: "folder-tree") }
}

struct OverlayHost: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if let sheet = app.sheet {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { app.closeSheet() }
                VStack(spacing: Theme.space.x4) {
                    Text(sheet.rawValue).font(VibeFont.mono(VibeFont.size.md, .bold)).foregroundStyle(Theme.color.textBright)
                    Text("sheet — assembling…").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textMuted)
                    VibeButton(title: "Close", variant: .secondary) { app.closeSheet() }
                }
                .padding(Theme.space.x8)
                .background(Theme.color.surface1)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius.lg))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius.lg).strokeBorder(Theme.color.borderStrong, lineWidth: 1))
            }
        }
    }
}
