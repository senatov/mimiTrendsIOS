#!/bin/zsh
set -euo pipefail

if (( $# != 3 )); then
    echo "Usage: zsh Scripts/build_installer_dmg.zsh APP_PATH OUTPUT_DMG VOLUME_NAME" >&2
    exit 2
fi

script_dir="${0:A:h}"
app_path="${1:A}"
output_dmg="${2:A}"
volume_name="$3"
mount_point="/Volumes/${volume_name}"
if [[ ! -d "${app_path}" || ! -f "${script_dir}/assets/InstallerBackground.png" ]]; then
    echo "The app bundle or installer background is missing." >&2
    exit 1
fi
if [[ -e "${mount_point}" ]]; then
    echo "Installer volume is already mounted at ${mount_point}." >&2
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mimitrends-installer.XXXXXX")"
writable_dmg="${work_dir}/installer-writable.dmg"
mounted=0
cleanup() {
    if (( mounted )); then
        hdiutil detach "${mount_point}" -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "${work_dir}"
}
trap cleanup EXIT

staging="${work_dir}/staging"
mkdir -p "${staging}/.background" "${output_dmg:h}"
ditto "${app_path}" "${staging}/${app_path:t}"
ln -s /Applications "${staging}/Applications"
cp "${script_dir}/assets/InstallerBackground.png" "${staging}/.background/background.png"
/usr/bin/SetFile -a V "${staging}/.background"

hdiutil create -quiet -volname "${volume_name}" -srcfolder "${staging}" \
    -fs HFS+ -format UDRW -ov "${writable_dmg}"
hdiutil attach -quiet -nobrowse -noverify -readwrite \
    -mountpoint "${mount_point}" "${writable_dmg}"
mounted=1
osascript "${script_dir}/configure_installer_window.applescript" "${mount_point}"

finder_state="${mount_point}/.DS_Store"
if [[ ! -s "${finder_state}" ]]; then
    echo "Finder did not save the custom installer window in ${finder_state}." >&2
    exit 1
fi
/usr/bin/python3 "${script_dir}/finalize_installer_window.py" "${finder_state}"
/bin/sync
hdiutil detach "${mount_point}" -quiet
mounted=0
hdiutil convert "${writable_dmg}" -quiet -format UDZO -ov -o "${output_dmg}"
hdiutil verify -quiet "${output_dmg}"
echo "Created custom Finder installer: ${output_dmg}"
