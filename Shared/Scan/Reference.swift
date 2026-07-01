// Reference.swift — static reference data: skill catalog, doc limits,
// skeleton policy defaults, autopilot defaults, relative-time formatting.

import Foundation

enum Reference {
    // Composable-skill catalog (lang-* / tool-* + the skeleton).
    static let skillCatalog: [SkillDef] = [
        SkillDef(skillId: "agentic-skeleton", name: "agentic-skeleton", kind: "skeleton", version: "0.2.0", ns: "—", owns: "collaboration container + universal contracts"),
        SkillDef(skillId: "lang-python", name: "lang-python", kind: "lang", version: "0.1.0", ns: "python", owns: "FastAPI · Pydantic v2 · async SQLAlchemy · uv · ruff · mypy"),
        SkillDef(skillId: "lang-react", name: "lang-react", kind: "lang", version: "0.1.0", ns: "react", owns: "React component & hook idioms"),
        SkillDef(skillId: "lang-react-spa", name: "lang-react-spa", kind: "lang", version: "0.1.0", ns: "react_spa", owns: "SPA routing, state, build layout"),
        SkillDef(skillId: "lang-go", name: "lang-go", kind: "lang", version: "0.1.0", ns: "go", owns: "Go service & module patterns"),
        SkillDef(skillId: "lang-mcp", name: "lang-mcp", kind: "lang", version: "0.2.0", ns: "mcp", owns: "MCP server tool/resource patterns"),
        SkillDef(skillId: "lang-docker", name: "lang-docker", kind: "lang", version: "0.1.0", ns: "docker", owns: "Dockerfile + compose conventions"),
        SkillDef(skillId: "lang-swift-apple", name: "lang-swift-apple", kind: "lang", version: "0.1.0", ns: "apple", owns: "SwiftUI · Apple platform idioms"),
        SkillDef(skillId: "lang-browser-extension", name: "lang-browser-extension", kind: "lang", version: "0.1.0", ns: "webext", owns: "WebExtension MV3 patterns"),
        SkillDef(skillId: "tool-ci", name: "tool-ci", kind: "tool", version: "0.1.0", ns: "ci", owns: "GitHub / Gitea Actions workflows"),
        SkillDef(skillId: "tool-vite", name: "tool-vite", kind: "tool", version: "0.1.0", ns: "vite", owns: "Vite build & dev-server config"),
    ]

    // Doc-size policy (lines) the app applies to agent-written files.
    static let docLimits: [String: (soft: Int, hard: Int)] = [
        "taskState": (400, 800),
        "agentsMd": (300, 500),
        "code": (250, 400),
    ]

    // Skeleton default values, for the inline policy diff (section.key → default).
    static let skeletonDefaults: [String: String] = [
        "architecture.max_public_functions_per_module": "6",
        "architecture.mode": "standard",
        "quality_gates.coverage.minimum_percentage": "70",
        "workflow.default_slice_completion_behavior": "stop-on-slice",
    ]

    // Fleet-wide autopilot rules (destructive ones start disarmed).
    static func defaultAutopilot(repoCount: Int) -> [AutopilotRule] {
        [
            AutopilotRule(ruleId: "rescan", label: "re-check on save", desc: "fsevents → re-run gates for the touched repo, debounced 2s", scope: "all repos", armed: true, danger: false, lastRan: "—", runs: 0),
            AutopilotRule(ruleId: "format", label: "format on save", desc: "run ruff / prettier / swiftformat on files an agent writes, before they commit", scope: "\(repoCount) repos", armed: true, danger: false, lastRan: "—", runs: 0),
            AutopilotRule(ruleId: "task-state-alarm", label: "alarm on TASK_STATE bloat", desc: "notify when TASK_STATE.md crosses 800 lines — an agent is hoarding state", scope: "all repos", armed: true, danger: false, lastRan: "—", runs: 0),
            AutopilotRule(ruleId: "prune-worktrees", label: "prune abandoned worktrees", desc: "git worktree remove for branches with 0 commits, untouched > 14 days", scope: "all repos", armed: false, danger: true, lastRan: "never", runs: 0),
            AutopilotRule(ruleId: "auto-push", label: "sign + push clean commits", desc: "when a worktree is clean and gates are green, sign and push automatically", scope: "all repos", armed: false, danger: true, lastRan: "never", runs: 0),
            AutopilotRule(ruleId: "skeleton-bump", label: "bump skeleton (minor)", desc: "pull drifted skeleton-owned files when only minor versions behind", scope: "all repos", armed: false, danger: true, lastRan: "never", runs: 0),
            AutopilotRule(ruleId: "install-hooks", label: "install skeleton agent hooks", desc: "install the missing PreToolUse bash-guard + Stop validate-gate and wire settings.json", scope: "repos missing", armed: false, danger: false, lastRan: "never", runs: 0),
        ]
    }

    // Source-file extensions considered by the line census, per stack family.
    static let codeExtensions: Set<String> = [
        "swift", "py", "ts", "tsx", "js", "jsx", "go", "rs", "kt", "java",
        "rb", "c", "cc", "cpp", "h", "m", "mm", "sh",
    ]
    static let ansibleExtensions: Set<String> = ["yml", "yaml"]
}

/// Relative-time formatting ("3s ago" … "5 weeks ago").
enum RelTime {
    static func ago(_ date: Date, now: Date) -> String {
        let s = Swift.max(0, now.timeIntervalSince(date))
        switch s {
        case ..<5: return "just now"
        case ..<60: return "\(Int(s))s ago"
        case ..<3600: return "\(Int(s / 60))m ago"
        case ..<86_400: return "\(Int(s / 3600))h ago"
        case ..<604_800: return "\(Int(s / 86_400))d ago"
        case ..<2_592_000:
            let w = Int(s / 604_800); return "\(w) week\(w == 1 ? "" : "s") ago"
        default:
            let mo = Int(s / 2_592_000); return "\(mo) month\(mo == 1 ? "" : "s") ago"
        }
    }
    /// Commits-behind phrasing helper.
    static func compact(_ interval: TimeInterval) -> String {
        ago(Date(timeIntervalSinceNow: -interval), now: Date(timeIntervalSinceNow: 0))
    }
}
