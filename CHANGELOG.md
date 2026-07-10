# Changelog

All notable changes to Vibe Dashboard are documented here. Format loosely
follows Keep a Changelog; versions are semver from `VERSION`.

## [0.66.0] — 2026-07-10

### Fixed
- **Watch panes no longer "reset" mid-watch — lane identity is now sacred.**
  Standard-session lanes (a session fanning out Agent-tool subagents, no
  workflow journal) were numbered by position in a name-sorted, recency-filtered
  file listing; agent ids are random hex, so each new wave's files interleaved
  alphabetically and shifted almost every lane — a completed pane suddenly
  streamed a *different* agent's transcript from the top (hit live on a
  19-subagent, 3-wave session). Lanes now stick to their FILE for the life of
  the window: new agents append after the highest existing id, and a file that
  ages past the recency filter stays put once shown (the filter only gates new
  admissions on a fresh watch).
- Workflow lanes hardened against the same class: replay-slot ids survive a
  slot whose agent file hasn't landed yet (no more compress-and-renumber), and
  on-disk-but-unjournaled files are admitted only on their second consecutive
  sighting — in their own high id space — instead of flashing into a lane and
  immediately migrating into their replay slot.

## [0.64.0] — 2026-07-10

### Fixed
- **The CPU saga, closed: ~125% → 12.5% (Debug, Xcode-attached)** — five
  sampled culprits, five fixes: (1) fleet reassembly on every transcript
  append → meaningful-change gating; (2) per-append watch-window ticks +
  whole-array lane publishing → per-lane observable boxes (a content tick
  re-renders one lane, not eight); (3) the pulse animating layout — first as
  height, then as an animated scaleEffect — → Canvas drawing in a fixed
  frame (sampled layout frames: 9,676 → 1), same for the scan bar and rescan
  spinner (zero repeatForever remains); (4) session detection re-parsing
  ~1.25 MB per recent transcript every ~5s → facts cached on (mtime, size);
  (5) six pulse instances each committing display updates on their own phase
  → one shared epoch, one commit per beat.
- FSEvents refresh debounce livelock (continuous events cancelled the pending
  refresh forever); targeted rescans no longer light the global "scanning"
  indicator; agent-busy repos re-probe at 30s.
- Phantom repos: a VIBE'd directory without its own .git (e.g. skeleton
  templates) no longer inherits the enclosing repo's git state; conflict
  markers are line-anchored (the scanner had flagged its own tests and its
  own implementation); the conflict finding lists every file.
- Hooks are read from project, local, AND user scope; this repo's bash-guard
  is wired (PreToolUse) so the guardrail critical clears honestly.

## [0.55.0] — 2026-07-09

### Fixed
- **CPU burn + phantom "hung" scan** (sampled live: 16 fleet reassemblies in
  5s): agent refreshes now gate on meaningful change instead of every
  transcript append; FSEvents refreshes floor at 5s; live-agent repos debounce
  re-probes at 10s; targeted rescans no longer light the global "scanning"
  indicator.
- **Waivers now affect the grade**: a waived finding leaves the feed AND its
  weight leaves compliance/health instantly, per-file for god-files; it stays
  disclosed in the waived list and returns on expiry.
- `.npmrc`/`.netrc`/`.pypirc` are flagged as secrets only when their content
  actually carries credentials.
- Worktree prune button promises only what the guard will do: "Prune N safe",
  with abandoned-but-unpushed worktrees explicitly noted as kept.

### Added
- **"VIBE only" toolbar toggle** (persisted): show — and count — only
  VIBE.yaml-instrumented repos.
- App opens on the Fleet view every launch; stat tiles centered and sized to
  fill one row; tooltips across gates, tiles, docs/agent cells; live-agent
  pulse animates again (active only); backfill multi-select records with one
  VIBE.yaml commit per repo.

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
