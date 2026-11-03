#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/_common.zsh"
require_xcode
require_project

if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--dry-run" ]]; }; then
    echo "Usage: zsh Scripts/release_macos.zsh [--dry-run]" >&2
    exit 2
fi
dry_run="${1:-}"
cd "${PROJECT_DIR}"

for tool in gh xcodegen; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "${tool} is required for a macOS release." >&2
        exit 1
    fi
done
if [[ "$(git branch --show-current)" != "main" || -n "$(git status --porcelain)" ]]; then
    echo "Release from a clean main branch so the tagged source matches the DMG." >&2
    exit 1
fi
git fetch --quiet --tags origin main
if ! git merge-base --is-ancestor origin/main HEAD; then
    echo "Local main has diverged from origin/main. Resolve it before releasing." >&2
    exit 1
fi
gh auth status >/dev/null 2>&1

current="$(/usr/bin/python3 "${SCRIPT_DIR}/release_version.py" current)"
local_tags="$(git tag --list)"
release_tags="$(gh release list --limit 1000 --json tagName --jq '.[].tagName')"
if git show-ref --verify --quiet "refs/tags/${current}" && ! gh release view "${current}" >/dev/null 2>&1; then
    echo "Tag ${current} exists without a GitHub Release. Finish that release before incrementing again." >&2
    exit 1
fi
next="$(printf '%s\n%s\n' "${local_tags}" "${release_tags}" | /usr/bin/python3 "${SCRIPT_DIR}/release_version.py" next)"
tag="${next}"
echo "Current ${current}; next macOS DMG and GitHub Release ${next}."
if [[ "${dry_run}" == "--dry-run" ]]; then
    exit 0
fi

notary_profile="${MIMITRENDS_NOTARY_PROFILE:-MiMiNotary}"
if ! xcrun notarytool history --keychain-profile "${notary_profile}" --output-format json >/dev/null 2>&1; then
    echo "Notary profile ${notary_profile} is unavailable. Set MIMITRENDS_NOTARY_PROFILE to a valid profile." >&2
    exit 1
fi
team_id="$(/usr/bin/sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*([A-Z0-9]+).*/\1/p' project.yml)"
if [[ -z "${team_id}" ]]; then
    echo "DEVELOPMENT_TEAM is missing from project.yml." >&2
    exit 1
fi
signing_identity="${MIMITRENDS_MAC_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | /usr/bin/awk -v team="${team_id}" '
    index($0, "Developer ID Application:") && index($0, "(" team ")") { print $2; exit }
')}"
if [[ -z "${signing_identity}" ]]; then
    echo "A Developer ID Application identity for team ${team_id} is required." >&2
    exit 1
fi

version_applied=0
release_committed=0
restore_on_failure() {
    local result=$?
    if (( result != 0 && version_applied && !release_committed )); then
        git restore -- project.yml mimiTrends-iOS.xcodeproj/project.pbxproj
        echo "Release failed before commit; project versions were restored." >&2
    elif (( result != 0 && release_committed )); then
        echo "Release commit/tag may exist. Inspect git and GitHub before starting another version." >&2
    fi
}
trap restore_on_failure EXIT

version_applied=1
/usr/bin/python3 "${SCRIPT_DIR}/release_version.py" set "${next}"
zsh "${SCRIPT_DIR}/generate_project.zsh"
release_dir="${DERIVED_DATA}/Releases/${next}"
mkdir -p "${release_dir}"
xcodebuild -quiet \
    -project "${PROJECT_FILE}" -scheme "${SCHEME}" -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
app_path="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Contents/Info.plist")"
if [[ "${actual_version}" != "${next}" ]]; then
    echo "Built app version ${actual_version} does not match ${next}." >&2
    exit 1
fi
codesign --force --sign "${signing_identity}" --options runtime --timestamp \
    --entitlements "${PROJECT_DIR}/MiMiTrends/Configuration/MacAppStore.entitlements" "${app_path}"
codesign --verify --deep --strict --verbose=2 "${app_path}"
signed_team="$(codesign -dv --verbose=4 "${app_path}" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
if [[ "${signed_team}" != "${team_id}" ]]; then
    echo "Signed app has team ${signed_team}; expected ${team_id}." >&2
    exit 1
fi

staging="${release_dir}/staging"
mkdir -p "${staging}"
ditto "${app_path}" "${staging}/${APP_NAME}.app"
ln -s /Applications "${staging}/Applications"
dmg="${release_dir}/${APP_NAME}-${next}.dmg"
hdiutil create -quiet -volname "${APP_NAME} ${next}" -srcfolder "${staging}" \
    -fs HFS+ -format UDZO -ov "${dmg}"
notary_result="${release_dir}/notary-result.json"
if ! xcrun notarytool submit "${dmg}" --keychain-profile "${notary_profile}" \
    --wait --output-format json > "${notary_result}"; then
    echo "Notarization submission failed; inspect ${notary_result}." >&2
    exit 1
fi
/usr/bin/python3 - "${notary_result}" <<'PY'
import json
from pathlib import Path
import sys

result = json.loads(Path(sys.argv[1]).read_text())
if result.get("status") != "Accepted":
    sys.exit(f"Notarization was not accepted: {result.get('status')}; inspect {sys.argv[1]}")
PY
xcrun stapler staple "${dmg}"
xcrun stapler validate "${dmg}"
hdiutil verify -quiet "${dmg}"

git add project.yml mimiTrends-iOS.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "NEW: Prepare macOS release ${next}" \
    -m "Advance the four-component app and build versions for the notarized DMG and matching GitHub Release."
release_committed=1
git tag -a "${tag}" -m "mimiTrends-iOS ${next}"
git push --atomic origin HEAD:main "refs/tags/${tag}"
gh release create "${tag}" "${dmg}" --verify-tag --title "${next}" --generate-notes
echo "Published notarized ${dmg} as GitHub Release ${next}."
