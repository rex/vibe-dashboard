// RepoDetailView.swift — the repo-detail shell: tab bar + tab routing.

import SwiftUI

enum RepoTab: String, CaseIterable, Hashable {
    case overview = "Overview", gates = "Gates", policy = "Policy", census = "Census"
    case build = "Build & Ship", agent = "Agent", hooks = "Hooks & MCP", findings = "Findings"

    var icon: String {
        switch self {
        case .overview: return "info"
        case .gates: return "shield-check"
        case .policy: return "file-code-2"
        case .census: return "list-tree"
        case .build: return "hammer"
        case .agent: return "bot"
        case .hooks: return "plug"
        case .findings: return "triangle-alert"
        }
    }
}

struct RepoDetailView: View {
    let repo: Repo
    @State private var tab: RepoTab = .overview

    private var tabs: [SegOption<RepoTab>] {
        RepoTab.allCases.map { t in
            SegOption(value: t, label: t.rawValue, icon: t.icon,
                      count: t == .findings && !repo.surprises.isEmpty ? repo.surprises.count : nil)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VibeTabs(selection: $tab, options: tabs)
                    .padding(.horizontal, Theme.space.x5)
            }
            .padding(.top, Theme.space.x3)
            .background(Theme.color.bgApp)

            Group {
                switch tab {
                case .overview: RepoOverviewTab(repo: repo)
                case .gates: RepoGatesTab(repo: repo)
                case .policy: RepoPolicyTab(repo: repo)
                case .census: RepoCensusTab(repo: repo)
                case .build: RepoBuildTab(repo: repo)
                case .agent: RepoAgentTab(repo: repo)
                case .hooks: RepoHooksTab(repo: repo)
                case .findings: RepoFindingsTab(repo: repo)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The repo's own findings, using the shared FindingsTable.
private struct RepoFindingsTab: View {
    let repo: Repo
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Findings").font(VibeFont.sans(VibeFont.size.xl, .semibold)).foregroundStyle(Theme.color.textBright)
                if repo.surprises.isEmpty {
                    VibePanel { EmptyState(icon: "check", tone: .ok, text: "no surprises. in policy. worktree clean.") }
                } else {
                    FindingsTable(findings: repo.surprises.map { var f = $0; f.repoId = repo.id; f.repoName = repo.name; return f })
                }
            }
            .padding(Theme.space.x5)
        }
    }
}
