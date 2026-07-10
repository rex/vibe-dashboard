// Repo.swift — the aggregate repo model.

import Foundation

enum RepoKind: String, Sendable, Hashable { case repo, workspace }

/// How thoroughly a repo is governed by the agentic skeleton. The whole point of
/// this app is to surface the repos drifting *out* of management.
enum ManagementLevel: String, Sendable, Hashable {
    case skeleton    // VIBE.yaml + a Makefile — policy AND the machinery to enforce it
    case partial     // VIBE.yaml present but no Makefile — policy nobody can run
    case unmanaged   // no VIBE.yaml — an agent has been here, but nothing governs it

    var label: String {
        switch self {
        case .skeleton: return "managed"
        case .partial: return "partial"
        case .unmanaged: return "UNMANAGED"
        }
    }
    var tone: VibeTone {
        switch self {
        case .skeleton: return .ok
        case .partial: return .warn
        case .unmanaged: return .danger
        }
    }
    var governed: Bool { self == .skeleton }
}

struct Repo: Identifiable, Sendable, Hashable {
    var id: String                       // stable, path-derived
    var name: String
    var path: String                     // display path (~/Code/…)
    var absolutePath: String
    var kind: RepoKind = .repo
    var parentId: String? = nil
    var children: [String] = []          // workspace child ids

    // identity
    var stack: String = "unknown"
    var lifecycle: String = "brownfield"
    var pm: String = "—"
    var framework: String = "—"
    var desc: String = ""
    var managed: Bool = false      // has VIBE.yaml / AGENTS.md / .claude — an agentic repo
    var vibePresent: Bool = false  // a VIBE.yaml file exists on disk (parseable or not)
    var vibeMalformed: Bool = false  // VIBE.yaml exists but Yams failed to parse it
    var management: ManagementLevel = .skeleton   // how completely the skeleton governs it
    var signedRequired: Bool = false   // VIBE.yaml workflow.signed_commits_required

    // rollup
    var health: Health = .ok
    var compliance: Int = 100
    var checkedAt: Date = Date()   // real wall-clock time this repo was last probed
    var checked: String = "just now"   // deprecated: prefer checkedAt + RelTime.ago (ages between scans)

    // signals
    var gates: [Gate] = []
    var coverage: Int? = nil
    var coverageFloor: Int? = nil
    var worktree = WorktreeState()
    var census = Census()
    var drift = Drift()
    var hygiene = Hygiene()
    var agents: [AgentInfo] = []       // every retained live/idle session mapped to this repo
    var agent: AgentInfo? = nil
    var worktrees: [Worktree] = []
    var docs = Docs()
    var serena: SerenaState? = nil
    var surprises: [Finding] = []
    var gradeFactors: [GradeFactor] = []   // the "why this grade" breakdown (empty = clean bill)
    var waivedSurprises: [Finding] = []    // findings actively waived — out of the feed AND the grade

    // local-only signals
    var build = RepoBuild()
    var makefile = MakefileInfo()
    var scm = Scm()
    var ci = CiInfo()
    var containers = Containers()
    var hooks: [Hook] = []
    var mcp: [McpServer] = []
    var serves: ServesInfo? = nil
    var skills: [SkillUse] = []
    var policy: [PolicySection] = []

    // derived
    var isWorkspace: Bool { kind == .workspace }
    var emblem: String { Brand.emblem(id: name, stack: stack) }
    var agentSessions: [AgentInfo] { agents.isEmpty ? agent.map { [$0] } ?? [] : agents }
    var agentActive: Bool { !agentSessions.isEmpty }
    var lang: Lang { Brand.langOf(stack) }

    func hasActiveGuardrail() -> Bool {
        hooks.contains { $0.event == "PreToolUse" && $0.status == .active }
    }
    var abandonedWorktrees: Int { worktrees.filter { $0.state == .abandoned }.count }
    var staleWorktrees: Int { worktrees.filter { $0.state != .active }.count }
}
