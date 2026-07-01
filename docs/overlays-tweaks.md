# Vibe for macOS — Overlays (⌘K + write sheets) & Tweaks Panel Spec

**Sources:** `ui_kits/vibe-macos/Overlays.js` (314 lines) + `ui_kits/vibe-macos/Tweaks.js` (103 lines), extracted from the **Vibe Dashboard Design System** handoff bundle. Cross-referenced against `app.js` (action bus, keyboard, context menu, tweak application), `MacChrome.js` (⌘K search affordance), `data.js` (exact model shapes), and the `tokens/*.css` + `components/components.css` token/DS layer.

**Target:** native macOS SwiftUI app, built pixel-faithfully from THIS spec (the engineer will not read the JS).
**Theme:** dark-mode only, no light theme, **no glassmorphism / no backdrop blur**. Surfaces are solid ink, delineated by hairline borders. Saturated hue signals state only; the brand accent IS the "ok" lime.
**Companion spec:** `docs/mac-parts.md` documents the shared primitives (`Icon`, `HealthDot`, `AgentPulse`, `SegMac`, `Kbd`, `MetaRow`, `Pill`, `Empty`, formatters, `agentTool`, token layer). This file reuses those primitives by name — read `mac-parts.md` first. Every token cited below (`--surface-1`, `--border`, `--space-3`, etc.) resolves to the raw hex/px given in `mac-parts.md §0` and re-cited inline here.

**4pt grid.** `1px == 1pt` on macOS @1x logical points; the prototype's px map 1:1 to SwiftUI points.

---

## 0. Token quick-reference (values this file cites)

| Token | Resolves to | Raw |
|---|---|---|
| `--surface-1` | `--ink-800` | `#12171A` (default sheet/panel bg) |
| `--surface-2` | `--ink-750` | `#171D20` (header/footer bars, section captions) |
| `--surface-sunken` | `--ink-850` | `#0E1213` (inputs, textareas, code wells) |
| `--surface-raised` | `--ink-700` | `#1D2428` (hover, popover, selected tweak seg) |
| `--surface-active` | `--ink-650` | `#232B30` (pressed/selected row, toggle-off track) |
| `--ink-1000` (`--bg-void`) | — | `#07090A` (segmented-control track, keycap bg) |
| `--border-subtle` | `--line-soft` | `#161C1F` (intra-list hairlines) |
| `--border` | `--line` | `#202A2E` (default 1pt border) |
| `--border-strong` | `--line-loud` | `#2E393F` (sheet/panel outer border, selected seg) |
| `--text-bright` | `--fg-50` | `#F1F6F3` (sheet title, input value) |
| `--text-primary` | `--fg-100` | `#E5ECE8` (body values, file paths) |
| `--text-secondary` | `--fg-300` | `#97A39E` (prose, row labels) |
| `--text-muted` | `--fg-400` | `#6B7773` (captions, micro-labels, close X) |
| `--text-faint` | `--fg-500` | `#4C5754` (placeholders, ghost repo path) |
| `--text-ghost` | `--fg-600` | `#353E3B` (kind eyebrow in palette) |
| `--accent` / `--ok` | `--lime-400` | `#B4FF34` |
| `--accent-hover` | `--lime-300` | `#CDFF74` |
| `--accent-press` | `--lime-500` | `#9BEC1B` |
| `--warn` | `--amber-400` | `#F7B23C` |
| `--danger` | `--red-400` | `#FF5B52` |
| `--info` | `--blue-400` | `#6FB7E0` |
| `--lime-ink` (`--text-on-accent`) | — | `#0B1400` (text/thumb on lime fill) |
| `--fg-300` | — | `#97A39E` (toggle-off thumb) |
| `--radius-xs` | `2px` | keycaps, pills, seg inner buttons, close-btn |
| `--radius-sm` | `4px` | buttons, inputs, selects, palette rows |
| `--radius-md` | `6px` | file-list cards, context menu |
| `--radius-lg` | `10px` | **sheets, palette, tweaks panel** |
| `--radius-full` | `999px` | toggle track/thumb, dots |
| `--shadow-lg` | — | `0 16px 40px rgba(0,0,0,0.55)` (sheet/palette/tweaks elevation) |
| `--shadow-pop` | — | `0 10px 30px rgba(0,0,0,0.6), 0 0 0 1px #2E393F` (context menu) |
| `--glow-ok-sm` | — | `0 0 10px rgba(180,255,52,0.30)` (primary-btn hover glow) |
| `--ring` | — | `0 0 0 2px var(--bg-app), 0 0 0 4px var(--focus-ring)` (focus) |
| `--ring-inset` | — | `inset 0 0 0 1px var(--focus-ring)` (input focus) |
| `--z-overlay` | `1000` | backdrop |
| `--z-popover` | `1100` | context menu |
| `--z-toast` | `1200` | toasts |
| `--ease-out` | `cubic-bezier(0.2,0.6,0.2,1)` | → SwiftUI `.timingCurve(0.2,0.6,0.2,1)` |
| `--dur-fast` | `140ms` | → `.easeOut(duration:0.14)` |

**Type scale (px == pt):** `--text-2xs` 10, `--text-xs` 11, `--text-sm` **12.5**, `--text-base` 14, `--text-md` **16**, `--text-lg` 20. Mono = **JetBrains Mono**, Sans = **Space Grotesk**. Weights: 400/500/600(sans only)/700/**800**(mono big numerals). Tracking: `--tracking-label` **0.08em** (UPPERCASE mono micro-labels). Enable tabular numerals (`.monospacedDigit()`) wherever mono renders data.

**Keyframes reused here:** `mac-fade-in` (opacity 0→1), `mac-sheet-in` (`from{opacity:0; translateY(-12px) scale(0.99)}`), `mac-pop-in` (`from{opacity:0; translateY(-6px) scale(0.98)}`), `vibe-pulse` (live dot). Respect `@Environment(\.accessibilityReduceMotion)` → collapse all durations to 0.

---

## Overlay architecture (how everything mounts)

All overlays are dispatched by one component, `Overlays.Sheets({ sheet, repo, data, actions })`, mounted once at the app root (`app.js:236`). `sheet` is either `null` or `{ type: <string> }`. The dispatcher (`Overlays.js:292–311`):

- `sheet === null` → render nothing.
- `sheet.type === 'palette'` → render `CommandPalette` (its own backdrop, top-aligned).
- Every other type → build the inner sheet, wrap it in a shared **`Backdrop`**. Alignment = `center` for `about`, else `top`.

`sheet` state lives in `app.js` (`useState(null)`). Openers on the `actions` bus:
- `actions.openSheet(type)` → `setSheet({ type })` — used by context menu + fix-its.
- `actions.openPalette()` → `setSheet({ type: 'palette' })`.
- `actions.closeSheet()` → `setSheet(null)` — passed to every sheet as `onClose`.

**Which types exist** (SwiftUI: model as an enum `SheetType`): `palette`, `reconcile`, `commit`, `prune`, `prune-all`, `waiver`, `apply-skill`, `install-hooks`, `about`. `reconcile / commit / prune / apply-skill / install-hooks` require a `selectedRepo`; if none, they render nothing (`repo ? … : null`).

**Global keyboard (from `app.js:196–207`, install one `NSEvent`/`.keyboardShortcut` layer):**
| Keys | Action |
|---|---|
| ⌘K (or ⌃K) | **toggle** palette (open if closed, close if the open sheet is the palette) |
| ⌘J (⌃J) | toggle console |
| ⌘R (⌃R) | `rescan()` |
| ⌘B (⌃B) | if a repo is selected → toast "make validate · running…" |
| Esc | close any sheet **and** dismiss the context menu (`setSheet(null); setCtx(null)`) |

**Backdrop dismiss:** clicking the backdrop calls `onClose`. Inside content, clicks `stopPropagation` so they don't dismiss (SwiftUI: put the dismiss tap on the dimming layer only).

---

## 1. `Backdrop` — shared dimming layer

**Purpose:** the modal scrim behind every sheet and the palette. (`Overlays.js:13–19`.)

**Structure (SwiftUI `ZStack`):** a full-bleed layer filling the app window (`position:absolute; inset:0`), `zIndex --z-overlay` (1000).
- **Fill:** `rgba(4,6,7,0.62)` — a near-black scrim at 62% (NOT a blur; a flat dim). `Color(hex:0x040607).opacity(0.62)`.
- **Child alignment:** a flex container centering horizontally. Vertical: `align='top'` → top-aligned with **`paddingTop: 7%`** of the window height; `align='center'` → centered (used by the About sheet only).
- **Animation:** `mac-fade-in 140ms ease-out` (opacity 0→1). SwiftUI `.transition(.opacity)` + `.animation(.easeOut(duration:0.14))`.
- **Tap:** background tap → `onClose`. The sheet child is a sibling that consumes its own taps.

**SwiftUI:** overlay the whole window; `Color.black-ish.opacity(0.62)` with `.onTapGesture { close() }`; the sheet is a `VStack` pinned to top with `.padding(.top, geometry.height * 0.07)` (7%) or centered.

---

## 2. `Sheet` — generic sheet shell

**Purpose:** the chrome shared by all confirm-gated write sheets (reconcile, commit, prune, waiver, apply-skill, install-hooks, about). (`Overlays.js:20–32`.) The palette does NOT use this shell (it has its own; see §10).

**Prototype signature:** `Sheet({ title, icon, onClose, footer, children, width = 560 })`.

**Container (`VStack`, top-anchored inside the Backdrop):**
- Width = `width` (per-sheet; default 560; see table below), `maxWidth 92%` of window, `maxHeight 82%` of window.
- Background `--surface-1` (#12171A); border **1pt `--border-strong`** (#2E393F); `borderRadius --radius-lg` (10pt); `boxShadow --shadow-lg` (`0 16px 40px rgba(0,0,0,0.55)`); `overflow:hidden`.
- Layout: `display:flex; flexDirection:column` → header / scroll body / optional footer.
- Animation `mac-sheet-in 200ms ease-out` (slide-down-and-settle: from opacity 0, y −12, scale 0.99). SwiftUI: `.transition(.move-ish)` — use `.opacity + .offset(y:-12) + .scaleEffect(0.99)` interpolated over 0.20s ease-out.

**Header bar (`HStack`, spacing 10pt, `alignItems:center`):**
- Padding **`13px 16px`** (top/bottom 13, left/right 16).
- `borderBottom` 1pt `--border` (#202A2E); background `--surface-2` (#171D20).
- Leading: `Icon name={icon} size=16`, color `--accent` (#B4FF34).
- Title: `flex:1`, JetBrains **Mono**, `--text-md` (16px), weight **700**, color `--text-bright` (#F1F6F3). (Title strings are per-sheet, e.g. `"Reconcile · magpie-macos"`.)
- Trailing **close button:** 26×26pt, centered, no border, transparent bg, cursor pointer, color `--text-muted` (#6B7773), `borderRadius --radius-xs` (2pt). Contains `Icon name="x" size=15`. Fires `onClose`.

**Body:** `flex:1; overflowY:auto; padding:16; minHeight:0` → scrollable content region, 16pt padding all sides. SwiftUI `ScrollView { … }.padding(16)`.

**Footer (only if `footer` provided):** `HStack`, `justifyContent:flex-end`, gap **10pt**, padding **`12px 16px`**, `borderTop` 1pt `--border`, background `--surface-2`. Holds the action buttons (Cancel + primary/danger). SwiftUI: bottom bar, buttons right-aligned.

**SwiftUI:** one reusable `SheetShell<Content, Footer>` view: fixed width, rounded 10pt, strong border, `--shadow-lg`, three vertical regions. Icon-title header (surface-2), scroll body (surface-1), footer bar (surface-2). Close X top-right.

---

## 3. Shared sheet sub-elements

### 3.1 `fileRow(icon, path, right, tone)` — a file line in a diff-preview list (`Overlays.js:34–40`)
`HStack`, spacing 10pt, `alignItems:center`, padding **`8px 11px`**, `borderBottom` 1pt `--border-subtle` (#161C1F), JetBrains Mono `--text-sm` (12.5px).
- Leading `Icon size=13`, color = `tone ? var(--{tone}) : var(--text-muted)`, `flex:none`.
- Path: `flex:1`, color `--text-primary`, **truncate with ellipsis, nowrap** (single line, `overflow:hidden; textOverflow:ellipsis`).
- `right`: trailing slot (a diff-count, badge, or arrow — passed by caller).

### 3.2 `diffCount(add, del)` — inline +add/−del (`Overlays.js:41`)
JetBrains Mono `--text-2xs` (10px). `<span style=color:--ok>+{add}</span>` space `<span style=color:--danger>−{del}</span>`. **The minus is U+2212 MINUS SIGN "−", not a hyphen.** e.g. `+18` (lime) `−7` (red). In the prototype `add`/`del` are `Math.random()`-generated per file (reconcile: `randInt(3..32)` / `randInt(0..11)`; commit: `randInt(4..43)` / `randInt(0..14)`). **The native app should show REAL diff counts** from git; the random values are placeholder demo data only — do not reproduce randomness.

### 3.3 File-list card (repeated pattern)
Sheets group files inside a bordered card: `border 1pt --border`, `borderRadius --radius-md` (6pt), `overflow:hidden`, usually `marginBottom 14pt`. It leads with a **section caption bar**: padding `8px 11px`, background `--surface-2`, `borderBottom 1pt --border`, JetBrains Mono `--text-2xs` (10px), `--tracking-label` (0.08em), **UPPERCASE**, color `--text-muted`. Caption text encodes a count, e.g. `skeleton-owned files · 4`, `staged · 3`, `skills to bump · 1`, `will scaffold`, `guardrail hooks`. Then N `fileRow`s.

### 3.4 `Field({ label, children })` — labeled form field (`Overlays.js:213–219`)
Used by waiver + apply-skill. `VStack(spacing:6pt)` as a `<label>`:
- Label span: JetBrains Mono `--text-2xs` (10px), `--tracking-label` (0.08em), **UPPERCASE**, color `--text-muted`.
- Then the control (`select` / `textarea`).

### 3.5 `.vibe-select` — the dropdown control (`components.css:152–172`)
JetBrains Mono `--text-sm` (12.5), color `--text-primary`, bg `--surface-sunken` (#0E1213), border 1pt `--border`, `borderRadius --radius-sm` (4pt), padding `9px 11px`, full width. Custom caret drawn as two 5×5 diagonal gradients at right (`--text-muted`). Hover → border `--border-strong`. Focus → border `--accent` + `box-shadow --ring-inset`. SwiftUI: use a styled `Menu`/`Picker` with `--surface-sunken` bg, mono 12.5, lime focus ring.

### 3.6 `textarea` (inline styled, commit + waiver)
Full width, `resize:vertical`, JetBrains Mono `--text-sm` (12.5), color `--text-primary`, bg `--surface-sunken`, border 1pt `--border`, `borderRadius --radius-sm`, padding `9px 11px`, no outline. `rows=3`. Commit placeholder: `commit message — one logical step…`. Waiver placeholder: `e.g. legacy module, scheduled for the v2 rewrite…`. SwiftUI `TextEditor` styled to match; min 3 text rows tall.

### 3.7 DS `Button` (footer actions) — `components.css:14–62`
Base `.vibe-btn`: `inline-flex`, gap 8pt, JetBrains Mono weight 500, `--text-sm` (12.5), `letterSpacing 0.01em`, `lineHeight 1`, padding **`8px 14px`**, border 1pt transparent, `borderRadius --radius-sm` (4pt). `:active` translateY(0.5px). Disabled → opacity 0.42. Optional leading icon slot 15×15pt.
- **`variant="ghost"` (Cancel/Close):** transparent bg, color `--text-secondary`, transparent border. Hover → bg `--surface-raised`, color `--text-primary`.
- **`variant="primary"` (Apply/Commit/Record/Install):** bg `--accent` (#B4FF34), color `--text-on-accent` (#0B1400), border `--accent`, **weight 700**. Hover → bg `--accent-hover` (#CDFF74) + `box-shadow --glow-ok-sm` (the button glows green on hover). Active → bg `--accent-press` (#9BEC1B). Leading icon 13pt.
- **`variant="danger"` (Prune):** transparent bg, color `--danger` (#FF5B52), border `--danger-line` (`rgba(255,91,82,0.34)`). Hover → bg `--danger-surface` (`rgba(255,91,82,0.12)`), border `--danger`. Leading icon 13pt.

### 3.8 DS `Switch` (commit sign toggle) — `components.css:177–191`
Track 38×22pt, `borderRadius --radius-full`, bg `--surface-active` (#232B30), border 1pt `--border-strong`. Thumb 16×16pt circle at `left:2`, bg `--fg-300` (#97A39E). **Checked:** track bg + border → `--accent`; thumb `translateX(16px)`, bg `--lime-ink` (#0B1400). Transition `--dur-fast` (140ms) ease-out. (Note: the **Tweaks** panel has its own toggle, §14 `TToggle`, 38×22 with `left 2↔18` and lime-ink thumb — same visual.)

### 3.9 DS `StatusBadge` (prune list state chip) — `components.css:85–105`
`.vibe-status--sm`: `inline-flex`, gap 5pt, JetBrains Mono weight 500, `--text-2xs` (10px), padding `3px 7px 3px 6px`, `borderRadius --radius-sm` (4pt), 1pt border. Leading 6×6pt dot in `currentColor`. Tones: `warn` → color `--warn`, bg `--warn-surface`, border `--warn-line`; `danger` → color `--danger`, bg `--danger-surface`, border `--danger-line`. Label `letterSpacing 0.02em`.

---

## 4. `ReconcileSheet` — reconcile skeleton drift (`Overlays.js:44–67`)

**Purpose:** preview + confirm pulling skeleton-owned files back to current (skeleton reconcile) and bumping behind skills. Opened from the sidebar/fleet **right-click → "Reconcile with skeleton…"** (`app.js:186`, disabled unless `node.drift.behind`), and from a fix-it whose `fix === 'reconcile'` (`app.js:157`).

**Props:** `{ repo, actions, onClose }`. Shell `title = 'Reconcile · ' + repo.name`, `icon = 'git-merge'`, **`width = 620`**.

**Data consumed:**
- `repo.name` → title.
- `repo.drift.behind` → e.g. `'2 minor'` (string) or `null`. Drives the intro line.
- `repo.drift.files` → integer count → slices the drift-file list to that length.
- `repo.skills[]` filtered to `s.status === 'behind'` → the "skills to bump" list. Each: `s.id`, `s.installed` (version string or `null`).

**Drift-file list** (demo placeholder — see note): `driftFiles` = a fixed 11-name array `['Makefile', '.claude/hooks/stop-gate.sh', 'scripts/check_docs.py', '.claude/hooks/session-start.sh', '.claude/settings.json', 'scripts/check_skeleton.py', '.pre-commit-config.yaml', 'scripts/check_precommit.py', 'scripts/check_architecture.py', '.github/workflows/validate.yml', 'Makefile.d/validate.mk']` **sliced to `repo.drift.files`**. *Native: replace with the real list of drifted skeleton-owned files.*

**Body layout (VStack):**
1. **Intro paragraph** (mono `--text-sm`, color `--text-secondary`, `lineHeight 1.5`, margin-bottom 14pt):
   - If `drift.behind`: `this repo is `**`{behind}`** (colored `--warn`)` behind the skeleton. these skeleton-owned files will be overwritten with the current version. your code is untouched.`
   - Else: `this repo is current with the skeleton.`
2. **Drift-file card** (only if `driftFiles.length`): §3.3 card, caption `skeleton-owned files · {N}`. Each row = `fileRow('file-diff', filename, diffCount(add,del), 'warn')` → warn-amber file-diff icon, path, `+add −del`.
3. **Skills-to-bump card** (only if `behindSkills.length`): §3.3 card, caption `skills to bump · {N}`. Each row = `fileRow('blocks', s.id, <span mono --text-2xs color:--text-muted>{s.installed || '—'} → latest</span>, 'info')` → info-blue `blocks` icon, skill id, `0.1.0 → latest` trailing.

**Footer:** `[Cancel ghost]  [Apply reconcile — primary, leading git-merge 13pt]`.
- **Cancel** → `onClose()`.
- **Apply reconcile** → `onClose()` then `actions.toast('reconciled ' + repo.name, driftFiles.length + ' skeleton files pulled · ' + behindSkills.length + ' skills bumped', 'ok')`.

**Empty variants:** if `drift.files === 0` and no behind skills, body is just the "current with the skeleton" line + no cards; footer still shows Apply reconcile (a no-op reconcile). Icons: `git-merge` (lucide) → `arrow.triangle.merge`; `file-diff` → `plus.forwardslash.minus` / `doc.badge.ellipsis`; `blocks` → `square.grid.2x2`.

---

## 5. `CommitSheet` — commit & push with sign toggle (`Overlays.js:70–95`)

**Purpose:** preview staged files, write a message, toggle GPG signing, then commit + push. Opened from right-click **"Commit & push…"** (`app.js:187`, disabled if `worktree.clean`), and fix-its `fix === 'commit…'` or `'sign + push'` (`app.js:158`).

**Props:** `{ repo, actions, onClose }`. Shell `title = 'Commit · ' + repo.name`, `icon = 'git-commit-horizontal'`, **`width = 580`**.

**State:** `sign` (`useState(true)` — default ON), `msg` (`useState('')` — the message text).

**Data consumed:**
- `repo.name` → title.
- `repo.stack` (string, e.g. `'python-fastapi'`, `'react'`, `'swift'`) → chooses the placeholder staged-file list (demo only). *Native: use real `git status` staged paths.*
- `repo.worktree.unstaged` (int) → number of files shown = `max(1, unstaged)` (list is sliced to this).
- `repo.worktree.signed` (bool) → if `false`, shows a `commits unsigned` danger pill in the branch row.
- `repo.agent.branch` (string) → the branch to commit on; falls back to `'main'` when no agent/branch.

**Placeholder staged files** (by stack, demo — replace with real): swift → `['Magpie/DownloadManager.swift','Magpie/Views/LibraryView.swift','Magpie/Models/Download.swift']`; react → `['src/entrypoints/popup/App.tsx','src/lib/grab.ts','src/components/Settings.tsx']`; else (python/other) → `['src/server.py','src/routes/billing.py','src/services/sync.py','tests/test_billing.py']`. Sliced to `max(1, unstaged)`.

**Body layout (VStack):**
1. **Branch row** (`HStack`, gap 10, mono `--text-sm`, color `--text-secondary`, margin-bottom 12): `Icon name="git-branch" size=14` (muted) + `on ` + **`{branch}`** (bold, `--text-primary`) + (if `!worktree.signed`) `Pill tone="danger"` reading `commits unsigned`.
2. **Staged-file card** (§3.3): caption `staged · {N}`. Each row = `fileRow('file-pen', path, diffCount(add,del), 'warn')` → warn `file-pen` icon, path, `+add −del`.
3. **Message textarea** (§3.6): `rows=3`, placeholder `commit message — one logical step…`, margin-bottom 12.
4. **Sign toggle row** (`HStack`, gap 10, cursor pointer, as a `<label>`): DS `Switch checked={sign}` + text (mono `--text-sm`, `--text-primary`): `sign commit ` then muted `· signed_commits_required is true`. Tapping the row/label toggles.

**Footer:** `[Cancel ghost]  [Commit & push — primary, leading git-commit-horizontal 13pt]`.
- **Commit & push** → `onClose()` then toast, **tone depends on the sign state**:
  - if `sign`: `toast('committed + pushed', '{N} files → {branch} · signed ✓', 'ok')`.
  - if `!sign`: `toast('committed + pushed', '{N} files → {branch} · UNSIGNED', 'warn')`.

**Icons:** `git-commit-horizontal` → `arrow.triangle.branch`/`smallcircle.filled.circle`; `git-branch` → `arrow.triangle.branch`; `file-pen` → `square.and.pencil`.

**Interaction note:** the sign toggle changing to OFF should NOT be blocked even though policy requires signing — it's a deliberate escape hatch that downgrades the resulting toast to `warn`/UNSIGNED. Mirror that: allow toggling off, warn on the result.

---

## 6. `PruneSheet` — prune worktrees (single repo + fleet-wide) (`Overlays.js:98–116`)

**Purpose:** preview + confirm `git worktree remove` on stale/abandoned worktrees. Two entry modes:
- **Per-repo** (`type: 'prune'`): right-click **"Prune worktrees…"** (`app.js:188`, danger, disabled if workspace or no non-active worktrees), fix-it `fix === 'prune'` (`app.js:159`). Props include `repo`.
- **Fleet-wide** (`type: 'prune-all'`): dispatcher passes `all` flag, no repo (`Overlays.js:301`).

**Props:** `{ repo, data, actions, onClose, all }`. Shell `icon = 'trash-2'`, **`width = 560`**, `title = all ? 'Prune worktrees · fleet' : 'Prune worktrees · ' + repo.name`.

**Data consumed → the prune list:**
- **fleet mode (`all`):** `data.worktreeSprawl.filter(w => w.state !== 'active')`. `data.worktreeSprawl` is `leaves.flatMap(r => r.worktrees.map(w => ({...w, repo: r.name, repoId: r.id})))` (`data.js:685`) — every worktree with its owning repo name attached.
- **per-repo:** `repo.worktrees.filter(w => w.state !== 'active').map(w => ({...w, repo: repo.name}))`.
- Each worktree `w`: `w.branch` (string), `w.created` (relative-time literal, e.g. `'6m ago'`, `'8d ago'`), `w.lastCommit` (unused here), `w.commits` (int), `w.state` (`'active' | 'stale' | 'abandoned'`), `w.repo` (name, shown only in fleet mode). Built via `W(branch, created, lastCommit, commits, state)` (`data.js:50`).

**Body layout (VStack):**
1. **Intro** (mono `--text-sm`, `--text-secondary`, `lineHeight 1.5`, margin-bottom 14): `these worktrees are stale or abandoned. `**`git worktree remove`**` (colored `--text-primary`) `deletes the working directory; branches and commits are kept.`
2. **List card** (§3.3 style but rows are custom, not `fileRow`): border 1pt `--border`, radius `--radius-md`, overflow hidden. Each row `HStack`, gap 10, `alignItems:center`, padding **`9px 11px`**, `borderBottom 1pt --border-subtle` (except last row → none), mono `--text-sm`:
   - `Icon name="git-branch" size=13`, color = `w.state === 'abandoned' ? --danger : --warn`, `flex:none`.
   - `flex:1`: `{w.branch}` (color `--text-primary`) + (fleet mode only) ` · {w.repo}` (color `--text-faint`).
   - Trailing meta (mono `--text-2xs`, `--text-muted`): `{w.created} · {w.commits} commits`.
   - Trailing **`StatusBadge size="sm"`** (§3.9): status = `w.state === 'abandoned' ? 'danger' : 'warn'`, label = `{w.state}` (e.g. `stale`, `abandoned`).

**Footer:** `[Cancel ghost]  [Prune {N} — DANGER variant, leading trash-2 13pt]` (N = list length).
- **Prune** → `onClose()` then `actions.toast('pruned ' + N + ' worktrees', 'git worktree remove × ' + N + ' · disk reclaimed', 'ok')`.

**Icons:** `trash-2` → `trash`; `git-branch` → `arrow.triangle.branch`.

---

## 7. `WaiverSheet` — record a policy waiver (`Overlays.js:119–145`)

**Purpose:** log a waiver for a finding (accept it for now, with a reason + expiry). No specific opener wired in the shipped context menu/fix-its — dispatched via `type: 'waiver'`. Works both with a `repo` (waives one of that repo's surprises) or fleet-wide (waives from `data.findings`).

**Props:** `{ repo, data, actions, onClose }`. Shell `title = 'Record a waiver'`, `icon = 'file-badge'`, **`width = 560`**.

**State:** `pick` (`useState('0')` — index-as-string of the chosen finding), `reason` (`''`), `expiry` (`useState('30d')`).

**Data consumed:** `finds = repo ? repo.surprises : data.findings`. Each finding `f` (built via `F(severity, pass, what, why, fix)`, `data.js:14`): `f.severity` (`'high' | 'med' | 'low'`), `f.what` (short label), plus `pass/why/fix`. `data.findings` = `leaves.flatMap(r => r.surprises.map(...))` (`data.js:680`).

**Body (VStack, gap 14):** three `Field`s (§3.4):
1. `Field label="finding"`: a `.vibe-select` bound to `pick`. Options = `finds.map((f,i) => <option value={String(i)}>{(f.severity||'').toUpperCase()} · {f.what}</option>)` → e.g. `MED · coverage 54% / 60`.
2. `Field label="reason — why this is acceptable for now"`: a `textarea` (§3.6) bound to `reason`, `rows=3`, placeholder `e.g. legacy module, scheduled for the v2 rewrite…`.
3. `Field label="expires"`: a `.vibe-select` bound to `expiry`, options: `7d`→"7 days", `30d`→"30 days", `90d`→"90 days", `never`→"never (permanent)".

**Footer:** `[Cancel ghost]  [Record waiver — primary, leading file-badge 13pt]`.
- **Record waiver** → `onClose()` then `actions.toast('waiver recorded', 'expires in ' + expiry + ' · logged to VIBE.yaml waivers[]', 'info')`.

**Icons:** `file-badge` → `checkmark.seal` / `doc.badge.gearshape`.

---

## 8. `ApplySkillSheet` — apply a missing skill (`Overlays.js:148–171`)

**Purpose:** scaffold a skill into a repo (`.claude/skills/<id>/`) + add its namespace to `VIBE.yaml`. Opened via fix-it `fix === 'apply skill'` (`app.js:161`), type `apply-skill`. Requires a repo.

**Props:** `{ repo, data, actions, onClose }`. Shell `title = 'Apply skill · ' + repo.name`, `icon = 'package-plus'`, **`width = 580`**.

**Data consumed:**
- `repo.skills[]` filtered to `s.status === 'missing'` → their `s.id`s = `missing`. (Skill entry `S(id, installed, status, note)`, `data.js:34`; status ∈ `ok | drift | behind | missing`.)
- `candidates` = `missing.length ? missing : data.skillCatalog.filter(s => s.kind !== 'skeleton').map(s => s.id)` — i.e. the repo's missing skills, or (if none missing) all non-skeleton catalog skills.
- `data.skillCatalog` (`data.js:20`): array of `{ id, name, kind ('skeleton'|'lang'|'tool'), version, ns (namespace, e.g. 'python'), owns (one-line description) }`.
- `pick` (`useState(candidates[0])`); `skill = data.skillCatalog.find(s => s.id === pick)`.

**Body (VStack, gap 14):**
1. `Field label="skill"`: `.vibe-select` bound to `pick`, options = `candidates.map(id => <option>{id}</option>)`.
2. **Description line:** mono `--text-sm`, color `--text-secondary`, `lineHeight 1.5` → `{skill.owns}` (e.g. `FastAPI · Pydantic v2 · async SQLAlchemy · uv · ruff · mypy`).
3. **"will scaffold" card** (§3.3, caption `will scaffold`), two rows:
   - `fileRow('file-plus', '.claude/skills/' + pick + '/', null, 'ok')` → ok-lime file-plus icon, the skills dir path, no trailing.
   - `fileRow('file-code-2', 'VIBE.yaml', <span mono --text-2xs color:--ok>+ {skill.ns}:</span>, 'ok')` → ok file-code icon, `VIBE.yaml`, trailing lime `+ python:`.

**Footer:** `[Cancel ghost]  [Apply skill — primary, leading package-plus 13pt]`.
- **Apply skill** → `onClose()` then `actions.toast('applied ' + pick, 'scaffolded skill + added ' + (skill.ns || pick) + ': namespace to VIBE.yaml', 'ok')`.

**Icons:** `package-plus` → `shippingbox` + badge / `plus.rectangle.on.folder`; `file-plus` → `doc.badge.plus`; `file-code-2` → `chevron.left.forwardslash.chevron.right` / `doc.text`.

---

## 9. `InstallHooksSheet` — install skeleton guardrail hooks (`Overlays.js:174–211`)

**Purpose:** preview + confirm copying the skeleton's guardrail hooks into `.claude/hooks/` and wiring `.claude/settings.json`. Opened via fix-it `fix === 'install hooks'` (`app.js:166`), type `install-hooks`. Requires a repo.

**Props:** `{ repo, data, actions, onClose }`. Shell `title = 'Install skeleton hooks · ' + repo.name`, `icon = 'shield-plus'`, **`width = 600`**.

**Data consumed:**
- `repo.hooks[]` (built via `H(src, event, matcher, cmd, status, opts)`, `data.js:497`): each `{ src ('claude'|'git'|'codex'), event (e.g. 'SessionStart'), matcher (e.g. 'Bash'|'Edit|Write'|null), cmd, status ('active'|'missing'|'nothing'|'drift'|'absent'), scope, skel, note }`.
- **Reference set** (the 4 skeleton claude hooks the sheet checks against, hardcoded in the sheet):
  | event | matcher | file | role |
  |---|---|---|---|
  | `SessionStart` | — | `.claude/hooks/session-start.sh` | load VIBE.yaml + repo rules into context |
  | `PreToolUse` | `Bash` | `.claude/hooks/bash-guard.sh` | block dangerous shell + writes outside scope |
  | `PostToolUse` | `Edit\|Write` | `.claude/hooks/format-edit.sh` | format every file the agent writes |
  | `Stop` | — | `.claude/hooks/stop-gate.sh` | run `make validate` — block finish while red |
- `stateOf(s)` = status of the matching `repo.hooks` entry where `src === 'claude' && event === s.event`, else `'absent'`.
- `need` = reference hooks whose state ≠ `'active'`.
- `n` = `need.length || 4` (install count for the button/toast).

**Per-state glyph + verb maps:**
| state | glyph icon (lucide) | verb word | icon color |
|---|---|---|---|
| `active` | `check` | `present` | `--ok` |
| `absent` | `file-plus` | `install` | `--accent` |
| `missing` | `file-x` | `restore` | `--danger` |
| `nothing` | `shield-off` | `replace stub` | `--danger` |
| `drift` | `file-diff` | `update` | `--accent` |

**Body (VStack):**
1. **Intro** (mono `--text-sm`, `--text-secondary`, `lineHeight 1.5`, margin-bottom 14):
   - if `need.length`: `this repo is missing {need.length} of the skeleton's guardrail hooks. they'll be copied into `**`.claude/hooks/`**` and wired into `**`.claude/settings.json`**`. your existing hooks are kept.` (the two paths colored `--text-primary`).
   - else: `this repo already has every skeleton guardrail. re-installing restores each script to the current skeleton version.`
2. **Hooks card** (§3.3, caption `guardrail hooks`), **all 4** reference hooks listed (present ones dimmed):
   Each row: `HStack`, gap 11, `alignItems:center`, padding **`9px 11px`**, `borderBottom 1pt --border-subtle`, **`opacity: active ? 0.5 : 1`**.
   - Leading `Icon size=14`: name = `active ? 'check' : glyph[state]`, color = `active ? --ok : (state==='missing'||state==='nothing') ? --danger : --accent`, `flex:none`.
   - Middle `VStack` (`flex:1, minWidth:0`):
     - Line 1: mono `--text-sm`, `--text-primary`: `{event}` + (if matcher) muted ` · {matcher}` → e.g. `PreToolUse · Bash`.
     - Line 2: **Space Grotesk (sans)** `--text-2xs`, `--text-muted`: `{file} — {role}` → e.g. `.claude/hooks/bash-guard.sh — block dangerous shell + writes outside scope`.
   - Trailing verb: mono `--text-2xs`, color = `active ? --ok : --accent`, text = `active ? 'present' : verb[state]`.

**Footer:** `[Cancel ghost]  [Install {n} — primary, leading shield-plus 13pt]`.
- **Install** → `onClose()` then `actions.toast('installed skeleton hooks', n + ' guardrail' + (n>1?'s':'') + ' written to .claude/hooks/ · settings.json wired', 'ok')`.

**Icons:** `shield-plus` → `checkmark.shield` / `shield.lefthalf.filled.badge.checkmark`; `check` → `checkmark`; `file-plus` → `doc.badge.plus`; `file-x` → `doc.badge.ellipsis` / `xmark.rectangle`; `shield-off` → `shield.slash`; `file-diff` → `plus.forwardslash.minus`.

---

## 10. `CommandPalette` — ⌘K launcher (`Overlays.js:223–267`)

**Purpose:** the fuzzy launcher to jump to a repo or run an action. Opened by ⌘K (toggle), by the toolbar search affordance (§13), and by the menu-bar "Command palette…" item. Its own backdrop (top-aligned, no `Sheet` shell).

**Props:** `{ data, actions, onClose }`.

**State:** `q` (query, `''`), `hi` (highlighted index, `0`). On mount, autofocus the input (`useEffect` → `inputRef.focus()`; SwiftUI `@FocusState` set true `.onAppear`).

**Command model — two kinds:**
- **`repoCmds`** (`kind: 'repo'`, listed FIRST): `data.repos.map(r => ({ kind:'repo', repo:r, label:r.name, sub:r.path, run: () => actions.openRepo(r.id) }))`. Consumes `r.name`, `r.path`, `r.id`, `r.health`.
- **`cmds`** (`kind: 'action'`, listed AFTER repos) — a fixed 8-item list:
  | icon (lucide) | label | run |
  |---|---|---|
  | `refresh-cw` | `Re-scan ~/Code` | `actions.rescan` |
  | `folder-tree` | `Go to Fleet` | `setView('fleet')` |
  | `radar` | `Go to Agents` | `setView('agents')` |
  | `triangle-alert` | `Go to Findings` | `setView('findings')` |
  | `gauge-circle` | `Go to Autopilot` | `setView('autopilot')` |
  | `blocks` | `Go to Skills` | `setView('skills')` |
  | `terminal` | `Toggle console` | `actions.toggleConsole` |
  | `sliders-horizontal` | `Open Tweaks` | `actions.openTweaks` |
- **`all = [...repoCmds, ...cmds]`** (repos first).

**Filtering (`Overlays.js:242`):** `ql = q.toLowerCase()`. If `ql` non-empty → keep items where `label.toLowerCase().includes(ql) || (sub||'').toLowerCase().includes(ql)` (substring match on label OR the repo path). Else show all. **Then `.slice(0, 9)`** — cap at 9 visible results. (Native: same case-insensitive substring; cap 9.)

**Layout — panel (NOT the `Sheet` shell):**
- Backdrop `align='top'` (§1: 7% top padding). Panel width **580**, `maxWidth 92%`, bg `--surface-1`, border 1pt `--border-strong`, `borderRadius --radius-lg` (10pt), `boxShadow --shadow-lg`, `overflow:hidden`, animation `mac-sheet-in 180ms ease-out`.
- **Search header** (`HStack`, gap 10, `alignItems:center`, padding `13px 16px`, `borderBottom 1pt --border`):
  - `Icon name="command" size=16`, color `--accent`.
  - **Text input**: `flex:1`, transparent bg, no border/outline, color `--text-bright`, JetBrains Mono `--text-md` (16px). Placeholder `jump to a repo or run an action…`.
  - **`Kbd`** reading `esc` (see mac-parts §10: mono 10px, `--text-faint`, border `--border-strong`, radius 2, padding `1×5`, bg `--ink-1000`).
- **Results list**: `maxHeight 340`, `overflowY:auto`, padding 6.
  - **Empty state** (`results.length === 0`): a centered `div`, padding 20, mono `--text-sm`, `--text-muted`, text `no matches`.
  - Each **result row** = a `<button>`: `HStack`, gap 11, full width, `textAlign:left`, padding **`9px 11px`**, `borderRadius --radius-sm` (4pt), no border, bg = **`hi === i ? --surface-active : transparent`** (highlighted row is filled #232B30):
    - Leading: if `kind==='repo'` → `HealthDot health={repo.health} size=8` (see mac-parts §7: colored dot, ok glows, danger pulses); else → `Icon name={icon} size=14`, color `--text-muted`.
    - Middle `flex:1`: mono `--text-sm`, `--text-primary` → `{label}`. If `sub` (repo path): appended `<span>` with `marginLeft 8`, `--text-faint`, `--text-2xs` (10px) → the repo path.
    - Trailing **kind eyebrow**: mono **9px** (raw, below `--text-2xs`), `--tracking-label` (0.08em), UPPERCASE, color `--text-ghost` (#353E3B) → `repo` or `action`.

**Keyboard (input `onKeyDown`, `Overlays.js:251`):**
- **ArrowDown** → `hi = min(results.length-1, hi+1)` (preventDefault).
- **ArrowUp** → `hi = max(0, hi-1)`.
- **Enter** → `run(hi)`: `onClose()` then the highlighted command's `run()`.
- Typing resets `hi = 0` (`onChange` sets `setHi(0)`).
- (Esc is handled globally, §0 — closes the palette. The visible `esc` keycap is a hint.)

**Mouse:** `onMouseEnter` a row → `setHi(i)` (hover moves the highlight). `onClick` a row → `run(i)`.

**SwiftUI:** a top-anchored floating card in a `.overlay`. `TextField` with `@FocusState`. A `List`/`LazyVStack` of buttons; keyboard arrow handling via `onKeyPress` / a key monitor updating `highlightedIndex`; Enter runs it. Highlighted row gets `--surface-active` fill. Cap results at 9. `command` icon (lucide) → `command`; `refresh-cw` → `arrow.clockwise`; `folder-tree` → `folder`; `radar` → `dot.radiowaves.left.and.right`; `triangle-alert` → `exclamationmark.triangle`; `gauge-circle` → `gauge`; `blocks` → `square.grid.2x2`; `terminal` → `terminal`; `sliders-horizontal` → `slider.horizontal.3`.

---

## 11. `AboutSheet` — About Vibe (`Overlays.js:270–289`)

**Purpose:** the About box. Type `about`, dispatched **center-aligned** (`Overlays.js:310`). Uses the `Sheet` shell.

**Props:** `{ data, actions, onClose }`. Shell `title = 'About Vibe'`, `icon = 'info'`, **`width = 460`**.

**Data consumed:** `data.build` (`{ version:'v1.4.2', commit:'9f3a1c0', date:'2026-06-28', channel:'dev', codename:'phosphor' }`), `data.scanner` (`{ root:'~/Code', host:'dev-mac', … }`), `data.totals.repos`, `data.totals.workspaces`.

**Body (VStack, `alignItems:center`, gap 18, padding `8px 0 6px`):**
1. **`window.VibeLogo size={40} mark sub="mission control for vibe coding"`** — the brand logo lockup (see `brand.js`/mac-parts Wordmark; big 40pt mark + subtitle).
2. **Meta block** (full width, `borderTop 1pt --border`, `paddingTop 12`, `VStack gap 2`), a stack of `MetaRow`s (mac-parts §12: UPPERCASE mono key, right-aligned value):
   - `version` → `{b.version} · {b.channel}` → `v1.4.2 · dev`.
   - `commit` → `{b.commit}` colored `--info` → `9f3a1c0`.
   - `built` → `{b.date}` → `2026-06-28`.
   - `codename` → `{b.codename}` → `phosphor`.
   - `scanning` → `{scanner.root} · {scanner.host}` → `~/Code · dev-mac`.
   - `watching` → `{totals.repos} repos · {totals.workspaces} workspaces`.
3. **Tagline** (Space Grotesk `--text-2xs`, `--text-muted`, centered, `lineHeight 1.5`): `reads ~/Code directly · keeps an eye on the agents`.

**Footer:** `[Close ghost]  [Identity & app icons — primary, leading shapes 13pt]`. The primary opens `identity.html` in a new tab (native: open the identity/asset reference, or omit).

**Icons:** `info` → `info.circle`; `shapes` → `square.on.circle` / `paintpalette`.

---

## 12. Right-click context menu (opener of the write sheets) (`app.js:51–71, 177–193`)

Not part of `Overlays.js`, but it is the **primary launcher** for the write sheets, so the engineer must build it. `ContextMenu({ menu, onClose })` renders a floating `mac-pop`.

**Panel:** `position:fixed` at `(min(x, winW-240), min(y, winH-260))` (clamps to stay on-screen), `zIndex --z-popover` (1100), `minWidth 220`, bg `--surface-raised` (#1D2428), border 1pt `--border-strong`, `borderRadius --radius-md` (6pt), `boxShadow --shadow-pop`, padding 5, animation `mac-pop-in 110ms ease-out`.

**Items** (each a button: `HStack` gap 10, padding `6px 9px`, `borderRadius --radius-xs`, mono `--text-sm`; hover → bg `--surface-active` (or `--danger-surface` for danger items); disabled → color `--text-ghost`, no hover; danger → color `--danger`). Separator = a 1pt `--border` line, `margin 5px 6px`. Icon size 13.

**Menu contents for a repo/workspace node** (`app.js:180–191`):
| label | icon | enabled-when | action |
|---|---|---|---|
| Open | `arrow-right` | always | `openRepo(node.id)` |
| Reveal in Finder | `folder-search` | always | toast |
| Open in editor | `code` | always | toast |
| — separator — | | | |
| Re-check | `play` | always | toast "make validate" |
| **Reconcile with skeleton…** | `git-merge` | `node.drift.behind` truthy | `setSelectedId(node.id); openSheet('reconcile')` |
| **Commit & push…** | `git-commit-horizontal` | `!node.worktree.clean` | `setSelectedId(node.id); openSheet('commit')` |
| **Prune worktrees…** | `trash-2` (danger) | not workspace AND some worktree `state!=='active'` | `setSelectedId(node.id); openSheet('prune')` |
| — separator — | | | |
| Copy path | `clipboard` | always | toast |

Dismiss: any window click or scroll closes the menu (and Esc, §0). SwiftUI: build a custom floating menu (a `Menu`/context menu with these gating rules), or a right-click-positioned popover.

---

## 13. Toolbar ⌘K search affordance (`MacChrome.js:212–221`)

The visible control that invites the palette. A `<button>` (`onClick = actions.openPalette`):
- `HStack`, gap 8, **height 30pt, width 200pt**, `flex:none`, padding `0 9px`.
- bg `--surface-sunken` (#0E1213), border 1pt `--border`, `borderRadius --radius-sm` (4pt), cursor **text**, color `--text-faint` (#4C5754), mono `--text-sm` (12.5).
- Leading `Icon name="search" size=14` (`flex:none`) → SF `magnifyingglass`.
- Middle `flex:1`, left-aligned, truncating: placeholder text `search fleet…`.
- Trailing **`Kbd`** reading `⌘K`.

SwiftUI: a 200×30 button styled as a faux search field; tapping opens the palette. Also present as a menu item "Command palette… ⌘K" in the app menu (`MacChrome.js:156`).

---

## 14. `MacTweaksPanel` — the Tweaks panel (`Tweaks.js`)

**Purpose:** a floating dark control panel (bottom-right) that adjusts **density, accent glow, window framing, desktop backdrop, and the demo fleet-health state**. In the prototype it is the design-tool "edit mode" panel driven by `postMessage`; **in the native app it is simply a Settings/Tweaks popover** the user opens. Opened by the palette's "Open Tweaks" and `actions.openTweaks` (`app.js:150`, which posts `__activate_edit_mode`). Persists to `localStorage['vibe.mac.tweaks']` (native: `@AppStorage`/UserDefaults).

**Prototype signature:** `MacTweaksPanel({ t, setTweak })` where `t` is the current tweak values and `setTweak(key, value)` writes one. Hidden unless "edit mode" is active (`open` state). A dismiss (X) hides it. **Native:** drop the `postMessage` host-protocol entirely; render the panel when the user opens Tweaks, persist via `@AppStorage`.

**Tweak model + defaults (`app.js:12` `TWEAK_DEFAULTS`):**
| key | type | default | options / range |
|---|---|---|---|
| `density` | enum | `comfortable` | `comfortable` \| `compact` |
| `glow` | int % | `100` | `0…150` step **10** |
| `framing` | enum | `fullbleed` | `fullbleed` \| `floating` |
| `desktop` | bool | `false` | (enabled only when `framing==='floating'`) |
| `health` | enum | `live` | `calm` \| `live` \| `onfire` (demo fleet state) |

**Panel container (`Tweaks.js:80`):** `position:fixed`, **`right:16, bottom:16`**, `zIndex 2147483646` (top-most), **width 256**, `VStack`, bg `--surface-1`, border 1pt `--border-strong`, `borderRadius --radius-lg` (10pt), `boxShadow --shadow-lg`, `overflow:hidden`, `fontFamily --font-mono`.

**Header (`HStack`, `justify:space-between`, padding `10px 12px`, `borderBottom 1pt --border`, bg `--surface-2`):**
- Left: `Icon name="sliders-horizontal" size=13` (color `--accent`) + `Tweaks` (mono `--text-sm`, weight 700, `--text-bright`).
- Right: close button 22×22, transparent, `--text-muted`, `Icon name="x" size=13`. Dismisses.

**Body (`VStack`, padding `6px 14px 14px`, gap 8):** section headers + rows in this order:

1. **`TSection label="display"`** — section caption: mono **9px**, `--tracking-label`, UPPERCASE, `--text-faint`, padding `12px 0 2px`.
2. **`TRow label="density"`** → **`TSeg`** with options `[comfortable, compact]`, value `t.density`, `onChange → setTweak('density', v)`.
3. **`TRow label="accent glow" value={t.glow + '%'}`** → **`TSlider`** min 0 max 150 step 10, value `t.glow`, `onChange → setTweak('glow', v)`. (The `value` "100%" shows at right of the row label.)
4. **`TSection label="window"`**.
5. **`TRow label="framing"`** → **`TSeg`** options `[full-bleed(value:fullbleed), floating]`, `onChange → setTweak('framing', v)`.
6. **Desktop-backdrop row** (a bespoke `HStack`, `justify:space-between`, NOT a `TRow`):
   - Label span mono `--text-xs` (11px): text `desktop backdrop`, color = `t.framing === 'floating' ? --text-secondary : --text-faint` (dims when disabled).
   - **`TToggle`** `on={t.desktop}`, `disabled={t.framing !== 'floating'}`, `onChange → setTweak('desktop', v)`.
7. **`TSection label="demo · fleet health"`**.
8. **`TRow label="state"`** → **`TSeg`** options `[calm, live, onfire(label:"on fire")]`, `onChange → setTweak('health', v)`.

### 14.1 `TSection` (`Tweaks.js:28`)
Mono 9px, `--tracking-label` (0.08em), UPPERCASE, `--text-faint` (#4C5754), padding `12px 0 2px`.

### 14.2 `TRow` (`Tweaks.js:31`)
`VStack(gap:6)`: top `HStack(justify:space-between, align:baseline)` = label (mono `--text-xs` 11px, `--text-secondary`) + optional right value (mono `--text-2xs` 10px, `--text-muted`); then the control below.

### 14.3 `TSeg` — mini segmented control (`Tweaks.js:42`)
`HStack`, padding 2, gap 2, bg `--ink-1000` (#07090A), border 1pt `--border`, `borderRadius --radius-sm` (4pt). Each option a `flex:1` button, padding `5px 4px`, `borderRadius --radius-xs` (2pt), mono `--text-2xs` (10px):
- **selected (`on`):** border 1pt `--border-strong`, bg `--surface-raised` (#1D2428), color `--text-primary`, weight **700**.
- **unselected:** border 1pt transparent, bg transparent, color `--text-muted`, weight 500.
- Click → `onChange(value)`.
(Same visual grammar as `SegMac` in mac-parts §9 but full-width segments, smaller.)

### 14.4 `TToggle` — switch (`Tweaks.js:52`)
`button role="switch" aria-checked`: 38×22pt, `borderRadius 999`, border 1pt (`on ? --accent : --border-strong`), bg (`on ? --accent : --surface-active`), disabled → opacity 0.45, cursor not-allowed. Thumb 16×16 circle at `top:2, left: on ? 18 : 2`, bg (`on ? --lime-ink : --fg-300`), transition `left --dur-fast ease-out`. `onChange(!on)` unless disabled.

### 14.5 `TSlider` — range input (`Tweaks.js:60`)
`<input type=range>` full width, `accentColor --accent` (lime track/thumb), min/max/step per row. `onChange → Number(value)`. SwiftUI `Slider(value:in:step:)` tinted lime.

### 14.6 What the tweaks DO (apply these behaviors natively — `app.js:14–17, 113–121, 209, 230`)

- **`density`** sets a family of layout CSS vars (SwiftUI: an `@Environment` density value driving these metrics):
  | var | comfortable | compact |
  |---|---|---|
  | `--mac-row` | 30px | 26px |
  | `--mac-row-lg` | 52px | 42px |
  | `--mac-pad` | 20px | 14px |
  | `--mac-tile-num` (StatTile numeral) | 38px | 30px |
  | `--mac-tile-pad` (StatTile padding) | 16px 18px | 11px 13px |
  | `--mac-gap-sm` | 8px | 6px |
  Also: console height = compact ? 178 : 210 (`app.js:230`).
- **`glow`** (0–150, %): scales the phosphor glow tokens live. With `g = glow/100`:
  - `--glow-ok-sm` = `0 0 {10*g}px rgba(180,255,52,{0.3*g})`.
  - `--glow-text-ok` = `0 0 {12*g}px rgba(180,255,52,{0.45*g})`.
  - `--glow-ok` = `0 0 0 1px var(--ok-border), 0 0 {16*g}px rgba(180,255,52,{0.22*g})`.
  At 0% glow is off; at 100% the default; up to 150% intensified. (Native: multiply glow radii/alpha by `glow/100`.)
- **`framing`**: `fullbleed` = the app fills the window edge-to-edge; `floating` = the mac "stage" floats with a margin (see `MacStage`). Only in `floating` does `desktop` matter.
- **`desktop`**: when `framing==='floating'` AND `desktop` → `vibrant = true` (shows a desktop-wallpaper backdrop behind the floating window). Disabled otherwise (toggle greyed).
- **`health`** (`calm`/`live`/`onfire`): **rebuilds the entire demo dataset** via `buildData(health)` (`app.js:20–48`). This is a **demo/prototype affordance** for showcasing the three fleet states:
  - `live` → the base data as-is (`VIBE_MAC_BUILD(base)`).
  - `calm` → forces everything healthy: `health='ok'`, no surprises, `compliance≥96`, clean signed worktree, agents idle, only active worktrees kept, gates flipped to ok, all docs ok, `drift` cleared.
  - `onfire` → forces trouble: workspaces `danger`; leaves `ok→warn`/else `danger`; `compliance -=22` (floor 40); agents forced active/unsupervised; injects an abandoned worktree; `taskState.status='danger'` (lines≥920); changelog danger (behind≥18); injects an "unsupervised agent session" high surprise.
  **Native:** if the app is a real scanner (per TASK_STATE.md), this control is optional — either keep it as a demo/screenshot toggle or omit. If kept, it should re-derive the displayed model through the same three transforms.

**SwiftUI:** a floating bottom-right popover, 256pt wide, 10pt radius, `--shadow-lg`; header with sliders icon + Tweaks + close; a `VStack` of section captions + `TRow`s. Reuse the `TSeg` (segmented), `TToggle` (switch), `TSlider` (slider). Wire each `setTweak` to `@AppStorage` and to the live density/glow/framing/health effects above.

**Icons:** `sliders-horizontal` → `slider.horizontal.3`; `x` → `xmark`.

---

## 15. Toasts (result surface for every sheet action) (`app.js:125–130`)

Every sheet's confirm fires `actions.toast(title, msg, tone)`. Not in `Overlays.js` (rendered by `Toasts` in the chrome), but the engineer needs the contract since every write ends in one:
- `toast(title, msg, tone='info')` pushes `{ id, title, msg, tone }`, auto-dismisses after **4400ms**.
- Tones used by sheets: `ok` (green — reconcile, prune, apply-skill, install-hooks, signed commit), `warn` (amber — UNSIGNED commit), `info` (blue — waiver). Map tone → color via `STATUS_COLOR` (mac-parts §4.2). `--z-toast` (1200).

---

## 16. Native build checklist (overlays + tweaks)

1. **One overlay coordinator** holding `sheet: SheetType?` and the tweak model; a `Backdrop` (62% flat scrim, 7%-top or centered) + `SheetShell` (10pt radius, strong border, `--shadow-lg`, surface-2 header/footer, surface-1 body).
2. **Seven write sheets**, each: icon-title header, an intro paragraph, one or more bordered file/preview cards with UPPERCASE-mono `· N` captions and truncating mono rows + `+add −del` (real git counts, U+2212 minus, lime/red), a right-aligned footer with `[Cancel ghost] [primary/danger]`. Widths: reconcile 620, commit 580, prune 560, waiver 560, apply-skill 580, install-hooks 600, about 460.
3. **Confirm-gated writes only**: no sheet mutates until the primary button; each primary calls `onClose()` then a `toast(...)` whose tone/text is spec'd above (commit tone flips on the sign toggle).
4. **Command palette**: top-anchored 580pt card, command icon + autofocused mono-16 input + `esc` keycap; repos-first then 8 actions; case-insensitive substring filter on label OR repo path; cap 9; arrow/enter/hover highlight with `--surface-active` fill; `HealthDot` for repos, lucide icon for actions, ghost `repo`/`action` eyebrow; "no matches" empty state.
5. **Tweaks panel**: bottom-right 256pt popover; sections display / window / demo·fleet-health; `TSeg` (density, framing, health), `TSlider` (glow 0–150 step 10, "%") , `TToggle` (desktop backdrop, disabled unless framing=floating). Wire density/glow/framing/health to their live effects; persist to `@AppStorage`.
6. **Exact paddings/sizes:** sheet header `13×16`, footer `12×16`, body `16`; fileRow `8×11`; prune/hooks rows `9×11`; caption bar `8×11`; palette row `9×11`; tweaks panel header `10×12`, body `6/14/14`; TSeg btn `5×4`; toggles 38×22 thumb 16; buttons `8×14` (primary/danger leading icon 13).
7. **Data paths consumed verbatim:** `repo.name`, `repo.drift.{behind,files}`, `repo.skills[].{id,installed,status}`, `repo.stack`, `repo.worktree.{clean,unstaged,signed}`, `repo.agent.branch`, `repo.worktrees[].{branch,created,commits,state}`, `repo.surprises[].{severity,what}` / `data.findings`, `repo.hooks[].{src,event,status}`, `data.worktreeSprawl[].{branch,created,commits,state,repo}`, `data.skillCatalog[].{id,ns,owns,kind}`, `data.repos[].{id,name,path,health}`, `data.build.{version,commit,date,channel,codename}`, `data.scanner.{root,host}`, `data.totals.{repos,workspaces}`.
8. **Motion:** `mac-fade-in`/`mac-sheet-in`/`mac-pop-in` on entry; primary button hover glow (`--glow-ok-sm`); palette highlight; all gated on reduce-motion (durations → 0).
