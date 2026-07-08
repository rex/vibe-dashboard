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
    var active: Bool = false
    var tool: String? = nil
    var branch: String? = nil
    var elapsed: String? = nil
    var filesTouched: Int = 0        // real: files changed vs HEAD (git diff --numstat)
    var linesAdded: Int? = nil       // real added lines; nil = not measurable (don't render)
    var linesRemoved: Int? = nil     // real removed lines; nil = not measurable (don't render)
    var lastActivity: String = "—"   // RelTime.ago of the newest working-tree mtime; "—" if unknown
    var note: String = "idle"        // honest summary derived from the real diff
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
