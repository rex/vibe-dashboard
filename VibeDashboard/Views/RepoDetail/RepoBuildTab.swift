// RepoBuildTab.swift — Build & Ship: Makefile targets, SCM, CI, containers.

import SwiftUI

/// Tiny layout constants local to this tab (everything else flows through Theme).
private enum BuildCol {
    static let grade: CGFloat = 24
    static let runBtn: CGFloat = 30
    static let icon: CGFloat = 14
}

struct RepoBuildTab: View {
    let repo: Repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Build & Ship")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                MakefilePanel(repo: repo)
                ScmPanel(scm: repo.scm)
                CiPanel(ci: repo.ci)
                ContainersPanel(containers: repo.containers)
            }
            .padding(Theme.space.x5)
        }
    }
}

// MARK: - Panel 1 · Makefile ---------------------------------------------------

private struct MakefilePanel: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    let repo: Repo

    private var groups: [(kind: TargetKind, label: String, items: [MakeTarget])] {
        [(.gate, "gate", targets(.gate)),
         (.run, "run", targets(.run)),
         (.util, "util", targets(.util))]
            .filter { !$0.items.isEmpty }
    }
    private func targets(_ k: TargetKind) -> [MakeTarget] {
        repo.makefile.targets.filter { $0.kind == k }
    }

    var body: some View {
        VibePanel(title: "makefile", icon: "hammer", flushBody: true) {
            if repo.makefile.targets.isEmpty {
                EmptyState(icon: "circle-slash", tone: .neutral, text: "no makefile targets detected")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.kind) { idx, group in
                        GroupHeader(label: group.label, count: group.items.count, first: idx == 0)
                        ForEach(group.items) { target in
                            TargetRow(repo: repo, target: target) {
                                app.runTarget(repo, target.name, host: store.fleet.scanner.host)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct GroupHeader: View {
    let label: String
    let count: Int
    let first: Bool
    var body: some View {
        HStack(spacing: Theme.space.x2) {
            Text(label).vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textFaint)
            Text("\(count)").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textGhost)
            Spacer()
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.top, first ? Theme.space.x3 : Theme.space.x4)
        .padding(.bottom, Theme.space.x2)
    }
}

private struct TargetRow: View {
    let repo: Repo
    let target: MakeTarget
    var run: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: Theme.space.x3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(target.name)
                    .font(VibeFont.mono(VibeFont.size.sm, .medium))
                    .foregroundStyle(Theme.color.textPrimary)
                    .lineLimit(1)
                if !target.desc.isEmpty {
                    Text(target.desc)
                        .font(VibeFont.sans(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VibeButton(title: "", icon: "play", variant: .ghost, size: .sm, action: run)
                .frame(width: BuildCol.runBtn)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x2)
        .background(hover ? Theme.color.surfaceRaised : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

// MARK: - Panel 2 · SCM ---------------------------------------------------------

private struct ScmPanel: View {
    let scm: Scm

    var body: some View {
        VibePanel(flushBody: true) {
            PanelHeaderRow(icon: "git-branch", title: "scm", grade: scm.grade) {
                Text(scm.branch)
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if scm.remotes.isEmpty {
                    EmptyState(icon: "circle-slash", tone: .neutral, text: "no remotes configured")
                } else {
                    ForEach(scm.remotes) { RemoteRow(remote: $0) }
                }
                NoteList(notes: scm.notes)
            }
        }
    }
}

private struct RemoteRow: View {
    let remote: Remote
    var body: some View {
        HStack(spacing: Theme.space.x3) {
            RemoteIcon(host: remote.host, size: BuildCol.icon)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.space.x1_5) {
                    Text(remote.name)
                        .font(VibeFont.mono(VibeFont.size.sm, .medium))
                        .foregroundStyle(Theme.color.textPrimary)
                    if remote.primary { Pill(text: "primary", tone: .ok) }
                    if remote.mirror { Pill(text: "mirror", tone: .neutral) }
                }
                Text(remote.url)
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AheadBehind(ahead: remote.ahead, behind: remote.behind)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x2_5)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

private struct AheadBehind: View {
    let ahead: Int
    let behind: Int
    var body: some View {
        HStack(spacing: Theme.space.x2) {
            if ahead == 0 && behind == 0 {
                Text("in sync").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
            } else {
                if ahead > 0 {
                    HStack(spacing: 2) {
                        VibeIcon("arrow-up", size: 10, color: Theme.color.ok)
                        Text("\(ahead)").font(VibeFont.mono(VibeFont.size.xxs, .medium)).foregroundStyle(Theme.color.ok)
                    }
                }
                if behind > 0 {
                    HStack(spacing: 2) {
                        VibeIcon("arrow-down", size: 10, color: Theme.color.warn)
                        Text("\(behind)").font(VibeFont.mono(VibeFont.size.xxs, .medium)).foregroundStyle(Theme.color.warn)
                    }
                }
            }
        }
    }
}

// MARK: - Panel 3 · CI ----------------------------------------------------------

private struct CiPanel: View {
    let ci: CiInfo

    var body: some View {
        VibePanel(flushBody: true) {
            PanelHeaderRow(icon: "git-merge", title: "ci", grade: ci.grade) {
                Text(ci.provider)
                    .font(VibeFont.mono(VibeFont.size.xxs, .medium))
                    .foregroundStyle(Theme.color.textSecondary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if !ci.configured || ci.workflows.isEmpty {
                    EmptyState(icon: "circle-slash", tone: .neutral, text: "ci not configured")
                } else {
                    ForEach(ci.workflows) { WorkflowRow(workflow: $0) }
                }
                NoteList(notes: ci.notes)
            }
        }
    }
}

private struct WorkflowRow: View {
    let workflow: CiWorkflow
    var body: some View {
        HStack(spacing: Theme.space.x3) {
            Image(systemName: workflow.status.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.color.tone(workflow.status.tone))
                .frame(width: 16, height: 16)
                .background(Theme.color.toneSurface(workflow.status.tone))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs))

            VStack(alignment: .leading, spacing: 1) {
                Text(workflow.name)
                    .font(VibeFont.mono(VibeFont.size.sm, .medium))
                    .foregroundStyle(Theme.color.textPrimary)
                    .lineLimit(1)
                Text(workflow.trigger)
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(workflow.last)
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textFaint)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x2_5)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

// MARK: - Panel 4 · Containers --------------------------------------------------

private struct ContainersPanel: View {
    let containers: Containers

    var body: some View {
        VibePanel(flushBody: true) {
            PanelHeaderRow(icon: "container", title: "containers", grade: containers.grade) {
                EmptyView()
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if !containers.configured || containers.items.isEmpty {
                    EmptyState(icon: "circle-slash", tone: .neutral, text: "no containers configured")
                } else {
                    ForEach(containers.items) { ContainerRow(item: $0) }
                }
                NoteList(notes: containers.notes)
            }
        }
    }
}

private struct ContainerRow: View {
    let item: ContainerItem
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x2) {
            HStack(spacing: Theme.space.x2) {
                VibeTag(text: item.kind, tone: .neutral, uppercase: true)
                Text(item.path)
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Theme.space.x2)
                GradeChip(grade: item.grade, size: BuildCol.grade)
            }
            VStack(alignment: .leading, spacing: Theme.space.x1_5) {
                ForEach(item.checks) { CheckRow(check: $0) }
            }
            .padding(.leading, Theme.space.x0_5)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x3)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

private struct CheckRow: View {
    let check: CheckItem
    var body: some View {
        HStack(spacing: Theme.space.x2) {
            VibeIcon(check.ok ? "check" : "x", size: 11,
                     color: check.ok ? Theme.color.ok : Theme.color.danger)
                .frame(width: 12)
            Text(check.text)
                .font(VibeFont.mono(VibeFont.size.xs))
                .foregroundStyle(check.ok ? Theme.color.textSecondary : Theme.color.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - Shared panel bits -----------------------------------------------------

/// A panel header carrying an icon + title on the left and a GradeChip on the
/// right, with an optional trailing accessory (branch, provider, …).
private struct PanelHeaderRow<Accessory: View>: View {
    let icon: String
    let title: String
    let grade: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Theme.space.x2) {
            VibeIcon(icon, size: 13, color: Theme.color.textSecondary)
            Text(title).vibeMicroLabel(VibeFont.size.xs, color: Theme.color.textSecondary)
            Spacer(minLength: Theme.space.x2)
            accessory()
            GradeChip(grade: grade)
        }
    }
}

/// Tinted note lines (Note.tone), shown under a panel's rows.
private struct NoteList: View {
    let notes: [Note]
    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.space.x1_5) {
                ForEach(notes) { note in
                    HStack(alignment: .top, spacing: Theme.space.x2) {
                        Circle().fill(Theme.color.tone(note.tone)).frame(width: 5, height: 5)
                            .padding(.top, 5)
                        Text(note.text)
                            .font(VibeFont.mono(VibeFont.size.xxs))
                            .foregroundStyle(note.tone == .neutral ? Theme.color.textMuted : Theme.color.tone(note.tone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.space.x4)
            .padding(.vertical, Theme.space.x3)
            .background(Theme.color.surfaceSunken)
        }
    }
}
