# MAP — module ownership & extension points

| Path | Owns | Extend by |
|---|---|---|
| `Shared/Theme/` | design tokens (color, font, spacing, radius, glow, motion) | edit `ColorPalette`/`Theme`; every view reads `Theme.*` |
| `Shared/DesignSystem/` | SwiftUI primitives + brand marks | add a component file; expose via its own `View` |
| `Shared/Models/` | `Sendable` domain value types | add a model; keep it a value type |
| `Shared/Scan/` | `~/Code` scanner + probes + `Process` runner | add a `*Probe`; wire into `FleetScanner` |
| `Shared/Services/` | `FleetStore` (`@Observable`), settings, formatters | inject via `.environment` |
| `VibeDashboard/Chrome/` | window chrome: toolbar, sidebar, inspector, console, status bar, menus | one file per region |
| `VibeDashboard/Views/` | screens; `Views/RepoDetail/` = the 7 repo tabs | add a screen; route from the toolbar nav |
| `VibeDashboard/Overlays/` | command palette, sheets, toasts, tweaks | add an overlay; present from the root |

## Data flow
`FleetScanner` (off-main) → `Fleet` value snapshot → `FleetStore` (`@MainActor
@Observable`) → views read `store.fleet`. Writes (commit, prune, reconcile) go
through confirm-gated sheets that call back into the scanner's `Process` runner.
