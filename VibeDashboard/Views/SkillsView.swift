// SkillsView.swift — fleet skill coverage: stat strip + expandable per-skill panels.

import SwiftUI

private enum SkillsLayout {
    static let chevron: CGFloat = 14
    static let userNameW: CGFloat = 220
    static let installW: CGFloat = 96
    static let statusW: CGFloat = 92
    static let rowH: CGFloat = 40
}

/// Skeleton / lang / tool → the pill tone + glyph.
private func kindTone(_ kind: String) -> VibeTone {
    switch kind {
    case "skeleton": return .policy
    case "lang": return .info
    case "tool": return .ok
    default: return .neutral
    }
}
private func kindIcon(_ kind: String) -> String {
    switch kind {
    case "skeleton": return "layers"
    case "lang": return "code-2"
    case "tool": return "wrench"
    default: return "puzzle"
    }
}

struct SkillsView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    @State private var expanded: Set<String> = []

    var body: some View {
        let skills = store.fleet.skillRollup
        let issueSkills = skills.filter { $0.issues > 0 }.count
        let cleanSkills = skills.count - issueSkills

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                header

                VibePanel(glow: issueSkills == 0, flushBody: true) {
                    let cols = [GridItem(.adaptive(minimum: 150), spacing: 1)]
                    LazyVGrid(columns: cols, spacing: 1) {
                        StatTile(value: "\(skills.count)", label: "skills", tone: .neutral, icon: "blocks")
                        StatTile(value: "\(cleanSkills)", label: "clean", tone: cleanSkills > 0 ? .ok : .neutral, icon: "shield-check")
                        StatTile(value: "\(issueSkills)", label: "with issues", tone: issueSkills > 0 ? .warn : .ok, icon: "triangle-alert")
                    }
                    .background(Theme.color.border)
                }

                if skills.isEmpty {
                    VibePanel { EmptyState(icon: "blocks", text: "no skills installed across the fleet") }
                } else {
                    VStack(spacing: Theme.space.x2_5) {
                        ForEach(skills) { skill in
                            SkillPanel(
                                skill: skill,
                                open: expanded.contains(skill.skillId),
                                toggle: { toggle(skill.skillId) },
                                openRepo: { app.openRepo($0) }
                            )
                        }
                    }
                }
            }
            .padding(Theme.space.x5)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
            Text("Skills")
                .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                .foregroundStyle(Theme.color.textBright)
            Text("skeleton, lang & tool coverage across every repo under \(store.fleet.scanner.root).")
                .font(VibeFont.mono(VibeFont.size.sm))
                .foregroundStyle(Theme.color.textSecondary)
            Text("shown only where a repo RECORDS a skill (VIBE.yaml skills:) or carries the skeleton stamp — never guessed from code. applied-but-unrecorded skills stay invisible until backfilled.")
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

// MARK: - per-skill panel

private struct SkillPanel: View {
    let skill: SkillRollup
    let open: Bool
    var toggle: () -> Void
    var openRepo: (String) -> Void
    @State private var hover = false

    var body: some View {
        VibePanel(flushBody: true) {
            VStack(spacing: 0) {
                headerRow
                if open {
                    VStack(spacing: 0) {
                        userHeader
                        ForEach(skill.users) { user in
                            SkillUserRow(user: user) { openRepo(user.repoId) }
                        }
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: Theme.space.x3) {
            Disclosure(open: open)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.space.x2) {
                    Text(skill.name)
                        .font(VibeFont.mono(VibeFont.size.md, .bold))
                        .foregroundStyle(Theme.color.textPrimary)
                        .lineLimit(1)
                    Pill(text: skill.kind, tone: kindTone(skill.kind), icon: kindIcon(skill.kind))
                }
                Text(skill.owns)
                    .font(VibeFont.sans(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                VibeIcon("git-commit-horizontal", size: 11, color: Theme.color.textGhost)
                Text(skill.latest)
                    .font(VibeFont.mono(VibeFont.size.xs, .medium))
                    .foregroundStyle(Theme.color.textSecondary)
            }

            HStack(spacing: 5) {
                VibeIcon("folder-git-2", size: 12, color: Theme.color.textGhost)
                Text("used by \(skill.count)")
                    .font(VibeFont.mono(VibeFont.size.xs))
                    .foregroundStyle(Theme.color.textMuted)
            }

            if skill.issues > 0 {
                StatusBadge(text: "\(skill.issues) drift", tone: issueTone, small: true)
            } else {
                StatusBadge(text: "in sync", tone: .ok, small: true)
            }
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x3)
        .frame(maxWidth: .infinity)
        .background(hover ? Theme.color.surfaceRaised : .clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: toggle)
    }

    /// worst tone among drifting users → danger if anything is missing.
    private var issueTone: VibeTone {
        skill.users.contains { $0.status == .missing } ? .danger : .warn
    }

    private var userHeader: some View {
        HStack(spacing: Theme.space.x3) {
            Text("repository").frame(maxWidth: .infinity, alignment: .leading)
            Text("installed").frame(width: SkillsLayout.installW, alignment: .leading)
            Text("status").frame(width: SkillsLayout.statusW, alignment: .leading)
            Text("note").frame(width: SkillsLayout.userNameW, alignment: .leading)
        }
        .vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x2)
        .frame(maxWidth: .infinity)
        .background(Theme.color.surface2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.color.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

// MARK: - per-user row

private struct SkillUserRow: View {
    let user: SkillUser
    var onTap: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: Theme.space.x3) {
            HStack(spacing: 8) {
                HealthDot(health: healthOf(user.status), size: 7)
                Text(user.name)
                    .font(VibeFont.mono(VibeFont.size.sm, .medium))
                    .foregroundStyle(Theme.color.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(user.installed ?? "—")
                .font(VibeFont.mono(VibeFont.size.xs))
                .foregroundStyle(user.installed == nil ? Theme.color.textGhost : Theme.color.textSecondary)
                .frame(width: SkillsLayout.installW, alignment: .leading)

            StatusBadge(text: user.status.rawValue, tone: user.status.tone, small: true)
                .frame(width: SkillsLayout.statusW, alignment: .leading)

            HStack(spacing: 7) {
                Text(user.note ?? "—")
                    .font(VibeFont.sans(VibeFont.size.xxs))
                    .foregroundStyle(user.note == nil ? Theme.color.textGhost : Theme.color.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                VibeIcon("chevron-right", size: SkillsLayout.chevron, color: Theme.color.textGhost)
            }
            .frame(width: SkillsLayout.userNameW, alignment: .leading)
        }
        .padding(.horizontal, Theme.space.x4)
        .frame(height: SkillsLayout.rowH)
        .background(hover ? Theme.color.surfaceRaised : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
    }

    private func healthOf(_ s: SkillState) -> Health {
        switch s {
        case .ok: return .ok
        case .missing: return .danger
        default: return .warn
        }
    }
}
