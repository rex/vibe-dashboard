#!/usr/bin/env bash
# notary-setup.sh — store notarization credentials ONCE into a keychain profile
# that release.sh reuses (`xcrun notarytool submit --keychain-profile`).
#
# This wrapper holds NO secrets. It runs Apple's own interactive
# `notarytool store-credentials`, which prompts YOU for your credentials and
# saves them to your login keychain. Two supported credential types:
#
#   • App Store Connect API key (recommended — no password, revocable):
#     a .p8 key from App Store Connect → Users and Access → Integrations →
#     App Store Connect API. Then:
#
#       ./Scripts/notary-setup.sh --key /path/AuthKey_XXXX.p8 \
#                                 --key-id XXXXXXXXXX --issuer <issuer-uuid>
#
#   • Apple ID + app-specific password:
#     create one at appleid.apple.com → Sign-In & Security → App-Specific
#     Passwords. Then (notarytool will prompt for the password):
#
#       ./Scripts/notary-setup.sh --apple-id you@example.com --team-id TEAMID
#
# The .p8 and the password must NEVER be committed; .gitignore already blocks
# AuthKey_*.p8, *.p8, .env, and friends. Override the profile name with
# NOTARY_PROFILE (must match what release.sh uses).
set -euo pipefail

PROFILE="${NOTARY_PROFILE:-vibe-notary}"

if [ "$#" -eq 0 ]; then
  sed -n '2,30p' "$0"          # print the usage header
  echo
  echo "No arguments given. Pass either --key/--key-id/--issuer (API key) or" >&2
  echo "--apple-id/--team-id (Apple ID). Target profile: '$PROFILE'." >&2
  exit 2
fi

echo ">>> storing notary credentials into keychain profile '$PROFILE'…"
xcrun notarytool store-credentials "$PROFILE" "$@"
echo ">>> done. Verify:  xcrun notarytool history --keychain-profile $PROFILE"
