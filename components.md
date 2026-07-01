# Vibe Dashboard — Design-System Primitives Spec (SwiftUI reimplementation contract)

> Source of truth: the React/Babel prototype "Vibe Dashboard Design System" (`components/**/*.jsx` + `components/components.css` + `tokens/*.css`).
> This document is exhaustive and self-contained. A SwiftUI engineer builds these 1:1 from this file **without reading the JS**.
> Platform: macOS, **dark mode ONLY** (no light theme). No glassmorphism, no backdrop blur. Depth = solid ink surfaces + hairline borders. Saturated hue appears ONLY to signal state.

---

## 0. Global foundations (tokens → SwiftUI constants)

### 0.1 Fonts
Two families carry the entire system. Bundle the weights below (Google Fonts: JetBrains Mono, Space Grotesk).

| Role | CSS var | Family | SwiftUI mapping |
|---|---|---|---|
| Mono (DEFAULT voice: labels, data, paths, codes, metrics, make-targets, code) | `--font-mono` | **JetBrains Mono** (fallback ui-monospace / SF Mono / Menlo) | Custom font "JetBrainsMono-*" |
| Sans / display (headings, hero numerals, buttons, prose) | `--font-sans` / `--font-display` / `--font-ui` / `--font-prose` | **Space Grotesk** (fallback system-ui) | Custom font "SpaceGrotesk-*" |

**Mono is the default** for nearly every primitive here (buttons, tags, badges, gate rows, inputs, tabs, meters, toasts). Space Grotesk appears only where explicitly stated (Card body prose, big display numerals — not covered by these primitives).

Weights available: JetBrains Mono `400 / 500 / 700 / 800` (+ italic 400/500); Space Grotesk `400 / 500 / 600 / 700`.
Named weights: regular 400, medium 500, semibold 600 (Space Grotesk only), bold 700, black 800 (JetBrains Mono ExtraBold — big numerals only).

**Numeral rendering:** everywhere mono shows data, enable tabular figures. CSS uses `font-feature-settings: 'tnum','zero'` (slashed zero). SwiftUI: apply `.monospacedDigit()` and, where the custom font supports it, the `tnum`/`zero` OpenType features via `Font`'s feature settings. Body default also sets `'ss01','cv01','tnum'`.

### 0.2 Type scale (px — use directly as SwiftUI point sizes)
| Token | px | Use |
|---|---|---|
| `--text-2xs` | **10** | legend ticks, dense micro-meta, sev tags, field labels, meter labels, gate cmd/detail, tag-uppercase |
| `--text-xs` | **11** | uppercase labels, badges (StatusBadge), Tag, panel title, toast msg |
| `--text-sm` | **12.5** | secondary UI, table cells, buttons(md), inputs, tabs, gate name, meter value, toast title |
| `--text-base` | **14** | default body / UI text, button(lg) |
| `--text-md` | 16 | emphasized body, card titles (not used by these primitives directly) |
| `--text-lg` | 20 | sub-headings |
| `--text-xl` | 26 | section headings |
| `--text-2xl` | 34 | page titles |
| `--text-3xl` | 46 | display |
| `--text-4xl` | 62 | hero numerals |
| `--text-5xl` | 84 | oversized metric |

Rule: never set mono below 11px or display below 13px (except intentional 9px/10px micro-ticks like the meter threshold caption at literal `9px`).

### 0.3 Letter spacing (tracking) — CSS `em`, convert to points at render size
| Token | em | Applied to |
|---|---|---|
| `--tracking-tight` | −0.02 | big display |
| `--tracking-snug` | −0.01 | headings |
| `--tracking-normal` | 0 | — |
| `--tracking-label` | **0.08** | UPPERCASE mono micro-labels (panel title, field label, meter label, tag-uppercase, sev tag) |
| `--tracking-wide` | 0.14 | eyebrows |
| button label | **0.01** | `.vibe-btn` letter-spacing |
| status label | **0.02** | `.vibe-status__label` |

SwiftUI: `.tracking(size_px * em)` in points (e.g. 10px label at 0.08em → `.tracking(0.8)`; 12.5px button at 0.01em → `.tracking(0.125)`).

### 0.4 Line heights
`--leading-none:1`, `--leading-tight:1.08`, `--leading-snug:1.28`, `--leading-normal:1.5`, `--leading-relaxed:1.65`. Primitives that set `line-height:1` want tight single-line layout (badges, tags, buttons, gates). Toast message uses `1.5`.

### 0.5 Spacing (4px grid) — CSS var → px → points
`--space-0:0`, `--space-px:1`, `--space-0_5:2`, `--space-1:4`, `--space-1_5:6`, `--space-2:8`, `--space-2_5:10`, `--space-3:12`, `--space-4:16`, `--space-5:20`, `--space-6:24`, `--space-7:28`, `--space-8:32`, `--space-10:40`, `--space-12:48`, `--space-16:64`, `--space-20:80`, `--space-24:96`.
Map px 1:1 to SwiftUI points.

### 0.6 Radii
`--radius-none:0`, `--radius-xs:2` (chips, sev tags, inline code, ticks), `--radius-sm:4` (buttons, inputs, badges, tags, gate rows), `--radius-md:6` (cards/panels, toast), `--radius-lg:10` (large containers/modals), `--radius-xl:14` (hero panels), `--radius-full:999` (dots, pill tags, switch, meter track).
SwiftUI: `RoundedRectangle(cornerRadius:)`; use `Capsule()` for `--radius-full`.

### 0.7 Border widths
`--border-w: 1px` (default hairline — 1:1 point, keep crisp), `--border-w-thick: 2px`.

### 0.8 Layout rails (context; not primitives)
`--rail-sidebar:248`, `--rail-inspector:340`, `--topbar-h:52`, `--row-h:44`, `--row-h-lg:56`, `--content-max:1440`.

### 0.9 Color tokens (resolve every semantic alias to a concrete hex/rgba)

**Ink surfaces (near-black, faintly cool):**
`--ink-1000 #07090A`, `--ink-900 #0A0D0E`, `--ink-850 #0E1213`, `--ink-800 #12171A`, `--ink-750 #171D20`, `--ink-700 #1D2428`, `--ink-650 #232B30`, `--ink-600 #2C353A`.

**Hairlines:** `--line-soft #161C1F`, `--line #202A2E`, `--line-loud #2E393F`.

**Foreground (green-tinted neutrals):**
`--fg-50 #F1F6F3`, `--fg-100 #E5ECE8`, `--fg-200 #C5CFCB`, `--fg-300 #97A39E`, `--fg-400 #6B7773`, `--fg-500 #4C5754`, `--fg-600 #353E3B`.

**Lime (brand accent = "healthy/live/in-policy"):**
`--lime-200 #E4FFB0`, `--lime-300 #CDFF74`, `--lime-400 #B4FF34` (PRIMARY ACCENT), `--lime-500 #9BEC1B`, `--lime-600 #7BC60E`, `--lime-700 #5A9209`, `--lime-ink #0B1400` (text/icon on a lime fill).

**Amber (warn/drift):** `--amber-300 #FFD479`, `--amber-400 #F7B23C`, `--amber-500 #E2982A`, `--amber-700 #8A5A12`, `--amber-ink #1A1000`.

**Red (fail/danger):** `--red-300 #FF8E87`, `--red-400 #FF5B52`, `--red-500 #E63E36`, `--red-700 #8A201B`, `--red-ink #1C0301`.

**Blue (info/links):** `--blue-300 #9CD2F2`, `--blue-400 #6FB7E0`, `--blue-500 #4E98C6`, `--blue-700 #275A78`, `--blue-ink #03131C`.

**Violet (policy/config, sparse):** `--violet-300 #C4B6FF`, `--violet-400 #A593F5`, `--violet-500 #8772E0`.

**Low-alpha state fills (chips, row tints, glows) — use exact rgba:**
- ok: `--ok-bg rgba(180,255,52,0.10)`, `--ok-bg-soft rgba(180,255,52,0.055)`, `--ok-border rgba(180,255,52,0.30)`
- warn: `--warn-bg rgba(247,178,60,0.12)`, `--warn-bg-soft rgba(247,178,60,0.06)`, `--warn-border rgba(247,178,60,0.32)`
- danger: `--danger-bg rgba(255,91,82,0.12)`, `--danger-bg-soft rgba(255,91,82,0.06)`, `--danger-border rgba(255,91,82,0.34)`
- info: `--info-bg rgba(111,183,224,0.12)`, `--info-bg-soft rgba(111,183,224,0.06)`, `--info-border rgba(111,183,224,0.30)`
- violet: `--violet-bg rgba(165,147,245,0.12)`, `--violet-border rgba(165,147,245,0.30)`

**Semantic aliases (author against these):**
- Surfaces: `--bg-app = ink-900`, `--bg-void = ink-1000`, `--surface-1 = ink-800` (default card), `--surface-2 = ink-750` (nested/table header), `--surface-sunken = ink-850` (inputs/wells/code), `--surface-raised = ink-700` (hover/popover/toast), `--surface-active = ink-650` (pressed/selected/switch off track/meter track).
- Borders: `--border-subtle = line-soft`, `--border = line`, `--border-strong = line-loud`, `--border-divider = ink-600`.
- Text: `--text-primary = fg-100`, `--text-bright = fg-50`, `--text-secondary = fg-300`, `--text-muted = fg-400`, `--text-faint = fg-500`, `--text-ghost = fg-600`, `--text-on-accent = lime-ink`.
- Accent: `--accent = lime-400`, `--accent-hover = lime-300`, `--accent-press = lime-500`, `--accent-dim = lime-600`.
- Status FG hue: `--ok = lime-400`, `--warn = amber-400`, `--danger = red-400`, `--info = blue-400`, `--policy = violet-400`.
- Status surface/line: `--ok-surface = ok-bg`, `--ok-line = ok-border`, `--warn-surface = warn-bg`, `--warn-line = warn-border`, `--danger-surface = danger-bg`, `--danger-line = danger-border`, `--info-surface = info-bg`, `--info-line = info-border`.
- Focus: `--focus-ring = lime-400`.

### 0.10 Effects
- Shadows (overlays only): `--shadow-sm 0 1px 2px rgba(0,0,0,.45)`, `--shadow-md 0 4px 14px rgba(0,0,0,.45)`, `--shadow-lg 0 16px 40px rgba(0,0,0,.55)`, `--shadow-pop 0 10px 30px rgba(0,0,0,.6) + a 1px ring of --line-loud`.
- Insets: `--inset-top inset 0 1px 0 rgba(255,255,255,0.03)` (etched top-light on cards — a 1px highlight line along the top edge), `--inset-hair inset 0 0 0 1px --line`.
- **Phosphor glows (the ONE special effect — "the board glows green when healthy"):**
  - `--glow-ok = 0 0 0 1px --ok-border, 0 0 16px rgba(180,255,52,0.22)` (1px ring + 16px green bloom)
  - `--glow-ok-sm = 0 0 10px rgba(180,255,52,0.30)`
  - `--glow-warn = 0 0 0 1px --warn-border, 0 0 16px rgba(247,178,60,0.20)`
  - `--glow-danger = 0 0 0 1px --danger-border, 0 0 16px rgba(255,91,82,0.22)`
  - `--glow-text-ok = 0 0 12px rgba(180,255,52,0.45)` (text glow)
  - SwiftUI: `.shadow(color:radius:x:y:)` layered; the "0 0 0 1px" ring = a `.overlay(RoundedRectangle.stroke(color, lineWidth:1))`; the bloom = a colored `.shadow(radius: 16*0.5≈8, ...)` (halve px blur for SwiftUI's radius convention, tune visually).
- Focus ring: `--ring = 0 0 0 2px --bg-app, 0 0 0 4px --focus-ring` (a 2px app-color gap then a 2px lime ring → a detached 2px lime outline offset 2px from the control). `--ring-inset = inset 0 0 0 1px --focus-ring`.
- **Motion (quick, mechanical, no bounce):** `--ease-out cubic-bezier(0.2,0.6,0.2,1)`, `--ease-in-out cubic-bezier(0.4,0,0.2,1)`. Durations: `--dur-instant 80ms`, `--dur-fast 140ms`, `--dur-base 200ms`, `--dur-slow 320ms`. SwiftUI: `.animation(.timingCurve(0.2,0.6,0.2,1, duration: 0.14), value:)` for the common `--dur-fast` transitions.
- Reduced motion: when Reduce Motion is on, treat all durations as 0 and disable pulse/blink (use static ~0.9 opacity for cursor).

### 0.11 Keyframes (liveness)
- `vibe-pulse` (used by StatusBadge live dot): `0%,100% → opacity 1, scale 1`; `50% → opacity 0.45, scale 0.82`. Duration 1.6s, ease-in-out, infinite.
- `vibe-cursor-blink` (brand caret, not a primitive here): 1.1s step blink.

---

## 1. Button — `Button` (`core/Button.jsx`, class `.vibe-btn`)

**Purpose.** The primary action primitive. Mono-set, tight radius. Exactly one `primary` (lime CTA) per view; `danger` for destructive/refusal actions; `ghost` for toolbar/inline. Appears everywhere an action is triggered (Re-check now, View policy, Dismiss, Pause monitoring, run make-targets in overlays).

**DOM / structure.**
`<button class="vibe-btn vibe-btn--{variant} [vibe-btn--{size}] [vibe-btn--block]">` → optional `<span class="vibe-btn__icon">{leadingIcon}</span>` → optional `<span class="vibe-btn__text">{children}</span>` → optional `<span class="vibe-btn__icon">{trailingIcon}</span>`.

**SwiftUI layout.** `Button { action }` with `HStack(spacing: 8) { leadingIcon; Text(label); trailingIcon }`. Fixed content spacing (`gap: 8px`). `whiteSpace: nowrap` → `.lineLimit(1).fixedSize(horizontal:true, vertical:false)`. `block` → `.frame(maxWidth: .infinity)` and the HStack centers.

**Base box (`.vibe-btn`):**
- Layout: inline-flex, center/center, **gap 8px**.
- Typography: `--font-mono`, weight **500**, size `--text-sm` **12.5px**, letter-spacing **0.01em** (→ `.tracking(0.125)`), line-height 1.
- Padding: **8px vertical / 14px horizontal** (md default).
- Border: **1px solid transparent** (variant sets color). Radius `--radius-sm` **4px**.
- Background transparent; color `--text-primary #E5ECE8` (variant overrides).
- Cursor pointer; user-select none.

**Sizes.**
- `sm`: padding **5px / 10px**, font `--text-xs` **11px**.
- `md` (default): padding 8/14, 12.5px.
- `lg`: padding **11px / 20px**, font `--text-base` **14px**.
- `block`: `display:flex; width:100%` (full-width).

**Icon slot (`.vibe-btn__icon`).** 15×15px box, `flex:none`; inner svg 100% with **stroke-width 2**. Lucide icons passed as nodes. SwiftUI: SF Symbol at 15pt, `.symbolRenderingMode(.monochrome)`, color = current label color.

**Variants (color-by-state):**
| Variant | bg | text | border | weight |
|---|---|---|---|---|
| `primary` | `--accent` lime-400 | `--text-on-accent` lime-ink #0B1400 | `--accent` | **700** |
| `secondary` (default) | `--surface-raised` ink-700 | `--text-primary` fg-100 | `--border-strong` line-loud #2E393F | 500 |
| `ghost` | transparent | `--text-secondary` fg-300 | transparent | 500 |
| `danger` | transparent | `--danger` red-400 | `--danger-line` rgba(255,91,82,.34) | 500 |
| `accent-ghost` | transparent | `--accent` lime-400 | `--ok-line` rgba(180,255,52,.30) | 500 |

**Interaction states.**
- Hover:
  - primary → bg `--accent-hover` lime-300, border lime-300, **box-shadow `--glow-ok-sm`** (green bloom).
  - secondary → bg `--surface-active` ink-650, border `--border-divider` ink-600.
  - ghost → bg `--surface-raised` ink-700, text `--text-primary`.
  - danger → bg `--danger-surface` danger-bg, border `--danger` red-400.
  - accent-ghost → bg `--ok-surface` ok-bg.
- Active/press: **`transform: translateY(0.5px)`** (whole button; SwiftUI: `.offset(y:0.5)` while pressed). primary additionally → bg `--accent-press` lime-500.
- Focus-visible: `--ring` (2px lime ring offset 2px). No default outline.
- Disabled (`disabled` / `aria-disabled`): **opacity 0.42**, cursor not-allowed, no transform, no shadow. SwiftUI: `.disabled(true).opacity(0.42)`.
- Transitions: bg/border/color/box-shadow at `--dur-fast` (140ms) ease-out; transform at `--dur-instant` (80ms).

**Props (contract):** `variant: primary|secondary|ghost|danger|accent-ghost` (default secondary); `size: sm|md|lg` (default md); `block: Bool` (default false); `leadingIcon/trailingIcon: node`; `disabled: Bool`; passes native button attrs (`onClick`, `type`).

---

## 2. Card / Panel — `Card` (`core/Card.jsx`, class `.vibe-panel`)

**Purpose.** The panel surface that holds every cluster of the console (a gate list, a metric block, a policy section). Flat, hairline border, faint inset top-light. Appears as the container for nearly every dashboard section. `variant="glow"` reserved for the all-healthy hero panel (loud on purpose).

**DOM / structure.**
`<section class="vibe-panel [vibe-panel--{variant}]">`
  → (if title or headerRight) `<header class="vibe-panel__header">` `<span class="vibe-panel__title">{title}</span>` (or empty `<span/>`) + (if headerRight) `<span class="vibe-panel__actions">{headerRight}</span>`
  → `<div class="vibe-panel__body [vibe-panel__body--flush]">{children}</div>`.

**SwiftUI layout.** `VStack(alignment:.leading, spacing:0)`. Optional header row = `HStack { title; Spacer(); headerRight }`. Body = content container. Card itself is a `VStack` with min-width 0 (`.frame(minWidth:0)`), `flex-direction: column`.

**Base (`.vibe-panel`):**
- Background `--surface-1` ink-800 #12171A. Border **1px solid `--border`** line #202A2E. Radius `--radius-md` **6px**.
- Box-shadow `--inset-top` (1px top highlight rgba(255,255,255,0.03)) → SwiftUI: overlay a 1px-tall white 3%-opacity line along the top inner edge (or `.overlay(alignment:.top){ Rectangle().fill(.white.opacity(0.03)).frame(height:1) }` inset by the corner radius).
- Layout: `display:flex; flex-direction:column; min-width:0`.

**Variants (surface treatment):**
- `default` → `--surface-1` ink-800.
- `raised` → `--surface-raised` ink-700.
- `sunken` → `--surface-sunken` ink-850.
- `glow` → **box-shadow `--glow-ok`** (1px ok-border ring + 16px green bloom), **border-color transparent** (the glow ring replaces the border). This is the phosphor "healthy hero" treatment.

**Header (`.vibe-panel__header`):**
- Layout: flex, align center, `justify-content: space-between`, **gap 12px**.
- Padding **12px vertical / 16px horizontal**. Border-bottom **1px solid `--border`**. **min-height 44px**.

**Title (`.vibe-panel__title`):**
- `--font-mono`, size `--text-xs` **11px**, weight 500, letter-spacing `--tracking-label` **0.08em**, **UPPERCASE** (`text-transform: uppercase`), color `--text-secondary` fg-300.
- Layout: inline-flex, align center, gap 8px (allows a leading icon).

**Body (`.vibe-panel__body`):** padding **16px** all sides, `min-width:0`. `flush` → padding **0** (for edge-to-edge tables/lists such as stacked GateRows).

**Props:** `title: node?`; `headerRight: node?`; `variant: default|raised|sunken|glow`; `flush: Bool`; `bodyClassName`. Header renders only if `title` or `headerRight` present. No hover/press states (static container).

---

## 3. Tag — `Tag` (`core/Tag.jsx`, class `.vibe-tag`)

**Purpose.** Neutral metadata pill for repo facts: stack, lifecycle, package manager, framework. `tagKey` renders a dimmed `key:` prefix so config values read like `stack: python`. Appears in repo headers / fact rows.

**DOM / structure.**
`<span class="vibe-tag [vibe-tag--{variant}] [vibe-tag--uppercase]">`
  → (if dot) `<span class="vibe-tag__dot"/>`
  → (if tagKey) `<span class="vibe-tag__key">{tagKey}</span><span class="vibe-tag__sep">:</span>`
  → `<span class="vibe-tag__val">{children}</span>`.

**SwiftUI layout.** `HStack(spacing: 6) { dot?; key?; sep?; value }` inside a rounded rect. `whiteSpace: nowrap`.

**Base (`.vibe-tag`):**
- Layout: inline-flex, align center, **gap 6px**.
- `--font-mono`, size `--text-xs` **11px**, weight 500, line-height 1.
- Padding **4px / 8px**. Radius `--radius-sm` **4px**.
- Background `--surface-2` ink-750. Color `--text-secondary` fg-300. Border **1px solid `--border`** line.

**Modifiers.**
- `uppercase` → `text-transform: uppercase`, letter-spacing `--tracking-label` **0.08em**, font shrinks to `--text-2xs` **10px**.
- `dot` → leading `.vibe-tag__dot` **6×6px** circle (`--radius-full`), `background: currentColor` (inherits the tag's text color).
- `tagKey` → `.vibe-tag__key` color `--text-muted` fg-400; `.vibe-tag__sep` (the literal `:`) color `--text-ghost` fg-600.

**Color variants:**
| Variant | text | border | bg |
|---|---|---|---|
| `neutral` (default) | `--text-secondary` fg-300 | `--border` line | `--surface-2` ink-750 |
| `accent` | `--accent` lime-400 | `--ok-line` rgba(180,255,52,.30) | `--ok-bg-soft` rgba(180,255,52,.055) |
| `info` | `--info` blue-400 | `--info-line` rgba(111,183,224,.30) | `--info-bg-soft` rgba(111,183,224,.06) |
| `policy` | `--policy` violet-400 | `--violet-border` rgba(165,147,245,.30) | `--violet-bg` rgba(165,147,245,.12) |

**Interaction:** none (static, non-interactive label).

**Props:** `variant: neutral|accent|info|policy`; `uppercase: Bool`; `dot: Bool`; `tagKey: node?`; `children` = value.

**Data usage examples:** `Tag(tagKey:"stack") { repo.stack }`, `Tag(tagKey:"lifecycle"){ repo.lifecycle }`, `Tag(tagKey:"pm"){ repo.pm }`, `Tag(tagKey:"framework"){ repo.framework }` — property paths `repo.stack` (e.g. "python-fastapi"), `repo.lifecycle` ("greenfield"/"brownfield"), `repo.pm` ("uv"), `repo.framework`.

---

## 4. StatusBadge — `StatusBadge` (`feedback/StatusBadge.jsx`, class `.vibe-status`)

**Purpose.** THE core signal element. Maps a repo/gate state to a tinted, dotted pill. Used everywhere a status shows: fleet rows, gate results, panel headers, KPIs. `live` = phosphor pulse for an actively-checking repo; `solid` = loud filled treatment for headline KPIs.

**DOM / structure.**
`<span class="vibe-status vibe-status--{status} [vibe-status--sm] [vibe-status--live] [vibe-status--solid]">`
  → (if dot, default true) `<span class="vibe-status__dot"/>`
  → `<span class="vibe-status__label">{children}</span>`.

**SwiftUI layout.** `HStack(spacing: 7) { dot?; Text(label) }` inside a rounded rect; `nowrap`.

**Base (`.vibe-status`):**
- Layout: inline-flex, align center, **gap 7px**.
- `--font-mono`, size `--text-xs` **11px**, weight 500, line-height 1.
- Padding **5px top/bottom, 10px right, 9px left** (`5px 10px 5px 9px` — slightly tighter on the dot side). Radius `--radius-sm` **4px**. Border 1px solid transparent (variant sets).
- `.vibe-status__label` letter-spacing **0.02em**.

**Dot (`.vibe-status__dot`).** **7×7px** circle (`--radius-full`), `background: currentColor`, `flex:none`.

**Size `sm`.** font `--text-2xs` **10px**; padding `3px 7px 3px 6px`; gap **5px**; dot **6×6px**.

**Status color variants:**
| status | text | bg | border |
|---|---|---|---|
| `ok` | `--ok` lime-400 | `--ok-surface` ok-bg (.10) | `--ok-line` (.30) |
| `warn` | `--warn` amber-400 | `--warn-surface` warn-bg (.12) | `--warn-line` (.32) |
| `danger` | `--danger` red-400 | `--danger-surface` danger-bg (.12) | `--danger-line` (.34) |
| `info` | `--info` blue-400 | `--info-surface` info-bg (.12) | `--info-line` (.30) |
| `neutral` (default) | `--text-secondary` fg-300 | `--surface-2` ink-750 | `--border` line |

**Modifiers.**
- `live` → the dot gets **box-shadow `--glow-ok-sm`** (green bloom) AND **animation `vibe-pulse` 1.6s ease-in-out infinite** (opacity 1→0.45, scale 1→0.82 at 50%). SwiftUI: a repeating `.easeInOut(duration:0.8).repeatForever(autoreverses:true)` scaling/opacity on the dot; disable under Reduce Motion.
- `solid` (loud KPI fill) — only ok and danger are defined:
  - `solid.ok` → bg `--ok` lime-400, text `--lime-ink` #0B1400, border `--ok`, weight **700**.
  - `solid.danger` → bg `--danger` red-400, text `--red-ink` #1C0301, border `--danger`, weight **700**.
  - solid dot `background: currentColor` (so on solid-ok the dot is lime-ink on lime).
- `dot=false` hides the dot.

**Interaction:** none (informational). Transitions n/a.

**Props:** `status: ok|warn|danger|info|neutral` (default neutral); `size: sm|md`; `live: Bool`; `solid: Bool`; `dot: Bool` (default true); `children` = label text.

**Data/label usage:** labels are free text derived from data — e.g. `"in policy"`, `"checking…"` (with `live`), `"{n} deltas"`, `"{n} surprises"` (danger), `"{compliance}% compliant"` (solid). `status` derives from `repo.health` (`ok`/`warn`/`danger`) or a gate result; `live` from `repo.live`/agent-active state.

---

## 5. SeverityTag — `SeverityTag` (`feedback/SeverityTag.jsx`, class `.vibe-sev`)

**Purpose.** Finding severity, mirroring the agentic-checkup scale. **HIGH** = a gate enforcing nothing / hard failure; **MED** = drift / soft-limit; **LOW** = informational. Appears on findings (Toasts, Findings feed rows, surprise lists).

**DOM / structure.** `<span class="vibe-sev vibe-sev--{level}">{label}</span>`. Label defaults to `level.toUpperCase()` (e.g. "HIGH") unless children override.

**SwiftUI layout.** A single `Text(label.uppercased())` in a tight rounded rect. No icon, no dot.

**Base (`.vibe-sev`):**
- Layout: inline-flex align center.
- `--font-mono`, weight **700**, size `--text-2xs` **10px**, letter-spacing **0.08em**, **UPPERCASE**, line-height 1.
- Padding **3px / 6px**. Radius `--radius-xs` **2px** (tighter than the sm-radius chips). Border 1px solid transparent.

**Level variants:**
| level | text | bg | border |
|---|---|---|---|
| `high` | `--danger` red-400 | `--danger-surface` (.12) | `--danger-line` (.34) |
| `med` | `--warn` amber-400 | `--warn-surface` (.12) | `--warn-line` (.32) |
| `low` (default) | `--text-muted` fg-400 | `--surface-2` ink-750 | `--border` line |

**Interaction:** none.

**Props:** `level: high|med|low` (default low); `children` overrides label.

**Data usage:** driven by `finding.severity` / `surprise.severity` (values `'high'|'med'|'low'`). Findings are sorted by severity rank `{high:0, med:1, low:2}`.

---

## 6. Meter — `Meter` (`feedback/Meter.jsx`, class `.vibe-meter`)

**Purpose.** A threshold bar for coverage / compliance percentages, with an optional policy-floor marker drawn on the track. If `status` is omitted it is derived from `threshold`: value ≥ floor → `ok`, below → `danger`. Appears in coverage/compliance panels.

**DOM / structure.**
`<div class="vibe-meter">`
  → (if label or showValue) `<div class="vibe-meter__top">` `<span class="vibe-meter__label">{label}</span>` (or empty span) + (if showValue) `<span class="vibe-meter__value">{value}{valueSuffix}</span>`
  → `<div class="vibe-meter__track">`
        (if threshold) `<span class="vibe-meter__thresh" style="left:{threshPct}%" data-label="{thresholdLabel || 'floor '+threshold}"/>`
        `<span class="vibe-meter__fill vibe-meter__fill--{resolved}" style="width:{pct}%"/>`.

**SwiftUI layout.** `VStack(alignment:.leading, spacing: 6)`:
1. top row: `HStack { Text(label); Spacer(); Text("\(value)\(suffix)") }` with `alignment: .firstTextBaseline` (CSS `align-items: baseline`).
2. track: `ZStack(alignment:.leading)` → GeometryReader-based fixed-height bar (`Capsule` track, `Capsule` fill anchored left, width = `pct% * trackWidth`), plus a 2px vertical marker positioned at `threshPct% * trackWidth`.

**Math (exact).**
- `pct = clamp(0..100, value/max*100)`.
- `resolved = status ?? (threshold == nil ? "info" : (value >= threshold ? "ok" : "danger"))`.
- `threshPct = threshold == nil ? nil : clamp(0..100, threshold/max*100)`.

**Top row.**
- `.vibe-meter__label`: `--font-mono`, `--text-2xs` **10px**, letter-spacing `--tracking-label` **0.08em**, **UPPERCASE**, color `--text-muted` fg-400.
- `.vibe-meter__value`: `--font-mono`, `--text-sm` **12.5px**, weight **700**, color `--text-primary` fg-100, **tabular numerals** (`font-feature-settings:'tnum'`).

**Track (`.vibe-meter__track`).** height **8px**, radius `--radius-full` (Capsule), background `--surface-active` ink-650, `overflow:hidden`.

**Fill (`.vibe-meter__fill`).** absolutely positioned left/top/bottom 0, radius full, `width` set inline (% ). Transition `width` at `--dur-slow` **320ms** ease-out (animate width changes). Color by resolved status:
- `ok` → `--ok` lime-400, **box-shadow `--glow-ok-sm`** (the fill glows green).
- `warn` → `--warn` amber-400.
- `danger` → `--danger` red-400.
- `info` → `--info` blue-400.

**Threshold marker (`.vibe-meter__thresh`).** 2px-wide vertical line, `top:-2px; bottom:-2px` (overshoots the track by 2px each end), background `--text-secondary` fg-300, z above fill. Its `::after` caption sits 14px above, centered, `--font-mono` **9px**, color `--text-muted`, nowrap; text = `data-label` = `thresholdLabel` or fallback `"floor {threshold}"`.

**Props:** `value` (num), `max` (default 100), `threshold: num?` (draws marker + auto-status), `thresholdLabel: node?` (default `floor <threshold>`), `status: ok|warn|danger|info|null` (force color), `label: node?`, `showValue: Bool` (default true), `valueSuffix: String` (default `"%"`).

**Data usage:** `Meter(value: repo.coverage, threshold: repo.coverageFloor, label:"COVERAGE")` — paths `repo.coverage` (e.g. 94), `repo.coverageFloor` (e.g. 90). Also compliance: `Meter(value: repo.compliance, valueSuffix:"%")` from `repo.compliance`; fleet-level `fleet.totals.compliance`. `null` coverage → render nothing / skip the meter.

---

## 7. Toast / Alert — `Toast` (`feedback/Toast.jsx`, class `.vibe-toast`)

**Purpose.** A surfaced finding from the worker stream. Left-border keyed to severity. Pairs realtime events with a headline + message ("god-file appeared", "worktree went dirty", "coverage dropped below floor"). Appears in the toast stack (z-index `--z-toast` 1200) and findings surfaces.

**DOM / structure.**
`<div class="vibe-toast vibe-toast--{status}" role="status">`
  → (if icon) `<span class="vibe-toast__icon">{icon}</span>`
  → `<div class="vibe-toast__body">` (if title) `<span class="vibe-toast__title">{title}</span>` + (if children) `<span class="vibe-toast__msg">{children}</span>` `</div>`
  → (if onClose) `<button class="vibe-toast__close" aria-label="Dismiss">` [inline X svg] `</button>`.

**SwiftUI layout.** `HStack(alignment:.top, spacing: 12) { icon?; VStack(alignment:.leading, spacing:3){ title?; msg? }.frame(maxWidth:.infinity, alignment:.leading); closeButton? }`. **Fixed width 360px** (`max-width:100%`). Card floats above plane.

**Base (`.vibe-toast`):**
- Layout: flex, `align-items: flex-start` (top), **gap 12px**, **width 360px**, max-width 100%.
- Background `--surface-raised` ink-700. Border **1px solid `--border-strong`** line-loud. **Left border widened to 3px** (`border-left-width: 3px`, color = status). Radius `--radius-md` **6px**.
- Padding **13px vertical / 14px horizontal**. Box-shadow `--shadow-pop` (0 10px 30px rgba(0,0,0,.6) + 1px line-loud ring).

**Left-border + icon color by status:**
| status | left border | icon color |
|---|---|---|
| `ok` | `--ok` lime-400 | `--ok` |
| `warn` | `--warn` amber-400 | `--warn` |
| `danger` | `--danger` red-400 | `--danger` |
| `info` (default) | `--info` blue-400 | `--info` |

SwiftUI: draw the 3px accent bar as a leading `Rectangle().fill(statusColor).frame(width:3)` inside the rounded clip, with the remaining 1px border in line-loud.

**Icon (`.vibe-toast__icon`).** 16×16px, `flex:none`, `margin-top:1px` (optical align to first text line). Lucide node.

**Title (`.vibe-toast__title`).** `--font-mono`, `--text-sm` **12.5px**, weight **700**, color `--text-primary`.

**Message (`.vibe-toast__msg`).** `--font-mono`, `--text-xs` **11px**, color `--text-secondary` fg-300, line-height **1.5**.

**Close button (`.vibe-toast__close`).** 16×16px, color `--text-muted` fg-400, no bg/border, cursor pointer, `flex:none`, padding 0. **Hover → color `--text-primary`.** Inline svg = an X: two crossed strokes `M18 6 6 18 M6 6l12 12`, `stroke-width 2`, round caps (lucide "x"). SF Symbol: `xmark`.

**Interaction:** the whole toast is `role="status"` (non-interactive except close). Close button hover state as above. Rendering of close only when `onClose` provided.

**Props:** `status: ok|warn|danger|info` (default info); `title: node?`; `icon: node?`; `onClose: (()->Void)?` (renders close when set); `children` = message body.

---

## 8. GateRow — `GateRow` (`data/GateRow.jsx`, class `.vibe-gate`)

**Purpose.** One quality-gate result line: an intrinsic status glyph, the gate name, the make-target that runs it, and a right-aligned detail (exit code, count, ratio). Maps to `quality_gates` in VIBE.yaml. Stack inside a `Card` (usually `flush` with `bare` rows) to render a gate report.

**DOM / structure.**
`<div class="vibe-gate vibe-gate--{status} [vibe-gate--bare]">`
  → `<span class="vibe-gate__icon">` [inline svg glyph per status] `</span>`
  → `<span class="vibe-gate__name">{name}</span>`
  → (if command) `<span class="vibe-gate__cmd">{command}</span>`
  → `<span class="vibe-gate__spacer"/>` (flex:1 pushes detail right)
  → (if detail) `<span class="vibe-gate__detail">{detail}</span>`.

**SwiftUI layout.** `HStack(spacing: 12) { icon; Text(name); Text(command)?; Spacer(minLength: 8); Text(detail)? }`. Row min-height 40px.

**Base (`.vibe-gate`):**
- Layout: flex, align center, **gap 12px**. Padding **10px / 12px**. Radius `--radius-sm` **4px**.
- Background `--surface-sunken` ink-850. Border **1px solid `--border`** line. **min-height 40px**.

**`bare` variant (divider-only, for flush lists):** background transparent, no border/radius, instead **border-bottom 1px solid `--border-subtle`** line-soft, padding **9px / 4px**. Use for stacked rows inside a `Card flush`.

**Icon (`.vibe-gate__icon`).** 15×15px, `flex:none`. Inline svg viewBox 0 0 24 24, fill none, stroke currentColor, **stroke-width 2**, round caps+joins. **Intrinsic glyph per status** (lucide-equivalent → SF Symbol):
- `ok` → check path `M20 6 9 17l-5-5` (lucide **check** → SF `checkmark`), color `--ok` lime-400.
- `warn` → warning triangle with bang: `M12 9v4`, `M12 17h.01`, triangle `M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z` (lucide **triangle-alert** → SF `exclamationmark.triangle`), color `--warn` amber-400.
- `fail` → X: `M18 6 6 18`, `M6 6l12 12` (lucide **x** → SF `xmark`), color `--danger` red-400.
- `skip` → circle + horizontal bar: `circle r=9`, `M8 12h8` (lucide **circle-minus/ban** → SF `minus.circle`), color `--text-muted` fg-400.
- (JS keys glyphs by `status`; the fallback is the `ok` check.)

**Name (`.vibe-gate__name`).** `--font-mono`, `--text-sm` **12.5px**, color `--text-primary`, weight 500.

**Command (`.vibe-gate__cmd`).** `--font-mono`, `--text-2xs` **10px**, color `--text-muted` fg-400. (e.g. "make lint")

**Detail (`.vibe-gate__detail`).** `--font-mono`, `--text-2xs` **10px**, color `--text-faint` fg-500. (e.g. "exit 0", "58% / 60", "1 god-file")

**Fail row emphasis.** `.vibe-gate--fail` (non-bare) → **border-color `--danger-line`**, background `--danger-bg-soft` rgba(255,91,82,.06) (a faint red tint on the whole failing row). (For `bare` fail rows only the icon is red; the row keeps the divider.)

**Interaction:** none (static result line).

**Props:** `name` (required); `command: node?`; `status: ok|warn|fail|skip` (default ok); `detail: node?`; `bare: Bool`.

**Data usage:** rows come from `repo.gates[]`, each `{ name, cmd, status, detail }` — bind `name→repo.gates[i].name`, `command→repo.gates[i].cmd`, `status→repo.gates[i].status`, `detail→repo.gates[i].detail`. Card title is typically the make-target, e.g. `Card(title:"make validate", flush:true)`.

---

## 9. Input — `Input` (`forms/Input.jsx`, classes `.vibe-input` / `.vibe-field` / `.vibe-input__wrap`)

**Purpose.** Mono text field on a sunken well. Optional label/hint wrap it in a field; a `leadingIcon` insets a glyph (e.g. search/filter for the fleet filter bar).

**DOM / structure.**
- Bare (no label/hint): either `<input class="vibe-input …">` OR (with leadingIcon) `<span class="vibe-input__wrap"><span class="vibe-input__lead">{icon}</span><input class="vibe-input …"/></span>`.
- Labelled: `<label class="vibe-field"><span class="vibe-field__label">{label}</span>{control}<span class="vibe-field__hint">{hint}</span></label>`.

**SwiftUI layout.** `VStack(alignment:.leading, spacing: 6){ label?; control; hint? }` (the `.vibe-field` wrapper, `min-width:0`). Control = `ZStack(alignment:.leading){ TextField; leadingIcon? }` with left inset when icon present.

**Field wrapper (`.vibe-field`).** flex column, **gap 6px**, min-width 0.
**Label (`.vibe-field__label`).** `--font-mono`, `--text-2xs` **10px**, weight 500, letter-spacing `--tracking-label` **0.08em**, **UPPERCASE**, color `--text-muted` fg-400.
**Hint (`.vibe-field__hint`).** `--font-mono`, `--text-2xs` **10px**, color `--text-faint` fg-500.

**Control (`.vibe-input`):**
- `--font-mono`, `--text-sm` **12.5px**, color `--text-primary` fg-100.
- Background `--surface-sunken` ink-850. Border **1px solid `--border`** line. Radius `--radius-sm` **4px**.
- Padding **9px / 11px**. width 100%. outline none.
- Placeholder color `--text-faint` fg-500.
- Transition border-color + box-shadow at `--dur-fast` 140ms.

**States.**
- Hover → border `--border-strong` line-loud.
- Focus → border `--accent` lime-400 + **box-shadow `--ring-inset`** (inset 1px lime ring). SwiftUI: on focus, stroke lime 1px inset.
- Disabled → opacity 0.5, not-allowed.
- `invalid` (`.vibe-input--invalid`) → border `--danger-line`; on focus → border `--danger` red-400 + inset 1px red ring. Sets `aria-invalid`.

**Leading icon inset (`.vibe-input__wrap` / `.vibe-input__lead`).** wrap is `position:relative` flex; `.vibe-input__lead` absolutely positioned **left:10px**, 14×14px, color `--text-muted` fg-400, `pointer-events:none`. When present the input gets **padding-left 32px** (icon clearance). Lucide node (e.g. "search"). SwiftUI: leading SF Symbol at 14pt inside the field, text inset 32px from left.

**Props:** `label: node?`; `hint: node?`; `invalid: Bool`; `leadingIcon: node?`; `id`; plus native input attrs (placeholder, value, onChange, type, disabled). If neither label nor hint set, returns the bare control.

---

## 10. Select — `Select` (`forms/Select.jsx`, class `.vibe-select`)

**Purpose.** Native select styled to match Input, with a mono caret. Used for policy/filter dropdowns.

**DOM / structure.** Same field wrapper pattern as Input. Control = `<select class="vibe-select">` populated from `options: {value,label}[]` OR `<option>` children.

**SwiftUI layout.** `VStack(alignment:.leading, spacing:6){ label?; Menu/Picker styled as the box; hint? }`. Render a custom caret (see below) rather than the OS popup indicator to match the mono chevron.

**Control (`.vibe-select`) — shares the `.vibe-input, .vibe-select` base:**
- `--font-mono`, `--text-sm` **12.5px**, color `--text-primary`.
- Background `--surface-sunken` ink-850. Border **1px solid `--border`**. Radius `--radius-sm` **4px**. Padding **9px / 11px**, but **padding-right 30px** to clear the caret. width 100%. outline none.
- `appearance: none` (custom caret).
- **Caret:** a mono "▾" drawn with two CSS gradients forming a 5×5px triangle, positioned near the right edge (right ~10–15px), colored `--text-muted` fg-400. SwiftUI: a `chevron.down` (lucide **chevron-down**) SF Symbol, 10–11pt, `--text-muted`, right-aligned ~10px from edge.

**States (inherited from `.vibe-input, .vibe-select`).** Hover → border `--border-strong`. Focus → border `--accent` + inset lime ring `--ring-inset`. Disabled → opacity 0.5.

**Field label/hint:** identical to Input (`.vibe-field__label` 10px uppercase tracked muted; `.vibe-field__hint` 10px faint).

**Props:** `label`, `hint`, `options: {value,label}[]?` (or `<option>` children), `id`, native select attrs (`value`, `onChange`, `disabled`).

---

## 11. Switch — `Switch` (`forms/Switch.jsx`, class `.vibe-switch`)

**Purpose.** A binary policy toggle (enable monitoring, require signed commits, gate on coverage). **Lime when on.** Controlled — `onChange` receives the next boolean. Optional inline mono label to the right, which also toggles.

**DOM / structure.**
`<button role="switch" aria-checked={checked} class="vibe-switch"><span class="vibe-switch__thumb"/></button>`.
With label: wrapped in `<label class="vibe-switch-row" style="inline-flex; gap:10px; cursor:pointer|not-allowed">` containing the button + `<span style="font-mono 12.5px text-secondary">{label}</span>`.

**SwiftUI layout.** Custom toggle (do NOT use system `Toggle` chrome — match the exact geometry): `HStack(spacing: 10){ track+thumb; Text(label)? }`. Track = `Capsule`.

**Track (`.vibe-switch`).**
- Fixed **width 38px × height 22px**, radius `--radius-full` (Capsule), `flex:none`, padding 0.
- OFF: background `--surface-active` ink-650, border **1px solid `--border-strong`** line-loud.
- ON (`aria-checked="true"`): background `--accent` lime-400, border `--accent`.
- Transition background + border-color at `--dur-fast` 140ms.

**Thumb (`.vibe-switch__thumb`).**
- **16×16px** circle (`--radius-full`), absolutely `left:2px` (so 2px inset both ends: 2 + 16 + 4-travel? — travel is 16px → right rest = 2+16+16=34, leaving 2px on the right, symmetric).
- OFF: background `--fg-300` #97A39E.
- ON: `transform: translateX(16px)` and background `--lime-ink` #0B1400 (dark thumb on lime track).
- Transition transform + background at `--dur-fast` 140ms.

**States.**
- Focus-visible → `--ring` (2px lime ring offset).
- Disabled → opacity 0.5, not-allowed; `onChange` suppressed.
- Click toggles → calls `onChange(!checked)`.

**Props:** `checked: Bool` (default false); `onChange: (Bool)->Void`; `disabled: Bool`; `label: node?`; `id`. Inline label style: `--font-mono`, `--text-sm` 12.5px, color `--text-secondary` fg-300.

**Data usage:** bound to policy booleans, e.g. `repo.worktree.signed`, monitoring/coverage-gate policy flags in `fleet.policy`/`autopilot`.

---

## 12. Tabs — `Tabs` (`navigation/Tabs.jsx`, classes `.vibe-tabs` / `.vibe-tab`)

**Purpose.** The section switcher inside a repo detail (Overview / Gates / Policy / Findings). Controlled — render the active panel yourself from `value`. Optional per-tab `count` badges and leading icons.

**DOM / structure.**
`<div class="vibe-tabs" role="tablist">`
  → for each tab: `<button role="tab" aria-selected={id===active} class="vibe-tab">` (if icon) `<span class="vibe-btn__icon">{icon}</span>` + `<span>{label}</span>` + (if count!=null) `<span class="vibe-tab__count">{count}</span>` `</button>`.
Active = `value ?? tabs[0].id`.

**SwiftUI layout.** `HStack(alignment:.center, spacing: 2){ tabButtons }` with a **bottom hairline** under the whole row. Each tab = `HStack(spacing: 7){ icon?; Text(label); Text(count)? }`. The active tab draws a 2px lime underline flush to the row's bottom edge.

**Bar (`.vibe-tabs`).** flex, `align-items: stretch`, **gap 2px**, **border-bottom 1px solid `--border`** line (a hairline runs the full width beneath the tabs).

**Tab (`.vibe-tab`).**
- `--font-mono`, `--text-sm` **12.5px**, weight 500. No border, transparent bg, cursor pointer.
- Padding **10px / 14px**. `position:relative`. inline-flex, align center, **gap 7px**.
- Color (idle) `--text-muted` fg-400. Transition color at `--dur-fast` 140ms.

**States.**
- Hover → color `--text-secondary` fg-300.
- Selected (`aria-selected="true"`) → color `--text-primary` fg-100, AND `::after` underline: absolutely positioned, `left:0 right:0 bottom:-1px`, **height 2px**, background `--accent` lime-400, **box-shadow `--glow-ok-sm`** (the active underline glows green). SwiftUI: a 2px lime `Rectangle` pinned to the tab's bottom edge (overlapping the row hairline by 1px) with a green shadow.
- Focus-visible → `--ring-inset` (inset lime ring), radius `--radius-xs` 2px.

**Icon slot.** reuses `.vibe-btn__icon` (15×15px, stroke-width 2). SF Symbol per tab (e.g. lucide icons like `gauge-circle`, `shield-check`, `radar` used across the app).

**Count (`.vibe-tab__count`).** `--font-mono`, `--text-2xs` **10px**, color `--text-faint` fg-500 (a dimmed trailing number, e.g. findings count).

**Props:** `tabs: {id, label, count?, icon?}[]`; `value: String?` (active id, defaults to first); `onChange: (String)->Void`. Fully controlled — the consumer swaps the panel body.

**Data usage:** tab `count` typically from a per-section total, e.g. Findings tab `count = repo.surprises.length` (or `fleet.findings` for a fleet view). Section ids drive which panel renders.

---

## 13. Cross-cutting SwiftUI implementation notes

1. **Everything is mono by default.** Only Card body prose / big display numerals use Space Grotesk. Buttons, tags, badges, gates, inputs, tabs, meters, toasts are ALL JetBrains Mono.
2. **UPPERCASE tracked micro-labels** (panel title, field label, meter label, tag-uppercase, sev tag): render text `.uppercased()` with `.tracking(size*0.08)`. Do NOT rely on the font for casing — the CSS uses `text-transform: uppercase` on normally-cased source strings.
3. **Tabular numerals** on every mono number (meter value/threshold, gate details, badge counts): `.monospacedDigit()` + slashed-zero feature where supported.
4. **Hairline borders are the depth system** — 1px strokes in `--border`/`--border-strong`/`--border-subtle`, never shadows, except for true floating overlays (Toast uses `--shadow-pop`; cards use only the 1px `--inset-top` top-light).
5. **The phosphor glow is the only "effect"** and appears in exactly these places: Button.primary hover (`--glow-ok-sm`), Card `glow` variant (`--glow-ok`), StatusBadge `live` dot (`--glow-ok-sm` + pulse), Meter ok fill (`--glow-ok-sm`), Tabs active underline (`--glow-ok-sm`). Implement as a colored `.shadow` (bloom) plus, for the ring variants, a 1px colored stroke overlay.
6. **Press feedback** is minimal and mechanical: Button nudges `translateY(0.5px)`; no bounce, no scale. Use `--ease-out (0.2,0.6,0.2,1)` / `--dur-fast 140ms` for color/border/shadow, `--dur-instant 80ms` for transform.
7. **Focus ring** is a detached 2px lime outline offset 2px from the control (`--ring`) for buttons/switch, or an inset 1px lime ring (`--ring-inset`) for inputs/select/tabs.
8. **Reduce Motion**: zero out all durations; disable StatusBadge pulse, meter width animation feel, and the brand cursor blink.
9. **State → color is fixed and semantic**: ok=lime, warn=amber, danger=red, info=blue, policy=violet, neutral=ink/fg. The brand accent IS ok-lime — this coupling is intentional ("the board glows green when the fleet is healthy").
10. **Data model property paths** these primitives consume (from `window.VIBE_MAC`): `repo.health` (`ok|warn|danger`), `repo.compliance`, `repo.live`, `repo.stack/lifecycle/pm/framework`, `repo.coverage`, `repo.coverageFloor`, `repo.gates[].{name,cmd,status,detail}`, `repo.surprises[].{severity,pass,what,why,fix}`, `repo.worktree.{clean,unstaged,unpushed,signed}`, `repo.census.godFiles[]`, `repo.docs.{taskState,agentsMd,claudeMd}.{lines,bytes,status}`, `repo.docs.changelog.{lastUpdated,behind,status}`, `repo.agent.{active,tool,branch,elapsed,filesTouched,lastActivity,note}`, `repo.serena.{present,active,project,memories,lastSession}`; fleet aggregates `fleet.totals.{repos,healthy,warn,danger,surprises,godFiles,dirty,compliance,agentsActive,...}` and `fleet.findings[]` (sorted high→med→low).

---

## 14. Lucide → SF Symbol icon vocabulary (mapping the engineer will need)

Icons are passed as nodes (Lucide SVGs, stroke-width 2). GateRow embeds its glyphs intrinsically (see §8). Icons observed in-app across these primitives and their host views, for the SF Symbol mapping table:

| Lucide | SF Symbol (suggested) | Where |
|---|---|---|
| check | checkmark | GateRow ok |
| triangle-alert | exclamationmark.triangle | GateRow warn |
| x | xmark | GateRow fail, Toast close |
| circle-minus / ban | minus.circle | GateRow skip |
| search | magnifyingglass | Input leadingIcon (filter bar) |
| chevron-down | chevron.down | Select caret |
| refresh-cw | arrow.clockwise | Button "Re-check now" |
| shield-check | checkmark.shield | policy/tabs |
| gauge-circle | gauge | tabs/overview |
| radar | dot.radiowaves.left.and.right | scan/tabs |
| git-branch | arrow.triangle.branch | worktree/agent |
| git-commit-horizontal | ... | commits |
| git-merge | arrow.triangle.merge | worktree |
| terminal / square-terminal | terminal | console |
| lock | lock | signed commits |
| play / pause | play / pause | autopilot |
| trash-2 | trash | destructive |
| external-link | arrow.up.forward.square | links |
| file-text / file-code-2 / file-warning / file-cog / file-badge | doc.* | docs census |
| folder-tree | folder | workspace tree |
| server / hard-drive / plug / webhook / workflow / waypoints / target / sliders-horizontal / wrench / scissors / eraser / undo-2 / history / download / package-plus / shield-plus / command / coffee / github | (map per SF catalog) | topbar / overlays / findings |

(Full observed set: arrow-down-narrow-wide, check, chevron-down/left/right, coffee, command, corner-down-right, download, eraser, external-link, file-badge, file-code-2, file-cog, file-text, file-warning, folder-tree, gauge-circle, git-branch, git-commit-horizontal, git-merge, github, hard-drive, history, lock, package-plus, panel-bottom, panel-right, pause, play, plug, radar, refresh-cw, scissors, search, server, shapes, shield-check, shield-plus, sliders-horizontal, square-terminal, target, terminal, trash-2, undo-2, waypoints, webhook, workflow, wrench, x.)

---

### Source manifest (all read from the prototype)
- CSS contract: `components/components.css` (all `.vibe-*` classes).
- Tokens: `tokens/colors.css`, `typography.css`, `spacing.css`, `effects.css`, `base.css`, `fonts.css`.
- Components: `core/{Button,Card,Tag}.jsx`, `feedback/{StatusBadge,SeverityTag,Meter,Toast}.jsx`, `data/GateRow.jsx`, `forms/{Input,Select,Switch}.jsx`, `navigation/Tabs.jsx` (+ matching `.d.ts` for prop enums and `.prompt.md` for usage examples).
- Data model / property paths: `ui_kits/vibe-macos/data.js` (`window.VIBE_MAC`).
