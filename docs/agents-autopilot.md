# Vibe for macOS — Agents & Autopilot screens (SwiftUI build spec)

**Source prototypes:** `ui_kits/vibe-macos/AgentsView.js` (122 lines) and
`ui_kits/vibe-macos/AutopilotView.js` (79 lines), React/Babel.
**Target:** native macOS SwiftUI, built pixel-faithfully from THIS spec (engineer will not read the JS).
**Shared primitives:** every component below composes the primitives already specced in
`docs/mac-parts.md` — `Icon`, `HealthDot`, `AgentPulse`, `LimitBar`, `Pill`, `Empty`,
`formatBytes`, `agentTool`, `STATUS_COLOR`. This file specs only the two screens and the
DS components they pull from the *dashboard* kit (`Card`, `Switch`, `StatusBadge`).
**Theme:** dark-mode only. Solid ink surfaces, hairline borders, saturated hue **only** for state.
`1px == 1pt` on macOS @1x. 4pt grid. Cite tokens AND raw px.

> Components/sections documented in this file: **12**
> 1. Token quick-reference · 2. DS `Card` · 3. DS `Switch` · 4. DS `StatusBadge` ·
> 5. AgentsView root · 6. Agents header · 7. `SessionCard` (+ working-now grid) ·
> 8. Worktree-sprawl card · 9. Doc-bloat leaderboard · 10. Changelog-staleness card ·
> 11. AutopilotView root + header · 12. `RuleCard` + recent-auto-actions log.

---

## 1. Token quick-reference (only the tokens these two screens touch)

Resolve each to a Swift constant in the Theme layer. All hex/rgba are from
`tokens/colors.css`, `tokens/spacing.css`, `tokens/typography.css`, `tokens/effects.css`.

**Surfaces / ink**
| Token | Alias | Value |
|---|---|---|
| `--surface-1` | ink-800 | `#12171A` (default card body) |
| `--surface-2` | ink-750 | `#171D20` (neutral pill bg) |
| `--surface-sunken` | ink-850 | `#0E1213` (prune button bg, disarmed rule icon box) |
| `--surface-raised` | ink-700 | `#1D2428` (ghost button bg) |
| `--surface-active` | ink-650 | `#232B30` (switch track off) |

**Borders (hairlines, 1px)**
| Token | Value |
|---|---|
| `--border-subtle` | `#161C1F` (row dividers) |
| `--border` | `#202A2E` (neutral pill/prune-tile border) |
| `--border-strong` | `#2E393F` (ghost button + switch-off border) |

**Status hues (foreground text/icon)**
| Semantic | Token | Hex |
|---|---|---|
| ok / accent | `--ok` = `--accent` = `--lime-400` | `#B4FF34` |
| warn | `--warn` = `--amber-400` | `#F7B23C` |
| danger | `--danger` = `--red-400` | `#FF5B52` |
| info | `--info` = `--blue-400` | `#6FB7E0` |
| text on lime | `--lime-ink` (`--text-on-accent`) | `#0B1400` |
| off-thumb fill | `--fg-300` (`--text-secondary`) | `#97A39E` |

**Low-alpha state fills + hairline borders (chips/tints)**
| Token | Value |
|---|---|
| `--ok-surface` (`--ok-bg`) | `rgba(180,255,52,0.10)` |
| `--ok-line` (`--ok-border`) | `rgba(180,255,52,0.30)` |
| `--ok-bg-soft` | `rgba(180,255,52,0.055)` |
| `--warn-surface` (`--warn-bg`) | `rgba(247,178,60,0.12)` |
| `--warn-line` (`--warn-border`) | `rgba(247,178,60,0.32)` |
| `--warn-bg-soft` | `rgba(247,178,60,0.06)` ← **SessionCard body tint** |
| `--danger-surface` (`--danger-bg`) | `rgba(255,91,82,0.12)` |
| `--danger-line` (`--danger-border`) | `rgba(255,91,82,0.34)` |
| `--danger-bg-soft` | `rgba(255,91,82,0.06)` ← **armed-destructive rule row tint** |

**Text ramp**
`--text-bright` `#F1F6F3` · `--text-primary` `#E5ECE8` · `--text-secondary` `#97A39E` ·
`--text-muted` `#6B7773` · `--text-faint` `#4C5754` · `--text-ghost` `#353E3B`.

**Radii / spacing / borders**
`--radius-xs` 2 · `--radius-sm` 4 · `--radius-md` 6 · `--radius-full` 999 ·
`--space-1..6` = 4/8/12/16/20/24 · `--border-w` 1px.

**Type scale (px == pt):** `--text-2xs` 10 · `--text-xs` 11 · `--text-sm` 12.5 ·
`--text-base` 14 · `--text-md` 16 · `--text-2xl` 34.
**Families:** mono = **JetBrains Mono** (`--font-mono`), sans = **Space Grotesk** (`--font-sans`).
**Weights:** 400 regular / 500 medium / 600 semibold (sans only) / 700 bold / 800 black.
**Tracking:** `--tracking-label` = **0.08em** (UPPERCASE mono micro-labels); `-0.02em` (page title); `0.01em`; `0.02em` (status-badge label).
**Tabular numerals:** every mono numeral uses `'tnum'` → SwiftUI `.monospacedDigit()`.

**Effects**
`--inset-top` = `inset 0 1px 0 rgba(255,255,255,0.03)` (etched top highlight on cards + SessionCard) ·
`--glow-ok-sm` = `0 0 10px rgba(180,255,52,0.30)` (LimitBar ok fill, HealthDot ok) ·
`--dur-fast` 140ms `.easeOut(0.2,0.6,0.2,1)` (switch thumb, disclosure).

**Screen padding:** both roots use `var(--mac-pad, 20px)` → **20pt** on all four sides.

---

## 2. DS `Card` — the panel surface (`components/core/Card.jsx` + `.vibe-panel` CSS)

**Purpose:** the bordered panel that wraps every clustered section on both screens
(worktree sprawl, doc bloat, changelog staleness, autopilot rule list, recent auto-actions).
**Props consumed here:** `title` (string, optional), `headerRight` (node, optional),
`flush` (bool — removes body padding), `variant` (default only on these screens).

**Visual structure (`VStack(spacing:0)`, `minWidth:0`):**
- **Panel container:** background `--surface-1` (#12171A); border `1px solid --border` (#202A2E);
  `cornerRadius --radius-md` (6pt); boxShadow `--inset-top` (etched top hairline —
  render as a 1pt top inner highlight `rgba(255,255,255,0.03)`, or approximate with a subtle
  top-edge overlay). `flexDirection: column`.
- **Header** (only rendered if `title != nil || headerRight != nil`):
  `HStack`, `alignItems:center`, `justifyContent:space-between`, **gap 12pt**,
  **padding 12px 16px**, **minHeight 44pt**, `borderBottom 1px solid --border`.
  - **Title** (`.vibe-panel__title`): JetBrains Mono, `--text-xs` (11), weight **500**,
    `letterSpacing --tracking-label` (0.08em), **UPPERCASE** (CSS `text-transform:uppercase`;
    the JS passes lowercase strings like `"worktree sprawl"` — uppercase them at render),
    color `--text-secondary` (#97A39E), `HStack` gap 8pt (for an optional leading glyph — not used on these screens).
  - **Right slot** (`headerRight`): right-aligned; holds a button, a `StatusBadge`, or a mono meta span (see call-sites).
- **Body** (`.vibe-panel__body`): **padding 16pt** by default; **`flush` → padding 0**.
  On these screens `flush` cards contain edge-to-edge rows that supply their own `10px 16px` / `9px 16px` padding.

**SwiftUI:** a reusable `Card` view = `VStack(spacing:0){ header?; Divider-as-border; body }`
inside a `RoundedRectangle(6)` fill(#12171A) + `.overlay(stroke(#202A2E,1))` + inset-top overlay.
Body is `flush ? content : content.padding(16)`.

---

## 3. DS `Switch` — armed/disarmed toggle (`components/forms/Switch.jsx` + `.vibe-switch` CSS)

**Purpose:** the one interactive control on Autopilot. Toggles a rule armed↔disarmed. Lime when on.
**Props consumed:** `checked` (bool = `armed[rule.id]`), `onChange` (fires `toggle(rule)`).
Rendered *without* a `label` here → **just the button** (external labels live in the RuleCard body).

**Visual structure (a `role="switch"` button):**
- **Track:** width **38pt**, height **22pt**, `borderRadius --radius-full` (999 → capsule),
  `position:relative`, `HStack alignItems:center`.
  - **OFF:** background `--surface-active` (#232B30); border `1px solid --border-strong` (#2E393F).
  - **ON (`aria-checked=true`):** background `--accent` (#B4FF34); border `1px solid --accent`.
- **Thumb (`.vibe-switch__thumb`):** absolute, **left 2pt**, **16×16pt**, `borderRadius --radius-full`.
  - **OFF:** fill `--fg-300` (#97A39E), `transform translateX(0)`.
  - **ON:** fill `--lime-ink` (#0B1400, dark on lime), `transform translateX(16pt)`.
  - Transition: `transform` + `background` over `--dur-fast` (140ms) `--ease-out`.
- **Focus:** `:focus-visible` → boxShadow `--ring` (`0 0 0 2px --bg-app, 0 0 0 4px --focus-ring`).
- **Disabled:** opacity 0.5, not-allowed cursor (not used on these screens).

**SwiftUI:** a custom capsule toggle (do **not** use stock `Toggle(.switch)` — the geometry is bespoke:
38×22 track, 16 thumb, 16pt travel, lime-ink thumb on lime track). `Capsule().fill(on ? lime : #232B30)`
`.overlay(Capsule().stroke(on ? lime : #2E393F, lineWidth:1))` with a `Circle().frame(16)` offset
`.animation(.easeOut(duration:0.14), value: on)`. Tap fires `onChange(!checked)`. Give it `.accessibilityAddTraits(.isToggle)`.

---

## 4. DS `StatusBadge` — dotted state pill (`components/feedback/StatusBadge.jsx` + `.vibe-status` CSS)

**Purpose:** on these screens: (a) worktree-sprawl card's "tidy" header badge, and (b) the per-row
`active`/`stale`/`abandoned` state badge. Always used at `size="sm"` here.
**Props consumed:** `status` (`ok|warn|danger`), `size="sm"`, children text (state word). `dot` defaults true.

**Visual structure (`HStack`, `alignItems:center`):**
- **`sm` metrics:** gap **5pt**, font `--text-2xs` (10), weight 500, `lineHeight 1`,
  **padding 3px 7px 3px 6px** (t/r/b/l), `borderRadius --radius-sm` (4pt), `border 1px solid`, `whiteSpace:nowrap`.
  (Default `md` would be gap 7, `--text-xs` 11, padding 5/10/5/9 — **not used on these screens**.)
- **Dot:** **6×6pt** (`sm`; `md` is 7) circle, `borderRadius 999`, fill = `currentColor` (the tone color), `flex:none`.
- **Label:** `letterSpacing 0.02em`; the JS passes lowercase state words (`active`/`stale`/`abandoned`/`tidy`) — render verbatim (no uppercasing).
- **Tone → color/fill/border:**
  | status | text | bg | border |
  |---|---|---|---|
  | `ok` | `--ok` #B4FF34 | `--ok-surface` (α.10) | `--ok-line` (α.30) |
  | `warn` | `--warn` #F7B23C | `--warn-surface` (α.12) | `--warn-line` (α.32) |
  | `danger` | `--danger` #FF5B52 | `--danger-surface` (α.12) | `--danger-line` (α.34) |
- `live`/`solid` variants exist in the DS but are **not** used on these two screens.

**SwiftUI:** `HStack(spacing:5){ Circle().fill(tone).frame(6); Text(label).monospaced().font(10).tracking(0.02em) }`
`.padding(EdgeInsets(top:3,leading:6,bottom:3,trailing:7))`
`.background(RoundedRectangle(4).fill(toneSurface))` `.overlay(RoundedRectangle(4).stroke(toneLine,1))`,
foreground = tone color.

---

# AGENTS SCREEN

## 5. `AgentsView` — root (fleet oversight)

**Purpose:** "Keep an eye on the agents." One scrollable screen answering four questions:
who is working **now**, the worktree **sprawl** they leave, the docs they **bloat**, the
changelogs they **forget**. Reached from the top-nav segmented control (`view === 'agents'`)
and from three of the Fleet stat tiles (`working` / `abandoned` / `doc bloat` all `setView('agents')`).

**Props:** `AgentsView({ data, actions })` where `data` is the computed `fleet` snapshot and
`actions` is the app action bag.

**Derived data (compute once at top of view, mirror exactly):**
- `t = data.totals` (the `fleet.totals` object).
- `sprawl = [...data.worktreeSprawl]` **sorted by state rank** `{abandoned:0, stale:1, active:2}`
  (abandoned first, active last). `data.worktreeSprawl` = every repo's `worktrees[]` flattened,
  each item spread with `.repo` (repo name) and `.repoId` added.
- `bloat = [...data.leaves]` **sorted DESC by `docs.taskState.lines`, then `.slice(0,5)`** (top 5 offenders).
- `stale = data.leaves.filter(r => r.docs.changelog.status !== 'ok')`
  **sorted DESC by `docs.changelog.behind`**.
- `abandonedCount = data.worktreeSprawl.filter(w => w.state === 'abandoned').length`.

**Layout (`VStack(alignment:.leading, spacing: 16pt)`, padding 20pt, vertically scrollable):**
1. **Header** (§6).
2. **"working now" section** (§7) — full-width.
3. **Two-column grid** (`gridTemplateColumns: '1.25fr 1fr'`, gap **16pt**, `alignItems:start`):
   - **Left (1.25fr):** worktree-sprawl `Card` (§8).
   - **Right (1fr):** a `VStack(spacing:16pt)` of doc-bloat `Card` (§9) then changelog-staleness `Card` (§10).

**SwiftUI:** root `ScrollView { VStack(alignment:.leading, spacing:16){ … } .padding(20) }`.
For the two-column grid use a `Grid` or an `HStack(alignment:.top, spacing:16)` with the left column
weighted 1.25 and right 1.0 (e.g. via `GeometryReader`-derived widths or a `.layoutPriority`/`frame` ratio).
The right column is itself a `VStack(spacing:16)`.

---

## 6. Agents header

**Structure (`VStack(alignment:.leading)`, no explicit gap — the `<p>` supplies its own top margin):**
- **Title `<h1>` "Agents":** Space Grotesk (`--font-sans`), weight **600**, `--text-2xl` (34pt),
  `letterSpacing -0.02em`, color `--text-bright` (#F1F6F3), margin 0.
- **Subtitle `<p>`:** margin **6px 0 0** (6pt top gap), JetBrains Mono, `--text-sm` (12.5), color `--text-secondary` (#97A39E).
  A single line built from `data.totals`:
  - `"{t.agentsActive} working now"` — the leading span is **`--warn`** (#F7B23C) when `t.agentsActive > 0`, else **`--ok`** (#B4FF34).
  - ` · {t.abandonedWorktrees} abandoned worktrees · {t.bloatedDocs} bloated docs · {t.staleChangelogs} stale changelogs. rein them in.` — remainder in `--text-secondary`.
  - Numbers are integers via `toLocaleString()` (grouped thousands), mono tabular.

**Data paths:** `data.totals.agentsActive`, `.abandonedWorktrees`, `.bloatedDocs`, `.staleChangelogs`
(all integers; see §11 derivation notes for how totals are computed).

**SwiftUI:** `VStack(alignment:.leading, spacing:6){ Text("Agents").font(sans 34, .semibold).tracking(-0.02).foregroundStyle(bright); (Text(...).foregroundStyle(warnOrOk) + Text(...).foregroundStyle(secondary)).font(mono 12.5) }`.
Use string concatenation of `Text` runs to color the leading count independently.

---

## 7. `SessionCard` + "working now" section

### 7a. The "working now" section wrapper
**Structure (`VStack(alignment:.leading, spacing: 9pt)`):**
- **Eyebrow label:** JetBrains Mono, `--text-2xs` (10), `letterSpacing --tracking-label` (0.08em),
  **UPPERCASE**, color `--text-faint` (#4C5754). Text = `"working now · {data.sessions.length}"`
  (the count is the number of live sessions). Render as `"WORKING NOW · N"`.
- **Body:**
  - **Empty state** (when `data.sessions.length === 0`): a `Card` with `flush` wrapping
    `Empty(icon:"moon")` → message **"no agents working. the fleet is quiet."** (tone ok/lime, `moon` icon 22pt).
    See `Empty` spec in mac-parts §16 (centered VStack spacing 10, padding 44×20, mono 12.5 muted).
  - **Non-empty:** a **responsive grid** — CSS `gridTemplateColumns: repeat(auto-fill, minmax(330px, 1fr))`, **gap 14pt**.
    One `SessionCard` per `data.sessions[i]`, keyed by `s.repo.id`.

**Grid semantics for SwiftUI:** cards are **min 330pt wide**, growing to fill; the row packs as many
330pt+ columns as fit, remainder stretches. Use `LazyVGrid(columns: [GridItem(.adaptive(minimum:330), spacing:14)], spacing:14)`.

### 7b. `SessionCard({ s, actions })`
`s = { repo, agent }` (a live session). This is the amber-tinted "an agent is working here right now" card.

**Container (`VStack(alignment:.leading, spacing: 12pt)`):**
- border `1px solid --warn-line` (rgba(247,178,60,0.32));
- background `--warn-bg-soft` (rgba(247,178,60,0.06)) — a faint amber wash;
- `cornerRadius --radius-md` (6pt); **padding 14pt**; boxShadow `--inset-top`.

**Row 1 — identity (`HStack, alignItems:center, gap 11pt`):**
- **Tool icon tile:** **34×34pt**, `flex:none`, `borderRadius --radius-sm` (4pt),
  background `--warn-surface` (α.12), border `1px solid --warn-line`, centered.
  Contains `Icon(name: agentTool(agent.tool).icon, size:17, color:--warn)`.
  `agentTool(id)` (mac-parts §4.3): `claude-code`→icon `bot`, `codex`→`square-terminal`, `serena`→`waypoints`; fallback `bot`.
- **Middle (`flex:1, minWidth:0`):**
  - **Repo button** (`HStack gap 7pt`, transparent button, `cursor:pointer`) → **`actions.openRepo(repo.id)`**:
    - `HealthDot(health: repo.health, size:8)` — see mac-parts §7 (ok lime + glow / warn amber / danger red + pulse).
    - `Text(repo.name)` — JetBrains Mono, `--text-md` (16), weight **700**, color `--text-bright` (#F1F6F3).
  - **Sub-line:** JetBrains Mono, `--text-2xs` (10), color `--text-muted` (#6B7773).
    Text = `"{agentTool(agent.tool).label} · {agent.branch} · {agent.elapsed}"`
    (e.g. `"codex · fix/billing-sync · 6m"`).
- **Trailing:** `AgentPulse(active:true, color:--warn, size:14)` — the 3-bar equalizer (mac-parts §8),
  amber, animated (staggered `mac-eq`), always `active` here.

**Row 2 — note:** JetBrains Mono, `--text-xs` (11), color `--text-secondary` (#97A39E), `lineHeight 1.5`.
Text = `agent.note` (e.g. `"patching the 3 failing billing tests"`).

**Row 3 — diff meta (`HStack, alignItems:center, gap 14pt`):** JetBrains Mono, `--text-2xs` (10), base color `--text-muted`.
- `"{agent.filesTouched} files"`.
- **Conditional** (only if `agent.linesAdded != null`):
  - `"+{agent.linesAdded.toLocaleString()}"` in `--ok` (#B4FF34).
  - `"−{agent.linesRemoved.toLocaleString()}"` in `--danger` (#FF5B52). **Note U+2212 MINUS SIGN "−", not a hyphen.** No space between the two.
- `"· last write {agent.lastActivity}"` in `--text-muted`.

**Row 4 — action buttons (`HStack, gap 8pt`), two equal-width ghost buttons:**
Shared `ghostBtn` style: `flex:1` (each takes half), `inline-flex` centered, **gap 7pt**, **padding 7pt** (all sides),
`borderRadius --radius-sm` (4), border `1px solid --border-strong` (#2E393F), background `--surface-raised` (#1D2428),
color `--text-primary` (#E5ECE8), JetBrains Mono `--text-sm` (12.5), `cursor:pointer`.
- **"Watch"** — leading `Icon(name:"terminal", size:13, color:--accent)` (lime). Click →
  **`actions.openRepo(repo.id)` then `actions.openConsole()`** (drills into the repo and opens the console/log panel).
- **"Pause"** — style override: `borderColor:--warn-line`, text color `--warn` (amber). Leading `Icon(name:"pause", size:13)` (inherits amber). Click →
  **`actions.toast('paused ' + agentTool(agent.tool).label, repo.name + ' · held for review', 'warn')`** (amber toast; no real state change in proto).

**Data paths consumed by SessionCard:**
`s.repo.id`, `s.repo.name`, `s.repo.health`, `s.agent.tool`, `s.agent.branch`, `s.agent.elapsed`,
`s.agent.note`, `s.agent.filesTouched`, `s.agent.linesAdded`, `s.agent.linesRemoved`, `s.agent.lastActivity`.
`data.sessions` = `leaves.filter(r => r.agent && r.agent.active).map(r => ({repo:r, agent:r.agent}))`.
`agent.elapsed`, `agent.lastActivity` are **pre-baked relative strings** (`"6m"`, `"11s ago"`) — render verbatim.

**Interactions summary:** repo-name button + both action buttons are the tap targets; the tool-tile
and pulse are decorative. Hover on ghost buttons: no explicit hover rule in the proto (they already sit
on `--surface-raised`) — give a subtle press feedback only. All icons `.accessibilityHidden(true)`.

**Icons (lucide → SF Symbol):** `bot`→`cpu`/`brain`, `square-terminal`→`terminal`, `waypoints`→`point.3.connected.trianglepath.dotted`, `terminal`→`terminal`, `pause`→`pause.fill`.

---

## 8. Worktree-sprawl card (left column)

**Purpose:** every extra git worktree across the fleet, worst first — the branches agents spin up and abandon.
**Card:** `title="worktree sprawl"`, `flush`, with a **`headerRight`** that switches on `abandonedCount`:
- **If `abandonedCount > 0`:** a **"Prune all N" danger button** —
  `inline-flex` centered, gap 6pt, **padding 4px 10px**, `borderRadius --radius-xs` (2), border `1px solid --danger-line`,
  background `--danger-surface` (α.12), color `--danger` (#FF5B52), JetBrains Mono `--text-2xs` (10), `cursor:pointer`.
  Leading `Icon(name:"trash-2", size:11)`. Label `"Prune all {abandonedCount}"`.
  Click → **`actions.openSheet('prune-all')`** (opens a confirm sheet; string literal is `'prune-all'`).
- **Else (nothing abandoned):** `StatusBadge(status:"ok", size:"sm")` with text **"tidy"** (dotted lime badge).

**Body:**
- **Empty** (`sprawl.length === 0`): `Empty(icon:"git-branch")` → **"no extra worktrees across the fleet."** (ok tone).
- **Non-empty:** a plain `VStack(spacing:0)` of rows; each row has a `borderBottom 1px solid --border-subtle`
  **except the last** (last row: no border).

**Each row (`HStack, alignItems:center, gap 11pt`, padding `10px 16px`):**
- **Leading icon:** `Icon(name:"git-branch", size:14)`, color = `--{WT_TONE[w.state]}`, `flex:none`.
  **`WT_TONE = { active:'ok', stale:'warn', abandoned:'danger' }`** → active=lime, stale=amber, abandoned=red.
- **Middle (`flex:1, minWidth:0`):**
  - **Branch line:** JetBrains Mono, `--text-sm` (12.5), color `--text-primary` (#E5ECE8),
    `whiteSpace:nowrap; overflow:hidden; textOverflow:ellipsis` (single-line, truncating). Text = `w.branch`.
  - **Meta button** → **`actions.openRepo(w.repoId)`**: JetBrains Mono, `--text-2xs` (10), color `--text-muted`, transparent.
    Text = `"{w.repo} · {w.created} · {w.commits} commits"` (e.g. `"magpie-macos · 12d ago · 0 commits"`).
- **State badge:** `StatusBadge(size:"sm")` with `status` derived from `WT_TONE[w.state]`
  (ok→ok / warn→warn / else→danger) and label = `w.state` (`active`/`stale`/`abandoned`), lowercase.
- **Trailing prune control (conditional):**
  - **If `w.state !== 'active'`:** a **26×26pt icon button** — `inline-flex` centered, `borderRadius --radius-xs` (2),
    border `1px solid --border` (#202A2E), background `--surface-sunken` (#0E1213), color `--text-muted`,
    `title="prune"`. Contains `Icon(name:"trash-2", size:12)`. Click →
    **`actions.toast('pruned', 'git worktree remove ' + w.branch + ' · ' + w.repo, 'ok')`** (green toast).
  - **If `w.state === 'active'`:** a **26pt-wide empty spacer** (`<span style={{width:26}}/>`) to keep alignment. Render an invisible 26pt-wide placeholder.

**Data paths / model:** `w = { branch, created, lastCommit, commits, state, repo, repoId }`
(built by `W(branch, created, lastCommit, commits, state)` then spread with `repo`+`repoId`).
`w.created` is a pre-baked relative string (`"12d ago"`); `w.lastCommit` is **not shown** on this screen.
`w.commits` is an integer (0 for abandoned spikes). `w.state ∈ {active, stale, abandoned}`.

**SwiftUI:** `Card(title:"WORKTREE SPRAWL", flush)`; header-right conditional view; body = `ForEach(sprawl)`
of a row `HStack` with a trailing 26pt cell that is either the prune button or `Color.clear.frame(width:26)`.
Divider between rows via `.overlay(alignment:.bottom)` 1pt line except last, or interleave `Divider().foregroundStyle(borderSubtle)`.

---

## 9. Doc-bloat leaderboard (right column, top)

**Purpose:** the top-5 fattest `TASK_STATE.md` files — the state agents hoard. A vertical bar-chart leaderboard.
**Card:** `title="doc bloat · TASK_STATE.md"` (NOT flush — 16pt body padding), with `headerRight` =
a mono meta span: `"soft {data.DOC_LIMITS.taskState.soft} · hard {data.DOC_LIMITS.taskState.hard}"`
→ **"soft 400 · hard 800"**. Style: JetBrains Mono, `--text-2xs` (10), color `--text-muted`.

**Body (`VStack, gap 13pt`):** one entry per `bloat[i]` (top 5 repos by `docs.taskState.lines`, DESC).

**Each entry (`VStack, gap 5pt`):**
- **Row button** → **`actions.openRepo(r.id)`** (`HStack, alignItems:baseline, justifyContent:space-between`, transparent):
  - **Left:** `Text(r.name)` — JetBrains Mono, `--text-xs` (11), color `--text-primary`.
  - **Right:** `Text("{r.docs.taskState.lines.toLocaleString()} ln · {formatBytes(r.docs.taskState.bytes)}")`
    (e.g. `"1,840 ln · 94 KB"`) — JetBrains Mono, `--text-2xs` (10). **Color-by-status:**
    if `r.docs.taskState.status === 'ok'` → `--text-muted`; else → `--{status}` (i.e. `--warn` or `--danger`).
- **`LimitBar`** (mac-parts §14): `value = r.docs.taskState.lines`, `soft = 400`, `hard = 800` (no `unit`, no `max`).
  - Track 6pt tall capsule (`--surface-active` #232B30), tone fill (`value>hard`→danger / `>soft`→warn / else ok),
    ok fill gets `--glow-ok-sm`; two 1pt ticks at soft/hard fractions (`--text-faint`); trailing right-aligned mono
    label (min 46pt, `--text-xs` 11, weight 700) in the tone color = `value.toLocaleString()`.

**Data paths / model:** `r.id`, `r.name`, `r.docs.taskState.lines` (int), `r.docs.taskState.bytes` (int),
`r.docs.taskState.status` (`ok|warn|danger`). `data.DOC_LIMITS.taskState = {soft:400, hard:800}`.
`formatBytes` per mac-parts §3.1 (byte thresholds/rounding — reproduce exactly).
`bloat` is `[...data.leaves].sort((a,b)=>b.docs.taskState.lines - a.docs.taskState.lines).slice(0,5)`.

**SwiftUI:** `Card(title:"DOC BLOAT · TASK_STATE.MD")` with header-right meta `Text`; body
`VStack(spacing:13){ ForEach(bloat){ VStack(spacing:5){ HStack(alignment:.firstTextBaseline){ name; Spacer(); meta }; LimitBar(...) } } }`.
Whole top row is one tap target (`Button`).

---

## 10. Changelog-staleness card (right column, bottom)

**Purpose:** every repo whose `CHANGELOG.md` is out of date, most-behind first.
**Card:** `title="changelog staleness"`, `flush`. No header-right.

**Body:**
- **Empty** (`stale.length === 0`): `Empty(icon:"history")` → **"every CHANGELOG is current."** (ok tone, `history` clock icon 22pt).
- **Non-empty:** rows, each with `borderBottom 1px solid --border-subtle` except the last.

**Each row (`HStack, alignItems:center, gap 11pt`, padding `9px 16px`):**
- **Leading icon:** `Icon(name:"history", size:14)`, color = `--{r.docs.changelog.status}` (warn/danger — never ok here since filtered `!== 'ok'`), `flex:none`.
- **Repo button** (`flex:1, textAlign:left`, transparent) → **`actions.openRepo(r.id)`**:
  JetBrains Mono, `--text-sm` (12.5), color `--text-primary`. Text = `r.name`.
- **Trailing meta:** `Text("{r.docs.changelog.behind} behind · {r.docs.changelog.lastUpdated}")`
  (e.g. `"41 behind · 5 weeks ago"`) — JetBrains Mono, `--text-2xs` (10), color = `--{r.docs.changelog.status}` (the tone).

**Data paths / model:** `r.docs.changelog = { lastUpdated: string, behind: int, status: 'ok'|'warn'|'danger' }`.
`lastUpdated` is a pre-baked relative string. `stale = data.leaves.filter(r => r.docs.changelog.status !== 'ok').sort((a,b)=>b.docs.changelog.behind - a.docs.changelog.behind)`.

**SwiftUI:** mirror §8's flush-row pattern; icon + `Button(name)` + `Spacer()` + tone-colored meta `Text`.

---

# AUTOPILOT SCREEN

## 11. `AutopilotView` — root + header (armable rules)

**Purpose:** "the aggressive end of the spectrum." Rules you trust enough to let run unattended.
**Armed** rules act on the filesystem *without asking*; **disarmed** rules still wait for a confirm.
**Destructive** rules are marked `destructive` and **start disarmed**. Reached via top-nav (`view === 'autopilot'`).

**Props:** `AutopilotView({ data, actions })`.

**Local state:** `armed` = a dict `{ ruleId: bool }` initialized from each rule's `.armed`
(`Object.fromEntries(data.autopilot.map(r => [r.id, r.armed]))`). This is per-view UI state (not persisted in proto).
- `armedCount = Object.values(armed).filter(Boolean).length`.
- `autoLog = data.activity.filter(a => a.kind === 'autopilot')` (only autopilot-kind entries for the log card).

**`toggle(rule)` (fires on Switch change):**
```
next = !armed[rule.id]
setArmed({ ...armed, [rule.id]: next })
if (next && rule.danger)
   toast('armed · ' + rule.label,
         'this rule now acts on the filesystem without asking. ' + rule.scope + '.', 'warn')  // amber warning
else
   toast((next?'armed':'disarmed') + ' · ' + rule.label,
         next ? 'running automatically · ' + rule.scope : 'back to confirm-first',
         next ? 'ok' : 'info')   // green when arming a safe rule; blue/info when disarming
```
So: arming a **danger** rule → **warn** toast; arming a **safe** rule → **ok** toast;
disarming any rule → **info** toast. Update local `armed` state immediately (optimistic).

**Layout (`VStack(alignment:.leading, spacing:16pt)`, padding 20pt, scrollable):**
1. **Header block** (`HStack, alignItems:flex-end, justifyContent:space-between, gap 20pt, flexWrap:wrap`):
   - **Left (`VStack`):**
     - `<h1>` **"Autopilot"** — Space Grotesk, weight 600, `--text-2xl` (34), `letterSpacing -0.02em`, color `--text-bright`.
     - `<p>` — margin `6px 0 0`, JetBrains Mono, `--text-sm` (12.5), color `--text-secondary`, **maxWidth 620pt**, `lineHeight 1.5`.
       Text: `"read-only watches and chores you trust enough to let run unattended. "` +
       **"destructive"** in `--danger` (#FF5B52) + `" rules start disarmed — arm one and it acts on disk without asking."`.
       (Split into colored `Text` runs — only the word "destructive" is red.)
   - **Right:** a `Pill` (mac-parts §15) — `tone = armedCount ? 'ok' : 'neutral'`, leading `icon="zap"`,
     text `"{armedCount} of {data.autopilot.length} armed"` (e.g. `"3 of 7 armed"`). Green pill when any armed, neutral otherwise.
2. **Rules `Card`** (`flush`): `ForEach(data.autopilot)` → a `RuleCard` (§12), passing `armed[r.id]` and `onToggle=toggle`.
3. **Recent-auto-actions `Card`** (`title="recent auto-actions"`, `flush`): the `autoLog` list (§12b).

**Data paths / model — `data.autopilot` (array of rule objects):**
`{ id, label, desc, scope, armed:bool, danger:bool, lastRan:string, runs:int }`. Real seed data:
| id | label | danger | armed (default) | scope | lastRan | runs |
|---|---|---|---|---|---|---|
| `rescan` | re-check on save | false | **true** | all repos | dev-mac · 11s ago | 2140 |
| `format` | format on save | false | **true** | 8 repos | demo-server · 2m ago | 318 |
| `task-state-alarm` | alarm on TASK_STATE bloat | false | **true** | all repos | magpie-macos · 9m ago | 4 |
| `prune-worktrees` | prune abandoned worktrees | **true** | false | all repos | never | 0 |
| `auto-push` | sign + push clean commits | **true** | false | 3 repos | never | 0 |
| `skeleton-bump` | bump skeleton (minor) | **true** | false | all repos | never | 0 |
| `install-hooks` | install skeleton agent hooks | false | false | 3 repos missing | never | 0 |

Note the invariant: **every `danger:true` rule ships `armed:false`** (destructive starts disarmed).
`desc` is a full sentence (see source for each). `scope`/`lastRan` are pre-baked strings; `runs` is an int.

**SwiftUI:** `ScrollView{ VStack(alignment:.leading, spacing:16){ header; rulesCard; logCard }.padding(20) }`.
Header is an `HStack(alignment:.bottom)` with a trailing `Pill`; on narrow widths it may wrap (flexWrap) —
acceptable to keep it a single row on macOS min widths. Hold `armed` in `@State private var armed: [String:Bool]`.

---

## 12. `RuleCard` + recent-auto-actions log

### 12a. `RuleCard({ rule, armed, onToggle })`
A single armable rule row inside the flush rules `Card`. This is the core Autopilot control.

**Container (`HStack, alignItems:flex-start, gap 14pt`, padding `14px 16px`):**
- `borderBottom 1px solid --border-subtle` (every row, including last — the card body is flush so the
  final hairline sits just above the card's bottom border; acceptable, mirror it).
- **Background (conditional danger tint):** `armed && rule.danger` → `--danger-bg-soft` (rgba(255,91,82,0.06)); else `transparent`.
  → an **armed destructive rule glows faintly red**; everything else is clear.

**Leading icon tile (34×34pt, `flex:none`, `borderRadius --radius-sm` 4, centered):**
- **Background:** `armed ? (rule.danger ? --danger-surface : --ok-surface) : --surface-sunken`.
- **Border:** `1px solid` → `armed ? (rule.danger ? --danger-line : --ok-line) : --border`.
- **Icon:** `Icon(name: rule.danger ? 'shield-alert' : 'gauge-circle', size:17)`,
  color = `armed ? (rule.danger ? --danger : --accent) : --text-muted`.
  → armed-safe = lime `gauge-circle` on lime-tint tile; armed-danger = red `shield-alert` on red-tint tile;
  disarmed = muted-gray icon on sunken tile.

**Middle (`flex:1, minWidth:0, VStack, gap 5pt`):**
- **Title + pills row (`HStack, alignItems:center, gap 10pt, flexWrap:wrap`):**
  - `Text(rule.label)` — JetBrains Mono, `--text-sm` (12.5), weight **700**, color `--text-primary`.
  - **If `rule.danger`:** `Pill(tone:"danger", icon:"triangle-alert")` text **"destructive"** (red pill: text `--danger`, bg `--danger-surface`, border `--danger-line`, leading warning-triangle icon 11pt).
  - **Armed/manual pill:** `armed ? Pill(tone:"ok"){"armed"} : Pill(tone:"neutral"){"manual"}`.
    - **armed** → lime pill (`--ok` text, `--ok-surface` bg, `--ok-line` border).
    - **manual** → neutral pill (`--text-secondary` text, `--surface-2` bg, `--border` border).
- **Description:** `Text(rule.desc)` — **Space Grotesk** (`--font-sans`, note: sans, not mono),
  `--text-sm` (12.5), color `--text-secondary`, `lineHeight 1.5`, `textWrap:pretty` (balanced wrapping).
- **Meta row (`HStack, alignItems:center, gap 12pt`):** JetBrains Mono, `--text-2xs` (10), color `--text-faint` (#4C5754):
  - `HStack gap 5pt`: `Icon(name:"target", size:11)` + `Text(rule.scope)` (e.g. "all repos").
  - `HStack gap 5pt`: `Icon(name:"history", size:11)` + `Text("last {rule.lastRan}")` (e.g. "last never" / "last magpie-macos · 9m ago").
  - **Conditional** (only if `rule.runs > 0`): `Text("{rule.runs.toLocaleString()} runs")` (e.g. "2,140 runs").

**Trailing toggle (`flex:none`, `paddingTop 4pt`):** the DS `Switch` (§3),
`checked = armed`, `onChange = () => onToggle(rule)`. (paddingTop 4 nudges it to align with the title baseline.)

**Pill spec** (mac-parts §15) recap: `HStack gap 5pt`, JetBrains Mono `--text-2xs` (10), padding `2px 6px`,
`borderRadius --radius-xs` (2), `lineHeight 1.4`, `border 1px solid`, optional leading `Icon size 11`.

**Data paths / model:** `rule.label`, `rule.desc`, `rule.scope`, `rule.lastRan`, `rule.runs`, `rule.danger`, `rule.id`; live `armed` bool from view state.

**SwiftUI:** `HStack(alignment:.top, spacing:14){ iconTile; VStack(alignment:.leading, spacing:5){ titleRow(WrappingHStack of pills); descText; metaRow }; Switch(...).padding(.top,4) }`
`.padding(.init(top:14,leading:16,bottom:14,trailing:16))`
`.background(armed && rule.danger ? dangerBgSoft : .clear)`
`.overlay(alignment:.bottom){ Rectangle().fill(borderSubtle).frame(height:1) }`.
The title-row pills use a wrapping HStack (`flexWrap:wrap`) so they flow to a second line on narrow cards.

### 12b. Recent auto-actions log (bottom `Card`, flush)
`title="recent auto-actions"`. Body = `autoLog` (= `data.activity.filter(a => a.kind==='autopilot')`).
- **Empty** (`autoLog.length === 0`): `Empty(icon:"gauge-circle")` → **"nothing automated yet."** (ok tone).
- **Non-empty rows** (`HStack, alignItems:center, gap 12pt`, padding `9px 16px`, JetBrains Mono `--text-xs` 11),
  `borderBottom 1px solid --border-subtle` except last:
  - **Timestamp:** `Text(a.t)` — color `--text-faint`, **width 34pt, textAlign:right, flex:none** (e.g. "1m", "9m").
  - **Icon:** `Icon(name:"gauge-circle", size:13)`, color = `STATUS_COLOR[a.tone] || --text-muted`
    (`STATUS_COLOR`: ok→`--ok`, warn→`--warn`, danger→`--danger`, info→`--info`), `flex:none`.
  - **Repo button:** `Text(a.repo)` — **width 130pt, flex:none, textAlign:left**, color `--text-secondary`, transparent button.
    Click handler: `() => (a.repoId || a.repo !== '—') ? actions.openRepo(a.repoId || a.repo) : null`
    (i.e. open the repo unless the repo cell is the em-dash placeholder "—"; passes `a.repoId` if present else the repo name).
  - **Message:** `Text(a.msg)` — `flex:1`, color `--text-primary` (e.g. "format on save · ruff --fix · 2 files").

**Data paths / model:** `data.activity[i] = { t:string, kind:string, repo:string, msg:string, tone:'ok'|'warn'|'danger'|'info', repoId?:string }`.
Autopilot-kind seed entries: `{t:'1m', repo:'demo-server', msg:'format on save · ruff --fix · 2 files', tone:'ok'}` and
`{t:'9m', repo:'magpie-macos', msg:'TASK_STATE.md crossed 1,800 lines → notified', tone:'warn'}`.

**SwiftUI:** flush `Card`; `ForEach(autoLog)` of an `HStack(spacing:12){ Text(t).frame(width:34,alignment:.trailing); Image; Button(repo).frame(width:130,alignment:.leading); Text(msg).frame(maxWidth:.infinity,alignment:.leading) }` with a bottom hairline except last.

---

## Cross-cutting notes for both screens

**Actions bag (from `app.js`):**
- `openRepo(id)` — navigates to the repo-detail view (records the return view).
- `openConsole()` — opens the bottom console/log panel.
- `openSheet(type)` — presents a confirm sheet by type string (AgentsView passes literal `'prune-all'`).
- `toast(title, msg, tone='info')` — transient toast; tones ok/warn/danger/info map to the status hues.
- `setView(v)` — top-level view switch (not called directly inside these two views, but they are *reached* via it).

**Relative-time & counts:** all `elapsed`/`lastActivity`/`created`/`lastUpdated`/`lastRan`/`a.t` are
**pre-baked strings** in the data model — render verbatim in mono. All integers use `toLocaleString()`
(grouped thousands, en-US `1,234`) and tabular numerals (`.monospacedDigit()`). The diff `+/−` uses
**U+2212 MINUS**, colored ok/danger.

**State → color legend used on these screens:**
| state | worktree (`WT_TONE`) | tone token | color |
|---|---|---|---|
| active / armed(safe) / ok | ok | `--ok` | #B4FF34 lime |
| stale / warn | warn | `--warn` | #F7B23C amber |
| abandoned / danger / destructive | danger | `--danger` | #FF5B52 red |
| info (log) | — | `--info` | #6FB7E0 blue |
| manual / neutral | — | `--text-secondary` on `--surface-2` | gray chip |

**Glow/pulse/animation on these screens:**
- `AgentPulse` (SessionCard) — animated amber equalizer, always active (mac-parts §8; freeze on reduce-motion).
- `HealthDot` (SessionCard) — ok phosphor glow / danger 1.5s pulse (mac-parts §7).
- `LimitBar` ok fill — `--glow-ok-sm` lime glow (doc-bloat, only when value ≤ soft).
- `Switch` thumb — 140ms slide on toggle; armed-danger row gains a static faint red wash (no animation).
- No other keyframed motion on these two screens. Respect `@Environment(\.accessibilityReduceMotion)`.

**Icons used (lucide → SF Symbol guidance; engineer finalizes):**
`bot`→`cpu`/`brain`, `square-terminal`→`terminal`, `waypoints`→`point.3.connected.trianglepath.dotted`,
`terminal`→`terminal`, `pause`→`pause.fill`, `git-branch`→`arrow.triangle.branch`, `trash-2`→`trash`,
`history`→`clock.arrow.circlepath`, `moon`→`moon`, `gauge-circle`→`gauge`, `shield-alert`→`exclamationmark.shield.fill`,
`triangle-alert`→`exclamationmark.triangle.fill`, `target`→`target`/`scope`, `zap`→`bolt.fill`.
All icons `.accessibilityHidden(true)` (decorative; labels carry meaning).
