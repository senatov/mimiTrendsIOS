#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
icon_dir="${project_dir}/MiMiTrends/Resources/Assets.xcassets/AppIcon.appiconset"

for tool in rsvg-convert magick; do
    command -v "${tool}" >/dev/null || { echo "${tool} is required to render app assets." >&2; exit 1; }
done

for size in 16 32 64 128 256 512 1024; do
    rsvg-convert -w "${size}" -h "${size}" "${icon_dir}/AppIcon.svg" \
        -o "${icon_dir}/AppIcon-${size}.png"
done

# iOS masks the square image itself; the Mac icon keeps its transparent corners.
magick "${icon_dir}/AppIcon-1024.png" -background '#122654' -alpha remove -alpha off \
    "${icon_dir}/AppIcon-iOS-1024.png"
rsvg-convert -w 660 -h 400 "${script_dir}/assets/InstallerBackground.svg" \
    -o "${script_dir}/assets/InstallerBackground.png"
