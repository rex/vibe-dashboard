#!/usr/bin/env bash
# audit-usage-descriptions.sh — cross-check API usage against
# NSUsageDescription strings in Info.plist.
#
# Apple rejects apps that call HealthKit / Camera / Location / etc.
# without the matching Info.plist string. This script greps source
# for the API calls and verifies each Info.plist in the workspace
# declares the matching key.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${1:-$REPO_ROOT}"

red()    { printf '\033[31m%s\033[0m\n' "$1" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

failures=0

# Find Info.plist files in app / extension targets (skip Pods etc.).
mapfile -t plists < <(find . -name "Info.plist" \
    -not -path "*/build/*" -not -path "*/.git/*" \
    -not -path "*/Pods/*" -not -path "*/Carthage/*" \
    -not -path "*/DerivedData/*" 2>/dev/null)

if [[ ${#plists[@]} -eq 0 ]]; then
    yellow "No Info.plist found. (Apps using GENERATE_INFOPLIST_FILE=YES + INFOPLIST_KEY_* don't have one.)"
    exit 0
fi

# Maps: source pattern → required NSUsageDescription key.
declare -A api_to_key=(
    ["HKHealthStore"]="NSHealthShareUsageDescription"
    ["HKQuantityType"]="NSHealthShareUsageDescription"
    ["CLLocationManager"]="NSLocationWhenInUseUsageDescription"
    ["AVCaptureDevice"]="NSCameraUsageDescription"
    ["PHPhotoLibrary"]="NSPhotoLibraryUsageDescription"
    ["CBCentralManager"]="NSBluetoothAlwaysUsageDescription"
    ["CBPeripheralManager"]="NSBluetoothAlwaysUsageDescription"
    ["EKEventStore"]="NSCalendarsFullAccessUsageDescription"
    ["CNContactStore"]="NSContactsUsageDescription"
    ["SFSpeechRecognizer"]="NSSpeechRecognitionUsageDescription"
    ["LAContext"]="NSFaceIDUsageDescription"
    ["ATTrackingManager"]="NSUserTrackingUsageDescription"
    ["CMMotionActivityManager"]="NSMotionUsageDescription"
    ["HMHomeManager"]="NSHomeKitUsageDescription"
    ["MFMessageComposeViewController"]="NSContactsUsageDescription"
)

# For each (pattern, key) pair: if pattern appears in source, every
# Info.plist that's an app or extension Info should declare the key.
for pattern in "${!api_to_key[@]}"; do
    key="${api_to_key[$pattern]}"

    # `|| true`: a zero-match grep exits 1, which under `set -o pipefail`
    # would abort the whole audit. Zero matches is the expected case.
    src_hits=$(grep -rE "\b$pattern\b" --include="*.swift" --include="*.m" --include="*.mm" \
        --exclude-dir=build --exclude-dir=.git --exclude-dir=Pods --exclude-dir=Carthage \
        --exclude-dir=DerivedData 2>/dev/null | wc -l | tr -d ' ' || true)

    if [[ $src_hits -gt 0 ]]; then
        # Pattern in source — check at least ONE Info.plist declares the key.
        declared_anywhere=false
        for plist in "${plists[@]}"; do
            if plutil -extract "$key" raw "$plist" >/dev/null 2>&1; then
                declared_anywhere=true
                break
            fi
        done

        if [[ "$declared_anywhere" == "true" ]]; then
            green "  ✓ $pattern → $key declared"
        else
            red "  ✗ $pattern used in source ($src_hits hits) but $key NOT in any Info.plist"
            failures=$((failures + 1))
        fi
    fi
done

# Also check: every declared NSUsageDescription string is non-empty
# (Apple rejects empty strings — common copy-paste failure).
echo
echo "Checking declared NSUsageDescription strings are non-empty..."
for plist in "${plists[@]}"; do
    if ! plutil -convert json -o - "$plist" >/dev/null 2>&1; then
        red "  ✗ $plist — plutil lint failed"
        failures=$((failures + 1))
        continue
    fi
    while read -r key; do
        value="$(plutil -extract "$key" raw "$plist" 2>/dev/null || true)"
        if [[ -z "$value" ]]; then
            red "  ✗ $plist — $key is empty"
            failures=$((failures + 1))
        fi
    done < <(plutil -convert json -o - "$plist" | grep -oE 'NS[A-Za-z]+UsageDescription' | sort -u)
done

echo
if [[ $failures -gt 0 ]]; then
    red "✗ $failures usage-description issue(s) found."
    yellow "Add the matching NS…UsageDescription key to VibeDashboard/Info.plist."
    exit 1
else
    green "✓ Usage descriptions audit passed."
fi
