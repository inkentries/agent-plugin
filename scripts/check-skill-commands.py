#!/usr/bin/env python3
"""Fail if the skill names a command the installed inkentry does not have.

The skill and the CLI ship from different repositories on different cadences,
so nothing else notices when a released CLI drops a command the skill still
tells an agent to run. An agent has no way to tell either: it runs what the
skill says and gets an error it cannot interpret.

Truth comes from the binary, not from a list kept here. `--help` is walked one
level deep, which covers every group the skill uses (`memory add`,
`plumbing graph-edges`, `server start`).
"""

import re
import subprocess
import sys
from pathlib import Path

SKILL = Path("skills/inkentry/SKILL.md")


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
INVOCATION = re.compile(
    r"(?:^|[|;&]|\$\()[ \t]*(?:[A-Z_][A-Z0-9_]*=\S*[ \t]+)*"
    r"inkentry[ \t]+([a-z][a-z0-9-]*)(?:[ \t]+([a-z][a-z0-9-]*))?"
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


def main() -> int:
    top = subcommands([])
    if not top:
        print("could not read `inkentry --help`; is the CLI installed?", file=sys.stderr)
        return 2
    groups = {name: subcommands([name]) for name in top}

    text = SKILL.read_text()
    unknown = []
    for chunk, base in code_regions(text, ignored_spans(text)):
        for m in re.finditer(INVOCATION, chunk):
            first, second = m.group(1), m.group(2)
            offset = base + m.start()
            unknown.extend(classify(first, second, offset, top, groups))

    if unknown:
        print(f"{SKILL} names commands the installed inkentry does not have:\n", file=sys.stderr)
        for name, offset in unknown:
            line = text.count("\n", 0, offset) + 1
            print(f"  {SKILL}:{line}: inkentry {name}", file=sys.stderr)
        print(
            "\nThe CLI moved and the skill did not. Fix the skill, or the agent "
            "will run a command that no longer exists.",
            file=sys.stderr,
        )
        return 1

    print(f"ok: every command {SKILL} names resolves against inkentry {version()}")
    return 0


def version() -> str:
    out = subprocess.run(["inkentry", "--version"], capture_output=True, text=True)
    return out.stdout.strip() or "(unknown)"


if __name__ == "__main__":
    sys.exit(main())
