#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/_common.zsh"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen is required to regenerate the project: brew install xcodegen" >&2
    exit 1
fi

cd "${PROJECT_DIR}"
xcodegen generate
cp "${PROJECT_FILE}/project.pbxproj" "${PROJECT_DIR}/mimiTrendsIOS.xcodeproj/project.pbxproj"
sed 's/container:mimiTrends-iOS.xcodeproj/container:mimiTrendsIOS.xcodeproj/g' \
    "${PROJECT_FILE}/xcshareddata/xcschemes/mimiTrends-iOS.xcscheme" \
    > "${PROJECT_DIR}/mimiTrendsIOS.xcodeproj/xcshareddata/xcschemes/mimiTrends-iOS.xcscheme"
echo "Generated ${PROJECT_FILE}"
