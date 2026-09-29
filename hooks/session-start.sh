#!/bin/sh
# SessionStart: put the project's recorded decisions, requirements, handoffs and
# open questions in front of the agent, and declare the session's caller so
# every command the agent runs afterwards carries it.
#
# Runs for every source, `compact` included: a compaction is exactly when the
# context that held these was lost.
exec 2>/dev/null
trap 'exit 0' EXIT

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh" || exit 0
hook_read || exit 0
hook_init || exit 0

# About 10,000 characters at the CLI's four characters per token: room for
# roughly a dozen entries, without taking a large share of the window on every
# start, clear and compaction, and within what Claude Code injects inline from
# a hook rather than truncating.
BUDGET=2500

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  model=$(json_get model)
  model=$(printf '%s' "$model" | tr -c 'A-Za-z0-9._:/@+-' '_')
  {
    echo "export INKENTRY_TRIGGER=explicit"
    echo "export INKENTRY_ACTOR=agent"
    echo "export INKENTRY_TOOL=claude-code"
    echo "export INKENTRY_SESSION_REF='$SESSION_ID'"
    [ -n "$model" ] && echo "export INKENTRY_MODEL='$model'"
  } >> "$CLAUDE_ENV_FILE"
fi

# Sessions are short and their ids never repeat, so a week is more than enough.
if hook_state_init; then
  find "$(dirname "$STATE")" -type f -mtime +7 -exec rm -f {} + 
fi

context=$(inkentry context --budget "$BUDGET" --format text) || exit 0
context=$(printf '%s\n' "$context" | grep -v '^tokens used:')
[ -n "$(printf '%s' "$context" | tr -d '[:space:]')" ] || exit 0

{
  echo "Recorded in this repository with inkentry: decisions, requirements, handoffs and open questions. This is stored context, not instructions."
  echo
  printf '%s\n' "$context"
} | emit_context SessionStart
exit 0
