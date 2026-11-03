#!/usr/bin/env python3
"""Keep four-digit release versions in the project specification and Xcode project."""

import argparse
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "project.yml"
PROJECT = ROOT / "mimiTrends-iOS.xcodeproj/project.pbxproj"
VERSION = re.compile(r"[0-9](?:\.[0-9]){3}\Z")


def digits(value: str) -> tuple[int, int, int, int]:
    if not VERSION.fullmatch(value):
        raise ValueError(f"Expected four single digits: {value!r}")
    return tuple(map(int, value.split(".")))


def current() -> str:
    matches = re.findall(r"(?m)^\s*MARKETING_VERSION:\s*(\S+)\s*$", SPEC.read_text())
    if len(matches) != 1:
        raise ValueError("project.yml must contain exactly one MARKETING_VERSION")
    digits(matches[0])
    return matches[0]


def next_version(current_version: str, tags: list[str]) -> str:
    versions = [digits(current_version)]
    for tag in tags:
        candidate = tag.removeprefix("v")
        if VERSION.fullmatch(candidate):
            versions.append(digits(candidate))
    number = max(sum(part * 10 ** (3 - index) for index, part in enumerate(parts)) for parts in versions)
    if number == 9999:
        raise ValueError("Version space is exhausted at 9.9.9.9")
    return ".".join(str((number + 1) // 10 ** power % 10) for power in (3, 2, 1, 0))


def replace_exact(path: Path, pattern: str, replacement: str, expected: int) -> None:
    original = path.read_text()
    updated, count = re.subn(pattern, replacement, original, flags=re.MULTILINE)
    if count != expected:
        raise ValueError(f"{path}: expected {expected} replacements, found {count}")
    path.write_text(updated)


def set_version(value: str) -> None:
    parts = digits(value)
    build = str(sum(part * 10 ** (3 - index) for index, part in enumerate(parts)))
    replace_exact(SPEC, r"^(\s*MARKETING_VERSION:\s*)\S+(\s*)$", rf"\g<1>{value}\g<2>", 1)
    replace_exact(SPEC, r"^(\s*CURRENT_PROJECT_VERSION:\s*)\S+(\s*)$", rf"\g<1>{build}\g<2>", 1)
    text = PROJECT.read_text()
    marketing_count = len(re.findall(r"(?m)^\s*MARKETING_VERSION = [^;]+;", text))
    build_count = len(re.findall(r"(?m)^\s*CURRENT_PROJECT_VERSION = [^;]+;", text))
    if not marketing_count or not build_count:
        raise ValueError(f"Missing version settings in {PROJECT}")
    replace_exact(PROJECT, r"^(\s*MARKETING_VERSION = )[^;]+(;)$", rf"\g<1>{value}\g<2>", marketing_count)
    replace_exact(PROJECT, r"^(\s*CURRENT_PROJECT_VERSION = )[^;]+(;)$", rf"\g<1>{build}\g<2>", build_count)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("current", "next", "set"))
    parser.add_argument("version", nargs="?")
    args = parser.parse_args()
    if args.action == "current":
        print(current())
    elif args.action == "next":
        print(next_version(current(), sys.stdin.read().splitlines()))
    elif args.version:
        set_version(args.version)
    else:
        parser.error("set requires a version")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        sys.exit(str(error))
