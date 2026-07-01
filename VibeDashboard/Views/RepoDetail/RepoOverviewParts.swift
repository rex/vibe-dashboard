// RepoOverviewParts.swift — prominent overview surfacing: a management banner and
// a "needs attention" strip that pulls the worst findings up top, so a 46-file
// dirty tree can't hide halfway down the Build & Ship tab.

import SwiftUI

/// A full-width strip shown when a repo is NOT fully skeleton-governed — the
/// single most important thing this app exists to make impossible to miss.
struct ManagementBanner: View {
    let level: ManagementLevel

    var body: some View {
        HStack(spacing: Theme.space.x3) {
            VibeIcon(level == .unmanaged ? "triangle-alert" : "circle-slash",
                     size: 18, color: Theme.color.tone(level.tone))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VibeFont.mono(VibeFont.size.md, .bold))
                    .foregroundStyle(Theme.color.tone(level.tone))
                Text(subtitle)
                    .font(VibeFont.sans(VibeFont.size.xs))
                    .foregroundStyle(Theme.color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.space.x2)
            StatusBadge(text: level.label, tone: level.tone, solid: true)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.toneSurface(level.tone))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md)
            .strokeBorder(Theme.color.tone(level.tone).opacity(0.55), lineWidth: 1))
    }

    private var title: String {
        switch level {
        case .unmanaged: return "UNMANAGED — no VIBE.yaml governs this repo"
        case .partial: return "PARTIAL — policy present, but no Makefile to enforce it"
        case .skeleton: return ""
        }
    }
    private var subtitle: String {
        switch level {
        case .unmanaged: return "An agent has worked here with no policy and no gates. Scaffold it or retire it."
        case .partial: return "VIBE.yaml declares rules nothing can run. Gate results below are not trustworthy."
        case .skeleton: return ""
        }
    }
}

/// The worst findings, pulled to the top of the Overview. Only shows when there
/// is something real to show — you're on this repo's page on purpose, so this is
/// surfacing, not fatigue.
struct OverviewAlerts: View {
    let repo: Repo

    private var top: [Finding] {
        Array(repo.surprises.sorted { $0.severity < $1.severity }.prefix(6))
            .map { var f = $0; f.repoId = repo.id; f.repoName = nil; return f }
    }
    private var worst: Severity? { repo.surprises.map(\.severity).min() }

    var body: some View {
        if !top.isEmpty {
            VibePanel(title: titleText, flushBody: true) {
                FindingsTable(findings: top)
                if repo.surprises.count > top.count {
                    Text("+ \(repo.surprises.count - top.count) more in the Findings tab")
                        .font(VibeFont.mono(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.space.x4)
                        .padding(.vertical, Theme.space.x2_5)
                }
            }
        }
    }

    private var titleText: String {
        let n = repo.surprises.count
        switch worst {
        case .high: return "NEEDS ATTENTION · \(n)"
        case .med: return "REVIEW · \(n)"
        default: return "MINOR · \(n)"
        }
    }
}

// MARK: - compact overview badges

struct ManagedBadge: View {
    let level: ManagementLevel
    var body: some View { StatusBadge(text: level.label, tone: level.tone, small: true) }
}

struct WorktreeBadge: View {
    let worktree: WorktreeState
    var body: some View {
        if worktree.clean && worktree.unpushed == 0 {
            Text("clean").foregroundStyle(Theme.color.ok)
        } else {
            HStack(spacing: Theme.space.x2) {
                if !worktree.clean {
                    StatusBadge(text: "\(worktree.unstaged) uncommitted", tone: .danger, small: true)
                }
                if worktree.unpushed > 0 {
                    StatusBadge(text: "\(worktree.unpushed) unpushed", tone: .danger, small: true)
                }
            }
        }
    }
}

struct SkeletonBadge: View {
    let drift: Drift
    var body: some View {
        HStack(spacing: Theme.space.x2) {
            Text(drift.version ?? "unstamped")
                .foregroundStyle(drift.version == nil ? Theme.color.textFaint : Theme.color.textPrimary)
            if let behind = drift.behind {
                StatusBadge(text: behind, tone: .warn, small: true)
            }
        }
    }
}
