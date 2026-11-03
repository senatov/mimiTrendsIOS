#!/usr/bin/env python3
"""Select the preceding release and write notes from every intervening commit."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys


VERSION_TAG = re.compile(r"v?([0-9])\.([0-9])\.([0-9])\.([0-9])\Z")
REPOSITORY_URL = "https://github.com/senatov/mimiTrendsIOS"


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args], text=True, capture_output=True, check=check
    )


def version_key(tag: str) -> tuple[int, int, int, int] | None:
    match = VERSION_TAG.fullmatch(tag)
    return tuple(map(int, match.groups())) if match else None


def previous_release(tags: list[str], head: str = "HEAD") -> str:
    candidates: list[tuple[tuple[int, int, int, int], str]] = []
    for tag in tags:
        key = version_key(tag)
        if key is None:
            continue
        if git("rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}", check=False).returncode:
            continue
        if git("merge-base", "--is-ancestor", tag, head, check=False).returncode:
            continue
        candidates.append((key, tag))
    return max(candidates)[1] if candidates else ""


def release_notes(previous: str, current: str) -> str:
    if version_key(current) is None:
        raise ValueError(f"Invalid release tag: {current}")
    if previous and version_key(previous) is None:
        raise ValueError(f"Invalid previous release tag: {previous}")
    if previous and git("merge-base", "--is-ancestor", previous, current, check=False).returncode:
        raise ValueError(f"{previous} is not an ancestor of {current}")

    revision_range = f"{previous}..{current}" if previous else current
    hashes = git("rev-list", "--reverse", revision_range).stdout.splitlines()
    if not hashes:
        raise ValueError(f"No commits found in {revision_range}")

    heading = f"Changes since {previous}" if previous else "Initial release changes"
    lines = [f"# mimiTrends-iOS {current}", "", heading, ""]
    if previous:
        lines.extend([f"[Compare changes]({REPOSITORY_URL}/compare/{previous}...{current})", ""])
    for commit in hashes:
        message = git("show", "-s", "--format=%B", commit).stdout.strip()
        subject, *body = message.splitlines()
        while body and not body[0].strip():
            body.pop(0)
        while body and not body[-1].strip():
            body.pop()
        lines.append(f"- **{subject}** (`{commit[:8]}`)")
        if any(line.strip() for line in body):
            lines.append("")
            lines.extend(f"  > {line}" if line else "  >" for line in body)
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="action", required=True)
    previous_command = subcommands.add_parser("previous")
    previous_command.add_argument("--head", default="HEAD")
    notes_command = subcommands.add_parser("generate")
    notes_command.add_argument("--previous", default="")
    notes_command.add_argument("--current", required=True)
    notes_command.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if args.action == "previous":
        print(previous_release(sys.stdin.read().splitlines(), args.head))
    else:
        args.output.write_text(release_notes(args.previous, args.current))
        print(f"Wrote release notes to {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
