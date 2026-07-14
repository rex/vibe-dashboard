// Signals.swift — per-repo health signals (value types).

import Foundation

struct Gate: Identifiable, Sendable, Hashable {
    var name: String
    var command: String
    var status: GateStatus
    var detail: String
    var id: String { name }
}

struct WorktreeState: Sendable, Hashable {
    var clean: Bool = true
    var unstaged: Int = 0
    var unpushed: Int = 0
    var signed: Bool = true
    /// The real `git status --porcelain` lines (capped), so the UI can render the
    /// actual changed-file list — grouped staged/modified/untracked/renamed — not
    /// just the counts above. Empty ⇒ nothing to show ⇒ an honest "clean" panel.
    var statusLines: [String] = []
}

enum WorktreeLife: String, Sendable, Hashable { case active, stale, abandoned
    var tone: VibeTone { self == .active ? .ok : self == .stale ? .warn : .danger }
}

struct Worktree: Identifiable, Sendable, Hashable {
    var path: String              // absolute checkout path — unique per worktree
    var branch: String
    var created: String
    var lastCommit: String
    var commits: Int
    var state: WorktreeLife
    var dirty: Bool = false        // uncommitted edits INSIDE this linked worktree (git status --porcelain)
    // Identity is the PATH, not the branch: two worktrees can share a branch name (or
    // the synthetic `detached@…` label), which collided under a branch-keyed id and
    // caused ForEach identity thrash. A checkout path is unique.
    var id: String { path }
}

struct FileLines: Identifiable, Sendable, Hashable {
    var path: String
    var lines: Int
    var excluded: Bool = false   // matched by architecture.exclude_globs — shown, not graded
    var id: String { path }
}

struct Census: Sendable, Hashable {
    var scanned: Int = 0
    var softCount: Int = 0
    var godFiles: [FileLines] = []          // over hard AND in scope — these are graded
    var excludedGodFiles: [FileLines] = []  // over hard but excluded via exclude_globs — shown, never graded
    var largest: [FileLines] = []
}

struct Drift: Sendable, Hashable {
    var behind: String? = nil       // e.g. "3 minor behind" vs skeleton fleet-max
    var files: Int = 0
    var version: String? = nil      // this repo's stamped .claude/skeleton-version
    var latest: String? = nil       // newest skeleton-version seen across the fleet
}

/// "Classic vibe-coding shenanigans" a local scanner can catch that a policy
/// file never will. Near-zero-false-positive facts only — alert fatigue is the
/// enemy, so every field here must mean a real, actionable problem.
struct Hygiene: Sendable, Hashable {
    var conflictFiles: [String] = []   // files with live <<<<<<< merge-conflict markers
    var junkFiles: [String] = []       // Finder dupes / .orig / .bak / .DS_Store on disk
    var secretFiles: [String] = []     // tracked .env / *.pem / id_rsa — secrets in git
    var trackedJunk: [String] = []     // node_modules / DerivedData / .venv committed to git
    var stashCount: Int = 0            // forgotten `git stash` entries
}

/// A detected live coding-agent session, populated from real git/process facts —
/// never constants. `linesAdded`/`linesRemoved` are nil when the diff could not be
/// measured (e.g. a repo with no HEAD) so the UI can HIDE them rather than render a
/// fabricated "+0 −0"; a measured no-op is a real 0 and is shown.
struct AgentInfo: Sendable, Hashable {
    var id: String = ""
    var active: Bool = false
    var state: AgentState = .active  // active (lime, <15m) vs idle (15–60m since last activity)
    var tool: String? = nil
    var branch: String? = nil
    var elapsed: String? = nil
    var sessionKind: AgentSessionKind = .standard
    var transcriptPath: String? = nil
    var workflowId: String? = nil
    var agentCount: Int? = nil       // workflow cards: agent transcripts currently in play
    var model: String? = nil         // recorded in the transcript; nil = not recorded (hide)
    var effort: String? = nil        // Codex reasoning effort; Claude doesn't record one
    var contextTokens: Int? = nil    // context-window tokens as of the last turn
    var filesTouched: Int = 0        // real: files changed vs HEAD (git diff --numstat)
    var linesAdded: Int? = nil       // real added lines; nil = not measurable (don't render)
    var linesRemoved: Int? = nil     // real removed lines; nil = not measurable (don't render)
    var lastActivityAt: Date? = nil
    var lastActivity: String = "—"   // RelTime.ago of the newest transcript/work-tree activity; "—" if unknown
    var note: String = "idle"        // honest summary derived from the real diff
}

extension AgentInfo {
    /// Build a live-session AgentInfo from a detected session + its measured work — the
    /// single construction path shared by the full scan and the background agent refresh.
    static func live(session s: AgentProbe.Session, work: AgentProbe.WorkStat,
                     clean: Bool, branch: String, now: Date) -> AgentInfo {
        let activityAt = [s.lastActivity, work.lastWrite].compactMap { $0 }.max()
        return AgentInfo(
            id: s.id, active: true, state: s.state, tool: s.tool, branch: branch, elapsed: s.elapsed,
            sessionKind: s.kind,
            transcriptPath: s.transcriptPath,
            workflowId: s.workflowId,
            agentCount: s.agentCount,
            model: s.telemetry.model,
            effort: s.telemetry.effort,
            contextTokens: s.telemetry.contextTokens,
            filesTouched: work.filesTouched,
            linesAdded: work.measured ? work.linesAdded : nil,
            linesRemoved: work.measured ? work.linesRemoved : nil,
            lastActivityAt: activityAt,
            lastActivity: activityAt.map { RelTime.ago($0, now: now) } ?? "—",
            note: note(work: work, clean: clean))
    }

    /// Honest one-line session summary from the measured diff — no constants.
    static func note(work: AgentProbe.WorkStat, clean: Bool) -> String {
        if work.filesTouched > 0 {
            return "\(work.filesTouched) file\(work.filesTouched == 1 ? "" : "s") changed since last commit"
        }
        return clean ? "live session · working tree clean" : "untracked changes in the working tree"
    }
}

struct DocFile: Sendable, Hashable {
    var lines: Int = 0
    var bytes: Int = 0
    var status: GateStatus = .ok
    var present: Bool = true
}

struct ChangelogInfo: Sendable, Hashable {
    var lastUpdated: String = "—"
    var behind: Int = 0
    var status: GateStatus = .ok
    var present: Bool = true
}

struct Docs: Sendable, Hashable {
    var taskState = DocFile()
    var agentsMd = DocFile()
    var claudeMd = DocFile()
    var changelog = ChangelogInfo()
    var taskStateMarkdown: String = ""
}

struct SerenaState: Sendable, Hashable {
    var present: Bool = false
    var active: Bool = false
    var project: String = ""
    var memories: Int = 0
    var lastSession: String = "—"
}

/// One deduction in a repo's grade — the "why this grade" building block. The
/// factor list IS the grade: compliance = 100 + Σdelta (clamped), health from the
/// score bands plus `critical` overrides. Every factor is visible in the repo's
/// breakdown panel, so a rating is never a mystery.
struct GradeFactor: Identifiable, Sendable, Hashable {
    var label: String        // "2 uncommitted files"
    var delta: Int           // negative points against the 100 baseline
    var tone: VibeTone
    var critical: Bool = false   // forces danger regardless of the score
    var detail: String = ""      // one line of why it matters
    var id: String { label }
}

struct Finding: Identifiable, Sendable, Hashable {
    var severity: Severity
    var pass: String
    var what: String
    var why: String
    var fix: String? = nil
    var repoId: String? = nil
    var repoName: String? = nil
    var id: String { (repoId ?? "") + "·" + pass + "·" + what }
}

// MARK: - Git status grouping (porcelain → readable buckets)

/// One changed path in a grouped `git status` view — a single file (or `old → new`
/// for a rename/copy), tagged with the raw 2-char porcelain XY code it came from.
struct GitStatusEntry: Identifiable, Sendable, Hashable {
    var code: String     // porcelain XY prefix, e.g. " M", "??", "R "
    var path: String     // display path; "old → new" for renames/copies
    var id: String { code + "·" + path }
}

/// The bucket a change falls into, with a glanceable tone + glyph. Declaration
/// order is the display order of the git-status panel (loudest first).
enum GitStatusKind: String, Sendable, Hashable, CaseIterable {
    case conflicted, staged, renamed, modified, deleted, untracked

    var label: String {
        switch self {
        case .conflicted: return "conflicted"
        case .staged: return "staged"
        case .renamed: return "renamed"
        case .modified: return "modified"
        case .deleted: return "deleted"
        case .untracked: return "untracked"
        }
    }
    var tone: VibeTone {
        switch self {
        case .conflicted: return .danger
        case .staged: return .ok
        case .renamed: return .info
        case .modified: return .warn
        case .deleted: return .danger
        case .untracked: return .neutral
        }
    }
    var icon: String {
        switch self {
        case .conflicted: return "octagon-alert"
        case .staged: return "check"
        case .renamed: return "arrow-right"
        case .modified: return "file-text"
        case .deleted: return "trash-2"
        case .untracked: return "plus"
        }
    }
}

struct GitStatusGroup: Identifiable, Sendable, Hashable {
    var kind: GitStatusKind
    var entries: [GitStatusEntry]
    var id: String { kind.rawValue }
}

/// Pure porcelain-v1 → grouped-status parsing. `git status --porcelain` emits one
/// `XY <path>` line per change (`R  old -> new` for renames, `?? path` for
/// untracked). We bucket by the most meaningful axis so a panel reads the way a
/// human would summarize the tree. Pure + testable — no IO, no side effects.
enum GitStatus {
    static func group(_ lines: [String]) -> [GitStatusGroup] {
        var buckets: [GitStatusKind: [GitStatusEntry]] = [:]
        for raw in lines {
            guard raw.count >= 3 else { continue }             // "XY path"
            let code = String(raw.prefix(2))
            let rest = String(raw.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty else { continue }
            let x = code.first ?? " "
            let y = code.dropFirst().first ?? " "
            let kind = classify(x: x, y: y)
            buckets[kind, default: []].append(
                GitStatusEntry(code: code, path: displayPath(rest, renamed: kind == .renamed)))
        }
        return GitStatusKind.allCases.compactMap { k in
            buckets[k].map { GitStatusGroup(kind: k, entries: $0) }
        }
    }

    /// XY porcelain code → bucket. Check order encodes priority: an unmerged pair is
    /// a conflict; `??` is untracked; an R/C on either side is a rename/copy; a D on
    /// either side is a deletion; any other index letter is a staged change; else a
    /// worktree modification. Pure + testable.
    static func classify(x: Character, y: Character) -> GitStatusKind {
        let conflict: Set<String> = ["DD", "AA", "AU", "UD", "UA", "DU", "UU"]
        if conflict.contains(String([x, y])) { return .conflicted }
        if x == "?" && y == "?" { return .untracked }
        if x == "R" || y == "R" || x == "C" || y == "C" { return .renamed }
        if x == "D" || y == "D" { return .deleted }
        if x != " " && x != "?" { return .staged }             // staged index change
        return .modified                                       // unstaged worktree edit
    }

    /// A rename/copy line is `old -> new`; render it with a nice arrow. Everything
    /// else passes through unchanged. Pure + testable.
    static func displayPath(_ s: String, renamed: Bool) -> String {
        guard renamed, let r = s.range(of: " -> ") else { return s }
        return String(s[..<r.lowerBound]) + " → " + String(s[r.upperBound...])
    }
}
