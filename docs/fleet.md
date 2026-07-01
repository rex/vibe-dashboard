# Vibe for macOS — `FleetView.js` Spec (Fleet Overview)

**Intended source:** `ui_kits/vibe-macos/FleetView.js` (React/Babel prototype).
**Target:** native macOS SwiftUI app, built pixel-faithfully from THIS spec (engineer will not read the JS).
**Companion spec:** `docs/mac-parts.md` — the shared primitives (`StatTile`, `HealthDot`, `AgentPulse`, `Pill`, `LimitBar`, `MetaRow`, `Icon`, formatters, tokens). FleetView is a **composition** of those primitives; read `mac-parts.md` §0 (tokens), §7 (HealthDot), §8 (AgentPulse), §13 (StatTile), §14 (LimitBar), §15 (Pill) first. This file specifies FleetView-specific layout and behavior and does not restate primitive internals.

---

## ⚠️ SOURCE-AVAILABILITY NOTICE — READ FIRST

At spec-authoring time the literal `FleetView.js` file was **not present on disk** (the handoff paths `undefined/ui_kits/vibe-macos/FleetView.js`, `undefined/tokens/*.css`, `undefined/components/components.css` never resolved to a checked-out design system). The **only** authoritative artifact available was `docs/mac-parts.md`, a sibling primitives spec that (a) fully specifies the **fleet stat strip** via the `StatTile` call-table and the `fleet.totals` data model, and (b) enumerates the exact data-model property paths FleetView consumes.

Consequently this spec is graded by confidence:

- **[VERIFIED]** — stated directly by `mac-parts.md` (stat strip contents/ordering/tones/icons, `fleet.totals` computation, data paths, primitive dimensions). Build these exactly.
- **[DERIVED]** — the only reasonable reading given the documented data model + the fleet's dark-ink/hairline design language. Safe to build; call out in review if a screenshot contradicts.
- **[ASSUMED]** — a plausible reconstruction of a detail the primitives spec does not pin down (exact repo-table column widths, header label casing, right-click menu items). **Confirm against a screenshot or the real `FleetView.js` before final pixel sign-off.**

Every non-verified statement below is tagged. Do not treat an ASSUMED value as ground truth.

---

## 0. Purpose & placement

**Purpose.** FleetView is the app's **home / overview screen** — the default `view` when not drilled into a repo. It answers "is my whole fleet of repos healthy right now?" at a glance, then lets the operator drill down. It has two stacked regions:

1. **Oversight stat strip** — a single row of big-number `StatTile`s (the fleet KPIs). **[VERIFIED]**
2. **Nested repo table** — repos grouped by workspace, each row summarizing health, agent activity, compliance, docs, drift, and worktree state; click a row to open the repo. **[DERIVED from the data model + `mac-parts.md` §17 primitive list]**

**Placement in app.** Rendered by the top-level shell when `view === 'fleet'` and `inRepo === false`. The top segmented control (`SegMac`, `mac-parts.md` §9) selects it; several stat tiles call `setView(...)` to jump to sibling views (`agents`, `findings`). Selecting a repo row calls the app's `openRepo(repo)` action, which flips `inRepo` and swaps the main pane to `RepoView`. **[VERIFIED for setView targets; DERIVED for openRepo]**

---

## 1. Screen layout (outer)

```
FleetView (VStack, alignment: .leading, spacing: 20pt / --space-5)
├─ Oversight stat strip   ← §2
└─ Nested repo table      ← §3
```

- **Container:** `VStack(alignment: .leading, spacing: 20)` — `--space-5` (20px) between the strip and the table. **[ASSUMED gap; DERIVED it is one of the grid steps 16–24]**
- **Page padding:** the parent content pane supplies padding; FleetView itself is edge-to-edge inside that pane. Assume the standard content inset **20–24pt** (`--space-5`/`--space-6`) if FleetView must own it. **[ASSUMED]**
- **Background:** inherits `--bg-app` (`#0A0D0E`). No card wraps the whole view. **[DERIVED]**
- **Scroll:** the whole view scrolls vertically (`ScrollView`); the stat strip scrolls away with the table (no sticky). **[ASSUMED]**

---

## 2. Oversight stat strip — `fleet.totals` KPIs  **[VERIFIED]**

The headline metrics row. Each cell is a `StatTile` (see `mac-parts.md` §13 for the full tile spec — 38pt JetBrains-Mono-800 numeral, `tnum`, 16×18 padding, `--surface-1` bg raising to `--surface-raised` on hover-if-clickable, tone→color with ok-only green text-glow).

### 2.1 Layout

- **Row:** a horizontal band of equal-priority tiles. Model as a `Grid` / `HStack` where every tile is `minWidth: 0` and flexes to share width equally. **[DERIVED: `StatTile` sets `minWidth:0`; tiles share a row]**
- **Separation:** tiles are delineated by **hairline dividers**, not per-tile borders — the tile itself draws no border (`mac-parts.md` §13: "Tiles sit in a grid/row separated by hairlines from the parent container"). Use a **1px `--border` (`#202A2E`) vertical hairline between tiles**, and a `--border` hairline framing the strip. Radius on the outer strip container ≈ `--radius-md` (6pt). **[DERIVED / ASSUMED exact frame]**
- **Count:** **6 tiles** (below). **[VERIFIED]**
- **Tile height:** intrinsic — driven by 16×18 padding + 10px label + 38px numeral + 8pt gap ≈ **~80pt tall**. **[DERIVED]**
- **Overflow:** if the window is narrow, tiles either wrap or the strip scrolls horizontally; the primitive uses `whiteSpace:nowrap` + `overflow:hidden` on labels, implying no wrap of a single tile. Prefer equal-width flexing down to a min, then horizontal scroll. **[ASSUMED]**

### 2.2 Tiles — exact contents, ordering, tones, icons  **[VERIFIED — from `mac-parts.md` §13 FleetView table]**

Order is left→right exactly as listed. `t` = `fleet.totals`. Tone helper: `tone(c) = c >= 95 ? ok : c >= 80 ? warn : danger`.

| # | value (data path) | unit | label | tone rule | lucide icon | onClick |
|---|---|---|---|---|---|---|
| 1 | `fleet.totals.repos` | — | `repos` | **neutral** (`--text-bright` #F1F6F3) | `folder-git-2` | — (not clickable) |
| 2 | `fleet.totals.compliance` | `%` | `compliance` | `tone(t.compliance)` → ok≥95 / warn≥80 / danger<80 | `gauge` | — |
| 3 | `fleet.totals.agentsActive` | — | `working` | `agentsActive > 0 ? warn : ok` | `bot` | `setView('agents')` |
| 4 | `fleet.totals.abandonedWorktrees` | — | `abandoned` | `> 0 ? danger : ok` | `git-branch` | `setView('agents')` |
| 5 | `fleet.totals.bloatedDocs` | — | `doc bloat` | `> 0 ? danger : ok` | `file-warning` | `setView('agents')` |
| 6 | `fleet.totals.surprises` | — | `surprises` | `> 0 ? danger : ok` | `triangle-alert` | `setView('findings')` |

Notes:
- **Labels are UPPERCASE tracked micro-labels** at render (JetBrains Mono, `--text-2xs` 10pt, `--tracking-label` 0.08em, `--text-muted` #6B7773) — the strings above are the source-case; the tile renders them uppercased. **[VERIFIED via StatTile spec]**
- **The `%` unit** on tile 2 renders at `0.5em`, weight 500, `--text-muted`, appended to the numeral. **[VERIFIED]**
- **Only `ok`-tone numerals get the green text glow** (`--glow-text-ok` = `0 0 12px rgba(180,255,52,0.45)`). warn/danger/neutral get no glow. So a fully-healthy fleet reads as a wall of glowing lime numbers. **[VERIFIED]**
- **Icons** are leading, `size 12`, `--text-muted`, sitting in the tile's label `HStack(spacing:7)`. Lucide→SF Symbol (guidance from `mac-parts.md` §1): `folder-git-2`→`folder.fill`, `gauge`→`gauge.with.dots.needle.67percent`, `bot`→`cpu`/`brain`, `git-branch`→`arrow.triangle.branch`, `file-warning`→`exclamationmark.triangle`, `triangle-alert`→`exclamationmark.triangle.fill`. **[VERIFIED map is guidance]**

### 2.3 `fleet.totals` computation (mirror on the data side)  **[VERIFIED — from `mac-parts.md` §13]**

Computed in the data layer (`data.js`), over `leaves` = the flat list of leaf repos:

- `repos = leaves.length`
- `compliance = Math.round(avg of each repo's compliance %)` — integer percent.
- `agentsActive = count(repo where agent.active === true)`
- `abandonedWorktrees = Σ over repos of count(worktrees where state === 'abandoned')`
- `bloatedDocs = count(repo where docs.taskState.status === 'danger' || docs.agentsMd.status === 'danger')`
- `surprises = Σ over repos of surprises.length`

The native app should either receive `fleet.totals` precomputed or compute it identically from the repo list. **Rounding:** compliance is `Math.round` (round-half-up) to a whole percent. **[VERIFIED]**

### 2.4 Stat-strip interactions  **[VERIFIED targets]**

- Tiles 3/4/5 (`working`, `abandoned`, `doc bloat`) → `setView('agents')`.
- Tile 6 (`surprises`) → `setView('findings')`.
- Tiles 1/2 (`repos`, `compliance`) have **no** click handler → not interactive, no hover raise, cursor stays default.
- **Hover** (only on the 4 clickable tiles): background `--surface-1` (#12171A) → `--surface-raised` (#1D2428), `--dur-fast` (140ms) ease-out; cursor pointer. **[VERIFIED via StatTile spec]**
- **Press:** no distinct press style documented; keep the raised bg. **[ASSUMED]**
- SwiftUI: wrap clickable tiles in a `Button`/`.onTapGesture` + `.onHover`; leave 1/2 as plain views.

---

## 3. Nested repo table  **[DERIVED — layout reconstructed from the data model; confirm column geometry against source]**

The body: every repo, grouped by workspace, one row per repo. This is the "fleet" you oversee. `mac-parts.md` confirms FleetView renders **`HealthDot` at size 9** and **`AgentPulse` at size 12 (warn, or danger when `repo.health==='danger'`)** in each row (`mac-parts.md` §7 "FleetView row 9", §8 "FleetView 12"). Those two facts anchor the row; the surrounding columns are derived from the documented per-repo data paths.

### 3.1 Workspace grouping  **[DERIVED]**

Repos are organized under their **workspace** parent (the same tree the sidebar shows). Rendering model:

```
Table (VStack, spacing: 0)
└─ ForEach workspace in fleet.workspaces:
   ├─ Workspace group header row       ← §3.2
   └─ ForEach repo (leaf) in workspace:
      └─ Repo row                       ← §3.3
```

- Repos are the **leaf** nodes (`leaves` in the data layer); intermediate workspace nodes are group headers, not clickable repo rows. **[DERIVED — `fleet.totals` is computed over `leaves`, implying a workspace→leaf tree]**
- Grouping key: the repo's workspace/parent id. **[ASSUMED path — likely `repo.workspace` or the tree parent]**
- **[ASSUMED]** Whether workspace groups are collapsible in FleetView: the `Disclosure` triangle primitive exists and is used in the **sidebar**; `mac-parts.md` does not list FleetView as a `Disclosure` call-site. **Assume workspace headers in FleetView are static section headers (not collapsible)** unless the source shows otherwise.

### 3.2 Workspace group header row  **[ASSUMED]**

A thin section divider introducing each workspace:

- **Layout:** `HStack`, leading-aligned, vertical padding ~`--space-1_5` (6pt), horizontal padding matching row inset.
- **Label:** workspace name in JetBrains Mono, `--text-2xs` (10pt) or `--text-xs` (11pt), `--tracking-label` (0.08em), **UPPERCASE**, `--text-muted` (#6B7773) — the standard tracked micro-label treatment used everywhere in the kit for section eyebrows.
- **Optional trailing meta:** repo count for the workspace, or an aggregate compliance figure, in `--text-faint` (#4C5754). **[ASSUMED — WorkspaceDetail uses `agg.repos/compliance/...`; FleetView headers may echo a subset]**
- **Separator:** a `--border-subtle` (#161C1F) hairline below the header. **[ASSUMED]**
- Background: transparent (inherits `--bg-app`). **[ASSUMED]**

### 3.3 Repo row — structure  **[DERIVED]**

One row per leaf repo, left→right. This is a horizontal composition; model as a `Grid` with fixed leading/trailing columns and a flexing name column, or an `HStack` with explicit widths.

```
Repo row (HStack, alignment: .center, spacing: 12pt / --space-3)
├─ [A] Health dot        HealthDot(size: 9)                         ← fixed 9pt   [VERIFIED size]
├─ [B] Agent pulse       AgentPulse(size: 12), only if agent.active ← fixed ~14pt [VERIFIED size]
├─ [C] Repo name + branch (VStack, leading)                        ← flex(1)     [DERIVED]
├─ [D] Agent column      (agent tool + activity summary)           ← ~fixed      [DERIVED]
├─ [E] Docs column       (LimitBar / status pills for docs)        ← ~fixed      [DERIVED]
├─ [F] Compliance        (percent, tone-colored)                   ← fixed       [DERIVED]
├─ [G] Drift / worktree  (behind / dirty / unsigned pills)         ← ~fixed      [DERIVED]
└─ [H] Chevron           Icon("chevron-right", size 12, muted)     ← fixed 14pt  [ASSUMED]
```

- **Row height:** intrinsic, driven by content; roughly **~44–48pt** to seat a 9pt dot, 12pt pulse, two lines of name/branch, and a 6pt `LimitBar`. **[ASSUMED]**
- **Row horizontal padding:** `--space-3` (12pt) to `--space-4` (16pt) each side. **[ASSUMED]**
- **Inter-column gap:** `--space-3` (12pt). **[ASSUMED]**
- **Row background:** transparent by default (inherits `--bg-app`). **Hover → `--surface-1` (#12171A)** (the standard hoverable-surface raise), `--dur-fast` 140ms. **[DERIVED from the kit's hover convention]**
- **Row separator:** a **1px `--border-subtle` (#161C1F)** hairline between rows (the same faint divider `MetaRow` uses). **[DERIVED]**
- **Selected/active row** (if FleetView tracks a hovered/focused repo): `--surface-active` (#232B30). **[ASSUMED]**

### 3.4 Repo row — columns in detail

Property paths below are the **[VERIFIED]** data model from `mac-parts.md` §17/§13; the **column geometry and which primitive renders each** is **[DERIVED]**.

**[A] Health dot — `HealthDot(health: repo.health, size: 9)`  [VERIFIED]**
- `repo.health` ∈ `'ok' | 'warn' | 'danger'` (idle→gray fallback).
- Fill: ok `#B4FF34` / warn `#F7B23C` / danger `#FF5B52` / idle `#4C5754`.
- Glow: ok → `0 0 10px rgba(180,255,52,0.30)`; danger → `0 0 9px rgba(255,91,82,0.6)`; warn/idle → none.
- **Pulses (`vibe-pulse`, 1.5s ease-in-out, opacity 1→0.45 + scale 1→0.82) ONLY when `health==='danger'`.** Gate on reduce-motion. `flex:none` (9pt fixed). See `mac-parts.md` §7.

**[B] Agent pulse — `AgentPulse(active: repo.agent.active, color: …, size: 12)`  [VERIFIED size/color rule]**
- Rendered **only when `repo.agent.active === true`** (a live session). When no agent, this column is empty (reserve the space or collapse it). **[DERIVED conditional]**
- `size: 12`. Three 2.5pt-wide bars, spacing 2pt, staggered `mac-eq` equalizer (bar durations 0.70/0.88/1.06s at 0/0.12/0.24s delay).
- **Color:** `--danger` (#FF5B52) when `repo.health === 'danger'`, else `--warn` (#F7B23C). **[VERIFIED — `mac-parts.md` §8 "FleetView 12" + the danger-if-danger-else-warn convention]**
- Reduce-motion: freeze at scaleY 0.4, opacity 0.4.

**[C] Repo name + branch  [DERIVED]**
- `VStack(alignment: .leading, spacing: 2pt)`, `flex(1)`, `minWidth: 0`, truncates with tail ellipsis.
- **Name (top):** `repo.name` — JetBrains Mono, `--text-sm` (12.5pt) or `--text-base` (14pt), weight 500–700, `--text-primary` (#E5ECE8). **[ASSUMED size/weight]**
- **Branch (below):** `repo.agent.branch` (when an agent is live) or the repo's current branch — JetBrains Mono, `--text-2xs` (10pt), `--text-muted` (#6B7773), often preceded by a `git-branch` icon (size 11, muted). **[DERIVED path `repo.agent.branch` is VERIFIED as a field]**

**[D] Agent column  [DERIVED — this is the "agent column" called out in the focus brief]**
- **When `repo.agent.active`:** show the agent tool + a terse activity summary.
  - **Tool label:** `agentTool(repo.agent.tool).label` — one of `claude code` / `codex` / `serena` (fallback `agent`). Mono, typically **`--warn` colored when the agent is live** (the kit's convention for an active agent), `--text-xs` (11pt). Optional leading tool icon (`bot` / `square-terminal` / `waypoints`) at size ~12–13. **[VERIFIED tool map (`mac-parts.md` §4.3); DERIVED coloring]**
  - **Activity summary:** built from `repo.agent.elapsed`, `repo.agent.filesTouched`, `repo.agent.linesAdded`, `repo.agent.linesRemoved` — the same composite `MetaRow` uses: **`{elapsed} · {filesTouched} files · +{linesAdded}/−{linesRemoved}`**. Formatting rules (`mac-parts.md` §3):
    - `elapsed` / `lastActivity` are **pre-baked literal strings** (`'6m'`, `'11s ago'`) — render verbatim, mono.
    - counts use `toLocaleString()` grouped thousands, tabular.
    - the diff is hand-built `'+' + linesAdded` (color `--ok` #B4FF34) and `'−' + linesRemoved` (**U+2212 MINUS**, color `--danger` #FF5B52). **[VERIFIED formatting]**
  - Optional `repo.agent.note` and `repo.agent.lastActivity` may render as a secondary muted line. **[DERIVED — both are VERIFIED fields]**
- **When idle (`agent.active === false`):** the agent column reads empty / a faint `—` in `--text-faint`, or an "idle" micro-label. **[ASSUMED]**

**[E] Docs column  [DERIVED — the "docs column" called out in the focus brief]**
- Summarizes documentation health. The verified doc model per repo is `repo.docs.{taskState, agentsMd, claudeMd, changelog}`, each with at least `.lines`, `.bytes`, `.status`.
- **Primary reading — a `LimitBar` on `taskState`** (the most-watched doc, TASK_STATE.md): `LimitBar(value: repo.docs.taskState.lines, soft: 400, hard: 800)` (`DOC_LIMITS.taskState`). Renders a 6pt capsule track (`--surface-active` bg), tone fill (ok gets lime glow), soft/hard ticks, and a trailing right-aligned mono value label (`--text-xs` 11pt, weight 700, tone color, min-width 46pt, tabular). Tone: `lines > 800 → danger`, `> 400 → warn`, else `ok`. See `mac-parts.md` §14. **[VERIFIED thresholds + path]**
- **Compact fallback** (if the row is too tight for a bar): a tone-colored line-count + byte string, e.g. **`"320 ln · 13.1 KB"`** using `formatBytes(repo.docs.taskState.bytes)` (`mac-parts.md` §3.1 rounding: 1 decimal <10KB, 0 decimals 10KB–1MB, 1 decimal ≥1MB) — colored by `repo.docs.taskState.status`. **[DERIVED presentation; VERIFIED formatter]**
- **Doc-bloat flag:** a repo where `docs.taskState.status==='danger'` or `docs.agentsMd.status==='danger'` is exactly what feeds the strip's `bloatedDocs` KPI — so a **danger-tone** docs cell in a row corresponds to +1 on the "doc bloat" tile. Represent danger with the danger fill/label (and, if using a pill, `Pill(tone: danger)`). **[VERIFIED linkage]**

**[F] Compliance  [DERIVED]**
- The per-repo compliance percent (the value averaged into `fleet.totals.compliance`).
- Render as a compact percent, tone-colored by the **same** `tone(c)= c>=95?ok:c>=80?warn:danger` used for the strip: JetBrains Mono, tabular, weight 700, `%` unit dimmer. **[VERIFIED tone rule; ASSUMED it appears per-row and its exact path, likely `repo.compliance`]**
- **[ASSUMED]** Could alternatively/additionally render as a tiny meter. Prefer a numeric percent to match the strip.

**[G] Drift / worktree state  [DERIVED]**
- Surfaces repo cleanliness from the verified paths `repo.drift.{behind, files}` and `repo.worktree.{clean, unstaged, unpushed, signed}`, plus `repo.census` if shown.
- Render as a cluster of `Pill`s (`mac-parts.md` §15 — 2×6 padding, 10pt mono, `--radius-xs`, tone fill+hairline):
  - **Behind:** if `repo.drift.behind > 0` → a `Pill` like `"{behind} behind"` (tone **warn**; **danger** if large). Uses `git-branch` context. **[ASSUMED label; VERIFIED path]**
  - **Dirty:** if `!repo.worktree.clean` (i.e. `unstaged`/`unpushed`) → a warn/neutral pill `"dirty"` / `"{unpushed} unpushed"`. **[ASSUMED label; VERIFIED path]**
  - **Unsigned:** if `repo.worktree.signed === false` → a **danger** pill `"commits unsigned"` (this exact string+tone is a documented Pill example in `mac-parts.md` §15). **[VERIFIED string+tone]**
  - **Abandoned worktrees:** repos contributing to `abandonedWorktrees` (`worktrees.state==='abandoned'`) may show an `"abandoned"` danger pill. **[VERIFIED linkage; ASSUMED per-row pill]**
- Clean repos show **no** pills here (or a single `ok` state). **[DERIVED]**

**[H] Chevron  [ASSUMED]**
- Trailing `Icon("chevron-right", size: 12, color: --text-muted)` (`chevron.right` SF Symbol) to signal the row opens the repo. Fixed 14pt box. Rotates? No — it's a navigation affordance, not a disclosure. **[ASSUMED presence]**

### 3.5 Empty state  **[DERIVED]**
- If a workspace has no repos, or the fleet is empty, use the `Empty` primitive (`mac-parts.md` §16): centered `VStack(spacing:10)`, 44×20 padding, mono `--text-sm` (12.5pt) `--text-muted`, a tone-colored 22pt icon on top.
- Suggested fleet-empty copy/icon: **`folder-git-2` / ok**, e.g. "no repos in the fleet yet." **[ASSUMED copy — the exact FleetView empty string is not in `mac-parts.md`]**
- A **quiet fleet** (no agents working) is not an empty state for FleetView — the rows still render; the "no agents working. the fleet is quiet." `moon`/ok empty state belongs to **AgentsView**, not here. **[VERIFIED it's an AgentsView string]**

---

## 4. Interactions & actions

| Trigger | Action | Confidence |
|---|---|---|
| Click stat tile 3/4/5 (`working`/`abandoned`/`doc bloat`) | `setView('agents')` | **[VERIFIED]** |
| Click stat tile 6 (`surprises`) | `setView('findings')` | **[VERIFIED]** |
| Click stat tile 1/2 (`repos`/`compliance`) | none (inert) | **[VERIFIED]** |
| Hover clickable stat tile | bg `--surface-1`→`--surface-raised`, 140ms | **[VERIFIED]** |
| **Click a repo row** | **`openRepo(repo)`** → sets `inRepo=true`, swaps main pane to `RepoView` for that repo | **[DERIVED — `openRepo` is the app's documented repo-open action; row-click is the standard drill-in]** |
| Hover a repo row | bg → `--surface-1` (#12171A), 140ms | **[DERIVED]** |
| **Right-click a repo row** | **context menu** — likely: Open, Open Agent, Open in Finder / Terminal, Commit (`openSheet('commit')`), Run target (`runTarget(...)`), Copy path | **[ASSUMED — the app has `openSheet('commit')` and `runTarget` actions per the shared brief; the exact FleetView menu is not documented. CONFIRM against source.]** |
| Keyboard | ↑/↓ to move selection, ⏎ to open, are the macOS-idiomatic bindings; not documented for FleetView specifically | **[ASSUMED]** |

**SwiftUI wiring:**
- Repo row → `Button { openRepo(repo) }` styled plain, or `.onTapGesture`. Add `.contextMenu { … }` for right-click.
- Stat tiles → per §2.4.
- Use `.onHover { hovering in … }` to drive the background raise on both tiles and rows.
- Respect `@Environment(\.accessibilityReduceMotion)` to freeze `HealthDot` pulse and `AgentPulse` equalizer.

---

## 5. Color-by-state summary (tokens FleetView uses)

| State | fg token | hex | low-alpha fill | hairline | glow |
|---|---|---|---|---|---|
| ok / accent | `--ok` | `#B4FF34` | `--ok-surface` `rgba(180,255,52,.10)` | `--ok-line` `rgba(180,255,52,.30)` | `--glow-ok-sm` / `--glow-text-ok` |
| warn | `--warn` | `#F7B23C` | `--warn-surface` `rgba(247,178,60,.12)` | `--warn-line` `rgba(247,178,60,.32)` | — |
| danger | `--danger` | `#FF5B52` | `--danger-surface` `rgba(255,91,82,.12)` | `--danger-line` `rgba(255,91,82,.34)` | red `0 0 9px rgba(255,91,82,.6)` (dot) |
| info | `--info` | `#6FB7E0` | `--info-surface` `rgba(111,183,224,.12)` | `--info-line` `rgba(111,183,224,.30)` | — |
| neutral | `--text-bright` #F1F6F3 (tiles) / `--text-secondary` #97A39E (pills) | — | `--surface-2` #171D20 (pills) | `--border` #202A2E | — |
| idle | `--fg-500` | `#4C5754` | — | — | — |

Surfaces: `--bg-app` #0A0D0E (page) · `--surface-1` #12171A (tile / row hover) · `--surface-raised` #1D2428 (clickable-tile hover) · `--surface-active` #232B30 (LimitBar track / selected row). Hairlines: `--border-subtle` #161C1F (row dividers) · `--border` #202A2E (strip frame / neutral pills) · `--border-strong` #2E393F.

---

## 6. Typography quick-reference (FleetView)

- **Stat numerals:** JetBrains Mono **800**, 38pt, `letterSpacing −0.03em`, `tnum`, tone-colored, ok-only glow. `%` unit at 0.5em/500/muted.
- **Stat labels / workspace headers:** JetBrains Mono, 10pt, `--tracking-label` 0.08em, **UPPERCASE**, `--text-muted`.
- **Repo name:** JetBrains Mono ~12.5–14pt, 500–700, `--text-primary`. **[ASSUMED sizes]**
- **Branch / agent summary / doc counts:** JetBrains Mono, 10–11pt, tabular, muted or tone-colored.
- **Pills:** JetBrains Mono 10pt, `lineHeight 1.4`.
- **LimitBar value:** JetBrains Mono 11pt, 700, tone-colored, tabular, min-width 46pt right-aligned.
- All data/numeric text is **mono + tabular** (`.monospacedDigit()` on JetBrains Mono). Never mono below 11pt (numerals excepted per scale).

---

## 7. Data model consumed by FleetView (property paths)

**Fleet-level [VERIFIED]:**
`fleet.totals.repos`, `.compliance`, `.agentsActive`, `.abandonedWorktrees`, `.bloatedDocs`, `.surprises` · `fleet.workspaces` / `leaves` (the repo tree). `DOC_LIMITS.taskState = {soft:400, hard:800}`.

**Per-repo [VERIFIED fields; row placement DERIVED]:**
`repo.name` · `repo.health` (`ok|warn|danger`) · `repo.agent.{active, tool, branch, elapsed, filesTouched, linesAdded, linesRemoved, note, lastActivity}` · `repo.docs.{taskState, agentsMd, claudeMd, changelog}.{lines, bytes, status}` · `repo.census.{scanned, soft, godFiles, largest}` · `repo.drift.{behind, files}` · `repo.worktree.{clean, unstaged, unpushed, signed}` · `repo.surprises[]` (feeds strip `surprises`) · per-repo compliance (`repo.compliance`, **[ASSUMED path]**).

**Formatting [VERIFIED]:** integers → `toLocaleString()` grouped thousands, tabular. Diffs → `+n` (ok) / `−n` (U+2212, danger). Bytes → `formatBytes` (§3.1 thresholds). Relative times → pre-baked literal strings rendered verbatim.

---

## 8. Build checklist (FleetView-specific)

1. **Stat strip [VERIFIED — build exactly]:** 6 `StatTile`s in order repos / compliance / working / abandoned / doc bloat / surprises, with the tone rules, icons, and `setView` handlers in §2.2/§2.4. Hairline-separated, no per-tile border. 38pt mono-800 numerals, ok-only glow.
2. **`fleet.totals` [VERIFIED]:** compute/consume per §2.3 (round compliance; count active agents; sum abandoned worktrees; count danger docs; sum surprises).
3. **Repo table [DERIVED — verify against source/screenshot]:** workspace-grouped rows; each row = HealthDot(9) + conditional AgentPulse(12) + name/branch + agent column + docs column (taskState LimitBar) + compliance + drift/worktree pills + chevron. Hover-raise to `--surface-1`, `--border-subtle` row dividers.
4. **Row click → `openRepo(repo)`; right-click → context menu [ASSUMED menu — confirm].**
5. **Liveness:** HealthDot danger-pulse + AgentPulse equalizer, both reduce-motion-gated.
6. **Before pixel sign-off:** obtain the real `FleetView.js` / a screenshot and reconcile every **[DERIVED]/[ASSUMED]** item — especially repo-table column order & widths, workspace-header content, per-repo compliance path, and the right-click menu.
