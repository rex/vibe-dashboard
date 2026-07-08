// OverlaySheetsMore.swift — the apply-skill / install-hooks / about sheets.
// Split out of OverlaySheets.swift to keep each file under the line limit.
// Module-internal; rendered by OverlayHost via the shared SheetShell.

import SwiftUI

// MARK: - Apply-skill sheet

struct ApplySkillSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo

    private var target: SkillUse? { repo.skills.first { $0.status == .missing } }

    var body: some View {
        let id = target?.skillId ?? "a skill"
        return SheetShell(title: "Apply skill · \(repo.name)", icon: "package-plus",
                          width: OverlayLayout.sheetW, confirm: "Apply skill", confirmIcon: "package-plus") {
            app.closeSheet()
            app.toast("applied \(id)", "scaffolded skill + added namespace to VIBE.yaml", .ok)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                if let use = target {
                    SheetProse(text: use.note ?? "scaffold this skill into the repo and register its namespace.")
                    FileCard(caption: "will scaffold") {
                        FileRow(icon: "file-plus", path: ".claude/skills/\(use.skillId)/", tone: .ok) { EmptyView() }
                        FileRow(icon: "file-code-2", path: "VIBE.yaml", tone: .ok) {
                            Text("+ \(use.skillId):")
                                .font(VibeFont.mono(VibeFont.size.xxs))
                                .foregroundStyle(Theme.color.ok)
                        }
                    }
                } else {
                    EmptyState(icon: "check", tone: .ok, text: "no missing skills — every namespace is applied")
                }
            }
        }
    }
}

// MARK: - Install-hooks sheet

struct InstallHooksSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    let repo: Repo
    /// The repo's current `core.hooksPath`, read live at open. nil = loading;
    /// "" = unset (hooks don't run); otherwise the configured value.
    @State private var hooksPath: String? = nil

    private var alreadyArmed: Bool { hooksPath == ".githooks" }

    var body: some View {
        SheetShell(title: "Install git hooks · \(repo.name)", icon: "shield-plus",
                   width: OverlayLayout.sheetW, confirm: alreadyArmed ? "Re-point" : "Set hooks path",
                   confirmIcon: "shield-plus", onConfirm: perform) {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                SheetProse(text: "points git at the repo's .githooks/ via core.hooksPath — the skeleton's `make install-hooks` step. Every commit then runs the repo's pre-commit gate. Nothing else on disk is touched.")
                FileCard(caption: "will run") {
                    FileRow(icon: "terminal", path: "git config core.hooksPath .githooks", tone: .ok) { EmptyView() }
                }
                FileCard(caption: "current core.hooksPath") {
                    FileRow(icon: alreadyArmed ? "check" : "git-branch",
                            path: hooksPath == nil ? "reading…"
                                : (hooksPath!.isEmpty ? "(unset — hooks don't run)" : hooksPath!),
                            tone: alreadyArmed ? .ok : (hooksPath?.isEmpty == false ? .warn : .neutral)) {
                        if alreadyArmed {
                            Text("armed").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.ok)
                        }
                    }
                }
            }
        }
        .task {
            let abs = (repo.absolutePath as NSString).expandingTildeInPath
            let r = await ProcessRunner.git(["config", "--get", "core.hooksPath"], cwd: abs)
            hooksPath = r.ok ? r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
    }

    private func perform() {
        app.closeSheet()
        let r = repo, host = store.fleet.scanner.host
        Task { @MainActor in
            let ok = await app.runGit(r, host: host, steps: [("config", GitWrite.hooksPathArgs)],
                                      okTitle: "hooks path set",
                                      okDetail: "core.hooksPath = .githooks · pre-commit gate armed")
            if ok { await store.rescan(repoId: r.id) }
        }
    }
}

// MARK: - Exclude-file sheet (the one write sheet that touches disk for real)

struct ExcludeSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    let repo: Repo
    let path: String

    private var vibePath: String { (repo.absolutePath as NSString).expandingTildeInPath + "/VIBE.yaml" }
    private var current: [String] { VibeYamlEditor.currentExcludes(vibePath: vibePath) }

    var body: some View {
        SheetShell(title: "Exclude from scope · \(repo.name)", icon: "file-code-2",
                   width: OverlayLayout.sheetW, confirm: "Exclude file", confirmIcon: "circle-slash",
                   confirmVariant: .danger) {
            perform()
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                SheetProse(text: "adds this file to architecture.exclude_globs so check-architecture stops counting it. VIBE.yaml is edited in place — a .bak backup is written first and the result is re-parsed and verified before it's saved. if anything looks off, nothing is written.")
                FileCard(caption: "add to exclude_globs") {
                    FileRow(icon: "file-code-2", path: path, tone: .warn) {
                        Text("+ exclude").font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.accent)
                    }
                }
                if !current.isEmpty {
                    FileCard(caption: "already excluded · \(current.count)") {
                        ForEach(current, id: \.self) { g in
                            FileRow(icon: "minus", path: g, tone: .neutral) { EmptyView() }
                        }
                    }
                }
            }
        }
    }

    private func perform() {
        app.closeSheet()
        let target = vibePath, glob = path, name = repo.name
        Task { @MainActor in
            let result = await Task.detached { VibeYamlEditor.addExcludeGlob(vibePath: target, glob: glob) }.value
            switch result {
            case .added(let g):
                app.toast("excluded from scope", "\(name) · VIBE.yaml + \(g)", .ok)
                await store.rescan()
            case .alreadyExcluded:
                app.toast("already excluded", "\(glob) is already in exclude_globs", .info)
            case .noVibe:
                app.toast("no VIBE.yaml", "\(name) has no policy file to edit", .warn)
            case .parseError:
                app.toast("VIBE.yaml won't parse", "refusing to edit a file that doesn't already parse", .danger)
            case .unsafe(let why):
                app.toast("left untouched", why, .danger)
            default: break   // skill-record results can't arise from addExcludeGlob
            }
        }
    }
}

// MARK: - About sheet

struct AboutSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    var body: some View {
        let b = store.fleet.appBuild
        let s = store.fleet.scanner
        let t = store.fleet.totals
        return SheetShell(title: "About Vibe", icon: "info", width: OverlayLayout.aboutW,
                          confirm: "OK", confirmIcon: "check") {
            app.closeSheet()
        } content: {
            VStack(alignment: .center, spacing: Theme.space.x5) {
                VibeLogo(size: 40, sub: "mission control for vibe coding", prompt: true, mark: true)
                VStack(spacing: 0) {
                    MetaRow(key: "version") { Text("\(b.version) · \(b.channel)") }
                    MetaRow(key: "commit") { Text(b.commit).foregroundStyle(Theme.color.info) }
                    MetaRow(key: "built") { Text(b.date) }
                    MetaRow(key: "codename") { Text(b.codename) }
                    MetaRow(key: "scanning") { Text("\(s.root) · \(s.host)") }
                    MetaRow(key: "watching") { Text("\(t.repos) repos · \(t.workspaces) workspaces") }
                }
                .overlay(alignment: .top) { Rectangle().fill(Theme.color.border).frame(height: 1) }
                Text("reads ~/Code directly · keeps an eye on the agents")
                    .font(VibeFont.sans(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
