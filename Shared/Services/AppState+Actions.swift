// AppState+Actions.swift — finding fix-it routing, clipboard, reveal, and the safe
// additive .gitignore write. Split out of AppState to keep that file lean; these are
// the real, honest side-effects a finding's action performs.

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Outcome of the additive `.gitignore` write — a Sendable value the off-actor write
/// hands back to the main actor for toasting.
private enum GitignoreWrite: Sendable { case unchanged, wrote, failed(String) }

extension AppState {
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

    // ---- clipboard + finding actions ----

    private func setClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Copy text to the clipboard and confirm it — a real, honest side-effect (the
    /// pasteboard genuinely holds `text`); the toast previews a single collapsed line.
    func copy(_ text: String, as label: String) {
        setClipboard(text)
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        toast("copied \(label)", flat.count > 64 ? String(flat.prefix(61)) + "…" : flat, .ok)
    }

    /// Build a detailed, context-rich agent prompt for a finding the app CANNOT fix
    /// itself (splitting a god-file, …), copy it, and steer the user to paste it into a
    /// coding agent. Resolves the finding's repo + file target live so the prompt carries
    /// the absolute repo path, the exact file, and its size. No terminal is opened —
    /// clipboard + steering only (auto-launching an agent is a bridge too far).
    func copyAgentPrompt(for f: Finding) {
        guard let repo = FleetStore.current?.fleet.repo(f.repoId) else {
            toast("couldn't build prompt", "no repo resolved for this finding", .neutral); return
        }
        let abs = (repo.absolutePath as NSString).expandingTildeInPath
        let t = FindingTarget.resolve(f, repo: repo)
        setClipboard(FindingPrompt.forFinding(f, repoPath: abs, file: t?.relPath, lines: t?.lines))
        toast("prompt copied", "paste into Claude Code to run the fix", .info)
    }

    /// The prompt path from the file viewer, where the god-file target is already
    /// resolved (repo path, file, and line count all in hand).
    func copyAgentPrompt(target t: FindingTarget) {
        let file = t.relPath ?? (t.repoAbsPath as NSString).lastPathComponent
        setClipboard(FindingPrompt.splitFile(repoPath: t.repoAbsPath, file: file, lines: t.lines ?? 0))
        toast("prompt copied", "paste into Claude Code to split the file", .info)
    }

    /// Add a repo-relative path to the repo's `.gitignore` — a safe, additive
    /// read/dedupe/append/write. Idempotent (an already-ignored path is a no-op), never
    /// reorders or rewrites existing lines; only appends when the entry is genuinely
    /// absent. A targeted rescan then refreshes the repo's git-derived state.
    func addToGitignore(repoId: String, repoAbsPath: String, relPath: String) {
        let giPath = (repoAbsPath as NSString).appendingPathComponent(".gitignore")
        let name = relPath
        Task {
            let outcome: GitignoreWrite = await Task.detached { () -> GitignoreWrite in
                let existing = (try? String(contentsOfFile: giPath, encoding: .utf8)) ?? ""
                let (newText, changed) = GitignoreEditor.append(to: existing, path: relPath)
                guard changed else { return .unchanged }
                do { try newText.write(toFile: giPath, atomically: true, encoding: .utf8); return .wrote }
                catch { return .failed(error.localizedDescription) }
            }.value
            switch outcome {
            case .unchanged:
                toast("already ignored", "\(name) is already in .gitignore", .info)
            case .wrote:
                toast("added to .gitignore", name, .ok)
                await FleetStore.current?.rescan(repoId: repoId)
            case .failed(let why):
                toast("couldn't write .gitignore", String(why.prefix(140)), .danger)
            }
        }
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
        case "split file": copyAgentPrompt(for: f)   // an AI-only fix — steer, don't fake it
        case "init serena", "scope server", "reconnect":
            toast("not yet wired", "\(f.fix ?? "this action") has no in-app action yet", .neutral)
        default: break
        }
    }
}
