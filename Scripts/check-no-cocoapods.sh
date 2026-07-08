#!/usr/bin/env bash
# check-no-cocoapods.sh — fail loudly if Podfile / Pods / Cartfile /
# Carthage are present anywhere in the repo.
#
# This skill is SPM-only. CocoaPods and Carthage are forbidden.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${1:-$REPO_ROOT}"

red()    { printf '\033[31m%s\033[0m\n' "$1" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

failures=0

forbid() {
    local name="$1"
    local pattern="$2"
    local found
    # Prune the xcodegen-generated `.xcodeproj`: its nested
    # `project.xcworkspace` is NOT a CocoaPods artifact and must not trip
    # this check. `|| true` keeps SIGPIPE from `head` from aborting `set -e`.
    found=$(find . -path "*/.git" -prune -o -path "*/build" -prune -o \
        -path "*.xcodeproj" -prune -o \
        -name "$pattern" -print 2>/dev/null | head -5 || true)
    if [[ -n "$found" ]]; then
        red "✗ $name detected:"
        printf '%s\n' "$found" >&2
        failures=$((failures + 1))
    fi
}

forbid "CocoaPods Podfile" "Podfile"
forbid "CocoaPods Podfile.lock" "Podfile.lock"
forbid "CocoaPods Pods/" "Pods"
forbid "CocoaPods Workspace (.xcworkspace alongside Podfile)" "*.xcworkspace"
forbid "Carthage Cartfile" "Cartfile"
forbid "Carthage Cartfile.resolved" "Cartfile.resolved"
forbid "Carthage Build dir" "Carthage"

# A standalone `<App>.xcworkspace` alongside a Podfile is a CocoaPods
# workspace and IS caught above. The `project.xcworkspace` nested inside
# the xcodegen-generated `.xcodeproj` is benign — `.xcodeproj` is pruned
# in forbid(), so a fresh `xcodegen generate` never trips this check.

if [[ $failures -gt 0 ]]; then
    red "✗ Forbidden dependency manager artifacts found ($failures kinds)."
    yellow "Migrate to Swift Package Manager (declare deps under packages: in project.yml)."
    yellow "See AGENTS.md for the SPM-only policy."
    exit 1
fi

green "✓ No CocoaPods / Carthage artifacts found."
