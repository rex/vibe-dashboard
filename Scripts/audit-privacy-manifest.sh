#!/usr/bin/env bash
# audit-privacy-manifest.sh — fail if PrivacyInfo.xcprivacy is
# missing or malformed.
#
# Run in CI before xcodebuild. Failing here is preferable to
# discovering the manifest is missing during App Review.
#
# Exits non-zero on:
#   - No PrivacyInfo.xcprivacy anywhere under the project.
#   - Manifest exists but plutil can't parse it.
#   - Manifest is missing the four required top-level keys.
#   - App uses UserDefaults / file timestamps / system uptime /
#     disk space / active keyboards in source AND the manifest
#     doesn't declare a matching NSPrivacyAccessedAPICategory.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${1:-$REPO_ROOT}"

red()    { printf '\033[31m%s\033[0m\n' "$1" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

failures=0

# 1. Find all PrivacyInfo.xcprivacy files in the workspace.
mapfile -t manifests < <(find . -name "PrivacyInfo.xcprivacy" -not -path "*/build/*" -not -path "*/.git/*" -not -path "*/Pods/*" -not -path "*/Carthage/*" 2>/dev/null)

if [[ ${#manifests[@]} -eq 0 ]]; then
    red "✗ No PrivacyInfo.xcprivacy found. REQUIRED for App Store submission since May 2024."
    yellow "  Add VibeDashboard/PrivacyInfo.xcprivacy and list it under targets.VibeDashboard.sources in project.yml."
    exit 1
fi

green "Found ${#manifests[@]} PrivacyInfo.xcprivacy file(s):"
printf '  %s\n' "${manifests[@]}"
echo

# 2. Validate each manifest parses as plist.
for manifest in "${manifests[@]}"; do
    echo "Checking $manifest..."

    if ! plutil -lint "$manifest" > /dev/null 2>&1; then
        red "  ✗ plutil lint failed."
        failures=$((failures + 1))
        continue
    fi

    # Convert to JSON for jq-style queries.
    json="$(plutil -convert json -o - "$manifest")"

    for required_key in NSPrivacyTracking NSPrivacyTrackingDomains NSPrivacyCollectedDataTypes NSPrivacyAccessedAPITypes; do
        if ! grep -q "\"$required_key\"" <<< "$json"; then
            red "  ✗ Missing required key: $required_key"
            failures=$((failures + 1))
        fi
    done
done

# 3. Cross-check: if source code touches a required-reason API but
# the manifest doesn't declare it, fail.
echo
echo "Auditing required-reason API usage in source..."

declare -A api_patterns=(
    ["NSPrivacyAccessedAPICategoryUserDefaults"]="UserDefaults"
    ["NSPrivacyAccessedAPICategoryFileTimestamp"]="(creationDate|contentModificationDate|attributesOfItem)"
    ["NSPrivacyAccessedAPICategorySystemBootTime"]="(systemUptime|mach_absolute_time|CACurrentMediaTime)"
    ["NSPrivacyAccessedAPICategoryDiskSpace"]="(volumeAvailableCapacity|volumeTotalCapacity)"
    ["NSPrivacyAccessedAPICategoryActiveKeyboards"]="UITextInputMode"
)

# Combine all manifests' JSON to check declared categories.
all_categories=""
for manifest in "${manifests[@]}"; do
    json="$(plutil -convert json -o - "$manifest")"
    declared_in_file=$(grep -oE "NSPrivacyAccessedAPICategory[A-Za-z]+" <<< "$json" | sort -u || true)
    all_categories="$all_categories"$'\n'"$declared_in_file"
done

for category in "${!api_patterns[@]}"; do
    pattern="${api_patterns[$category]}"

    # Search Swift / Obj-C source for the API usage.
    # `|| true`: a zero-match grep exits 1, which under `set -o pipefail`
    # would abort the whole script mid-audit. We WANT zero matches here.
    matches=$(grep -rE "$pattern" --include="*.swift" --include="*.m" --include="*.mm" \
        --exclude-dir=build --exclude-dir=.git --exclude-dir=Pods --exclude-dir=Carthage \
        2>/dev/null | wc -l | tr -d ' ' || true)

    if [[ $matches -gt 0 ]]; then
        if grep -q "$category" <<< "$all_categories"; then
            green "  ✓ $category — declared ($matches source hits)"
        else
            red "  ✗ $category — NOT DECLARED ($matches source hits found)"
            failures=$((failures + 1))
        fi
    fi
done

# 4. Final result.
echo
if [[ $failures -gt 0 ]]; then
    red "✗ $failures privacy-manifest issue(s) found."
    yellow "Fix VibeDashboard/PrivacyInfo.xcprivacy (the apple: privacy_manifest policy in VIBE.yaml requires it)."
    exit 1
else
    green "✓ Privacy manifest audit passed."
fi
