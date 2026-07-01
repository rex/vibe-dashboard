# Changelog

All notable changes to Vibe Dashboard are documented here. Format loosely
follows Keep a Changelog; versions are semver from `VERSION`.

## [0.2.0] — 2026-07-01

### Added
- **Design system** ported to SwiftUI: Vibe tokens (ink ramp, acid-lime accent,
  tight radii, phosphor glow), the two-family type system (vendored JetBrains
  Mono + Space Grotesk), a Lucide→SF Symbol bridge, and the full component
  library (panel, buttons, tag/status/severity/grade badges, meter, gate row,
  tabs, fields, toast, brand marks: VibeMark/VibeLogo/AppEmblem/LangGlyph).
- **Live `~/Code` scanner** (no mock data): discovery + nested-workspace
  detection, git (branch/dirty/unpushed/signature/remotes/worktrees), line
  census, doc bloat, Serena, `.claude`/`.git`/`.cursor` hooks, `.mcp.json`,
  Yams-parsed `VIBE.yaml` + skeleton diff, live claude/codex session detection
  (ps + lsof), and derived gates/compliance/health/findings/grades. Fleet is
  filtered to managed (agentic) repos.
- **Native Mac chrome**: unified toolbar (segmented nav, ⌘K search, Re-scan,
  panel toggles), source-list sidebar (nested tree + scanner footer),
  contextual inspector, console drawer (output · shell · live activity), status
  bar, menu-bar Commands + a MenuBarExtra fleet popover.
- **All screens**: Fleet, Agents, Findings, Skills, Autopilot, Workspace
  rollup, and the 7-tab Repo detail (Overview / Gates / Policy / Census /
  Build & Ship / Agent / Hooks & MCP) + per-repo Findings.
- **Overlays**: ⌘K command palette + confirm-gated write sheets.
- Running Makefile targets into the shell console (`make validate`, etc.).

## [0.1.0] — 2026-07-01

### Added
- Scaffolded the macOS app from the `lang-swift-apple` standard: xcodegen
  `project.yml` (macOS app + Swift Testing target, Yams dependency), Makefile
  with the universal build/validate interface, Privacy Manifest, entitlements
  (un-sandboxed local dev tool), version stamping via `generate-build-info.sh`.
- Agentic-skeleton collaboration contracts: `AGENTS.md`, `VIBE.yaml`,
  `TASK_STATE.md`, `MAP.md`, `CHANGELOG.md`, `CLAUDE.md`/`GEMINI.md` symlinks.
