// FileViewerSheet.swift — "see the offending file BEFORE you act on it" modal, plus
// the small PURE helpers that back the per-finding actions:
//
//   • GitignoreEditor — idempotent .gitignore append (read / dedupe / append)
//   • FindingPrompt   — detailed agent-prompt templates for the AI-only fixes
//   • FindingTarget   — maps a Finding + its Repo to the file(s) an action touches
//
// The viewer is presented LOCALLY from a finding row via `.sheet(item:)` (not the
// AppState overlay layer), so the whole feature stays inside this slice. Two modes:
// a bounded, line-numbered file reader, and a live `git status` for a dirty tree.

import SwiftUI
import Foundation

// MARK: - GitignoreEditor (pure)

/// The pure, testable core of the "Add to .gitignore" action. NO file IO here — it
/// takes the CURRENT `.gitignore` body and a repo-relative path and returns the new
/// body plus whether anything actually changed. Idempotent: a path already present as
/// an exact (trimmed) line yields `changed == false`, so re-running never appends a
/// duplicate. Additive only — every existing line and comment is preserved.
enum GitignoreEditor {
    /// Is `path` already listed verbatim (exact trimmed-line match)? We deliberately do
    /// NOT evaluate gitignore glob semantics — only avoid duplicate literal lines.
    static func contains(_ body: String, path: String) -> Bool {
        let needle = path.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return false }
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { $0.trimmingCharacters(in: .whitespaces) == needle }
    }

    /// Append `path` if absent. Returns `(text, changed)`. When `changed` is false the
    /// text is returned unmodified (the path was already present, or was blank). A
    /// missing trailing newline is added before the new entry so lines never fuse.
    static func append(to body: String, path: String) -> (text: String, changed: Bool) {
        let clean = path.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !contains(body, path: clean) else { return (body, false) }
        var out = body
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        out += clean + "\n"
        return (out, true)
    }
}

// MARK: - FindingPrompt (pure)

/// Centralized, PURE agent-prompt templates for the fixes that CAN'T be done
/// programmatically (splitting a god-file, resolving a merge, …) and must be handed to
/// a coding agent. Each prompt is self-contained — absolute repo path, the exact file,
/// its size, the specific ask, and a closing `make validate` — so it can be pasted
/// straight into Claude Code with no extra context. Opening a terminal and running the
/// agent for the user is deliberately NOT done; steering + clipboard is the honest line.
enum FindingPrompt {
    static let hardLimit = 400

    /// The god-file split prompt. Names the repo, the file, its line count, the hard
    /// limit, the concrete ask, and the closing validation step.
    static func splitFile(repoPath: String, file: String, lines: Int,
                          hardLimit: Int = FindingPrompt.hardLimit) -> String {
        """
        Repo: \(repoPath)
        File: \(file) — \(lines) lines

        `\(file)` is \(lines) lines, over the \(hardLimit)-line hard limit. Split it into
        cohesive, single-responsibility files, each comfortably under \(hardLimit) lines,
        preserving behavior and the public API. Group related types together, keep access
        control and imports correct, and update every reference so nothing else breaks.

        When you're done, run `make validate` and confirm it passes before finishing.
        """
    }

    /// The prompt for any finding the app steers to an agent. A god-file gets the split
    /// template; anything else gets a context-rich generic ask built from the finding.
    static func forFinding(_ f: Finding, repoPath: String, file: String?, lines: Int?,
                           hardLimit: Int = FindingPrompt.hardLimit) -> String {
        if f.pass == "Census", let file, let lines {
            return splitFile(repoPath: repoPath, file: file, lines: lines, hardLimit: hardLimit)
        }
        let fileLine = file.map { "File: \($0)\n" } ?? ""
        return """
        Repo: \(repoPath)
        \(fileLine)Problem: \(f.what)
        Why it matters: \(f.why)

        Fix this in the repo above, preserving behavior and the public API. When you're
        done, run `make validate` and confirm it passes before finishing.
        """
    }
}

// MARK: - FindingTarget (pure mapping)

/// What a finding points at on disk — the file(s) an action would view / gitignore /
/// copy, plus the god-file line count. Derived from the finding's OWN structured repo
/// (census, hygiene, docs) where possible, and from the finding text only for the path
/// a god-file embeds. `resolve` returns nil for a finding with no actionable file
/// target and no dirty-tree git-status view.
struct FindingTarget: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case godFile, docBloat, junk, secret, trackedJunk, conflict, dirtyTree }
    var repoId: String
    var repoName: String
    var repoAbsPath: String          // ~-expanded absolute repo root
    var relPath: String?             // primary offending file/dir, repo-relative
    var lines: Int?                  // god-file / task-state line count when known
    var kind: Kind

    var id: String { repoId + "·" + kind.rawValue + "·" + (relPath ?? "") }
    var absPath: String? { relPath.map { (repoAbsPath as NSString).appendingPathComponent($0) } }

    var isGitStatus: Bool { kind == .dirtyTree }
    /// A concrete file we can render (a tracked-junk DIR name isn't viewable).
    var canViewFile: Bool { relPath != nil && kind != .dirtyTree && kind != .trackedJunk }
    var canExclude: Bool { kind == .godFile }                       // architecture scope is source-only
    var canGitignore: Bool { relPath != nil && (kind == .junk || kind == .secret || kind == .trackedJunk) }
    var canPrompt: Bool { kind == .godFile }                        // AI-split steering
    var isFileScoped: Bool { relPath != nil }

    /// The repo-relative path a god-file finding embeds in its `what` ("god-file: X"),
    /// or a doc-bloat finding's fixed filename. PURE — text only, no repo needed.
    static func embeddedPath(pass: String, what: String) -> String? {
        if pass == "Census", let r = what.range(of: "god-file: ") {
            let p = String(what[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            return p.isEmpty ? nil : p
        }
        if pass == "Docs" {
            if what.hasPrefix("TASK_STATE.md") { return "TASK_STATE.md" }
            if what.hasPrefix("CHANGELOG.md") { return "CHANGELOG.md" }
        }
        return nil
    }

    /// Map a finding to its on-disk target using the repo's structured facts. Returns
    /// nil when there's nothing a file-scoped action could touch.
    static func resolve(_ f: Finding, repo: Repo?) -> FindingTarget? {
        guard let repo else { return nil }
        let abs = (repo.absolutePath as NSString).expandingTildeInPath
        func make(_ kind: Kind, _ rel: String?, _ lines: Int? = nil) -> FindingTarget {
            FindingTarget(repoId: repo.id, repoName: repo.name, repoAbsPath: abs,
                          relPath: rel, lines: lines, kind: kind)
        }
        switch f.pass {
        case "Census":
            guard let rel = embeddedPath(pass: f.pass, what: f.what) else { return nil }
            let lines = (repo.census.godFiles + repo.census.excludedGodFiles).first { $0.path == rel }?.lines
            return make(.godFile, rel, lines)
        case "Docs":
            guard let rel = embeddedPath(pass: f.pass, what: f.what) else { return nil }
            return make(.docBloat, rel, rel == "TASK_STATE.md" ? repo.docs.taskState.lines : nil)
        case "Hygiene":
            // Guard each list so an empty one yields NO target (never an empty menu).
            if f.what.hasPrefix("merge markers"), let p = repo.hygiene.conflictFiles.first { return make(.conflict, p) }
            if f.what.hasPrefix("secret tracked"), let p = repo.hygiene.secretFiles.first { return make(.secret, p) }
            if f.what.contains("stray backup"), let p = repo.hygiene.junkFiles.first { return make(.junk, p) }
            if f.what.hasSuffix("committed"), let p = repo.hygiene.trackedJunk.first { return make(.trackedJunk, p) }
            return nil
        case "Worktree":
            if f.what.contains("uncommitted") { return make(.dirtyTree, nil) }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - FileViewerSheet (the modal)

/// A read-only viewer for a finding's offending file (bounded, line-numbered) or a
/// live `git status` for a dirty tree. Presented from a finding row via `.sheet`.
/// `app` is passed in explicitly (not read from the environment) so the footer's copy
/// actions are always wired regardless of sheet environment propagation.
struct FileViewerSheet: View {
    let app: AppState
    let target: FindingTarget
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState = .loading

    private enum LoadState: Sendable {
        case loading
        case file(text: String, lineCount: Int, bytes: Int, truncated: Bool)
        case output(text: String, ok: Bool)     // live git status
        case failed(String)
    }

    private static let sheetW: CGFloat = 800
    private static let sheetH: CGFloat = 620
    nonisolated private static let maxBytes = 200 * 1024   // read from the detached loader

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: Self.sheetW, height: Self.sheetH)
        .background(Theme.color.surface1)
        .task { await load() }
    }

    // ---- header ----
    private var header: some View {
        HStack(spacing: Theme.space.x2_5) {
            VibeIcon(target.isGitStatus ? "terminal" : "file-code-2", size: 16, color: Theme.color.accent)
            Text(target.isGitStatus ? "git status" : (target.relPath ?? "file"))
                .font(VibeFont.mono(VibeFont.size.md, .bold))
                .foregroundStyle(Theme.color.textBright)
                .lineLimit(1).truncationMode(.middle)
            Pill(text: target.repoName, icon: "folder-git-2")
            Spacer(minLength: Theme.space.x2)
            headerMeta
            Button { dismiss() } label: { VibeIcon("x", size: 15, color: Theme.color.textMuted) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }

    @ViewBuilder private var headerMeta: some View {
        switch state {
        case .file(_, let lineCount, let bytes, _):
            Text("\(lineCount) ln · \(byteLabel(bytes))")
                .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.textFaint)
        case .output(_, let ok):
            StatusBadge(text: ok ? "live" : "git error", tone: ok ? .ok : .danger, small: true)
        default:
            EmptyView()
        }
    }

    // ---- body ----
    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            centered { Text("reading…").font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textMuted) }
        case .failed(let why):
            centered { EmptyState(icon: "file-warning", tone: .warn, text: why) }
        case .output(let text, _):
            plainWell(text)
        case .file(let text, let lineCount, _, let truncated):
            VStack(spacing: 0) {
                if truncated {
                    Text("showing first 200 KB — the file is larger")
                        .font(VibeFont.mono(VibeFont.size.xxs)).foregroundStyle(Theme.color.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.space.x4).padding(.vertical, Theme.space.x2)
                        .background(Theme.color.warnSurfaceSoft)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.border).frame(height: 1) }
                }
                codeWell(text: text.isEmpty ? "(empty file)" : text, lineCount: max(lineCount, 1))
            }
        }
    }

    private func centered<V: View>(@ViewBuilder _ inner: () -> V) -> some View {
        inner().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.color.surfaceSunken)
    }

    /// Line-numbered code well: a right-aligned number gutter beside the source, both
    /// mono at the same line height so rows align, scrollable on both axes.
    private func codeWell(text: String, lineCount: Int) -> some View {
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 0) {
                Text(gutter(lineCount))
                    .font(VibeFont.mono(VibeFont.size.xs))
                    .foregroundStyle(Theme.color.textGhost)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(codeLineSpacing)
                    .padding(.vertical, Theme.space.x3)
                    .padding(.horizontal, Theme.space.x2_5)
                    .frame(minWidth: CGFloat(String(lineCount).count) * 9 + 16, alignment: .trailing)
                    .background(Theme.color.surface2)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.color.borderSubtle).frame(width: 1) }
                Text(text)
                    .font(VibeFont.mono(VibeFont.size.xs))
                    .foregroundStyle(Theme.color.textPrimary)
                    .lineSpacing(codeLineSpacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.vertical, Theme.space.x3)
                    .padding(.horizontal, Theme.space.x3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.color.surfaceSunken)
    }

    /// Plain (no gutter) monospace well for git-status output.
    private func plainWell(_ text: String) -> some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(VibeFont.mono(VibeFont.size.sm))
                .foregroundStyle(Theme.color.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(Theme.space.x4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.color.surfaceSunken)
    }

    // ---- footer ----
    private var footer: some View {
        HStack(spacing: Theme.space.x2_5) {
            if target.isGitStatus {
                VibeButton(title: "Re-run", icon: "refresh-cw", variant: .secondary, size: .sm) {
                    Task { await load() }
                }
                if case .output(let text, _) = state {
                    VibeButton(title: "Copy output", icon: "copy", variant: .ghost, size: .sm) {
                        app.copy(text, as: "git status")
                    }
                }
            } else if let abs = target.absPath, let rel = target.relPath {
                VibeButton(title: "Copy path", icon: "copy", variant: .ghost, size: .sm) {
                    app.copy(abs, as: "file path")
                }
                VibeButton(title: "Copy name", icon: "copy", variant: .ghost, size: .sm) {
                    app.copy((rel as NSString).lastPathComponent, as: "file name")
                }
                if target.canPrompt {
                    VibeButton(title: "Copy agent prompt", icon: "sparkles", variant: .accentGhost, size: .sm) {
                        app.copyAgentPrompt(target: target)
                    }
                }
            }
            Spacer()
            VibeButton(title: "Close", variant: .secondary, size: .sm) { dismiss() }
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x3)
        .frame(maxWidth: .infinity)
        .background(Theme.color.surface2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.color.border).frame(height: 1) }
    }

    // ---- load ----
    @MainActor private func load() async {
        state = .loading
        if target.isGitStatus {
            let r = await ProcessRunner.git(["-c", "color.ui=false", "status"], cwd: target.repoAbsPath)
            let body = r.stdout + (r.stderr.isEmpty ? "" : (r.stdout.isEmpty ? "" : "\n") + r.stderr)
            state = .output(text: body.isEmpty ? "(git produced no output)" : body, ok: r.ok)
            return
        }
        guard let abs = target.absPath else { state = .failed("no file path for this finding"); return }
        state = await Task.detached { FileViewerSheet.read(abs, maxBytes: Self.maxBytes) }.value
    }

    /// Bounded file read (≤ maxBytes), UTF-8 with a latin-1 fallback; binary content is
    /// refused rather than rendered as mojibake. Runs off the main actor.
    nonisolated private static func read(_ absPath: String, maxBytes: Int) -> LoadState {
        guard let handle = FileHandle(forReadingAtPath: absPath) else {
            return .failed("file not found on disk:\n\(absPath)")
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxBytes + 1)) ?? Data()
        let truncated = data.count > maxBytes
        let slice = truncated ? data.prefix(maxBytes) : data
        guard let text = String(data: slice, encoding: .utf8) ?? String(data: slice, encoding: .isoLatin1),
              !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return .failed("can't display — this looks like a binary file")
        }
        return .file(text: text, lineCount: FileProbes.lineCount(Data(text.utf8)), bytes: data.count, truncated: truncated)
    }

    private var codeLineSpacing: CGFloat { 2 }
    private func gutter(_ n: Int) -> String { (1...n).map(String.init).joined(separator: "\n") }
    private func byteLabel(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes) B" : String(format: "%.1f KB", Double(bytes) / 1024)
    }
}
