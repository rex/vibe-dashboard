// CommitSheet.swift — the commit + push write sheet. Real changed paths are read
// live from `git status --porcelain` at open; the confirm fires git add · commit ·
// push through AppState.runGit. Split out of OverlaySheets.swift; module-internal,
// rendered by OverlayHost via the shared SheetShell.

import SwiftUI

struct CommitSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    let repo: Repo
    @State private var sign = true
    @State private var message = ""
    /// The REAL changed paths, read live from `git status --porcelain` at open —
    /// nil while loading. No fabricated `max(1, unstaged)` placeholder rows.
    @State private var changed: [String]?

    private var branch: String { repo.build.branch }
    private var files: [String] { changed ?? [] }
    private var canCommit: Bool { GitWrite.isCommittable(message) && !files.isEmpty }

    var body: some View {
        SheetShell(title: "Commit · \(repo.name)", icon: "git-commit-horizontal",
                   width: OverlayLayout.sheetW, confirm: "Commit & push", confirmIcon: "git-commit-horizontal",
                   confirmDisabled: !canCommit, onConfirm: perform) {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                HStack(spacing: Theme.space.x2_5) {
                    VibeIcon("git-branch", size: 14, color: Theme.color.textMuted)
                    Text("on ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary)
                    + Text(branch).font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.textPrimary)
                    if !repo.worktree.signed { Pill(text: "commits unsigned", tone: .danger) }
                }
                changedCard
                VibeTextField(placeholder: "commit message — one logical step…", text: $message, onSubmit: perform)
                Button { sign.toggle() } label: {
                    HStack(spacing: Theme.space.x2_5) {
                        VibeSwitch(isOn: $sign)
                        Text("sign commit ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textPrimary)
                        + Text(repo.signedRequired ? "· signed_commits_required is true" : "· uses -S (recommended)")
                            .font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textMuted)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .task {
            let abs = (repo.absolutePath as NSString).expandingTildeInPath
            let r = await ProcessRunner.git(["status", "--porcelain"], cwd: abs)
            changed = r.stdout
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0.dropFirst(3)) }
                .filter { !$0.isEmpty }
        }
    }

    @ViewBuilder private var changedCard: some View {
        if changed == nil {
            FileCard(caption: "reading working tree…") {
                FileRow(icon: "refresh-cw", path: "git status --porcelain", tone: .neutral) { EmptyView() }
            }
        } else if files.isEmpty {
            FileCard(caption: "changed · 0") {
                FileRow(icon: "check", path: "working tree clean — nothing to commit", tone: .ok) { EmptyView() }
            }
        } else {
            FileCard(caption: "changed · \(files.count)") {
                ForEach(files.prefix(40), id: \.self) { p in
                    FileRow(icon: "file-pen", path: p, tone: .warn) { EmptyView() }
                }
                if files.count > 40 {
                    FileRow(icon: "more-horizontal", path: "+ \(files.count - 40) more", tone: .neutral) { EmptyView() }
                }
            }
        }
    }

    private func perform() {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = files
        guard GitWrite.isCommittable(msg), !paths.isEmpty else { return }
        app.closeSheet()
        let r = repo, host = store.fleet.scanner.host, signed = sign, n = paths.count, br = branch
        let steps: [(label: String, args: [String])] = [
            ("add", GitWrite.addAllArgs),
            ("commit", GitWrite.commitArgs(message: msg, sign: signed)),
            ("push", GitWrite.pushArgs),
        ]
        Task { @MainActor in
            let ok = await app.runGit(r, host: host, steps: steps, okTitle: "committed + pushed",
                                      okDetail: "\(n) file\(n == 1 ? "" : "s") → \(br)\(signed ? " · signed" : " · UNSIGNED")")
            if ok { await store.rescan(repoId: r.id) }
        }
    }
}
