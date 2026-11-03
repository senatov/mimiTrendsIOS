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
echo "Generated ${PROJECT_FILE}"
