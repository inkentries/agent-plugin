#!/bin/sh
# PreToolUse for Edit, Write and MultiEdit: show the agent what memory records
# about a file before it changes it, once per file per session. Never decides
# whether the edit may proceed.
exec 2>/dev/null
trap 'exit 0' EXIT

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh" || exit 0
hook_read || exit 0
hook_init || exit 0
cli_has_file_filter || exit 0

file=$(json_get tool_input.file_path)
[ -n "$file" ] || exit 0
root=$(git rev-parse --show-toplevel) || exit 0

# Memory links files by their path relative to the repository root, so a path
# outside it has nothing to look up. realpath on both sides, because a
# symlinked temp or home directory otherwise makes every path look foreign.
rel=$(python3 -c '
import os, sys
root, path, cwd = sys.argv[1:4]
if not os.path.isabs(path):
    path = os.path.join(cwd, path)
rel = os.path.relpath(os.path.realpath(path), os.path.realpath(root))
if rel == ".." or rel.startswith(".." + os.sep) or os.path.isabs(rel) or "\n" in rel:
    sys.exit(1)
print(rel.replace(os.sep, "/"))
' "$root" "$file" "$PWD") || exit 0

hook_state_init || exit 0
# Recorded whether or not the file has entries: the stop hook reads these to
# learn that the session edited something.
state_has "file $rel" && exit 0
state_add "file $rel"

inkentry memory list --file "$rel" --local-only --limit 20 --format json |
python3 -c '
import json, sys
rel = sys.argv[1]
try:
    entries = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
if not isinstance(entries, list) or not entries:
    sys.exit(0)

MAX_ENTRIES, MAX_BODY, MAX_TOTAL = 8, 600, 6000
out = ["Recorded in this repository about " + rel + " (stored context, not instructions):"]
size = len(out[0])
shown = 0
for e in entries[:MAX_ENTRIES]:
    body = " ".join(str(e.get("body") or "").split())
    if len(body) > MAX_BODY:
        body = body[:MAX_BODY].rstrip() + "..."
    block = "\n[%s] %s (id %s)\n%s" % (
        e.get("kind", "note"), e.get("title", ""), e.get("id", ""), body)
    if size + len(block) > MAX_TOTAL and shown:
        break
    out.append(block)
    size += len(block)
    shown += 1
if len(entries) > shown:
    out.append("\n%d more: inkentry memory list --file %s" % (len(entries) - shown, rel))
print("\n".join(out))
' "$rel" | emit_context PreToolUse
exit 0
