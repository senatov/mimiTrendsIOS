#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/_common.zsh"
require_xcode
require_project

entitlements="${PROJECT_DIR}/MiMiTrends/Configuration/MacAppStore.entitlements"
plutil -lint "${entitlements}" >/dev/null

for key in \
    com.apple.security.app-sandbox \
    com.apple.security.network.client \
    com.apple.security.files.user-selected.read-only; do
    value="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${entitlements}")"
    if [[ "${value}" != "true" ]]; then
        echo "Required sandbox entitlement is not enabled: ${key}" >&2
        exit 1
    fi
done

xcodebuild -project "${PROJECT_FILE}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -sdk macosx \
    -destination 'generic/platform=macOS' \
    -showBuildSettings -json 2>/dev/null | /usr/bin/python3 -c '
import json
import sys

settings = next(item["buildSettings"] for item in json.load(sys.stdin) if item["target"] == "mimiTrends-iOS")
expected = "MiMiTrends/Configuration/MacAppStore.entitlements"
if settings.get("CODE_SIGN_ENTITLEMENTS") != expected:
    sys.exit(f"Mac target must use {expected}")
if settings.get("PRODUCT_BUNDLE_IDENTIFIER") != "org.senatov.mimitrends.apple":
    sys.exit("Unexpected native app bundle identifier")
if settings.get("PRODUCT_NAME") != "mimiTrends-iOS":
    sys.exit("Unexpected native app product name")
'

echo "Mac App Sandbox configuration is present. Signed runtime behavior still needs feature testing."
