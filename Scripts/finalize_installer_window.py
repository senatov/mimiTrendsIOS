#!/usr/bin/env python3
"""Validate Finder's installer view and hide its tab bar in .DS_Store."""

import plistlib
import sys
from pathlib import Path


def plist_blobs(data: bytes):
    start = 0
    while (start := data.find(b"bplist00", start)) != -1:
        for end in range(start + 40, min(len(data), start + 65_536) + 1):
            trailer = data[end - 32 : end]
            if trailer[:6] != bytes(6):
                continue
            offset_size, ref_size = trailer[6:8]
            count = int.from_bytes(trailer[8:16], "big")
            table_offset = int.from_bytes(trailer[24:32], "big")
            if not (1 <= offset_size <= 8 and 1 <= ref_size <= 8 and 1 <= count < 1_000):
                continue
            if table_offset + count * offset_size != end - start - 32:
                continue
            blob = data[start:end]
            try:
                value = plistlib.loads(blob)
            except (ValueError, TypeError, OverflowError):
                continue
            yield start, end, blob, value
            break
        start += 8


def set_boolean_in_plist(blob: bytes, key: str, value: bool) -> bytes:
    trailer = blob[-32:]
    offset_size, ref_size = trailer[6:8]
    count = int.from_bytes(trailer[8:16], "big")
    top = int.from_bytes(trailer[16:24], "big")
    table_offset = int.from_bytes(trailer[24:32], "big")
    offsets = [
        int.from_bytes(blob[table_offset + index * offset_size : table_offset + (index + 1) * offset_size], "big")
        for index in range(count)
    ]
    root = offsets[top]
    marker = blob[root]
    if marker >> 4 != 0xD or marker & 0xF == 0xF:
        raise ValueError("Finder window settings have an unsupported plist layout")
    entries = marker & 0xF
    refs = [
        int.from_bytes(blob[root + 1 + index * ref_size : root + 1 + (index + 1) * ref_size], "big")
        for index in range(2 * entries)
    ]
    updated = bytearray(blob)
    for index in range(entries):
        key_offset = offsets[refs[index]]
        key_marker = blob[key_offset]
        if key_marker >> 4 != 0x5 or key_marker & 0xF == 0xF:
            continue
        length = key_marker & 0xF
        if blob[key_offset + 1 : key_offset + 1 + length].decode("ascii") != key:
            continue
        value_offset = offsets[refs[entries + index]]
        if blob[value_offset] not in (0x08, 0x09):
            raise ValueError(f"{key} is not a Boolean")
        updated[value_offset] = 0x09 if value else 0x08
        if plistlib.loads(updated)[key] != value:
            raise ValueError(f"Could not update {key}")
        return bytes(updated)
    raise ValueError(f"Finder window settings do not contain {key}")


def main(path: Path) -> None:
    data = bytearray(path.read_bytes())
    window = icons = None
    for start, end, blob, value in plist_blobs(data):
        if isinstance(value, dict) and "ShowTabView" in value:
            window = value
            data[start:end] = set_boolean_in_plist(blob, "ShowTabView", False)
        elif isinstance(value, dict) and "backgroundType" in value:
            icons = value
    if window is None or icons is None:
        raise ValueError("Finder did not save installer window settings")
    if window.get("ShowToolbar") or window.get("ShowStatusBar") or window.get("ShowSidebar"):
        raise ValueError("Finder saved a standard window instead of the installer layout")
    background = icons.get("backgroundImageAlias", b"")
    if icons.get("backgroundType") != 2 or b"background.png" not in background:
        raise ValueError("Finder did not save the installer background")
    path.write_bytes(data)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: finalize_installer_window.py DS_STORE_PATH")
    main(Path(sys.argv[1]))
