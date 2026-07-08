// RepoTabsCore.swift — the four core repo-detail tabs:
// Overview (identity + meta + compliance), Gates (quality gates + coverage),
// Census (line-count god-files + largest), Policy (VIBE.yaml vs skeleton).

import SwiftUI

// A small layout constant for the tab-page column split.
private enum RepoTabLayout {
    static let metaColumns: CGFloat = 300
}

// MARK: - Overview

struct RepoOverviewTab: View {
    let repo: Repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Overview")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                // Identity header: logo · name · FULL PATH · glanceable badges.
                RepoOverviewHeader(repo: repo)

                if repo.management != .skeleton { ManagementBanner(level: repo.management) }

                // Repository + Compliance first — the most actionable, glanceable state.
                HStack(alignment: .top, spacing: Theme.space.x4) {
                    VibePanel(title: "REPOSITORY") { metaRows }
                        .frame(maxWidth: RepoTabLayout.metaColumns)

                    VStack(alignment: .leading, spacing: Theme.space.x4) {
                        VibePanel(title: "COMPLIANCE", glow: repo.health == .ok) {
                            VStack(alignment: .leading, spacing: Theme.space.x3) {
                                Meter(label: "IN POLICY",
                                      value: Double(repo.compliance),
                                      tone: complianceTone(repo.compliance))
                                StatusBadge(text: "\(repo.compliance)% compliant",
                                            tone: complianceTone(repo.compliance),
                                            solid: true)
                            }
                        }
                        VibePanel(title: "GATES", flushBody: true) { gateStrip }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // The real git change-set, grouped.
                GitStatusPanel(repo: repo)

                // Needs-attention / findings LAST — surfaced, but below the actionable state.
                OverviewAlerts(repo: repo)
            }
            .padding(Theme.space.x5)
        }
    }

    @ViewBuilder private var metaRows: some View {
        VStack(spacing: 0) {
            MetaRow(key: "stack") { Text(repo.lang.label) }
            MetaRow(key: "managed") { ManagedBadge(level: repo.management) }
            MetaRow(key: "lifecycle") { Text(repo.lifecycle) }
            MetaRow(key: "pm") { Text(repo.pm) }
            MetaRow(key: "framework") { Text(repo.framework) }
            MetaRow(key: "branch") { Text(repo.build.branch) }
            MetaRow(key: "worktree") { WorktreeBadge(worktree: repo.worktree) }
            MetaRow(key: "skeleton") { SkeletonBadge(drift: repo.drift) }
            MetaRow(key: "build") { Text(repo.build.version) }
            MetaRow(key: "commit") { Text(repo.build.commit) }
            MetaRow(key: "checked") { Text(RelTime.ago(repo.checkedAt, now: Date())) }
        }
    }

    @ViewBuilder private var gateStrip: some View {
        if repo.gates.isEmpty {
            EmptyState(icon: "shield-check", tone: .neutral, text: "no gates declared")
        } else {
            VStack(spacing: 0) {
                ForEach(repo.gates) { g in
                    GateRow(name: g.name, command: g.command,
                            status: g.status, detail: g.detail, bare: true)
                }
            }
        }
    }
}

// MARK: - Gates

struct RepoGatesTab: View {
    let repo: Repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Gates")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                VibePanel(title: "QUALITY GATES", flushBody: true) {
                    if repo.gates.isEmpty {
                        EmptyState(icon: "shield-check", tone: .neutral,
                                   text: "no quality gates declared in VIBE.yaml")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(repo.gates) { g in
                                GateRow(name: g.name, command: g.command,
                                        status: g.status, detail: g.detail, bare: true)
                            }
                        }
                    }
                }

                if let coverage = repo.coverage {
                    VibePanel(title: "COVERAGE") {
                        Meter(label: "COVERAGE",
                              value: Double(coverage),
                              floor: repo.coverageFloor.map(Double.init),
                              tone: coverageTone(coverage, floor: repo.coverageFloor))
                    }
                }
            }
            .padding(Theme.space.x5)
        }
    }

    private func coverageTone(_ v: Int, floor: Int?) -> VibeTone {
        guard let f = floor else { return .info }
        return v >= f ? .ok : .danger
    }
}

// MARK: - Census

struct RepoCensusTab: View {
    @Environment(AppState.self) private var app
    let repo: Repo

    /// Right-click → exclude this file from architecture scope (confirm-gated write).
    @ViewBuilder private func excludeMenu(_ path: String) -> some View {
        if repo.vibePresent {
            Button("Exclude from architecture scope") { app.requestExclude(repoId: repo.id, path: path) }
        } else {
            Text("no VIBE.yaml to edit")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Census")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                HStack(spacing: Theme.space.x2) {
                    Text("\(repo.census.scanned) files scanned")
                        .font(VibeFont.mono(VibeFont.size.sm))
                        .foregroundStyle(Theme.color.textSecondary)
                    if repo.census.softCount > 0 {
                        Pill(text: "\(repo.census.softCount) over soft", tone: .warn)
                    }
                }

                VibePanel(title: "GOD FILES · 250 SOFT / 400 HARD") {
                    if repo.census.godFiles.isEmpty {
                        EmptyState(icon: "check", tone: .ok,
                                   text: "no god-files. every file under the 400-line limit.")
                    } else {
                        VStack(alignment: .leading, spacing: Theme.space.x3) {
                            ForEach(repo.census.godFiles) { f in
                                fileBar(f)
                            }
                        }
                    }
                }

                if !repo.census.excludedGodFiles.isEmpty {
                    VibePanel(title: "EXCLUDED FROM GRADING · \(repo.census.excludedGodFiles.count)") {
                        VStack(alignment: .leading, spacing: Theme.space.x3) {
                            Text("Over the 400-line hard limit but matched by architecture.exclude_globs — shown for visibility, not counted against this repo's grade.")
                                .font(VibeFont.sans(VibeFont.size.xs))
                                .foregroundStyle(Theme.color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(repo.census.excludedGodFiles) { f in
                                fileBar(f)
                            }
                        }
                    }
                }

                if !repo.census.largest.isEmpty {
                    VibePanel(title: "LARGEST FILES", flushBody: true) {
                        VStack(spacing: 0) {
                            ForEach(repo.census.largest) { f in
                                MetaRow(key: f.path) {
                                    HStack(spacing: Theme.space.x2) {
                                        if f.excluded { Pill(text: "excluded", tone: .neutral) }
                                        Text("\(f.lines) ln")
                                            .foregroundStyle(f.excluded ? Theme.color.textFaint : largestTone(f.lines))
                                    }
                                }
                                .contextMenu { excludeMenu(f.path) }
                            }
                        }
                        .padding(.horizontal, Theme.space.x4)
                    }
                }
            }
            .padding(Theme.space.x5)
        }
    }

    @ViewBuilder private func fileBar(_ f: FileLines) -> some View {
        VStack(alignment: .leading, spacing: Theme.space.x1) {
            HStack(spacing: Theme.space.x2) {
                Text(f.path)
                    .font(VibeFont.mono(VibeFont.size.xs, .medium))
                    .foregroundStyle(f.excluded ? Theme.color.textSecondary : Theme.color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if f.excluded { Pill(text: "excluded", tone: .neutral) }
            }
            LimitBar(value: Double(f.lines), soft: 250, hard: 400, unit: " ln")
        }
        .contentShape(Rectangle())
        .contextMenu { excludeMenu(f.path) }
    }

    private func largestTone(_ lines: Int) -> Color {
        if lines > 400 { return Theme.color.danger }
        if lines > 250 { return Theme.color.warn }
        return Theme.color.textPrimary
    }
}

// MARK: - Policy

struct RepoPolicyTab: View {
    let repo: Repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Policy")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                if repo.policy.isEmpty {
                    VibePanel {
                        EmptyState(icon: "file-code-2", tone: .neutral,
                                   text: "no VIBE.yaml on disk")
                    }
                } else {
                    ForEach(repo.policy) { section in
                        VibePanel(title: section.section.uppercased(), flushBody: true) {
                            VStack(spacing: 0) {
                                ForEach(section.rows) { row in
                                    PolicyRowView(row: row)
                                }
                            }
                            .padding(.horizontal, Theme.space.x4)
                        }
                    }
                }
            }
            .padding(Theme.space.x5)
        }
    }
}

/// One VIBE.yaml `key … value` line, with delta/invalid annotation. Array-valued
/// keys (exclude_globs, scope_globs…) collapse to a count and expand to the full
/// list on click — nothing is silently hidden behind a "+N".
private struct PolicyRowView: View {
    let row: PolicyRow
    @State private var expanded = false

    var body: some View {
        if let values = row.values {
            VStack(alignment: .leading, spacing: 0) {
                MetaRow(key: row.k) {
                    Button { withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() } } label: {
                        HStack(spacing: Theme.space.x1_5) {
                            Text("\(values.count) items").foregroundStyle(Theme.color.textPrimary)
                            VibeIcon(expanded ? "chevron-up" : "chevron-down", size: 11, color: Theme.color.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if expanded {
                    VStack(alignment: .leading, spacing: Theme.space.x1) {
                        ForEach(Array(values.enumerated()), id: \.offset) { _, val in
                            Text(val)
                                .font(VibeFont.mono(VibeFont.size.xs))
                                .foregroundStyle(Theme.color.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, Theme.space.x2)
                }
            }
        } else {
            MetaRow(key: row.k) { valueView }
        }
    }

    @ViewBuilder private var valueView: some View {
        switch row.note {
        case "delta":
            HStack(spacing: Theme.space.x2) {
                Text(row.v).foregroundStyle(Theme.color.accent)
                if let skel = row.skel {
                    Text(skel)
                        .foregroundStyle(Theme.color.textFaint)
                        .strikethrough(true, color: Theme.color.textGhost)
                }
                Pill(text: "delta", tone: .policy)
            }
        case "invalid":
            HStack(spacing: Theme.space.x2) {
                Text(row.v).foregroundStyle(Theme.color.danger)
                Pill(text: "invalid", tone: .danger)
            }
        default:
            Text(row.v)
        }
    }
}
