# AGENTS — Vibe Dashboard

## 1. What this is

Vibe Dashboard is a native **macOS** app (SwiftUI, Swift 6) that continuously
monitors a fleet of agentic-skeleton repositories under `~/Code` for adherence
to each repo's `VIBE.yaml` policy — and, because it runs locally, for the things
only a local app can see: live coding-agent sessions, git worktree sprawl, doc
bloat, `CHANGELOG` staleness, Serena project state, lifecycle hooks, and MCP
servers. It is the realtime, multi-repo face of the in-chat `agentic-checkup`
skill. The visual language is the **Vibe Dashboard design system**: dark,
mono-dominant, one acid-lime accent that doubles as the "healthy/live" signal.

## 2. Setup & commands

```bash
brew install xcodegen        # one-time toolchain
make build-mac               # xcodegen generate + build (unsigned)
make run                     # build + launch the app
make test                    # unit tests (Swift Testing)
make validate                # build + lint + check-architecture + check-docs (the gate)
make lint                    # SwiftLint (advisory)
make check-architecture      # file-size census (soft 250 / hard 400)
```

`project.yml` is the source of truth; the `.xcodeproj` is regenerated and
gitignored. Never hand-edit the project file.

## 3. Standard

This app is built to the `lang-swift-apple` north-star standard: Swift 6 strict
concurrency, SwiftUI + `@Observable`, xcodegen, no CocoaPods/Carthage, Privacy
Manifest present. The `apple:` namespace in `VIBE.yaml` is owned by that skill.

## 4. Architecture rules

- All design values flow through `Shared/Theme` (`Theme.color/font/spacing/…`).
  No raw `Color(hex:)`, `.padding(12)`, or ad-hoc fonts in views.
- Models in `Shared/Models` are `Sendable` value types.
- Scanning/IO lives in `Shared/Scan` (off the main actor); UI reads a single
  `@MainActor @Observable FleetStore` in `Shared/Services`.
- Files stay under **400** lines (hard) / **250** (soft) — this app enforces the
  same limit it measures.

## 5. Not sandboxed

The app is intentionally un-sandboxed (reads `~/Code`, runs `git`/`make`). Do
not add `com.apple.security.app-sandbox` — it would break the scanner.

## 9. Gotchas

- The pre-build `generate-build-info.sh` needs a git `HEAD`; a zero-commit
  checkout fails the build. Keep at least one commit.
- `SWIFT_STRICT_CONCURRENCY: complete` is on — probes must be `Sendable`-clean.
