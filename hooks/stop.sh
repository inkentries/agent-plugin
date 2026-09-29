#!/bin/sh
# Stop: once per session, and only if the session edited a file or committed,
# ask the agent to record what it decided before it stops. This is the one hook
# that may block, and it blocks at most once.
exec 2>/dev/null
trap 'exit 0' EXIT

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh" || exit 0

# Claude Code sets this when the agent is already continuing because a Stop
# hook blocked it. Blocking again would loop.
hook_read || exit 0
[ "$(json_get stop_hook_active)" = true ] && exit 0
hook_init || exit 0

cli_has_reconcile || exit 0
hook_state_init || exit 0
state_has stopped && exit 0
grep -q '^file ' "$STATE" || state_has committed || exit 0

# Marked before the reason is emitted, so a second Stop always passes even if
# this one is interrupted.
state_add stopped

reason=$(cat <<'PROMPT'
Before you stop: if this session made a decision, confirmed a requirement, or rejected an approach, record it now, one entry each, then stop. If nothing qualifies, stop without recording.

inkentry memory add --reconcile --format json --kind <decision|requirement|antipattern> --title "<short noun phrase>" --body "<what, why, what was rejected, what it affects>" --tags <existing tags> --files <repo-relative paths>

Run inkentry memory tags first and reuse a tag. If the write exits 3, read the candidates and repeat it with --supersedes, --relates-to, --contradicts or --distinct-from <id>. The rules are in the Memory section of the inkentry skill.
PROMPT
)

printf '%s' "$reason" | python3 -c '
import json, sys
print(json.dumps({"decision": "block", "reason": sys.stdin.read()}))
'
exit 0
