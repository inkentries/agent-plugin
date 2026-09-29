#!/bin/sh
# Shared by every hook; sourced, never run.
#
# A hook must never fail the agent's action, so nothing here exits non-zero,
# and every caller installs `trap 'exit 0' EXIT` before sourcing this file.
# Each function that can fail returns non-zero and the caller exits 0.
#
# JSON is parsed with python3, since jq is not guaranteed. Without python3 (or
# without inkentry) `hook_init` fails and the hook does nothing.

# Reads the hook input from stdin. Not folded into `hook_init`, which callers
# may need to run after inspecting the input themselves.
hook_read() {
  HOOK_INPUT=$(cat) || return 1
  [ -n "$HOOK_INPUT" ]
}

# Declares the caller, moves to the project directory and checks that there is
# something to talk to. Needs HOOK_INPUT.
hook_init() {
  command -v python3 >/dev/null 2>&1 || return 1
  command -v inkentry >/dev/null 2>&1 || return 1

  SESSION_ID=$(json_get session_id)
  SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_-' '_')
  [ -n "$SESSION_ID" ] || return 1

  dir=$(json_get cwd)
  [ -n "$dir" ] || dir=${CLAUDE_PROJECT_DIR:-$PWD}
  cd "$dir" 2>/dev/null || return 1
  in_inkentry_project "$dir" || return 1

  # Hooks are the automatic caller. The agent's own commands are declared
  # `explicit` in the session's env file instead.
  INKENTRY_TRIGGER=hook
  INKENTRY_ACTOR=agent
  INKENTRY_TOOL=claude-code
  INKENTRY_SESSION_REF=$SESSION_ID
  export INKENTRY_TRIGGER INKENTRY_ACTOR INKENTRY_TOOL INKENTRY_SESSION_REF
}

# Prints the scalar at a dotted path in the hook input, or nothing.
json_get() {
  printf '%s' "$HOOK_INPUT" | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        v = v[k]
except Exception:
    sys.exit(0)
if isinstance(v, bool):
    print("true" if v else "false")
elif isinstance(v, (str, int, float)):
    print(v)
' "$1"
}

# inkentry finds its project by walking up from the main worktree root looking
# for a `.inkentry` directory, so a linked worktree resolves to the main one.
in_inkentry_project() {
  has_inkentry_above "$1" && return 0
  common=$(cd "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || return 1
  [ -n "$common" ] || return 1
  main=$(cd "$1" && cd "$common" 2>/dev/null && pwd -P) || return 1
  has_inkentry_above "$(dirname "$main")"
}

has_inkentry_above() {
  d=$1
  while [ -n "$d" ]; do
    [ -d "$d/.inkentry" ] && return 0
    parent=$(dirname "$d")
    [ "$parent" = "$d" ] && return 1
    d=$parent
  done
  return 1
}

# Per-session state: one line per fact, matched whole. Lives in the plugin's
# persistent data directory, never in CLAUDE_PLUGIN_ROOT, which changes on
# update. Outside Claude Code it falls back to a per-user directory in TMPDIR.
hook_state_init() {
  base=${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/inkentry-agent-hooks-$(id -u)}
  (umask 077 && mkdir -p "$base/sessions") 2>/dev/null || return 1
  STATE=$base/sessions/$SESSION_ID
  (umask 077 && : >> "$STATE") 2>/dev/null || return 1
}

state_has() {
  grep -Fxq -- "$1" "$STATE" 2>/dev/null
}

state_add() {
  printf '%s\n' "$1" >> "$STATE" 2>/dev/null
}

# Reads text on stdin and prints it as the additional context of the named
# hook event. Prints nothing when the text is empty.
emit_context() {
  python3 -c '
import json, sys
text = sys.stdin.read().strip()
if text:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": sys.argv[1], "additionalContext": text}}))
' "$1"
}

# The plugin can be installed before the CLI that has these commands, so each
# hook asks the installed binary rather than assuming a version.
cli_has_file_filter() {
  inkentry memory list --help 2>/dev/null | grep -q -- '--file'
}

cli_has_anchor() {
  inkentry memory anchor --help >/dev/null 2>&1
}

cli_has_reconcile() {
  inkentry memory add --help 2>/dev/null | grep -q -- '--reconcile'
}
