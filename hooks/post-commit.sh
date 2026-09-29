#!/bin/sh
# PostToolUse for Bash: after the agent runs `git commit` (or `--amend`), claim
# the commit for the memory entries written on the way to it. The git
# post-commit hook does this too, but git hooks are per clone and often absent.
exec 2>/dev/null
trap 'exit 0' EXIT

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh" || exit 0
hook_read || exit 0
hook_init || exit 0
cli_has_anchor || exit 0

# Matches on the command's words, not its text: `git log --grep commit` and
# `echo git commit` are not commits. Only `git [global options] commit` at the
# start of a command, after `&&`, `||`, `;`, `|` or a shell keyword, counts.
# A commit made through `bash -c` or an alias is not seen; a missed anchor is
# claimed by the next commit or the git hook.
printf '%s' "$HOOK_INPUT" | python3 -c '
import json, shlex, sys

try:
    command = json.load(sys.stdin)["tool_input"]["command"]
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    tokens = list(lexer)
except Exception:
    sys.exit(1)

OPERATORS = set(["&&", "||", ";", "|", "&", "(", ")", ";;"])
KEYWORDS = set(["then", "do", "else", "elif", "if", "while", "until", "!", "{"])
WITH_VALUE = set(["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"])

segments, current = [], []
for token in tokens:
    if token in OPERATORS:
        segments.append(current)
        current = []
    else:
        current.append(token)
segments.append(current)

def is_git_commit(words):
    i = 0
    while i < len(words) and (words[i] in KEYWORDS or ("=" in words[i] and not words[i].startswith("-"))):
        i += 1
    if i >= len(words) or words[i].rsplit("/", 1)[-1] != "git":
        return False
    i += 1
    while i < len(words) and words[i].startswith("-"):
        i += 2 if words[i] in WITH_VALUE else 1
    return i < len(words) and words[i] == "commit"

sys.exit(0 if any(is_git_commit(s) for s in segments) else 1)
' || exit 0

hook_state_init && state_add committed
inkentry memory anchor --commit HEAD
exit 0
