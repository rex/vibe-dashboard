# Changelog

All notable changes to Vibe Dashboard are documented here. Format loosely
follows Keep a Changelog; versions are semver from `VERSION`.

## [0.53.0] — 2026-07-09

### Changed
- **Severity-weighted grading**: health is no longer a flat OR that let one
  dirty file rate like committed secrets. Every problem is a weighted factor;
  compliance = 100 − deductions, health from the score bands, and critical
  factors (governance fraud, merge markers, tracked secrets, an unguarded live
  agent) still force danger. Dirty/unpushed scale with size; a live session
  halves the dirty penalty.
- **"Why this grade"**: every repo's COMPLIANCE panel lists each deduction
  (criticals flagged); the fleet compliance column shows the top reasons on
  hover. The factor list IS the grade — they cannot disagree.
- **Targeted rescan is full-fidelity**: excluding a god-file (or any VIBE.yaml
  edit) re-probes just that repo — census, policy, docs, hygiene — and updates
  all views in seconds; no more fleet sweep for a one-line edit.
- Fleet table mirrors the sidebar's filesystem structure; stat tiles compacted
  to fit one row; agent cards widened with model / effort / context-window
  telemetry from the transcript; the live-agent pulse animates again (active
  agents only, low-rate periodic timeline).

## [0.51.0] — 2026-07-09

### Added
- **Watch lanes**: workflow watching now renders concurrency LANES whose streams
  continue through phase handoffs — when an agent returns and the next one picks
  up, the same lane keeps streaming behind a loud in-stream "hop" divider (stage
  number, the new agent's task, start time). Lane assignment replays the
  workflow's `journal.jsonl`; convergence lands in the lowest freed lane.
- **Named, plan-aware workflow windows**: the persisted script's `meta` literal
  (name, description, phase titles) and the terminal `wf_<id>.json` (status,
  summary, duration) drive the window title, a "plan: …" phase strip, real
  "k/N agents returned" progress, and a completed badge. Lane titles fall back
  to the agent's actual prompt when its meta.json carries no description.
- **FSEvents push updates**: transcript writes refresh agent cards in ~1s and
  tick watch windows in ~150ms; repo writes trigger a per-repo debounced
  re-score (noise-filtered, echo-cooled) — no full rescan needed for a repo's
  grade to track reality.

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
