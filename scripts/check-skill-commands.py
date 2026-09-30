#!/usr/bin/env python3
"""Fail if the skill or a hook names a command the installed inkentry does not have.

The skill and the CLI ship from different repositories on different cadences,
so nothing else notices when a released CLI drops a command the skill still
tells an agent to run. An agent has no way to tell either: it runs what the
skill says and gets an error it cannot interpret.

Truth comes from the binary, not from a list kept here. `--help` is walked one
level deep, which covers every group the skill uses (`memory add`,
`plumbing graph-edges`, `server start`).

The one list kept here is `scripts/pending-release.json`: commands the skill
and hooks name before the release that adds them ships. While the installed
CLI is older than the version listed, a missing command is skipped. Once it is
at or above that version the command must exist, and the entry is stale and
should be deleted.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

SKILL = Path("skills/inkentry/SKILL.md")
HOOKS = Path("hooks/hooks.json")
PENDING = Path("scripts/pending-release.json")


def subcommands(path: list[str]) -> set[str]:
    """Names clap lists under `inkentry <path> --help`."""
    out = subprocess.run(
        ["inkentry", *path, "--help"], capture_output=True, text=True
    )
    if out.returncode != 0:
        return set()
    names, in_commands = set(), False
    for line in out.stdout.splitlines():
        if re.match(r"^\s*(Commands|SUBCOMMANDS):", line):
            in_commands = True
            continue
        if in_commands:
            if re.match(r"^\s*\w+.*:\s*$", line) and not line.startswith("  "):
                break
            m = re.match(r"^\s+([a-z][a-z0-9-]*)(?:,\s*[a-z-]+)?\s{2,}\S", line)
            if m:
                names.add(m.group(1))
    return names


# `inkentry` as the command being run, not as a word. Anchored to a shell
# boundary so `git notes --ref=inkentry show HEAD` is git's `show`, not ours,
# and a quoted `"Keeps inkentry self-contained"` is prose in an argument.
# MULTILINE, so a command on any line of a block counts, not only the first.
INVOCATION = re.compile(
    r"(?:^|[|;&]|\$\()[ \t]*(?:[A-Z_][A-Z0-9_]*=\S*[ \t]+)*"
    r"inkentry[ \t]+([a-z][a-z0-9-]*)(?:[ \t]+([a-z][a-z0-9-]*))?",
    re.MULTILINE,
)


def ignored_spans(text: str):
    """Regions the skill marks as deliberately naming dead commands.

    The migration table lists what was removed beside what replaced it. Its
    left column is supposed to name commands the CLI no longer has.
    """
    spans = []
    for m in re.finditer(r"<!--\s*skill-commands:\s*ignore-until-blank-line.*?-->", text):
        end = text.find("\n\n", m.end())
        spans.append((m.start(), len(text) if end == -1 else end))
    return spans


def code_regions(text: str, ignored=()):
    """(source, offset) for every fenced block and inline code span.

    Prose is excluded deliberately. "inkentry is a context retrieval tool" and
    "inkentry uses the best ranking available" are English sentences, and a
    guard that reports them is a guard someone deletes.
    """
    def suppressed(pos):
        return any(lo <= pos < hi for lo, hi in ignored)

    regions = []
    for m in re.finditer(r"```[a-z]*\n(.*?)```", text, re.DOTALL):
        if not suppressed(m.start(1)):
            regions.append((m.group(1), m.start(1)))
    for m in re.finditer(r"`([^`\n]+)`", text):
        if not suppressed(m.start(1)):
            regions.append((m.group(1), m.start(1)))
    return regions


def classify(first, second, offset, top, groups):
    if first not in top:
        return [(first, offset)]
    # Only judge the second word when the first really is a group:
    # `inkentry search authentication` has a query there, not a subcommand.
    if second and groups.get(first) and second not in groups[first]:
        return [(f"{first} {second}", offset)]
    return []


def parse_version(text: str):
    """(major, minor, patch, is_release) from any text holding x.y.z, or None.

    A prerelease sorts below its release, so 1.2.0-rc1 is still "before 1.2.0".
    """
    m = re.search(r"(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.-]+)?", text)
    if not m:
        return None
    return (int(m[1]), int(m[2]), int(m[3]), 0 if m[4] else 1)


def pending_commands(installed) -> dict[str, str]:
    """Commands not yet released, mapped to the version that adds them.

    Empty when the installed version cannot be read, so an unknown version
    never hides a missing command.
    """
    if not PENDING.exists() or installed is None:
        return {}
    listed = json.loads(PENDING.read_text())
    return {
        name: since
        for name, since in listed.items()
        if (target := parse_version(since)) and installed < target
    }


def scanned_files():
    """(path, text, regions) for every file whose commands are checked."""
    text = SKILL.read_text()
    yield SKILL, text, code_regions(text, ignored_spans(text))
    # Each hook command is a shell line of its own, so one per line here and
    # the line reported is the hook's position in the file.
    commands = [
        hook["command"]
        for groups in json.loads(HOOKS.read_text())["hooks"].values()
        for group in groups
        for hook in group["hooks"]
    ]
    text = "\n".join(commands)
    yield HOOKS, text, [(text, 0)]


def main() -> int:
    top = subcommands([])
    if not top:
        print("could not read `inkentry --help`; is the CLI installed?", file=sys.stderr)
        return 2
    groups = {name: subcommands([name]) for name in top}
    installed = parse_version(version())
    pending = pending_commands(installed)

    unknown, skipped = [], set()
    for path, text, regions in scanned_files():
        for chunk, base in regions:
            for m in re.finditer(INVOCATION, chunk):
                first, second = m.group(1), m.group(2)
                offset = base + m.start()
                for name, at in classify(first, second, offset, top, groups):
                    if name in pending:
                        skipped.add(name)
                    else:
                        unknown.append((path, name, text.count("\n", 0, at) + 1))

    if unknown:
        print("commands named that the installed inkentry does not have:\n", file=sys.stderr)
        for path, name, line in unknown:
            print(f"  {path}:{line}: inkentry {name}", file=sys.stderr)
        print(
            "\nThe CLI moved and the skill did not. Fix the skill or the hook, or "
            "the agent will run a command that no longer exists.",
            file=sys.stderr,
        )
        return 1

    for name in sorted(skipped):
        print(f"skipped: inkentry {name} arrives in {pending[name]}, installed is {version()}")
    stale = stale_entries(top, groups, installed)
    for name, since in stale:
        print(
            f"stale: scripts/pending-release.json lists inkentry {name} for {since}, "
            "and the installed CLI already has it; delete the entry",
            file=sys.stderr,
        )

    print(
        f"ok: every command {SKILL} and {HOOKS} name "
        f"resolves against inkentry {version()}"
    )
    return 0


def stale_entries(top, groups, installed):
    """Entries whose release has shipped and whose command the CLI has."""
    if not PENDING.exists() or installed is None:
        return []
    stale = []
    for name, since in json.loads(PENDING.read_text()).items():
        target = parse_version(since)
        first, _, second = name.partition(" ")
        if target and installed >= target and first in top and second in groups.get(first, ()):
            stale.append((name, since))
    return stale


def version() -> str:
    out = subprocess.run(["inkentry", "--version"], capture_output=True, text=True)
    return out.stdout.strip() or "(unknown)"


if __name__ == "__main__":
    sys.exit(main())
