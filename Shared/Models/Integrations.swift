// Integrations.swift — build/SCM/CI/containers/hooks/MCP/skills/policy models.

import Foundation

struct RepoBuild: Sendable, Hashable {
    var version: String = "v0.1.0"
    var commit: String = "-------"
    var date: String = "—"
    var dirty: Bool = false
    var branch: String = "main"
}

enum TargetKind: String, Sendable, Hashable { case gate, run, util }
struct MakeTarget: Identifiable, Sendable, Hashable {
    var name: String
    var desc: String
    var kind: TargetKind
    var id: String { name }
}
struct MakefileInfo: Sendable, Hashable {
    var count: Int = 0
    var note: String? = nil
    var targets: [MakeTarget] = []
}

struct Note: Identifiable, Sendable, Hashable {
    var tone: VibeTone
    var text: String
    var id: String { text }
}

struct Remote: Identifiable, Sendable, Hashable {
    var name: String
    var host: String       // github | gitea | other
    var url: String
    var ahead: Int = 0
    var behind: Int = 0
    var primary: Bool = false
    var mirror: Bool = false
    var id: String { name }
}

struct Scm: Sendable, Hashable {
    var branch: String = "main"
    var remotes: [Remote] = []
    var grade: String = "n/a"
    var notes: [Note] = []
    var signed: Bool = true
}

struct CiWorkflow: Identifiable, Sendable, Hashable {
    var name: String
    var trigger: String
    var status: GateStatus
    var last: String
    var id: String { name }
}
struct CiInfo: Sendable, Hashable {
    var provider: String = "none"
    var configured: Bool = false
    var workflows: [CiWorkflow] = []
    var grade: String = "n/a"
    var notes: [Note] = []
}

struct CheckItem: Identifiable, Sendable, Hashable {
    var ok: Bool
    var text: String
    var id: String { text }
}
struct ContainerItem: Identifiable, Sendable, Hashable {
    var kind: String        // dockerfile | compose
    var path: String
    var checks: [CheckItem]
    var grade: String
    var id: String { path }
}
struct Containers: Sendable, Hashable {
    var configured: Bool = false
    var items: [ContainerItem] = []
    var grade: String = "n/a"
    var notes: [Note] = []
}

enum HookStatus: String, Sendable, Hashable {
    case active, nothing, missing, drift, disabled
    var tone: VibeTone {
        switch self {
        case .active: return .ok
        case .nothing, .drift: return .warn
        case .missing: return .danger
        case .disabled: return .neutral
        }
    }
}
struct Hook: Identifiable, Sendable, Hashable {
    var src: String         // claude | codex | git | cursor
    var event: String
    var matcher: String? = nil
    var command: String
    var status: HookStatus
    var scope: String = "project"
    var skel: Bool = false
    var note: String? = nil
    var id: String { src + "·" + event + "·" + command }
}

enum McpStatus: String, Sendable, Hashable {
    // `configured` = declared in .mcp.json but reachability NOT verified (we don't
    // connect). It renders neutral, never a green "connected" we never measured.
    case configured, connected, failed, unused, disabled
    var tone: VibeTone {
        switch self {
        case .connected: return .ok
        case .configured: return .neutral
        case .failed: return .danger
        case .unused: return .warn
        case .disabled: return .neutral
        }
    }
}
struct McpServer: Identifiable, Sendable, Hashable {
    var name: String
    var transport: String   // stdio | http | sse
    var target: String
    var status: McpStatus
    var tools: [String] = []
    var scope: String = "project"
    var agents: [String] = ["claude"]
    var broad: Bool = false
    var note: String? = nil
    var id: String { name }
}

struct Consumer: Identifiable, Sendable, Hashable {
    var repoId: String
    var name: String
    var status: String
    var token: String
    var id: String { repoId }
}
struct ServesInfo: Sendable, Hashable {
    var transport: String
    var capability: String
    var tools: [String]
    var guarded: [String]
    var consumers: [Consumer]
}

enum SkillState: String, Sendable, Hashable { case ok, drift, behind, missing
    var tone: VibeTone { self == .ok ? .ok : self == .missing ? .danger : .warn }
}
struct SkillUse: Identifiable, Sendable, Hashable {
    var skillId: String
    var installed: String? = nil
    var status: SkillState = .ok
    var note: String? = nil
    var id: String { skillId }
}
struct SkillDef: Identifiable, Sendable, Hashable {
    var skillId: String
    var name: String
    var kind: String        // skeleton | lang | tool
    var version: String
    var ns: String
    var owns: String
    var id: String { skillId }
}

struct PolicyRow: Identifiable, Sendable, Hashable {
    var k: String
    var v: String
    var note: String? = nil   // "delta" | "invalid"
    var skel: String? = nil
    var matched: String? = nil
    var values: [String]? = nil   // full list for array-valued keys (exclude_globs, scope_globs…)
    var id: String { k }
}
struct PolicySection: Identifiable, Sendable, Hashable {
    var section: String
    var rows: [PolicyRow]
    var id: String { section }
}

struct AutopilotRule: Identifiable, Sendable, Hashable {
    var ruleId: String
    var label: String
    var desc: String
    var scope: String
    var armed: Bool
    var danger: Bool
    var lastRan: String
    var runs: Int
    var id: String { ruleId }
}

struct ActivityEntry: Identifiable, Sendable, Hashable {
    var t: String
    var kind: String        // fsevents | agent | autopilot | scan
    var repo: String
    var msg: String
    var tone: VibeTone
    var seq: Int
    var id: Int { seq }
}
