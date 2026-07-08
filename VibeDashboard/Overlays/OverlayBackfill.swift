// OverlayBackfill.swift — human-gated "backfill skills from transcripts" sheet.
// Evidence (a real /lang-*//tool-* execution, from on-disk transcripts and/or the
// AgentsView index) → your confirmation → a verified VIBE.yaml skills: entry.
//
// Exact repo matches are one-click. A skill run from a WORKSPACE ROOT was applied
// to some child repo the session cwd can't name, so those expand into the
// workspace's children (each shown with its stack) and you record per-child.

import SwiftUI

private struct ExactMatch: Identifiable {
    let ev: SkillEvidence; let repo: Repo
    var id: String { ev.id + "|" + repo.id }
}
private struct WSGroup: Identifiable {
    let ev: SkillEvidence; let label: String; let children: [Repo]
    var id: String { "ws·" + ev.id }
}

struct BackfillSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    @State private var evidence: [SkillEvidence] = []
    @State private var loading = true
    @State private var unparsed = 0                     // Skill lines that matched but wouldn't parse
    @State private var agentsViewError: String?   // non-nil ⇒ AgentsView query/DB error
    @State private var done: Set<String> = []   // "evidenceId|repoId" recorded this session

    private func recordedNow(_ repo: Repo, _ e: SkillEvidence) -> Bool {
        repo.skills.contains { $0.skillId == e.skillId } || done.contains(e.id + "|" + repo.id)
    }

    /// Split evidence into one-click exact matches and workspace-root groups.
    /// BOTH the evidence cwd and each repo's absolutePath are normalized (tilde,
    /// symlink, trailing slash) before comparison — a raw string compare drops a
    /// `~/Code/foo`, `/Users/…/foo/`, or `/private`-symlinked cwd as non-managed,
    /// hiding real applied-skill evidence from the backfill entirely.
    private func classify() -> (exacts: [ExactMatch], groups: [WSGroup]) {
        let normLeaves = store.fleet.leaves.map { (repo: $0, norm: TranscriptProbe.normalizedPath($0.absolutePath)) }
        var exacts: [ExactMatch] = []
        var groups: [WSGroup] = []
        for e in evidence.sorted(by: { $0.repoPath < $1.repoPath }) {
            let repoN = TranscriptProbe.normalizedPath(e.repoPath)
            if let leaf = normLeaves.first(where: { $0.norm == repoN })?.repo {
                if !recordedNow(leaf, e) { exacts.append(ExactMatch(ev: e, repo: leaf)) }
            } else {
                let kids = normLeaves.filter { $0.norm.hasPrefix(repoN + "/") && !recordedNow($0.repo, e) }.map { $0.repo }
                if !kids.isEmpty {
                    let label = store.fleet.workspaces.first { TranscriptProbe.normalizedPath($0.absolutePath) == repoN }?.name
                        ?? (repoN as NSString).lastPathComponent
                    groups.append(WSGroup(ev: e, label: label, children: kids))
                }
            }
        }
        return (exacts, groups)
    }
    private var ambiguous: Int {
        let normLeaves = store.fleet.leaves.map { TranscriptProbe.normalizedPath($0.absolutePath) }
        return evidence.filter { e in
            let repoN = TranscriptProbe.normalizedPath(e.repoPath)
            return !normLeaves.contains { $0 == repoN || $0.hasPrefix(repoN + "/") }
        }.count
    }
    private func versionSuffix(_ id: String) -> String {
        TranscriptProbe.installedVersion(id).map { "@\($0)" } ?? ""
    }
    private func exactSubtitle(_ m: ExactMatch) -> String {
        "\(m.repo.name) · \(m.repo.lang.label) · \(m.ev.lastSeen) · via \(m.ev.source)"
    }
    private func groupCaption(_ g: WSGroup) -> String {
        "\(g.ev.skillId)\(versionSuffix(g.ev.skillId)) · ran at \(g.label) root — pick the repo(s) that got it"
    }
    private func childSubtitle(_ g: WSGroup, _ child: Repo) -> String {
        "\(child.lang.label) · via \(g.ev.source) \(g.ev.lastSeen)"
    }

    var body: some View {
        let c = classify()
        return SheetShell(title: "Backfill skills from transcripts", icon: "history",
                          width: OverlayLayout.sheetW, confirm: "Done", confirmIcon: "check") {
            app.closeSheet()
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                SheetProse(text: "where a skeleton skill (/lang-, /tool-, /agentic-, scaffold, retrofit) "
                    + "was actually RUN (on-disk transcripts + AgentsView). "
                    + "exact repo matches are one-click; a skill run from a workspace root lets you pick the child repo(s) that got it. "
                    + "each records a verified, backed-up entry into that repo's VIBE.yaml skills:.")
                if loading {
                    loadingRow
                } else if c.exacts.isEmpty && c.groups.isEmpty {
                    EmptyState(icon: "check", tone: .ok, text: "no unrecorded skill evidence to backfill")
                } else {
                    VStack(spacing: Theme.space.x2_5) {
                        if !c.exacts.isEmpty {
                            FileCard(caption: "exact matches · \(c.exacts.count)") {
                                ForEach(c.exacts) { m in
                                    BackfillRow(title: m.ev.skillId, subtitle: exactSubtitle(m),
                                                version: TranscriptProbe.installedVersion(m.ev.skillId)) { record(m.ev, m.repo) }
                                }
                            }
                        }
                        ForEach(c.groups) { g in
                            FileCard(caption: groupCaption(g)) {
                                ForEach(g.children) { child in
                                    BackfillRow(title: child.name, subtitle: childSubtitle(g, child)) { record(g.ev, child) }
                                }
                            }
                        }
                    }
                }
                if ambiguous > 0 {
                    Text("\(ambiguous) event(s) at non-managed paths skipped.")
                        .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                }
                if unparsed > 0 {
                    Text("\(unparsed) transcript line(s) matched but couldn't be parsed — possible schema drift.")
                        .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                }
                if let agentsViewError {
                    Text("AgentsView index unavailable: \(agentsViewError)")
                        .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textMuted).lineLimit(2)
                }
            }
        }
        .task {
            let result = await TranscriptProbe.scan()
            evidence = result.evidence
            unparsed = result.unparsedSkillLines
            agentsViewError = result.agentsViewError
            loading = false
        }
    }

    private var loadingRow: some View {
        HStack(spacing: Theme.space.x2) {
            ProgressView().controlSize(.small)
            Text("scanning transcripts + AgentsView index…")
                .font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, Theme.space.x4)
    }

    private func record(_ e: SkillEvidence, _ repo: Repo) {
        let vibePath = (repo.absolutePath as NSString).expandingTildeInPath + "/VIBE.yaml"
        let id = e.skillId, applied = e.lastSeen, name = repo.name, mark = e.id + "|" + repo.id
        let version = TranscriptProbe.installedVersion(id)
        Task { @MainActor in
            let result = await Task.detached {
                VibeYamlEditor.recordSkill(vibePath: vibePath, id: id, version: version, applied: applied)
            }.value
            switch result {
            case .skillRecorded(let rid):
                done.insert(mark)
                app.toast("recorded \(rid)", "\(name) · VIBE.yaml skills: + \(version ?? "no version")", .ok)
                await store.rescan()
            case .alreadyRecorded:
                done.insert(mark); app.toast("already recorded", "\(id) already in \(name)", .info)
            case .noVibe: app.toast("no VIBE.yaml", "\(name) has no policy file to edit", .warn)
            case .parseError: app.toast("VIBE.yaml won't parse", "refusing to edit \(name)", .danger)
            case .unsafe(let why): app.toast("left untouched", why, .danger)
            default: break
            }
        }
    }
}

private struct BackfillRow: View {
    let title: String
    let subtitle: String
    var version: String?
    var onRecord: () -> Void

    var body: some View {
        HStack(spacing: Theme.space.x3) {
            VibeIcon("blocks", size: 14, color: Theme.color.info)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.space.x2) {
                    Text(title)
                        .font(VibeFont.mono(VibeFont.size.sm, .medium)).foregroundStyle(Theme.color.textPrimary)
                    if let version {
                        Text("→ \(version)")
                            .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
                    }
                }
                Text(subtitle)
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
