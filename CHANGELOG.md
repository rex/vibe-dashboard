# Changelog

All notable changes to Vibe Dashboard are documented here. Format loosely
follows Keep a Changelog; versions are semver from `VERSION`.

## [1.1.0] — 2026-07-14

### Fixed
- **Sessions at a workspace root were invisible.** The Agents view, the fleet
  "agents active" total, and the workspace detail count all iterated leaf repos
  only — so a session running AT a workspace root (a multi-repo session driving
  an ecosystem dir) attached to the workspace repo and then appeared nowhere.
  Found live: five sessions running (two mains at workspace roots, two
  workflows, one standard) with exactly one visible. All three surfaces now
  include workspace-attached sessions.
- **Workflow cards no longer migrate between repos.** A workflow card's repo
  attachment followed whichever agent transcript was newest, so the card hopped
  between the workspace root (invisible, see above) and whatever component repo
  an agent happened to be working in — rendering as a lone "agent inside a
  workflow" on the wrong repo row, then vanishing on the next tick. The card is
  now homed at the OWNING session's cwd (read from the parent transcript, with
  the newest-agent fallback preserved); the newest agent still drives
  lifecycle and telemetry.

### Added
- Workflow session cards show their lane count ("· N agents") beside the
  workflow id — a workflow reads as a group, not as one lone agent.

## [1.0.0] — 2026-07-10

**Vibe Dashboard 1.0 — mission control for vibe coding.**

Eighty-two releases of iteration, declared done by its human. What 1.0 means:

- **A real oversight console**: a fleet of agentic repos scored against their
  own `VIBE.yaml` policies — severity-weighted grades whose "why this grade"
  breakdown *is* the grade, hygiene detection tuned against alert fatigue,
  waivers that actually move the number.
- **Live agent watching**: Claude Code / Codex sessions detected from their
  transcripts, multi-agent workflows rendered as concurrency lanes that follow
  streams across phase hand-offs — push-driven by FSEvents, flat idle CPU.
- **Trustworthy by contract**: nothing fake is shown as real. Every value is
  measured or labelled honestly. 233 tests and a self-enforcing gate
  (`make validate`) hold the line in CI.
- **Shipped like a real Mac app**: Developer ID-signed, notarized, stapled
  DMG; Sparkle auto-updates double-gated by EdDSA + notarization and proven
  end-to-end against the live public feed.
- **Open source (MIT)**, with a history scrubbed for publication and a fleet
  policy harness anyone can adopt: any repo with a `VIBE.yaml` is a citizen.

## [0.82.0] — 2026-07-10

### Fixed
- `make publish` release-notes extraction handles the MAJOR.MINOR marketing
  string vs. the CHANGELOG's full-triplet headings (found publishing v0.81 —
  the first release shipped with a fallback title instead of its notes).

## [0.81.0] — 2026-07-10

### Added
- **`make publish`** — the final leg of the release pipeline: generates an
  EdDSA-signed Sparkle `appcast.xml` (key read from the login Keychain),
  publishes the notarized DMG + appcast as a GitHub Release, and verifies the
  live feed + enclosure URLs end to end. First public release ships with this.

## [0.80.0] — 2026-07-10

### Added
- **Public-facing polish**: hero README — real fleet screenshot, feature tour,
  `VIBE.yaml` harness documentation, install-from-Releases — plus a GitHub
  social-preview card (`docs/social-preview.png`) rendered from the design
  system's own tokens, typefaces, and icon geometry.

### Changed
- **Git history rewritten pre-publish**: internal hostnames, team IDs, home
  paths, and org names scrubbed from every blob and commit message; local dev
  journals purged from history. Commit count and the shipped tree preserved
  exactly (HEAD tree hash byte-identical before/after).

## [0.78.0] — 2026-07-10

### Fixed
- **`make` and Xcode no longer fight over SwiftPM state.** CLI builds keep
  their package clones and binary artifacts in `build/spm`
  (`-clonedSourcePackagesDirPath`), isolated from Xcode's — the shared-cache
  collision that produced "Missing package product 'Sparkle'" after a
  command-line build can no longer occur.

### Changed
- Final pre-publish sweep: genericized the last internal hostname/path
  references in the design docs; `REMEDIATION_PLAN.md` joins the gitignored
  local dev journals.

## [0.77.0] — 2026-07-10

### Added
- **Sparkle auto-updates activated** — generated the EdDSA signing keypair; the
  public key is in Info.plist and the private key lives in the Keychain (backed
  up separately). The in-app updater now runs in real builds (it stayed inert
  while the key was a placeholder). Publishing the first appcast is the last
  step — see [docs/RELEASE.md](docs/RELEASE.md).

## [0.76.0] — 2026-07-10

### Changed
- **Prepared for open-source release (MIT).** Rewrote the public README, added a
  LICENSE, and swept the repo for secrets/PII — gitleaks (full 75-commit history)
  plus a manual scan found no credentials. Extracted fleet owner-scoping (git
  hosts / GitHub orgs) out of the source into a git-ignored `OwnerScope` config
  (`Shared/Scan/OwnerScope.swift`; empty by default — managed repos are
  owned-by-default, so behaviour is unchanged), and genericized personal paths,
  team IDs, and project names across tests and docs. `TASK_STATE.md` and
  `BACKLOG.md` are now git-ignored (kept locally). The Sparkle appcast is served
  from this repo's own GitHub Releases.

## [0.74.0] — 2026-07-10

### Added
- **Auto-updates via Sparkle.** The app embeds Sparkle 2, checks a signed
  appcast on a schedule, and shows release notes + an Install button when a newer
  notarized build appears (auto-check + prompt), plus a "Check for Updates…"
  item under the app menu. Updates are gated by an EdDSA signature over the
  archive AND the app's Developer ID / notarization. The feed + downloads are
  served from this repo's GitHub Releases, with `SUFeedURL` pointing at
  `releases/latest/download/appcast.xml`.
  - The updater starts only in a real shipped app: never under the unit-test
    host (a live updater there hangs the runner) and not until `SUPublicEDKey`
    is a real key (the repo ships a clearly-marked placeholder). The menu item
    is present but disabled until then.
  - Remaining setup (a public releases repo + a Sparkle EdDSA keypair, both
    account-scoped) and the per-release publish flow are documented in
    [docs/RELEASE.md](docs/RELEASE.md).

## [0.72.0] — 2026-07-10

### Fixed
- **The archived app was silently misconfigured — surfaced by notarization.**
  An xcodegen gotcha: when a target's `settings:` block also carries `groups:`,
  every sibling build-setting key is DROPPED unless nested under `base:`. So
  archives had been building with the derived (wrong) bundle id
  `com.piercemoore.VibeDashboard`, no custom `Info.plist`, no entitlements, and
  no hardened runtime. Nesting the block under `base:` restores all of it:
  correct `com.piercemoore.vibe`, the un-sandboxed + network-client
  entitlements, and hardened runtime — the last being a notarization
  prerequisite (Apple's first rejection: "does not have the hardened runtime
  enabled"). `make release` now yields a notarized, stapled,
  Gatekeeper-accepted universal DMG (`spctl` → "Notarized Developer ID").
  Note: the bundle-id correction means locally-stored prefs/waivers (keyed by
  bundle id in `UserDefaults`) reset once — the identity is correct now.
- Release preflight now asserts the hardened-runtime flag on the exported app
  *before* the notary round-trip. The check captures the signature and matches
  against the string rather than `codesign | grep -q`, which trips SIGPIPE under
  `set -o pipefail` and false-failed on a flag that was present.

## [0.70.0] — 2026-07-10

### Added
- **Release pipeline — Developer ID signing, notarization, stapled DMG**
  (`make release` → `Scripts/release.sh`). Archives universal (arm64 + x86_64)
  with hardened runtime on, exports Developer ID, notarizes and staples the app
  so it verifies offline, then builds / signs / notarizes / staples a
  drag-to-`/Applications` DMG (pure `hdiutil`, no external dep). Companions:
  `make release-check` preflights the certificate + notary profile and reports
  exactly what's missing; `make dmg-local` packages an unsigned DMG for bundle
  testing without a certificate; `make notary-setup` stores notary credentials
  once. Un-sandboxed ⇒ direct distribution, never the Mac App Store. One-time
  setup documented in [docs/RELEASE.md](docs/RELEASE.md).

## [0.69.0] — 2026-07-10

### Added
- **Findings — group by codebase**: a persisted "group by repo" toggle breaks
  the feed into per-repo sections, each with a tappable header (worst-severity
  chip + count) that jumps straight to the repo detail. Sections are ordered
  worst-severity-first, then by volume, then name.
- **Findings — filter by type**: a type menu narrows the board to a single
  finding type (Hygiene, Architecture, Docs, …). Severity badges, the headline,
  and every count reflect the active type slice; the two filters compose. A type
  whose last finding gets waived falls back to "all types" so the feed can never
  strand itself empty.

## [0.68.0] — 2026-07-10

### Changed
- **Live-agent pulse is now the `waveform` SF Symbol** with an animated
  variable-color sweep, replacing the hand-rolled Canvas equalizer. Symbol
  effects render via Core Animation on the GPU: the bars sweep without waking
  the main thread, re-running SwiftUI `body`, or touching layout, and idle
  completely when no agent is active — the cheapest of the four pulse
  iterations to date. It colours (`.foregroundStyle`) and scales (`.font`)
  natively, so every call site (sidebar, fleet, inspector, watch window, status
  bar, menu bar) keeps the exact same `active`/`color`/`size` API.

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
