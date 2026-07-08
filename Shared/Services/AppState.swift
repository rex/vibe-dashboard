// AppState.swift — navigation + panel + overlay UI state (the action bus).

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum AppView: String, Hashable, CaseIterable { case fleet, agents, findings, skills, autopilot, repo }
enum ConsoleTab: String, Hashable, CaseIterable { case output, shell, activity }

enum SheetKind: String, Identifiable, Hashable {
    case about, reconcile, commit, prune, waiver, applySkill, installHooks, palette, excludeFile, backfillSkills
    var id: String { rawValue }
}

/// A pending "exclude this file from architecture scope" request, awaiting confirm.
struct ExcludeRequest: Hashable { var repoId: String; var path: String }

struct ShellEntry: Identifiable {
    let id = UUID()
    var repoName: String
    var host: String
    var cwd: String
    var cmd: String
    var lines: [(text: String, tone: VibeTone)]
    var ok: Bool
}

@MainActor
@Observable
final class AppState {
    var view: AppView = .fleet
    var selectedId: String?
    var returnView: AppView = .fleet
    var inspectorOpen = true
    var consoleOpen = false
    var consoleTab: ConsoleTab = .activity
    var sheet: SheetKind?
    var pendingExclude: ExcludeRequest?
    var toasts: [ToastData] = []
    var shellLog: [ShellEntry] = []
    private var toastSeq = 0
    /// Auto-dismiss timers, keyed by toast id, so each is cancelled on explicit
    /// dismissal — the handle isn't discarded (no unbounded timer churn) and a
    /// reused id can't fire a stale dismissal.
    private var toastTimers: [Int: Task<Void, Never>] = [:]

    /// Read-only view of the live auto-dismiss timers (by toast id). Surfaced so
    /// tests can assert every dismissed toast also tears its timer down.
    var activeToastTimerIDs: Set<Int> { Set(toastTimers.keys) }

    private static let navKey = "vibe.mac.nav"

    init() {
        if let d = UserDefaults.standard.dictionary(forKey: Self.navKey) {
            if let v = d["view"] as? String, let av = AppView(rawValue: v) { view = av }
            selectedId = d["selectedId"] as? String
            inspectorOpen = (d["inspectorOpen"] as? Bool) ?? true
            consoleOpen = (d["consoleOpen"] as? Bool) ?? false
        }
    }
    private func persist() {
        UserDefaults.standard.set([
            "view": view.rawValue, "selectedId": selectedId ?? "",
            "inspectorOpen": inspectorOpen, "consoleOpen": consoleOpen,
        ], forKey: Self.navKey)
    }

    func goView(_ v: AppView) { view = v; selectedId = nil; persist() }
    func openRepo(_ id: String) {
        if view != .repo { returnView = view }
        view = .repo; selectedId = id; persist()
    }
    func back() { view = returnView; selectedId = nil; persist() }
    func toggleInspector() { inspectorOpen.toggle(); persist() }
    func toggleConsole() { consoleOpen.toggle(); persist() }
    func openConsole(_ tab: ConsoleTab? = nil) { consoleOpen = true; if let tab { consoleTab = tab }; persist() }
    func openSheet(_ k: SheetKind) { sheet = k }
    func closeSheet() { sheet = nil }
    /// Ask to exclude a file from a repo's architecture scope (confirm-gated write).
    func requestExclude(repoId: String, path: String) {
        pendingExclude = ExcludeRequest(repoId: repoId, path: path)
        openSheet(.excludeFile)
    }
    func togglePalette() { sheet = (sheet == .palette) ? nil : .palette }

    @discardableResult
    func toast(_ title: String, _ message: String = "", _ tone: VibeTone = .info) -> Int {
        toastSeq += 1
        let id = toastSeq
        toasts.append(ToastData(id: id, title: title, message: message, tone: tone))
        toastTimers[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.4))
            guard !Task.isCancelled else { return }
            self?.dismissToast(id)
        }
        return id
    }
    func dismissToast(_ id: Int) {
        toastTimers.removeValue(forKey: id)?.cancel()
        toasts.removeAll { $0.id == id }
    }

    /// Actually run a Makefile target in the repo, streaming output to the shell console.
    func runTarget(_ repo: Repo, _ target: String, host: String) {
        openConsole(.shell)
        let pending = toast("make \(target)", "\(repo.name) · running…", .info)
        let abs = (repo.absolutePath as NSString).expandingTildeInPath
        Task {
            let makeCandidates = ["/opt/homebrew/bin/make", "/usr/bin/make"]
            let makePath = makeCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
                ?? "/usr/bin/make"
            let result = await ProcessRunner.run(makePath, [target], cwd: abs, timeout: 180)
            let raw = (result.stdout + (result.stderr.isEmpty ? "" : "\n" + result.stderr))
            let lines: [(text: String, tone: VibeTone)] = raw
                .split(separator: "\n", omittingEmptySubsequences: false).prefix(200)
                .map { (String($0), Self.lineTone(String($0))) }
            dismissToast(pending)
            shellLog.append(ShellEntry(repoName: repo.name, host: host, cwd: repo.path,
                                       cmd: "make \(target)", lines: Array(lines), ok: result.ok))
            if shellLog.count > 12 { shellLog.removeFirst(shellLog.count - 12) }
            consoleTab = target.contains("validate") ? .output : .shell
            toast("make \(target)", repo.name + (result.ok ? " · done" : " · exit \(result.code)"), result.ok ? .ok : .danger)
        }
    }

    /// Classify a shell-output line's tone for the console. Pure — shared by
    /// `runTarget` and the real git-write runners below.
    nonisolated static func lineTone(_ s: String) -> VibeTone {
        let low = s.lowercased()
        if low.contains("error") || low.contains("fail") || s.contains("✗") { return .danger }
        if low.contains("warn") || s.contains("⚠") { return .warn }
        if s.contains("✓") || low.contains("passed") || low.contains("green") { return .ok }
        return .neutral
    }

    /// Run a sequence of git subcommands in `repo`, streaming ONE shell entry and
    /// returning whether EVERY step exited 0. Reuses the ProcessRunner/shellLog path
    /// `runTarget` uses. The success toast fires ONLY on an all-zero run; a non-zero
    /// step STOPS the sequence and surfaces the REAL stderr — never a fabricated "done".
    @discardableResult
    func runGit(_ repo: Repo, host: String, steps: [(label: String, args: [String])],
                okTitle: String, okDetail: String) async -> Bool {
        openConsole(.shell)
        let abs = (repo.absolutePath as NSString).expandingTildeInPath
        let git = ProcessRunner.gitPath
        let pending = toast(okTitle, "\(repo.name) · running…", .info)
        var lines: [(text: String, tone: VibeTone)] = []
        var ok = true
        var failErr = ""
        for step in steps {
            lines.append(("$ git " + step.args.joined(separator: " "), .neutral))
            let r = await ProcessRunner.run(git, step.args, cwd: abs, timeout: 120)
            let body = r.stdout + (r.stderr.isEmpty ? "" : (r.stdout.isEmpty ? "" : "\n") + r.stderr)
            for ln in body.split(separator: "\n", omittingEmptySubsequences: false).prefix(120) where !ln.isEmpty {
                lines.append((String(ln), Self.lineTone(String(ln))))
            }
            if !r.ok {
                ok = false
                failErr = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append(("✗ git \(step.label) exited \(r.code)", .danger))
                break
            }
        }
        dismissToast(pending)
        let cmd = "git " + steps.map { $0.label }.joined(separator: " · ")
        shellLog.append(ShellEntry(repoName: repo.name, host: host, cwd: repo.path, cmd: cmd, lines: lines, ok: ok))
        if shellLog.count > 12 { shellLog.removeFirst(shellLog.count - 12) }
        if ok {
            toast(okTitle, okDetail, .ok)
        } else {
            let first = failErr.split(separator: "\n").first.map(String.init) ?? "exit non-zero"
            toast(okTitle + " · failed", String(first.prefix(140)), .danger)
        }
        return ok
    }

    /// Remove each ABANDONED worktree with `git worktree remove` (NO `--force`). The
    /// on-disk path is resolved LIVE from `git worktree list` (the Worktree model
    /// carries no path). The guard refuses stale/active/unpushed worktrees; git
    /// itself refuses a dirty one and that non-zero surfaces honestly — never a
    /// fabricated "pruned". Returns true only if something was actually removed and
    /// nothing failed (so the caller knows whether a rescan is warranted).
    @discardableResult
    func pruneWorktrees(_ repo: Repo, worktrees: [Worktree], host: String) async -> Bool {
        openConsole(.shell)
        let abs = (repo.absolutePath as NSString).expandingTildeInPath
        let git = ProcessRunner.gitPath
        let listing = await ProcessRunner.run(git, ["worktree", "list", "--porcelain"], cwd: abs, timeout: 30)
        let pathByBranch = Dictionary(GitProbe.parseWorktrees(listing.stdout, repoAbs: abs).map { ($0.branch, $0.path) },
                                      uniquingKeysWith: { first, _ in first })
        let pending = toast("prune worktrees", "\(repo.name) · running…", .info)
        var lines: [(text: String, tone: VibeTone)] = []
        var removed = 0, failed = 0, refused = 0
        var failErr = ""
        for wt in worktrees {
            switch GitWrite.pruneDecision(state: wt.state, unpushedCommits: wt.commits) {
            case .refuse(let why):
                refused += 1
                lines.append(("⚠ \(wt.branch): \(why)", .warn))
            case .remove:
                guard let path = pathByBranch[wt.branch] else {
                    refused += 1
                    lines.append(("⚠ \(wt.branch): worktree not found — already removed?", .warn))
                    continue
                }
                let args = GitWrite.worktreeRemoveArgs(path: path)
                lines.append(("$ git " + args.joined(separator: " "), .neutral))
                let r = await ProcessRunner.run(git, args, cwd: abs, timeout: 60)
                if r.ok {
                    removed += 1
                    lines.append(("✓ removed \(wt.branch)", .ok))
                } else {
                    failed += 1
                    failErr = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
                    for ln in failErr.split(separator: "\n").prefix(6) { lines.append((String(ln), .danger)) }
                }
            }
        }
        dismissToast(pending)
        shellLog.append(ShellEntry(repoName: repo.name, host: host, cwd: repo.path,
                                   cmd: "git worktree remove × \(worktrees.count)", lines: lines, ok: failed == 0))
        if shellLog.count > 12 { shellLog.removeFirst(shellLog.count - 12) }
        if failed > 0 {
            let first = failErr.split(separator: "\n").first.map(String.init) ?? "git worktree remove failed"
            toast("prune failed", String(first.prefix(140)), .danger)
        } else if removed > 0 {
            toast("pruned \(removed) worktree\(removed == 1 ? "" : "s")",
                  refused > 0 ? "\(refused) kept — not safe to remove" : "git worktree remove · disk reclaimed", .ok)
        } else {
            toast("nothing pruned",
                  refused > 0 ? "\(refused) worktree\(refused == 1 ? "" : "s") kept — not safe to remove" : "no matching worktrees", .warn)
        }
        return failed == 0 && removed > 0
    }

    /// Reveal a path in Finder — a REAL action for places the app can only observe,
    /// not act (an agent process can't be paused, so we surface where it works).
    func reveal(path: String) {
        let p = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: p) else {
            toast("couldn't reveal", "path not found on disk", .neutral); return
        }
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
        #endif
    }

    /// Reveal the repo a finding belongs to (the "open file" fix). Resolves the path
    /// live from the store — replaces a faked "opened <x>" toast for a no-op.
    private func revealFinding(_ f: Finding) {
        guard let id = f.repoId, let abs = FleetStore.current?.fleet.repo(id)?.absolutePath else {
            toast("couldn't reveal", "no path for this finding", .neutral); return
        }
        reveal(path: abs)
    }

    /// Route a finding's fix-it to the matching action. Points sheets at the
    /// finding's repo by setting `selectedId` — WITHOUT force-navigating into repo
    /// detail. Verbs with no real in-app action say so honestly (neutral tone)
    /// instead of emitting a success toast for work that never happened.
    func runFix(_ f: Finding) {
        if let rid = f.repoId, !rid.isEmpty { selectedId = rid }
        switch f.fix {
        case "reconcile": openSheet(.reconcile)
        case "commit…", "sign + push": openSheet(.commit)
        case "prune": openSheet(.prune)
        case "apply skill": openSheet(.applySkill)
        case "install hooks": openSheet(.installHooks)
        case "open console", "re-run", "open tests": openConsole(.output); toast("console", f.what, .info)
        case "open file": revealFinding(f)
        case "split file", "init serena", "scope server", "reconnect":
            toast("not yet wired", "\(f.fix ?? "this action") has no in-app action yet", .neutral)
        default: break
        }
    }
}
