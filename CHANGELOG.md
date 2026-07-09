# Changelog

All notable changes to Vibe Dashboard are documented here. Format loosely
follows Keep a Changelog; versions are semver from `VERSION`.

## [0.48.0] — 2026-07-09

### Added
- **Agent Watch window**: transcript watching moved from a fixed modal sheet to
  a dedicated resizable window per target — full-height panes per agent,
  incremental byte-offset tailing (only appended bytes are read per 0.7s tick),
  sticky bottom-follow with a "↓ n new" chip and a follow-all control, block
  markdown rendering (fenced code wells, headings, lists, quotes, tables),
  tool calls paired with their results into single collapsed rows (expand for
  input/result; live "running" state until the result lands), ghosted thinking
  rows, workflow hop dividers, pane titles/status from `meta.json` +
  `journal.jsonl` (spawn order, returned-vs-running, recorded result), and
  ⌘+/⌘−/⌘0 font control persisted across windows.
- Watch entry points from both the Agents module and the repo-detail Agent tab.

### Fixed
- **Agent auto-refresh never ran**: the background monitor was started only
  after the initial fleet scan completed, so a slow or wedged scan silently
  disabled live-agent detection. It now starts before the scan, ticks
  immediately, runs every 30s, and refreshes on app activation.
- **Session cards collapse to human units**: one card per workflow instead of
  one per workflow agent file; subagent transcripts fold into their parent
  session and extend its liveness instead of spawning duplicate cards.

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
