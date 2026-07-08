// ReconcileSheet.swift — the skeleton-reconcile confirm sheet (pull skeleton-owned
// files + bump behind skills). Split out of OverlaySheets.swift; module-internal,
// rendered by OverlayHost via the shared SheetShell.

import SwiftUI

struct ReconcileSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo

    var body: some View {
        SheetShell(title: "Reconcile · \(repo.name)", icon: "git-merge",
                   width: OverlayLayout.sheetW, confirm: "Apply reconcile", confirmIcon: "git-merge") {
            app.closeSheet()
            app.toast("reconciled \(repo.name)",
                      "\(repo.drift.files) skeleton files pulled · skills bumped", .ok)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                if let behind = repo.drift.behind {
                    Text("this repo is ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary)
                    + Text(behind).font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.warn)
                    + Text(" behind the skeleton. these skeleton-owned files will be "
                           + "overwritten with the current version. your code is untouched.")
                        .font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary)
                } else {
                    SheetProse(text: "this repo is current with the skeleton.")
                }
                let skillBumps = repo.skills.filter { $0.status == .behind }
                if repo.drift.files > 0 {
                    FileCard(caption: "skeleton-owned files · \(repo.drift.files)") {
                        ForEach(0..<repo.drift.files, id: \.self) { _ in
                            FileRow(icon: "file-diff", path: ".claude/…", tone: .warn) { EmptyView() }
                        }
                    }
                }
                if !skillBumps.isEmpty {
                    FileCard(caption: "skills to bump · \(skillBumps.count)") {
                        ForEach(skillBumps) { s in
                            FileRow(icon: "blocks", path: s.skillId, tone: .info) {
                                Text("\(s.installed ?? "—") → latest")
                                    .font(VibeFont.mono(VibeFont.size.xxs))
                                    .foregroundStyle(Theme.color.textMuted)
                            }
                        }
                    }
                }
            }
        }
    }
}
