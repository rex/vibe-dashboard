#!/usr/bin/env bash
# release.sh — Developer ID signing → notarization → stapled DMG for Vibe Dashboard.
#
# Vibe is un-sandboxed and distributed DIRECTLY (never the Mac App Store), so the
# shipping artifact is a NOTARIZED, STAPLED DMG. This is the whole prescribed
# pipeline; see docs/RELEASE.md for the one-time credential setup.
#
# Modes:
#   release.sh check     Preflight only — report what's present/missing. No changes,
#                        no network. Safe to run anytime.
#   release.sh local     Build an UNSIGNED Release app + DMG into dist/. NOT
#                        distributable (won't pass Gatekeeper) — for smoke-testing
#                        the bundle + packaging without a Developer ID certificate.
#   release.sh           Full pipeline: archive (universal) → export (Developer ID,
#                        hardened runtime) → notarize + staple the app → build,
#                        sign, notarize + staple the DMG. Requires a Developer ID
#                        Application certificate AND a stored notary profile.
#
# Config (env overrides):
#   NOTARY_PROFILE   keychain profile for notarytool   (default: vibe-notary)
#   TEAM_ID          Apple Developer team id            (default: auto-detect from cert)
#   DIST             output directory                   (default: dist)
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-vibe-notary}"
DIST="${DIST:-dist}"
SCHEME="VibeDashboard"
PROJECT="VibeDashboard.xcodeproj"
APP_NAME="VibeDashboard.app"

BUILD_NUM="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
MARKETING="$(./Scripts/generate-build-info.sh --print-marketing 2>/dev/null || echo 0.0)"
DMG_NAME="VibeDashboard-${MARKETING}.dmg"

c_reset=$'\e[0m'; c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_dim=$'\e[2m'
say()  { printf '%s>>> %s%s\n' "$c_dim"  "$1" "$c_reset"; }
ok()   { printf '%s  ✓ %s%s\n' "$c_ok"   "$1" "$c_reset"; }
warn() { printf '%s  ! %s%s\n' "$c_warn" "$1" "$c_reset"; }
die()  { printf '%s  ✗ %s%s\n' "$c_err"  "$1" "$c_reset" >&2; exit 1; }

# The exact "Developer ID Application: …" identity string, or empty if absent.
# Always exits 0 (empty output when no cert) so it's safe under `set -e`.
dev_id_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | head -1 | sed -E 's/^[^"]*"([^"]*)".*$/\1/' || true
}
# Team id from the cert's trailing "(TEAMID)", unless TEAM_ID is set. Exits 0.
detect_team() {
  local id; id="$(dev_id_identity)"
  [ -n "$id" ] && echo "$id" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' || true
}

preflight() {
  say "release preflight — v${MARKETING} (build ${BUILD_NUM})"
  local ready=1
  local id; id="$(dev_id_identity)"
  if [ -n "$id" ]; then ok "Developer ID cert: $id"
  else
    ready=0
    warn "No 'Developer ID Application' certificate in the keychain."
    warn "  → Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + Developer ID Application"
    warn "    (needs Apple Developer Program membership). Then re-run 'make release-check'."
  fi
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    ok "notary profile '$NOTARY_PROFILE' stored and valid"
  else
    ready=0
    warn "No usable notary profile '$NOTARY_PROFILE'."
    warn "  → store one once:  ./Scripts/notary-setup.sh   (see docs/RELEASE.md)"
  fi
  local team="${TEAM_ID:-$(detect_team || true)}"
  if [ -n "$team" ]; then ok "team id: $team"; else warn "team id not detected (set TEAM_ID)"; fi
  local t
  for t in xcodebuild codesign xcrun hdiutil stapler ditto xcodegen; do
    if command -v "$t" >/dev/null 2>&1; then ok "tool: $t"; else die "missing required tool: $t"; fi
  done
  if [ "$ready" -eq 1 ]; then ok "READY — 'make release' can run the full pipeline."
  else warn "NOT READY — resolve the ! items above, then 'make release'."; fi
}

regen() { xcodegen generate >/dev/null; }

build_unsigned_app() {
  say "building unsigned Release app…" >&2
  regen
  local out="$DIST/local"; rm -rf "$out"; mkdir -p "$out"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$out/dd" \
    CODE_SIGNING_ALLOWED=NO \
    CURRENT_PROJECT_VERSION="$BUILD_NUM" MARKETING_VERSION="$MARKETING" build >/dev/null
  echo "$out/dd/Build/Products/Release/$APP_NAME"
}

# Archive (universal) + export a Developer ID-signed app; echoes the .app path.
archive_and_export() {
  local id team
  id="$(dev_id_identity)"; [ -n "$id" ] || die "No Developer ID Application cert — run 'make release-check'."
  team="${TEAM_ID:-$(detect_team)}"; [ -n "$team" ] || die "Team id undetermined — set TEAM_ID."
  say "archiving (Release, universal, Developer ID)…" >&2
  regen
  local arch="$DIST/VibeDashboard.xcarchive"; rm -rf "$arch"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$arch" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CURRENT_PROJECT_VERSION="$BUILD_NUM" MARKETING_VERSION="$MARKETING" \
    DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Manual \
    "CODE_SIGN_IDENTITY=Developer ID Application" \
    archive >&2
  say "exporting Developer ID app…" >&2
  local exp="$DIST/export"; rm -rf "$exp"
  local opts="$DIST/ExportOptions.plist"; mkdir -p "$DIST"
  sed "s/__TEAM_ID__/$team/" ExportOptions.plist > "$opts"
  xcodebuild -exportArchive -archivePath "$arch" -exportPath "$exp" \
    -exportOptionsPlist "$opts" >&2
  echo "$exp/$APP_NAME"
}

notarize() {  # <path-to-dmg-or-zip>
  say "submitting $(basename "$1") to Apple notary (can take a few minutes)…"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

case "${1:-full}" in
  check)
    preflight
    ;;

  local)
    app="$(build_unsigned_app)"
    dmg="$DIST/$DMG_NAME"
    ./Scripts/make-dmg.sh "$app" "$dmg" "Vibe Dashboard ${MARKETING}"
    warn "UNSIGNED local DMG — testing only, will NOT pass Gatekeeper:"
    ok   "$dmg"
    ;;

  full)
    preflight
    app="$(archive_and_export)"
    say "verifying signature + hardened runtime…"
    codesign --verify --deep --strict --verbose=2 "$app"
    # Capture once, then match against the string — piping codesign straight into
    # `grep -q` under `set -o pipefail` makes codesign take SIGPIPE when grep closes
    # the pipe early, which falsely trips the check even when the flag IS present.
    sig="$(codesign -dvv "$app" 2>&1 || true)"
    grep -iE 'flags=|Authority=Developer ID App' <<<"$sig" || true
    # Fail HERE, not after a multi-minute notary round-trip, if the runtime flag is
    # missing — that's exactly what a dropped ENABLE_HARDENED_RUNTIME produces, and
    # the notary service rejects it with "does not have the hardened runtime enabled".
    if ! grep -Eq 'flags=0x[0-9a-f]+\([^)]*runtime' <<<"$sig"; then
      die "hardened runtime is NOT set on the app — notarization would reject it. Check ENABLE_HARDENED_RUNTIME in project.yml (it must be under settings.base)."
    fi
    ok "hardened runtime present"

    # 1) Notarize + staple the APP itself (via a zip) so it verifies OFFLINE.
    zip="$DIST/VibeDashboard.zip"; rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"
    notarize "$zip"
    xcrun stapler staple "$app"
    say "gatekeeper assessment of the notarized app:"
    spctl --assess --type execute --verbose=4 "$app" || warn "spctl assess returned non-zero"
    ok "app notarized + stapled"

    # 2) Package the stapled app, then sign + notarize + staple the DMG.
    dmg="$DIST/$DMG_NAME"
    ./Scripts/make-dmg.sh "$app" "$dmg" "Vibe Dashboard ${MARKETING}"
    codesign --force --sign "$(dev_id_identity)" --timestamp "$dmg"
    notarize "$dmg"
    xcrun stapler staple "$dmg"
    ok "RELEASE COMPLETE — v${MARKETING}"
    ok "$dmg"
    ;;

  *)
    die "unknown mode '$1' — use: check | local | full"
    ;;
esac
