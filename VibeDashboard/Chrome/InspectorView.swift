// InspectorView.swift — the contextual right rail.

import SwiftUI

struct InspectorView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                if let r = store.fleet.repo(app.selectedId) {
                    RepoInspector(repo: r)
                } else {
                    FleetInspector(fleet: store.fleet)
                }
            }
            .padding(Theme.space.x4)
        }
        .frame(width: Theme.layout.inspector)
        .background(ColorPalette.ink900)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.color.border).frame(width: 1) }
    }
}

private struct FleetInspector: View {
    let fleet: Fleet
    @Environment(AppState.self) private var app
    var body: some View {
        let t = fleet.totals
        Text("fleet oversight").vibeMicroLabel(VibeFont.size.xs, color: Theme.color.textSecondary)
        VibePanel {
            VStack(spacing: 0) {
                MetaRow(key: "in policy") { Text("\(t.healthy)").foregroundStyle(Theme.color.ok) }
                MetaRow(key: "drifting") { Text("\(t.warn)").foregroundStyle(Theme.color.warn) }
                MetaRow(key: "surprises") { Text("\(t.danger)").foregroundStyle(Theme.color.danger) }
                MetaRow(key: "agents working") { Text("\(t.agentsActive)") }
                MetaRow(key: "abandoned worktrees") { Text("\(t.abandonedWorktrees)") }
                MetaRow(key: "doc bloat") { Text("\(t.bloatedDocs)") }
                MetaRow(key: "guardrail-less") { Text("\(t.guardrailless)").foregroundStyle(t.guardrailless > 0 ? Theme.color.danger : Theme.color.textPrimary) }
            }
        }
        if !fleet.findings.isEmpty {
            Text("top findings").vibeMicroLabel(VibeFont.size.xs, color: Theme.color.textSecondary)
            VStack(spacing: Theme.space.x1_5) {
                ForEach(fleet.findings.prefix(6)) { f in
                    Button { app.runFix(f) } label: {
                        HStack(spacing: Theme.space.x2) {
                            SeverityTag(severity: f.severity)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.what).font(VibeFont.mono(VibeFont.size.xs, .medium)).foregroundStyle(Theme.color.textPrimary).lineLimit(1)
                                Text(f.repoName ?? "").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(Theme.space.x2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.color.surface1)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm).strokeBorder(Theme.color.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct RepoInspector: View {
    let repo: Repo
    @Environment(AppState.self) private var app
    var body: some View {
        HStack(spacing: Theme.space.x3) {
            AppEmblem(emblem: repo.emblem, stack: repo.stack, size: 40, live: repo.agent?.state == .active)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name).font(VibeFont.mono(VibeFont.size.md, .semibold)).foregroundStyle(Theme.color.textBright).lineLimit(1)
                StatusBadge(text: repo.isWorkspace ? "workspace" : "\(repo.compliance)% · \(repo.health.rawValue)", tone: repo.health.tone, small: true)
            }
        }
        VibePanel {
            VStack(spacing: 0) {
                MetaRow(key: "stack") { Text(repo.lang.label) }
                MetaRow(key: "branch") { Text(repo.build.branch) }
                MetaRow(key: "worktree") { Text(repo.worktree.clean ? "clean" : "\(repo.worktree.unstaged) dirty").foregroundStyle(repo.worktree.clean ? Theme.color.ok : Theme.color.warn) }
                MetaRow(key: "signed") { Text(repo.worktree.signed ? "yes" : "no").foregroundStyle(repo.worktree.signed ? Theme.color.ok : Theme.color.danger) }
                if let s = repo.serena { MetaRow(key: "serena") { Text("\(s.memories) memories") } }
                MetaRow(key: "build") { Text(repo.build.version).foregroundStyle(Theme.color.info) }
            }
        }
        if let a = repo.agent, a.active {
            VibePanel(title: "live agent", glow: false) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { AgentPulse(active: true, color: Theme.color.warn); Text(a.tool ?? "agent").font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.warn) }
                    Text("\(a.branch ?? "main") · \(a.elapsed ?? "—") · \(a.filesTouched) files")
                        .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted)
                    Text(a.note).font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textSecondary)
                }
            }
        }
        VStack(spacing: Theme.space.x1_5) {
            VibeButton(title: "Open detail", icon: "arrow-right", variant: .secondary, size: .sm, block: true) { app.openRepo(repo.id) }
            if !repo.worktree.clean {
                VibeButton(title: "Commit & push…", icon: "git-commit-horizontal", variant: .accentGhost, size: .sm, block: true) { app.openSheet(.commit) }
            }
        }
    }
}
