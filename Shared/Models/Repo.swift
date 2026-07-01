// Repo.swift — the aggregate repo model.

import Foundation

enum RepoKind: String, Sendable, Hashable { case repo, workspace }

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
    var signedRequired: Bool = false   // VIBE.yaml workflow.signed_commits_required

    // rollup
    var health: Health = .ok
    var compliance: Int = 100
    var checked: String = "just now"

    // signals
    var gates: [Gate] = []
    var coverage: Int? = nil
    var coverageFloor: Int? = nil
    var worktree = WorktreeState()
    var census = Census()
    var drift = Drift()
    var agent: AgentInfo? = nil
    var worktrees: [Worktree] = []
    var docs = Docs()
    var serena: SerenaState? = nil
    var surprises: [Finding] = []

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
    var agentActive: Bool { agent?.active ?? false }
    var lang: Lang { Brand.langOf(stack) }

    func hasActiveGuardrail() -> Bool {
        hooks.contains { $0.event == "PreToolUse" && $0.status == .active }
    }
    var abandonedWorktrees: Int { worktrees.filter { $0.state == .abandoned }.count }
    var staleWorktrees: Int { worktrees.filter { $0.state != .active }.count }
}
