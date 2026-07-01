# Changelog

All notable changes to Vibe Dashboard are documented here. Format loosely
follows Keep a Changelog; versions are semver from `VERSION`.

## [0.1.0] — 2026-07-01

### Added
- Scaffolded the macOS app from the `lang-swift-apple` standard: xcodegen
  `project.yml` (macOS app + Swift Testing target, Yams dependency), Makefile
  with the universal build/validate interface, Privacy Manifest, entitlements
  (un-sandboxed local dev tool), version stamping via `generate-build-info.sh`.
- Agentic-skeleton collaboration contracts: `AGENTS.md`, `VIBE.yaml`,
  `TASK_STATE.md`, `MAP.md`, `CHANGELOG.md`, `CLAUDE.md`/`GEMINI.md` symlinks.
