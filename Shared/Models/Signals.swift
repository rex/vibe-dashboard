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
    var branch: String
    var created: String
    var lastCommit: String
    var commits: Int
    var state: WorktreeLife
    var id: String { branch }
}

struct FileLines: Identifiable, Sendable, Hashable {
    var path: String
    var lines: Int
    var id: String { path }
}

struct Census: Sendable, Hashable {
    var scanned: Int = 0
    var softCount: Int = 0
    var godFiles: [FileLines] = []
    var largest: [FileLines] = []
}

struct Drift: Sendable, Hashable {
    var behind: String? = nil
    var files: Int = 0
}

struct AgentInfo: Sendable, Hashable {
    var active: Bool = false
    var tool: String? = nil
    var branch: String? = nil
    var elapsed: String? = nil
    var filesTouched: Int = 0
    var linesAdded: Int? = nil
    var linesRemoved: Int? = nil
    var lastActivity: String = "—"
    var note: String = "idle"
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
