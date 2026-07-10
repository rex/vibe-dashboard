#!/usr/bin/env bash
# make-dmg.sh <app-path> <dmg-path> [volume-name]
#
# A compact, compressed (UDZO) DMG containing the app plus an /Applications drop
# target — the conventional drag-to-install layout. Pure `hdiutil`, no external
# dependency (create-dmg is intentionally NOT required).
set -euo pipefail

app="${1:?usage: make-dmg.sh <app-path> <dmg-path> [volume-name]}"
dmg="${2:?usage: make-dmg.sh <app-path> <dmg-path> [volume-name]}"
vol="${3:-Vibe Dashboard}"

[ -d "$app" ] || { echo "make-dmg: app bundle not found: $app" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"

rm -f "$dmg"
mkdir -p "$(dirname "$dmg")"
hdiutil create -volname "$vol" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
echo "made $dmg"
