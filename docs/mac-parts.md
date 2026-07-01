# Vibe for macOS — `mac-parts.js` Shared Primitives Spec

**Source:** `ui_kits/vibe-macos/mac-parts.js` (React/Babel prototype, 220 lines)
**Target:** native macOS SwiftUI app, built pixel-faithfully from THIS spec (engineer will not read the JS).
**Theme:** dark-mode only. No light theme. No glassmorphism / no backdrop blur. Surfaces are solid ink, delineated by hairline borders. Saturated hue appears **only** to signal state. The brand accent IS the "ok" lime — the board glows green when the fleet is healthy.

This file defines the shared native-app primitives that every macOS view composes: the Lucide icon shim, macOS traffic lights, a macOS segmented control, live agent-activity indicators (pulse dot + equalizer), disclosure triangle, stat tiles, limit/meter bars, pills, keycaps, meta rows, empty-states, the brand wordmark, and the formatters + shared maps/hooks.

---

## 0. Global foundations (tokens → Swift)

All measurements below cite the CSS custom property **and** its resolved raw value. Map every token to a Swift constant. **4 pt grid.** `1px == 1pt` on macOS at @1x logical points (the prototype's px map 1:1 to SwiftUI points).

### 0.1 Color tokens (resolve these to `Color`)

**Ink / surfaces (backgrounds):**
| Token | Alias | Hex |
|---|---|---|
| `--ink-1000` | `--bg-void` | `#07090A` |
| `--ink-900` | `--bg-app` | `#0A0D0E` |
| `--ink-850` | `--surface-sunken` | `#0E1213` |
| `--ink-800` | `--surface-1` | `#12171A` |
| `--ink-750` | `--surface-2` | `#171D20` |
| `--ink-700` | `--surface-raised` | `#1D2428` |
| `--ink-650` | `--surface-active` | `#232B30` |
| `--ink-600` | `--border-divider` | `#2C353A` |

**Hairlines / borders:**
| Token | Alias | Hex |
|---|---|---|
| `--line-soft` | `--border-subtle` | `#161C1F` |
| `--line` | `--border` | `#202A2E` |
| `--line-loud` | `--border-strong` | `#2E393F` |

**Foreground / text (green-tinted neutrals):**
| Token | Alias | Hex |
|---|---|---|
| `--fg-50` | `--text-bright` | `#F1F6F3` |
| `--fg-100` | `--text-primary` | `#E5ECE8` |
| `--fg-200` | (strong secondary) | `#C5CFCB` |
| `--fg-300` | `--text-secondary` | `#97A39E` |
| `--fg-400` | `--text-muted` | `#6B7773` |
| `--fg-500` | `--text-faint` | `#4C5754` |
| `--fg-600` | `--text-ghost` | `#353E3B` |

**Status hues (foreground):**
| Semantic | Token | Resolves to | Hex |
|---|---|---|---|
| ok / accent | `--ok`, `--accent` | `--lime-400` | `#B4FF34` |
| accent-hover | `--accent-hover` | `--lime-300` | `#CDFF74` |
| accent-press | `--accent-press` | `--lime-500` | `#9BEC1B` |
| accent-dim | `--accent-dim` | `--lime-600` | `#7BC60E` |
| warn | `--warn` | `--amber-400` | `#F7B23C` |
| danger | `--danger` | `--red-400` | `#FF5B52` |
| info | `--info` | `--blue-400` | `#6FB7E0` |
| policy | `--policy` | `--violet-400` | `#A593F5` |
| on-accent (text on lime fill) | `--text-on-accent` | `--lime-ink` | `#0B1400` |

**Low-alpha state fills + hairline borders (chips/pills/tints).** Note the pattern `--<tone>-surface` → `--<tone>-bg`; `--<tone>-line` → `--<tone>-border`:
| Token | Value |
|---|---|
| `--ok-surface` (`--ok-bg`) | `rgba(180,255,52,0.10)` |
| `--ok-line` (`--ok-border`) | `rgba(180,255,52,0.30)` |
| `--warn-surface` (`--warn-bg`) | `rgba(247,178,60,0.12)` |
| `--warn-line` (`--warn-border`) | `rgba(247,178,60,0.32)` |
| `--danger-surface` (`--danger-bg`) | `rgba(255,91,82,0.12)` |
| `--danger-line` (`--danger-border`) | `rgba(255,91,82,0.34)` |
| `--info-surface` (`--info-bg`) | `rgba(111,183,224,0.12)` |
| `--info-line` (`--info-border`) | `rgba(111,183,224,0.30)` |
| `--violet-bg` | `rgba(165,147,245,0.12)` |
| `--violet-border` | `rgba(165,147,245,0.30)` |

There is **no** `--policy-surface` / `--policy-line` token — policy pills fall back to the neutral treatment (see Pill).

### 0.2 Radii, borders, spacing
| Token | Value | Use |
|---|---|---|
| `--radius-xs` | `2px` | chips, ticks, keycaps, segmented inner buttons, pills |
| `--radius-sm` | `4px` | buttons, inputs, badges, segmented outer container |
| `--radius-md` | `6px` | cards, panels |
| `--radius-lg` | `10px` | large containers, modals |
| `--radius-xl` | `14px` | hero panels |
| `--radius-full` | `999px` | dots, pill tags, meter tracks |
| `--border-w` | `1px` | default border width |
| `--border-w-thick` | `2px` | — |
| `--space-1`…`--space-6` | `4,8,12,16,20,24px` | grid steps (`--space-1_5`=6, `--space-2_5`=10) |

### 0.3 Typography
- **Mono (default voice):** `--font-mono` = **JetBrains Mono** (weights 400/500/700/800; italic 400/500). Everything data/label/code.
- **Sans (display/UI):** `--font-sans` = **Space Grotesk** (400/500/600/700). Headings, hero prose, buttons.
- **Type scale (px == pt):** `--text-2xs` **10**, `--text-xs` **11**, `--text-sm` **12.5**, `--text-base` **14**, `--text-md` **16**, `--text-lg` **20**, `--text-xl` **26**, `--text-2xl` **34**, `--text-3xl` **46**, `--text-4xl` **62**.
- **Weights:** regular 400, medium 500, semibold 600 (Space Grotesk only), bold 700, black **800** (JetBrains Mono ExtraBold — the big numerals).
- **Tracking:** `--tracking-tight` −0.02em; `--tracking-snug` −0.01em; `--tracking-label` **0.08em** (UPPERCASE mono micro-labels); `--tracking-wide` **0.14em** (eyebrows).
- **Tabular numerals:** wherever mono renders data, enable `'tnum'` (SwiftUI: `.monospacedDigit()` on JetBrains Mono, or the `.featureSettings` for `tnum`/`zero`). Big numerals additionally use `fontFeatureSettings: 'tnum'`.
- Never set mono below 11px or display below 13px.

### 0.4 Effects / motion
| Token | Value |
|---|---|
| `--shadow-pop` | `0 10px 30px rgba(0,0,0,0.6), 0 0 0 1px #2E393F` (popover/menus) |
| `--inset-top` | `inset 0 1px 0 rgba(255,255,255,0.03)` (etched top highlight; used on active segment) |
| `--glow-ok-sm` | `0 0 10px rgba(180,255,52,0.30)` (small phosphor glow — live dots, cursor, ok meter fill) |
| `--glow-text-ok` | `0 0 12px rgba(180,255,52,0.45)` (text-shadow glow on "ok" hero numerals) |
| `--ease-out` | `cubic-bezier(0.2,0.6,0.2,1)` |
| `--ease-in-out` | `cubic-bezier(0.4,0,0.2,1)` |
| `--dur-fast` | `140ms` — swift `.easeOut(duration:0.14)` |
| `--dur-base` | `200ms` |

**Reduced motion:** respect `prefers-reduced-motion` (SwiftUI `@Environment(\.accessibilityReduceMotion)`): when set, disable ALL keyframed liveness — the equalizer bars, sheet/pop animations, scan bar, and the durations collapse to 0ms. Static fallbacks: equalizer bars freeze at `scaleY(0.4)` @ opacity 0.4; pulse dot stops.

### 0.5 Keyframes to reimplement (see `injectMacKeyframes` + base.css)
| Name | Definition | Where |
|---|---|---|
| `mac-eq` | `0%,100% → scaleY(0.35); 50% → scaleY(1)` | AgentPulse bars |
| `mac-sheet-in` | `from{opacity:0; translateY(-12px) scale(0.99)} to{none}` | sheets/overlays (not in this file's components) |
| `mac-pop-in` | `from{opacity:0; translateY(-6px) scale(0.98)} to{none}` | popovers |
| `mac-fade-in` | `opacity 0→1` | generic |
| `mac-scan-x` | `translateX(-100%) → translateX(320%)` | scan bar |
| `vibe-cursor-blink` (base.css) | `0%,49%{opacity:1} 50%,100%{opacity:0}`, `1.1s steps(1,end) infinite` | Wordmark cursor |
| `vibe-pulse` (base.css) | `0%,100%{opacity:1; scale(1)} 50%{opacity:0.45; scale(0.82)}`, `1.5s ease-in-out infinite` | HealthDot violation pulse |

---

## 1. `Icon` — Lucide icon shim

**Purpose:** universal icon primitive. In the prototype, renders `<i data-lucide="name">` which Lucide's `createIcons()` swaps in-place for an inline `<svg>`. Appears in virtually every component.

**Prototype signature:** `Icon({ name, size = 16, style, strokeWidth })`
- Outer wrapper `<span class="lic">` gets `font-size: {size}px` (the SVG is sized `1em × 1em`, so **`size` in px == icon box in pt**).
- `.lic` CSS: `display:inline-flex; align-items:center; justify-content:center; vertical-align:middle;`
- `.lic svg`: `width:1em; height:1em; stroke-width:2; display:block;` → **default Lucide stroke width is 2**, overridable via `strokeWidth` prop.
- Color is inherited from `currentColor` (set via the passed `style.color`).

**SwiftUI mapping:** the engineer maps each Lucide name → SF Symbol. Render as `Image(systemName:)` with `.font(.system(size: size))` or `.frame(width: size, height: size)`, `.foregroundStyle(color)`. Default size **16pt**, default stroke ≈ SF Symbol `.regular`/medium weight (Lucide stroke-2 ≈ SF Symbol regular at this scale). Icon is decorative (`aria-hidden`) → `.accessibilityHidden(true)` unless it carries the only label.

**Lucide → SF Symbol name map used across the kit (build this dictionary):**
`bot`→`cpu`/`brain`, `square-terminal`→`terminal`, `waypoints`→`point.3.connected.trianglepath.dotted`, `chevron-right`→`chevron.right`, `folder-git-2`→`folder`, `gauge`→`gauge.with.dots.needle.67percent`, `git-branch`→`arrow.triangle.branch`, `file-warning`→`exclamationmark.triangle`, `triangle-alert`→`exclamationmark.triangle.fill`, `blocks`→`square.grid.2x2`, `check`→`checkmark`, `moon`→`moon`, `history`→`clock.arrow.circlepath`, `webhook`→`link`, `plug-zap`→`bolt.badge.a`, `gauge-circle`→`gauge`, `radio`→`dot.radiowaves.left.and.right`, `zap`→`bolt.fill`, `pause`→`pause.fill`, `server`→`server.rack`, `folder-git-2`→`folder.fill`. (Engineer finalizes; these are guidance.)

---

## 2. `useLucide` hook

**Purpose:** after each render, calls `window.lucide.createIcons()` to hydrate all `<i data-lucide>` placeholders into SVGs. **No SwiftUI equivalent needed** — SF Symbols render natively. Document only so the engineer knows every view calls it (it is a render side-effect, not layout). **Ignore in the native port.**

---

## 3. Formatters

### 3.1 `formatBytes(n)` — byte formatter
Exact algorithm (reproduce precisely):
```
if n == null        → "—"  (em dash)
if n < 1024         → "{n} B"                       // e.g. 512 → "512 B"
if n < 1024*1024    → "{n/1024 rounded} KB"
                        decimals = 1 if n < 10240 else 0
                        // 3600 → "3.5 KB"; 31200 → "30 KB"
else                → "{(n/1048576).toFixed(1)} MB" // 13400 → "0.0 MB" (bug-faithful; 1.5M → "1.5 MB")
```
Rendered in mono, always paired with a line count, e.g. `"320 ln · 13.1 KB"` / `"740 lines · 30 KB"`. **Reproduce the rounding thresholds exactly** (1 decimal under 10 KB, 0 decimals 10 KB–1 MB, 1 decimal ≥1 MB).

### 3.2 Number formatter — `Number.toLocaleString()`
There is no named function; the kit calls JS `value.toLocaleString()` inline for every integer (line counts, `+210`, runs, files). This yields **grouped thousands with the user locale separator** (en-US: `1,234`). SwiftUI: `value.formatted(.number.grouping(.automatic))` or a `NumberFormatter` with `numberStyle = .decimal`. Always mono + tabular.
Signed diffs are hand-built: `'+' + n.toLocaleString()` and `'−' + n.toLocaleString()` (note: **U+2212 MINUS SIGN "−", not a hyphen**), colored `--ok` / `--danger`.

### 3.3 Relative time
**No formatter exists in this file.** Relative-time strings are **pre-baked literals** in the data model (`checked: '3s ago'`, `agent.elapsed: '6m'`, `agent.lastActivity: '11s ago'`, `changelog.lastUpdated: '2d ago'`). The native app receives these as strings and renders them verbatim in mono. (If the native app computes them live, mirror the terse style: `Ns / Nm / Nh / Nd ago`.)

---

## 4. Shared maps & `agentTool`

### 4.1 `HEALTH_COLOR` (health → color)
```
ok:'--ok'(#B4FF34)  warn:'--warn'(#F7B23C)  danger:'--danger'(#FF5B52)  idle:'--fg-500'(#4C5754)
```
Used by `HealthDot`. Note the **`idle`** key (faint gray) is the fallback for unknown/idle.

### 4.2 `STATUS_COLOR` (status → color)
```
ok:'--ok'  warn:'--warn'  danger:'--danger'  info:'--info'(#6FB7E0)
```
Used to color AgentPulse in the console by console-line `tone`.

### 4.3 `AGENT_TOOLS` + `agentTool(id)`
Maps an agent-tool id → `{ label, icon }`:
| id | label | lucide icon |
|---|---|---|
| `claude-code` | `claude code` | `bot` |
| `codex` | `codex` | `square-terminal` |
| `serena` | `serena` | `waypoints` |

`agentTool(id)` returns the entry, or fallback `{ label: id || 'agent', icon: 'bot' }`. Data source: `repo.agent.tool` / `agent.tool` (nullable when idle). Rendered as label text (mono, often colored `--warn` when the agent is live) and/or its icon.

---

## 5. `Wordmark` — brand wordmark with live cursor

**Purpose:** the "vibe" brand lockup with a blinking phosphor cursor block. Appears in the macOS chrome/topbar (`MacChrome.js` `<Wordmark size={15} sub="" />`).

**Structure (SwiftUI `HStack`, `.firstTextBaseline` alignment, spacing 8pt):**
- Word group: `HStack(spacing:0)` baseline-aligned:
  - `"vibe"` — **JetBrains Mono, weight 800, size = `size`px** (default 18), `letterSpacing −0.03em`, color `--text-bright` (#F1F6F3), `lineHeight 1`.
  - **Cursor block** immediately after: width `0.32em`, height `0.8em`, `margin-left 0.1em`, background `--accent` (#B4FF34), shadow `--glow-ok-sm`, animation `vibe-cursor-blink 1.1s steps(1,end) infinite` (hard on/off blink, 50% duty). Render as a small filled `Rectangle` with a green glow (`.shadow(color: lime.opacity(0.30), radius:5)`), toggling opacity 1↔0 on a 1.1s repeating timer (`steps(1)` = no fade).
- Optional `sub` eyebrow (only if non-empty): JetBrains Mono, size `size*0.5`, `--tracking-wide` (0.14em), UPPERCASE, color `--text-muted`.

---

## 6. `TrafficLights` — macOS window controls

**Purpose:** the close/minimize/zoom buttons in the app's custom title bar (`MacChrome.js` line 196, `<TrafficLights onClose={()=>{}} />`). Since the native app has a real macOS title bar, this may be **replaced by the system traffic lights** — but if a custom chrome is used, reproduce exactly.

**Structure:** `HStack(spacing: 8pt)`, vertically centered. Three circles, left→right:
| Order | Color | Action |
|---|---|---|
| 1 close | `#FF5F57` | fires `onClose` (role=button, clickable) |
| 2 minimize | `#FEBC2E` | (no handler in proto) |
| 3 zoom | `#28C840` | (no handler in proto) |

Each dot: **12×12pt**, `borderRadius 999px` (full circle), **border `0.5px solid rgba(0,0,0,0.25)`** (subtle dark rim). Container `title="close · minimize · zoom"` tooltip. No hover glyphs are drawn in the proto (flat solid dots). **Native:** prefer the real window buttons; if custom, these exact hexes + 12pt + 0.5pt inner dark stroke.

---

## 7. `HealthDot` — status dot (pulses only on violation)

**Purpose:** compact repo/system health indicator. Ubiquitous — fleet rows, agent rows, sidebar, inspector, command palette, chrome. Sizes vary by context (see below).

**Prototype signature:** `HealthDot({ health = 'ok', size = 8 })` — a circle.
- Diameter = `size` pt, `borderRadius 999px`, `flex:none` (never shrinks).
- **Fill** = `HEALTH_COLOR[health]` → ok #B4FF34 / warn #F7B23C / danger #FF5B52 / idle #4C5754.
- **Shadow/glow by state:**
  - `ok` → `--glow-ok-sm` = `0 0 10px rgba(180,255,52,0.30)` (the healthy phosphor glow).
  - `danger` (violation) → `0 0 9px rgba(255,91,82,0.6)` (red glow).
  - anything else (warn/idle) → no shadow.
- **Animation:** `vibe-pulse 1.5s ease-in-out infinite` **only when `health === 'danger'`** (opacity 1→0.45, scale 1→0.82). ok/warn/idle are static.

**Data:** `health` from `repo.health` / `r.health` / `node.health` / `c.repo.health` (values `'ok' | 'warn' | 'danger'`; idle-fallback gray for unknown).

**Observed sizes:** FleetView row 9; AgentsView row 8; MacChrome title 7 / footer 6; MacInspector 9 / nested 7; Overlays palette 8; RepoAgent header 11.

**SwiftUI:** `Circle().fill(color).frame(width:size,height:size)` + conditional `.shadow`. Pulse = `.scaleEffect`/`.opacity` on a 1.5s `.easeInOut(...).repeatForever(autoreverses:true)` gated on `health == .danger` and reduce-motion off.

---

## 8. `AgentPulse` — live agent equalizer (3 bars)

**Purpose:** signals an agent is actively working. Shown wherever a live session appears — sidebar node, fleet row, workspace row, console header, agents list, chrome menu/footer, inspector, repo cards.

**Prototype signature:** `AgentPulse({ active = true, color = 'var(--warn)', size = 13 })`.
**Structure:** `HStack(spacing: 2pt)`, centered, container `height = size`. **Three vertical bars**:
- Each bar: **width 2.5pt**, **height = `size`**, `borderRadius 2pt`, `background = color`, `transformOrigin center`.
- **When `active`:** `animation: mac-eq {0.7 + i*0.18}s ease-in-out {i*0.12}s infinite` — bar 0 = 0.70s/0s delay, bar 1 = 0.88s/0.12s, bar 2 = 1.06s/0.24s. Keyframe `mac-eq`: scaleY 0.35 → 1 → 0.35. Opacity 1.
- **When inactive:** no animation, `opacity 0.4`, `transform scaleY(0.4)` (short, dim, frozen).

**Default `color` = `--warn`** (amber) — most call-sites pass amber for an active agent, switching to `--danger` (red) when `repo.health === 'danger'`, or `STATUS_COLOR[tone]` in the console. **Data:** gated on `repo.agent.active` / `agent.active` / `node`-has-agent.

**Observed sizes/colors:** MacSidebar 11 (danger if node danger else warn); FleetView 12; WorkspaceDetail 11; MacConsole 9 (`STATUS_COLOR[a.tone]`); AgentsView 14 (warn); MacChrome 11 & 9 (warn/danger); RepoHooks 15 (danger — unguarded agent); MacInspector 13/10 (warn); RepoView 11 (warn); RepoAgent 12 (warn).

**SwiftUI:** `HStack(spacing:2)` of 3 `RoundedRectangle(cornerRadius:2).frame(width:2.5,height:size)`; animate `.scaleY` per-bar with staggered durations/delays and `.repeatForever`. Reduce-motion → freeze at scaleY 0.4, opacity 0.4.

---

## 9. `SegMac` — macOS segmented control

**Purpose:** the primary top-nav segmented control (MacChrome toolbar) and in-view sub-nav / filter toggles (Findings severity filter, RepoView form/raw toggle).

**Prototype signature:** `SegMac({ value, onChange, options, size = 'md' })`.
`options` = `[{ value, label, icon?, count?, title? }]`.

**Container (outer track):** `HStack(spacing:2)`, `padding: 2pt` all around, background `--ink-1000` (#07090A, the void), **border `1px solid --border`** (#202A2E), `borderRadius --radius-sm` (4pt).

**Each segment button:** `HStack(spacing:6pt)`, centered.
- Padding: **`md` = 5px 13px**, **`sm` = 4px 9px**.
- Font: JetBrains Mono, size `md`=`--text-xs`(11) / `sm`=`--text-2xs`(10), `letterSpacing 0.01em`, `whiteSpace:nowrap`.
- `borderRadius --radius-xs` (2pt).
- **Selected (`on`) state:** border `1px solid --border-strong`(#2E393F); background `--surface-raised`(#1D2428); text `--text-primary`(#E5ECE8); font-weight **700**; boxShadow `--inset-top`.
- **Unselected:** border `1px solid transparent`; background transparent; text `--text-muted`(#6B7773); font-weight **500**; no shadow.
- **Leading icon** (if `o.icon`): size `md`=13 / `sm`=12; color selected `--accent`(#B4FF34) / unselected `--text-faint`(#4C5754).
- **Trailing count** (if `o.count != null`): `fontSize 0.85em`, weight 700; color selected `--text-faint` / unselected `--text-ghost`(#353E3B).
- Cursor pointer; `title` = `o.title || o.label` tooltip.

**Interaction:** click → `onChange(o.value)`. In MacChrome the value is `inRepo ? '' : view` (when inside a repo, nothing is selected) and `onChange = setView`. Selection is driven entirely by matching `o.value === value`.

**SwiftUI:** a custom `HStack` of buttons inside a padded, bordered container (do **not** use the stock `Picker(.segmented)` — the styling is bespoke: void track, raised selected chip with inset-top highlight, mono labels, tinted icons, ghost counts).

---

## 10. `Kbd` — keycap

**Purpose:** keyboard-shortcut hint chips (⌘K in the chrome search, `esc` in the command palette).

**Prototype:** inline `<span>`: JetBrains Mono, `--text-2xs`(10), color `--text-faint`(#4C5754), **border `1px solid --border-strong`**(#2E393F), `borderRadius --radius-xs`(2pt), **padding `1px 5px`**, `lineHeight 1.5`, background `--ink-1000`(#07090A).

**SwiftUI:** small mono `Text` with the above padding, `.background(void)`, `.overlay(RoundedRectangle(2).stroke(borderStrong))`.

---

## 11. `Disclosure` — disclosure triangle

**Purpose:** expand/collapse toggle for tree rows (MacSidebar workspace nodes with children).

**Prototype signature:** `Disclosure({ open, onClick })` — a button.
- Box: **14×14pt**, `padding 0`, no background, `flex:none`, centered.
- Contains `Icon name="chevron-right" size=12`, color `--text-muted`(#6B7773).
- **Rotation:** `transform: rotate(90deg)` when `open` else none, transition `transform --dur-fast(140ms) --ease-out`.

**Interaction (MacSidebar):** `onClick={(e)=>{ e.stopPropagation(); onToggle(node.id); }}` — stops row-selection bubbling; toggles the node's expanded state.

**SwiftUI:** `Button` with `Image(systemName:"chevron.right").font(.system(size:12))` `.rotationEffect(open ? .degrees(90) : .zero)` `.animation(.easeOut(duration:0.14), value: open)`. Consume the tap so it doesn't trigger the row.

---

## 12. `MetaRow` — label : value row

**Purpose:** key/value rows in inspector detail cards (RepoView agent/worktree/census meta, etc.).

**Prototype signature:** `MetaRow({ k, children, mono = true })`.
- `HStack`, `alignItems: baseline`, `justifyContent: space-between`, **gap 14pt**, **padding `7px 0`** (vertical only), `borderBottom 1px solid --border-subtle`(#161C1F).
- **Key (`k`):** JetBrains Mono, `--text-2xs`(10), `--tracking-label`(0.08em), **UPPERCASE**, color `--text-muted`, `whiteSpace:nowrap`.
- **Value (`children`):** family = mono ? `--font-mono` : `--font-sans`; `--text-sm`(12.5); color `--text-primary`; `textAlign:right`. (Callers frequently override the value color inline: warn/ok/danger.)

**Data examples:** `agentTool(a.tool).label`, `a.branch`, `a.elapsed · a.filesTouched files · +a.linesAdded/−a.linesRemoved`, `repo.checked`, `repo.census.scanned`, `repo.census.godFiles.length`, `repo.census.soft`, `repo.drift.behind`.

**SwiftUI:** `HStack(alignment:.firstTextBaseline)` with `Spacer()`, bottom `Divider`-like 1pt line in `border-subtle`.

---

## 13. `StatTile` — big metric tile

**Purpose:** the large KPI tiles in the fleet stat strip / workspace / skills overview. A row of these forms the dashboard headline metrics.

**Prototype signature:** `StatTile({ value, unit, label, tone = 'neutral', icon, onClick })`.
- **Layout:** `VStack(alignment:.leading, spacing: 8pt)` (`--mac-gap-sm` fallback 8), **padding `16px 18px`** (`--mac-tile-pad` fallback), `minWidth:0`. Background `--surface-1`(#12171A); on hover **and** clickable → `--surface-raised`(#1D2428); transition `background --dur-fast`. Cursor pointer only if `onClick`. (Tiles sit in a grid/row separated by hairlines from the parent container — the tile itself draws no border.)
- **Label (top):** `HStack(spacing:7pt)`, self-start, JetBrains Mono, `--text-2xs`(10), `--tracking-label`(0.08em), UPPERCASE, color `--text-muted`, `whiteSpace:nowrap`, `overflow:hidden`. Optional leading `Icon size=12`.
- **Value (below):** JetBrains Mono, **weight 800**, size `--mac-tile-num` fallback **38px**, `lineHeight 1`, `letterSpacing −0.03em`, `fontFeatureSettings 'tnum'` (tabular), `whiteSpace:nowrap`, color = tone color (below), text-shadow = ok→`--glow-text-ok` else none.
  - **Unit** (if given): appended `<span>` at `fontSize 0.5em`, weight 500, color `--text-muted` (e.g. the `%` in `91%`).
- **Tone → value color:** ok `--ok` / warn `--warn` / danger `--danger` / info `--info` / **neutral `--text-bright`** (#F1F6F3, the default). Only `ok` gets the green text glow.

**Data + tones (FleetView `fleet.totals`, `tone(c)= c>=95?ok:c>=80?warn:danger`):**
| value | unit | label | tone | icon | onClick |
|---|---|---|---|---|---|
| `t.repos` | — | `repos` | neutral | `folder-git-2` | — |
| `t.compliance` | `%` | `compliance` | `tone(t.compliance)` | `gauge` | — |
| `t.agentsActive` | — | `working` | `agentsActive?warn:ok` | `bot` | `setView('agents')` |
| `t.abandonedWorktrees` | — | `abandoned` | `?danger:ok` | `git-branch` | `setView('agents')` |
| `t.bloatedDocs` | — | `doc bloat` | `?danger:ok` | `file-warning` | `setView('agents')` |
| `t.surprises` | — | `surprises` | `?danger:ok` | `triangle-alert` | `setView('findings')` |

WorkspaceDetail uses `agg.repos/compliance/agents/abandoned/surprises` (labels: `child repos`, `avg compliance`, `working`, `abandoned trees`, `surprises`); SkillsView uses `t.skills` (`skills active`, icon `blocks`). `fleet.totals` is computed in `data.js`: `repos=leaves.length`, `compliance=Math.round(avg)`, `agentsActive=count(agent.active)`, `abandonedWorktrees=Σ worktrees.state=='abandoned'`, `bloatedDocs=count(docs.taskState.status=='danger' || docs.agentsMd.status=='danger')`, `surprises=Σ surprises.length`.

**Interaction:** hover raises background (only if clickable); click fires `onClick` (mostly `setView(...)` to drill into a view). **SwiftUI:** `Button`/tap-gesture wrapping a `VStack`; hover via `.onHover`.

---

## 14. `LimitBar` — line/limit meter (soft/hard thresholds)

**Purpose:** shows a measured value against soft/hard limits — TASK_STATE line count vs 400/800, code-file lines vs 250/400, doc lines. Used in AgentsView doc-bloat rows, RepoView file census, RepoAgent, MacInspector.

**Prototype signature:** `LimitBar({ value, soft, hard, unit = '', max })`.
- **Cap:** `cap = max || Math.max(hard*1.15, value*1.05)` (the track's 100%). **Fill %:** `min(100, value/cap*100)`.
- **Tone:** `value > hard → danger`; `value > soft → warn`; else `ok`.
- **Layout:** `HStack(spacing: 10pt)`, centered.
  - **Track:** `flex:1`, **height 6pt**, `borderRadius 999px`, background `--surface-active`(#232B30), `overflow:hidden`, `position:relative`.
    - **Threshold marks** (if soft/hard given): a `1pt`-wide vertical tick at `left = min(100, v/cap*100)%`, `top:-2 bottom:-2` (slightly taller than track), background `--text-faint`(#4C5754), `zIndex 2`, `title="soft {v}"` / `"hard {v}"`.
    - **Fill:** absolute left, full height, `width = pct%`, background `--{tone}`; boxShadow `--glow-ok-sm` when tone is ok (healthy fill glows), else none.
  - **Value label (trailing):** JetBrains Mono, `--text-xs`(11), weight 700, color `--{tone}`, **minWidth 46pt**, `textAlign:right`, tabular (`'tnum'`). Text = `value.toLocaleString() + unit`.

**Data / thresholds:**
- AgentsView: `value=r.docs.taskState.lines`, `soft=DOC_LIMITS.taskState.soft(400)`, `hard=.hard(800)`.
- RepoView census file: `value=f.lines`, `soft=250`, `hard=400`.
- RepoAgent: `value=doc.lines`, `soft=limits.soft`, `hard=limits.hard`.
- MacInspector: `value=ts.lines`, taskState soft 400 / hard 800.
- `DOC_LIMITS = { taskState:{soft:400,hard:800}, agentsMd:{soft:300,hard:500}, code:{soft:250,hard:400} }`.

**SwiftUI:** `HStack(spacing:10)` → `ZStack(alignment:.leading)` capsule track (6pt) with an inner capsule fill (tone color, ok gets lime glow) + two 1pt tick overlays positioned by fraction; trailing right-aligned mono label (min 46pt) in the tone color.

---

## 15. `Pill` — small status pill

**Purpose:** tiny inline status/label chip. Used across the kit: `armed`/`manual`, `destructive`, `N/M connected`, `no guardrail`, `schema valid`/`N invalid`, `N deltas`, `commits unsigned`, etc.

**Prototype signature:** `Pill({ children, tone = 'neutral', icon })`.
- `HStack(spacing:5pt)`, centered, JetBrains Mono, `--text-2xs`(10), `borderRadius --radius-xs`(2pt), **padding `2px 6px`**, `whiteSpace:nowrap`, `lineHeight 1.4`, `border 1px solid`.
- **Tone mapping:**
  - `neutral` (default): text `--text-secondary`(#97A39E), bg `--surface-2`(#171D20), border `--border`(#202A2E).
  - any other tone `t`: text `--{t}`, bg `--{t}-surface`, border `--{t}-line` — i.e. ok/warn/danger/info use their low-alpha fill + hairline (§0.1). **Note:** there is no `--policy-surface`/`--policy-line`; a "policy" pill is expressed as neutral tone with an inline violet-colored child (see RepoView `{deltas} deltas`).
- Optional leading `Icon size=11`.

**Tone-by-state examples:** `armed`→ok; `manual`→neutral; `destructive`→danger+`triangle-alert`; `{live}/{n} connected`→ ok if all live else warn +`radio`; `{n} of {m} armed`→ ok if any else neutral +`zap`; `no guardrail`→ danger if agent active else warn; `schema valid`→ok, `{invalid} invalid`→danger; `commits unsigned`→danger.

---

## 16. `Empty` — empty-state block

**Purpose:** the reassuring "nothing here / all clean" placeholder inside cards & sections. Used when a list is empty (no findings, no agents, no sprawl, current changelogs, no hooks, no MCP, no automation).

**Prototype signature:** `Empty({ icon = 'check', children, tone = 'ok' })`.
- `VStack`, centered (both axes), **spacing 10pt**, **padding `44px 20px`**, JetBrains Mono, `--text-sm`(12.5), color `--text-muted`(#6B7773), `textAlign:center`.
- **Icon on top:** `size 22`, color `--{tone}` (default ok lime). Then the message `<span>`.

**Tone/icon by call-site:** `check`/ok "No findings."; `moon`/ok "no agents working. the fleet is quiet."; `git-branch`/ok "no extra worktrees…"; `history`/ok "every CHANGELOG is current."; `webhook`/**danger** "no hooks configured. the agent runs unguarded."; `plug-zap`/ok "no MCP servers…"; `gauge-circle`/ok "nothing automated yet."

**SwiftUI:** centered `VStack(spacing:10)` with SF Symbol (22pt, tone-colored) + mono muted caption, generous vertical padding (44pt).

---

## 17. Component index / window globals

`mac-parts.js` exports (via `Object.assign(window, …)`): `Icon, useLucide, formatBytes, HEALTH_COLOR, STATUS_COLOR, AGENT_TOOLS, agentTool, Wordmark, TrafficLights, HealthDot, AgentPulse, SegMac, Kbd, Disclosure, MetaRow, StatTile, LimitBar, Pill, Empty` — all available as global helpers to every macOS view module (`MacChrome`, `MacSidebar`, `MacInspector`, `MacConsole`, `FleetView`, `AgentsView`, `WorkspaceDetail`, `RepoView`, `RepoAgent`, `RepoHooks`, `FindingsView`, `SkillsView`, `AutopilotView`, `Overlays`, `Tweaks`).

### Native build checklist
1. Define a token layer (Color/Font/Metric constants) from §0 — this is the substrate for every primitive.
2. Build a Lucide→SF Symbol map (§1) as the single `Icon` entry point.
3. Reproduce the two liveness animations exactly: **HealthDot** danger-pulse (`vibe-pulse`, 1.5s) and **AgentPulse** staggered equalizer (`mac-eq`, per-bar 0.70/0.88/1.06s @ 0/0.12/0.24s delay). Gate both on reduce-motion.
4. Match tabular numerals + JetBrains Mono weight 800 for all big numerals (StatTile) and the tone→color + ok-only glow rules.
5. Preserve exact paddings/sizes: SegMac 5×13 / 4×9; StatTile 16×18 pad + 38pt numerals; LimitBar 6pt track + 46pt label; Pill 2×6; MetaRow 7px vertical + 14pt gap; Empty 44×20; traffic dots 12pt; keycap 1×5.
6. Consume the documented data paths verbatim: `repo.health`, `repo.agent.{active,tool,branch,elapsed,filesTouched,linesAdded,linesRemoved,note,lastActivity}`, `repo.docs.taskState.{lines,bytes,status}` (+`agentsMd/claudeMd/changelog`), `repo.census.{scanned,soft,godFiles,largest}`, `repo.drift.{behind,files}`, `repo.worktree.{clean,unstaged,unpushed,signed}`, `fleet.totals.{repos,compliance,agentsActive,abandonedWorktrees,bloatedDocs,surprises,...}`, `DOC_LIMITS`.
