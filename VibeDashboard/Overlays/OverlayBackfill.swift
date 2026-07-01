// OverlayBackfill.swift — the human-gated "backfill skills from transcripts" sheet.
// Evidence (a real /lang-*//tool-* execution in a repo) → your confirmation →
// a verified VIBE.yaml skills: entry. Only EXACT repo matches are offered; the
// writes go through VibeYamlEditor (backed-up, re-parsed, atomic).

import SwiftUI

private struct BackfillMatch: Identifiable {
    let ev: SkillEvidence
    let repo: Repo
    var id: String { ev.id }
}

struct BackfillSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    @State private var evidence: [SkillEvidence] = []
    @State private var loading = true
    @State private var done: Set<String> = []

    /// Evidence whose cwd exactly matches a managed repo that doesn't already
    /// record the skill — the only cases safe to offer as one-click records.
    private var matches: [BackfillMatch] {
        evidence.compactMap { e in
            guard !done.contains(e.id),
                  let repo = store.fleet.leaves.first(where: { $0.absolutePath == e.repoPath }),
                  !repo.skills.contains(where: { $0.skillId == e.skillId }) else { return nil }
            return BackfillMatch(ev: e, repo: repo)
        }
        .sorted { $0.repo.name == $1.repo.name ? $0.ev.skillId < $1.ev.skillId : $0.repo.name < $1.repo.name }
    }
    private var ambiguous: Int {
        evidence.filter { e in !store.fleet.leaves.contains { $0.absolutePath == e.repoPath } }.count
    }

    var body: some View {
        SheetShell(title: "Backfill skills from transcripts", icon: "history",
                   width: OverlayLayout.sheetW, confirm: "Done", confirmIcon: "check") {
            app.closeSheet()
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                SheetProse(text: "where a /lang- or /tool- skill was actually RUN in a repo that doesn't record it yet. "
                    + "recording writes a verified, backed-up entry to that repo's VIBE.yaml skills: block. "
                    + "evidence, not proof — only exact repo matches are shown.")
                if loading {
                    HStack(spacing: Theme.space.x2) {
                        ProgressView().controlSize(.small)
                        Text("scanning ~/.claude transcripts…")
                            .font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, Theme.space.x4)
                } else if matches.isEmpty {
                    EmptyState(icon: "check", tone: .ok, text: "no unrecorded skill evidence to backfill")
                } else {
                    FileCard(caption: "found · \(matches.count)") {
                        ForEach(matches) { m in
                            BackfillRow(match: m, version: TranscriptProbe.installedVersion(m.ev.skillId)) {
                                record(m)
                            }
                        }
                    }
                }
                if ambiguous > 0 {
                    Text("\(ambiguous) event(s) at workspace roots / non-managed paths skipped as ambiguous — record those by hand.")
                        .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task {
            evidence = await TranscriptProbe.scan()
            loading = false
        }
    }

    private func record(_ m: BackfillMatch) {
        let vibePath = (m.repo.absolutePath as NSString).expandingTildeInPath + "/VIBE.yaml"
        let id = m.ev.skillId, applied = m.ev.lastSeen, name = m.repo.name
        let version = TranscriptProbe.installedVersion(id)
        Task { @MainActor in
            let result = await Task.detached {
                VibeYamlEditor.recordSkill(vibePath: vibePath, id: id, version: version, applied: applied)
            }.value
            switch result {
            case .skillRecorded(let rid):
                done.insert(m.ev.id)
                app.toast("recorded \(rid)", "\(name) · VIBE.yaml skills: + \(version ?? "no version")", .ok)
                await store.rescan()
            case .alreadyRecorded:
                done.insert(m.ev.id); app.toast("already recorded", "\(id) already in \(name)", .info)
            case .noVibe: app.toast("no VIBE.yaml", "\(name) has no policy file to edit", .warn)
            case .parseError: app.toast("VIBE.yaml won't parse", "refusing to edit \(name)", .danger)
            case .unsafe(let why): app.toast("left untouched", why, .danger)
            default: break
            }
        }
    }
}

private struct BackfillRow: View {
    let match: BackfillMatch
    let version: String?
    var onRecord: () -> Void

    var body: some View {
        HStack(spacing: Theme.space.x3) {
            VibeIcon("blocks", size: 14, color: Theme.color.info)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.space.x2) {
                    Text(match.ev.skillId)
                        .font(VibeFont.mono(VibeFont.size.sm, .medium)).foregroundStyle(Theme.color.textPrimary)
                    Text("→ \(version ?? "no version")")
                        .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                }
                Text("\(match.repo.name) · last run \(match.ev.lastSeen) · via \(match.ev.source)")
                    .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VibeButton(title: "Record", icon: "check", variant: .accentGhost, size: .sm, action: onRecord)
                .fixedSize()
        }
        .padding(.horizontal, 11).padding(.vertical, Theme.space.x2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}
