// OverlayHost.swift — the modal layer: ⌘K command palette + confirm-gated
// write sheets (commit / prune / reconcile / apply-skill / install-hooks /
// waiver / about), each over a flat dimmed backdrop. Mounted once at the app
// root (`MacRootView`). Dark, mono-dominant; terse lowercase-technical voice.

import SwiftUI

// Small layout constants local to the overlay layer.
private enum OL {
    static let paletteW: CGFloat = 580
    static let sheetW: CGFloat = 560
    static let aboutW: CGFloat = 460
    static let topInset: CGFloat = 0.07     // fraction of window height
    static let listMax: CGFloat = 340
    static let bodyMax: CGFloat = 460
}

struct OverlayHost: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    var body: some View {
        if let sheet = app.sheet {
            GeometryReader { geo in
                ZStack(alignment: sheet == .about ? .center : .top) {
                    Theme.color.bgVoid.opacity(0.62)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { app.closeSheet() }

                    content(sheet)
                        .padding(.top, sheet == .about ? 0 : geo.size.height * OL.topInset)
                        .frame(maxWidth: 0.92 * geo.size.width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private func content(_ sheet: SheetKind) -> some View {
        switch sheet {
        case .palette:
            CommandPalette()
        case .about:
            AboutSheet()
        case .commit:
            if let r = store.fleet.repo(app.selectedId) { CommitSheet(repo: r) }
        case .prune:
            if let r = store.fleet.repo(app.selectedId) { PruneSheet(repo: r) }
        case .reconcile:
            if let r = store.fleet.repo(app.selectedId) { ReconcileSheet(repo: r) }
        case .applySkill:
            if let r = store.fleet.repo(app.selectedId) { ApplySkillSheet(repo: r) }
        case .installHooks:
            if let r = store.fleet.repo(app.selectedId) { InstallHooksSheet(repo: r) }
        case .waiver:
            WaiverSheet(repo: store.fleet.repo(app.selectedId))
        }
    }
}

// MARK: - Command palette (⌘K)

private struct PaletteItem: Identifiable {
    enum Kind { case repo, action }
    let id: String
    let kind: Kind
    let label: String
    let sub: String?
    let icon: String
    let health: Health?
    let run: () -> Void
}

private struct CommandPalette: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    @State private var query = ""
    @FocusState private var focused: Bool

    private var items: [PaletteItem] {
        let repos = store.fleet.leaves + store.fleet.workspaces
        let repoItems = repos.map { r in
            PaletteItem(id: "repo·" + r.id, kind: .repo, label: r.name, sub: r.path,
                        icon: "folder-git-2", health: r.health) {
                app.openRepo(r.id); app.closeSheet()
            }
        }
        func act(_ id: String, _ icon: String, _ label: String, _ run: @escaping () -> Void) -> PaletteItem {
            PaletteItem(id: "act·" + id, kind: .action, label: label, sub: nil, icon: icon, health: nil) {
                run(); app.closeSheet()
            }
        }
        let actions: [PaletteItem] = [
            act("rescan", "refresh-cw", "Re-scan ~/Code") { Task { await store.rescan() } },
            act("fleet", "folder-tree", "Go to Fleet") { app.goView(.fleet) },
            act("agents", "radar", "Go to Agents") { app.goView(.agents) },
            act("findings", "triangle-alert", "Go to Findings") { app.goView(.findings) },
            act("skills", "blocks", "Go to Skills") { app.goView(.skills) },
            act("autopilot", "gauge-circle", "Go to Autopilot") { app.goView(.autopilot) },
            act("console", "terminal", "Toggle console") { app.toggleConsole() },
            act("inspector", "panel-right", "Toggle inspector") { app.toggleInspector() },
        ]
        return repoItems + actions
    }

    private var filtered: [PaletteItem] {
        let q = query.lowercased()
        let base = q.isEmpty ? items : items.filter {
            $0.label.lowercased().contains(q) || ($0.sub?.lowercased().contains(q) ?? false)
        }
        return Array(base.prefix(9))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.space.x2_5) {
                VibeIcon("command", size: 16, color: Theme.color.accent)
                TextField("jump to a repo or run an action…", text: $query)
                    .textFieldStyle(.plain)
                    .font(VibeFont.mono(VibeFont.size.md))
                    .foregroundStyle(Theme.color.textBright)
                    .focused($focused)
                Kbd("esc")
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }

            if filtered.isEmpty {
                Text("no matches")
                    .font(VibeFont.mono(VibeFont.size.sm))
                    .foregroundStyle(Theme.color.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.space.x5)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered) { item in PaletteRow(item: item) }
                    }
                    .padding(Theme.space.x1_5)
                }
                .frame(maxHeight: OL.listMax)
            }
        }
        .frame(width: OL.paletteW)
        .background(Theme.color.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous)
            .strokeBorder(Theme.color.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 16)
        .onAppear { focused = true }
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    @State private var hover = false
    var body: some View {
        Button(action: item.run) {
            HStack(spacing: Theme.space.x2_5) {
                if item.kind == .repo, let h = item.health {
                    HealthDot(health: h, size: 8).frame(width: 14)
                } else {
                    VibeIcon(item.icon, size: 14, color: Theme.color.textMuted).frame(width: 14)
                }
                Text(item.label)
                    .font(VibeFont.mono(VibeFont.size.sm))
                    .foregroundStyle(Theme.color.textPrimary)
                    .lineLimit(1)
                if let sub = item.sub {
                    Text(sub)
                        .font(VibeFont.mono(VibeFont.size.xxs))
                        .foregroundStyle(Theme.color.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.space.x2)
                Text(item.kind == .repo ? "repo" : "action")
                    .font(VibeFont.mono(9, .medium))
                    .tracking(9 * VibeFont.track.label)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.color.textGhost)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? Theme.color.surfaceActive : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Sheet shell

/// The chrome shared by every confirm-gated write sheet: icon-title header,
/// scrollable body, footer bar with Cancel + primary confirm.
private struct SheetShell<Body: View>: View {
    @Environment(AppState.self) private var app
    let title: String
    let icon: String
    var width: CGFloat = OL.sheetW
    var confirm: String
    var confirmIcon: String
    var confirmVariant: VibeButtonVariant = .primary
    var onConfirm: () -> Void
    @ViewBuilder var content: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.space.x2_5) {
                VibeIcon(icon, size: 16, color: Theme.color.accent)
                Text(title)
                    .font(VibeFont.mono(VibeFont.size.md, .bold))
                    .foregroundStyle(Theme.color.textBright)
                    .lineLimit(1)
                Spacer(minLength: Theme.space.x2)
                Button { app.closeSheet() } label: {
                    VibeIcon("x", size: 15, color: Theme.color.textMuted)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.color.surface2)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }

            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.space.x4)
            }
            .frame(maxHeight: OL.bodyMax)

            HStack(spacing: Theme.space.x2_5) {
                Spacer()
                VibeButton(title: "Cancel", variant: .ghost) { app.closeSheet() }
                VibeButton(title: confirm, icon: confirmIcon, variant: confirmVariant, action: onConfirm)
            }
            .padding(.horizontal, Theme.space.x4)
            .padding(.vertical, Theme.space.x3)
            .frame(maxWidth: .infinity)
            .background(Theme.color.surface2)
            .overlay(alignment: .top) { Rectangle().fill(Theme.color.border).frame(height: 1) }
        }
        .frame(width: width)
        .background(Theme.color.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.lg, style: .continuous)
            .strokeBorder(Theme.color.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 16)
    }
}

// Shared sheet sub-elements ------------------------------------------------

private struct SheetProse: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VibeFont.mono(VibeFont.size.sm))
            .foregroundStyle(Theme.color.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A bordered file-list card with an UPPERCASE section caption + rows.
private struct FileCard<Rows: View>: View {
    let caption: String
    @ViewBuilder var rows: () -> Rows
    var body: some View {
        VStack(spacing: 0) {
            Text(caption)
                .vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, Theme.space.x2)
                .background(Theme.color.surface2)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
            rows()
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(Theme.color.border, lineWidth: 1))
    }
}

/// One file line inside a `FileCard`.
private struct FileRow<Right: View>: View {
    let icon: String
    let path: String
    var tone: VibeTone = .neutral
    @ViewBuilder var right: () -> Right
    var body: some View {
        HStack(spacing: Theme.space.x2_5) {
            VibeIcon(icon, size: 13, color: tone == .neutral ? Theme.color.textMuted : Theme.color.tone(tone))
            Text(path)
                .font(VibeFont.mono(VibeFont.size.sm))
                .foregroundStyle(Theme.color.textPrimary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            right()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, Theme.space.x2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

// MARK: - Commit sheet

private struct CommitSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo
    @State private var sign = true
    @State private var message = ""

    private var branch: String { repo.agent?.branch ?? "main" }
    private var count: Int { max(1, repo.worktree.unstaged) }

    var body: some View {
        SheetShell(title: "Commit · \(repo.name)", icon: "git-commit-horizontal",
                   width: OL.sheetW, confirm: "Commit & push", confirmIcon: "git-commit-horizontal") {
            app.closeSheet()
            if sign {
                app.toast("committed + pushed", "\(count) files → \(branch) · signed ✓", .ok)
            } else {
                app.toast("committed + pushed", "\(count) files → \(branch) · UNSIGNED", .warn)
            }
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                HStack(spacing: Theme.space.x2_5) {
                    VibeIcon("git-branch", size: 14, color: Theme.color.textMuted)
                    Text("on ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary)
                    + Text(branch).font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.textPrimary)
                    if !repo.worktree.signed { Pill(text: "commits unsigned", tone: .danger) }
                }
                FileCard(caption: "staged · \(count)") {
                    ForEach(0..<count, id: \.self) { i in
                        FileRow(icon: "file-pen", path: repo.path + "/…", tone: .warn) {
                            EmptyView()
                        }.opacity(i == 0 ? 1 : 0.85)
                    }
                }
                VibeTextField(placeholder: "commit message — one logical step…", text: $message)
                Button { sign.toggle() } label: {
                    HStack(spacing: Theme.space.x2_5) {
                        VibeSwitch(isOn: $sign)
                        Text("sign commit ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textPrimary)
                        + Text("· signed_commits_required is true")
                            .font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textMuted)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Prune sheet

private struct PruneSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo
    private var stale: [Worktree] { repo.worktrees.filter { $0.state != .active } }

    var body: some View {
        SheetShell(title: "Prune worktrees · \(repo.name)", icon: "trash-2",
                   width: OL.sheetW, confirm: "Prune \(stale.count)", confirmIcon: "trash-2",
                   confirmVariant: .danger) {
            app.closeSheet()
            app.toast("pruned \(stale.count) worktrees",
                      "git worktree remove × \(stale.count) · disk reclaimed", .ok)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                SheetProse(text: "these worktrees are stale or abandoned. git worktree remove deletes the working directory; branches and commits are kept.")
                if stale.isEmpty {
                    EmptyState(icon: "check", tone: .ok, text: "no non-active worktrees to prune")
                } else {
                    VStack(spacing: 0) {
                        ForEach(stale) { w in
                            HStack(spacing: Theme.space.x2_5) {
                                VibeIcon("git-branch", size: 13,
                                         color: Theme.color.tone(w.state.tone))
                                Text(w.branch)
                                    .font(VibeFont.mono(VibeFont.size.sm))
                                    .foregroundStyle(Theme.color.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: Theme.space.x2)
                                Text("\(w.created) · \(w.commits) commits")
                                    .font(VibeFont.mono(VibeFont.size.xxs))
                                    .foregroundStyle(Theme.color.textMuted)
                                StatusBadge(text: w.state.rawValue, tone: w.state.tone, small: true)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
                        .strokeBorder(Theme.color.border, lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Reconcile sheet

private struct ReconcileSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo

    var body: some View {
        SheetShell(title: "Reconcile · \(repo.name)", icon: "git-merge",
                   width: OL.sheetW, confirm: "Apply reconcile", confirmIcon: "git-merge") {
            app.closeSheet()
            app.toast("reconciled \(repo.name)",
                      "\(repo.drift.files) skeleton files pulled · skills bumped", .ok)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                if let behind = repo.drift.behind {
                    Text("this repo is ").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary)
                    + Text(behind).font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.warn)
                    + Text(" behind the skeleton. these skeleton-owned files will be overwritten with the current version. your code is untouched.")
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

// MARK: - Apply-skill sheet

private struct ApplySkillSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo

    private var target: SkillUse? { repo.skills.first { $0.status == .missing } }

    var body: some View {
        let id = target?.skillId ?? "a skill"
        return SheetShell(title: "Apply skill · \(repo.name)", icon: "package-plus",
                          width: OL.sheetW, confirm: "Apply skill", confirmIcon: "package-plus") {
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

private struct InstallHooksSheet: View {
    @Environment(AppState.self) private var app
    let repo: Repo

    private struct Ref { let event: String; let matcher: String?; let file: String; let role: String }
    private let refs: [Ref] = [
        Ref(event: "SessionStart", matcher: nil, file: ".claude/hooks/session-start.sh", role: "load VIBE.yaml + repo rules into context"),
        Ref(event: "PreToolUse", matcher: "Bash", file: ".claude/hooks/bash-guard.sh", role: "block dangerous shell + writes outside scope"),
        Ref(event: "PostToolUse", matcher: "Edit|Write", file: ".claude/hooks/format-edit.sh", role: "format every file the agent writes"),
        Ref(event: "Stop", matcher: nil, file: ".claude/hooks/stop-gate.sh", role: "run make validate — block finish while red"),
    ]

    private func active(_ r: Ref) -> Bool {
        repo.hooks.contains { $0.src == "claude" && $0.event == r.event && $0.status == .active }
    }
    private var needed: Int { refs.filter { !active($0) }.count }

    var body: some View {
        let n = max(needed, 1)
        return SheetShell(title: "Install skeleton hooks · \(repo.name)", icon: "shield-plus",
                          width: OL.sheetW, confirm: "Install \(n)", confirmIcon: "shield-plus") {
            app.closeSheet()
            app.toast("installed skeleton hooks",
                      "\(n) guardrail\(n > 1 ? "s" : "") written to .claude/hooks/ · settings.json wired", .ok)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                if needed > 0 {
                    SheetProse(text: "this repo is missing \(needed) of the skeleton's guardrail hooks. they'll be copied into .claude/hooks/ and wired into .claude/settings.json. your existing hooks are kept.")
                } else {
                    SheetProse(text: "this repo already has every skeleton guardrail. re-installing restores each script to the current skeleton version.")
                }
                FileCard(caption: "guardrail hooks") {
                    ForEach(refs.indices, id: \.self) { i in
                        let r = refs[i]
                        let on = active(r)
                        HStack(alignment: .top, spacing: 11) {
                            VibeIcon(on ? "check" : "file-plus", size: 14,
                                     color: on ? Theme.color.ok : Theme.color.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.event + (r.matcher.map { " · \($0)" } ?? ""))
                                    .font(VibeFont.mono(VibeFont.size.sm))
                                    .foregroundStyle(Theme.color.textPrimary)
                                Text("\(r.file) — \(r.role)")
                                    .font(VibeFont.sans(VibeFont.size.xxs))
                                    .foregroundStyle(Theme.color.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: Theme.space.x2)
                            Text(on ? "present" : "install")
                                .font(VibeFont.mono(VibeFont.size.xxs))
                                .foregroundStyle(on ? Theme.color.ok : Theme.color.accent)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .opacity(on ? 0.5 : 1)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
                    }
                }
            }
        }
    }
}

// MARK: - Waiver sheet

private struct WaiverSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store
    let repo: Repo?
    @State private var reason = ""
    @State private var expiry = "30d"

    private var findings: [Finding] { repo?.surprises ?? store.fleet.findings }

    var body: some View {
        SheetShell(title: "Record a waiver", icon: "shield-check",
                   width: OL.sheetW, confirm: "Record waiver", confirmIcon: "shield-check",
                   confirmVariant: .primary) {
            app.closeSheet()
            app.toast("waiver recorded", "expires in \(expiry) · logged to VIBE.yaml waivers[]", .info)
        } content: {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                if let f = findings.first {
                    fieldLabel("finding")
                    HStack(spacing: Theme.space.x2) {
                        SeverityTag(severity: f.severity)
                        Text(f.what)
                            .font(VibeFont.mono(VibeFont.size.sm))
                            .foregroundStyle(Theme.color.textPrimary)
                            .lineLimit(1)
                    }
                } else {
                    SheetProse(text: "no open findings to waive.")
                }
                fieldLabel("reason — why this is acceptable for now")
                VibeTextField(placeholder: "e.g. legacy module, scheduled for the v2 rewrite…", text: $reason)
                fieldLabel("expires")
                HStack(spacing: Theme.space.x1_5) {
                    ForEach(["7d", "30d", "90d", "never"], id: \.self) { opt in
                        Button { expiry = opt } label: {
                            Text(opt)
                                .font(VibeFont.mono(VibeFont.size.xs, .medium))
                                .foregroundStyle(expiry == opt ? Theme.color.textOnAccent : Theme.color.textSecondary)
                                .padding(.horizontal, Theme.space.x2_5).padding(.vertical, Theme.space.x1_5)
                                .background(expiry == opt ? Theme.color.accent : Theme.color.surfaceSunken)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                                    .strokeBorder(expiry == opt ? Theme.color.accent : Theme.color.border, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).vibeMicroLabel(VibeFont.size.xxs, color: Theme.color.textMuted)
    }
}

// MARK: - About sheet

private struct AboutSheet: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    var body: some View {
        let b = store.fleet.appBuild
        let s = store.fleet.scanner
        let t = store.fleet.totals
        return SheetShell(title: "About Vibe", icon: "info", width: OL.aboutW,
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
