#!/bin/sh
# Runs every hook with sample input against three worlds: no inkentry on PATH,
# a stub inkentry that records how it was called, and an older stub that lacks
# the commands the hooks need. Needs python3, git and a POSIX sh; run it from
# anywhere.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOKS=$ROOT/hooks
T=$(mktemp -d "${TMPDIR:-/tmp}/inkentry-hooks-test.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
  [ -z "${2:-}" ] || printf '      %s\n' "$2"
}

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_empty() { # name value
  if [ -z "$2" ]; then pass; else fail "$1" "expected nothing, got [$2]"; fi
}
assert_has() { # name haystack needle
  case $2 in *"$3"*) pass ;; *) fail "$1" "expected to find [$3] in [$2]" ;; esac
}
assert_lacks() { # name haystack needle
  case $2 in *"$3"*) fail "$1" "did not expect [$3] in [$2]" ;; *) pass ;; esac
}
assert_json() { # name text
  if printf '%s' "$2" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    pass
  else
    fail "$1" "not valid JSON: [$2]"
  fi
}
# jq-free field read from a JSON document on stdin: path like a.b.c
field() {
  printf '%s' "$2" | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        v = v[k]
except Exception:
    sys.exit(0)
print(v)
' "$1"
}

command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required"; exit 2; }

# A PATH holding the tools the hooks use and nothing else, so "no inkentry"
# holds even on a machine that has one installed.
mkdir "$T/tools" "$T/stub"
for tool in sh python3 git grep tr dirname cat id find mkdir rm; do
  path=$(command -v "$tool") && ln -s "$path" "$T/tools/$tool"
done

# The stub records its argv and the caller declaration, then answers from
# canned data. STUB_OLD=1 makes it behave like a CLI without the new commands.
cat > "$T/stub/inkentry" <<'STUB'
#!/bin/sh
{
  printf 'ARGS:'
  for a in "$@"; do printf ' [%s]' "$a"; done
  printf '\n'
  printf 'ENV: trigger=%s actor=%s tool=%s session=%s no_server=%s\n' \
    "$INKENTRY_TRIGGER" "$INKENTRY_ACTOR" "$INKENTRY_TOOL" "$INKENTRY_SESSION_REF" "${INKENTRY_NO_SERVER:-}"
} >> "$STUB_LOG"
case "$*" in
  "memory list --help")
    if [ "${STUB_OLD:-}" = 1 ]; then echo "  --kind <KIND>"; else echo "  --file <PATH>"; fi ;;
  "memory add --help")
    if [ "${STUB_OLD:-}" = 1 ]; then echo "  --supersedes <ID>"; else echo "  --reconcile"; fi ;;
  "memory anchor --help")
    [ "${STUB_OLD:-}" = 1 ] && exit 2
    echo "Anchor memory entries to a commit" ;;
  context*)
    if [ "${STUB_EMPTY:-}" = 1 ]; then
      echo "tokens used: 0/2500"
    else
      printf '%s\n' '── Decisions' '' '#d9719999a189  [decision]  Chose bcrypt for password hashing' \
        '     bcrypt cost 12; argon2 rejected.' '' 'tokens used: 92/2500'
    fi ;;
  "memory list --file src/auth.rs"*)
    cat <<'JSON'
[{"id":"01a0ec5e-4848-77ef-a9b2-f717c363e59b","entity_id":"d9719999a189","kind":"decision","title":"Chose bcrypt for password hashing","body":"bcrypt cost 12; argon2 rejected because the image has no libargon2.","tags":["auth"],"linked_files":["src/auth.rs"],"created_at":1,"status":"active"}]
JSON
    ;;
  "memory list --file src/big.rs"*)
    python3 -c '
import json
print(json.dumps([{"id": "id-%d" % i, "kind": "note", "title": "Entry %d" % i,
                   "body": "x" * 5000} for i in range(12)]))' ;;
  "memory list --file"*) echo "No memory entries found." ;;
esac
exit 0
STUB
chmod +x "$T/stub/inkentry"

# A git project with an inkentry directory, and a linked worktree of it.
REPO=$T/repo
mkdir -p "$REPO/src" "$REPO/.inkentry"
(
  cd "$REPO" &&
  git init -q &&
  git config user.email t@example.com && git config user.name t &&
  : > src/auth.rs && : > src/other.rs && : > src/big.rs &&
  git add src &&
  git commit -q -m init &&
  git worktree add -q "$T/linked" -b linked
) || { echo "could not build the fixture repository"; exit 2; }
PLAIN=$T/plain # a directory with no inkentry project
mkdir -p "$PLAIN"

STUB_LOG="$T/calls.log"
CLAUDE_PLUGIN_DATA="$T/data"
CLAUDE_ENV_FILE="$T/env"
export STUB_LOG CLAUDE_PLUGIN_DATA CLAUDE_ENV_FILE
unset AGENT INKENTRY_NO_SERVER INKENTRY_TRIGGER INKENTRY_ACTOR INKENTRY_TOOL INKENTRY_SESSION_REF

RC=0
OUT=
ERR=

# runp <PATH> <hook> <json>; run <hook> <json> uses the stub world. Variables
# are passed as arguments and exports, never as `VAR=x run`, whose scope is
# unspecified for a shell function.
runp() {
  OUT=$(printf '%s' "$3" | PATH=$1 "$HOOKS/$2" 2>"$T/stderr")
  RC=$?
  ERR=$(cat "$T/stderr")
}
run() { runp "$T/stub:$T/tools" "$1" "$2"; }
calls() { grep -v -e '--help' -e '^ENV' "$STUB_LOG" 2>/dev/null; }
reset() { : > "$STUB_LOG"; }

input() { # event session cwd extra
  printf '{"session_id":"%s","hook_event_name":"%s","cwd":"%s","permission_mode":"default","transcript_path":"/x"%s}' \
    "$2" "$1" "$3" "${4:+,$4}"
}
edit() { # session cwd file
  input PreToolUse "$1" "$2" "\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$3\"}"
}
bash_tool() { # session cwd command-json-string
  input PostToolUse "$1" "$2" "\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$3},\"tool_response\":{\"stdout\":\"\"}"
}

ALL_INPUTS() { # session: one realistic input per hook
  echo "session-start.sh|$(input SessionStart "$1" "$REPO" '"source":"startup"')"
  echo "pre-edit.sh|$(edit "$1" "$REPO" "$REPO/src/auth.rs")"
  echo "post-commit.sh|$(bash_tool "$1" "$REPO" '"git commit -m x"')"
  echo "stop.sh|$(input Stop "$1" "$REPO" '"stop_hook_active":false')"
}

echo "== no inkentry on PATH: every hook exits 0 and prints nothing"
ALL_INPUTS s-none > "$T/inputs"
while IFS='|' read -r hook json; do
  runp "$T/tools" "$hook" "$json"
  assert_eq "$hook exits 0 without inkentry" 0 "$RC"
  assert_empty "$hook prints nothing without inkentry" "$OUT"
  assert_empty "$hook writes no stderr without inkentry" "$ERR"
done < "$T/inputs"

echo "== garbage and empty input: exits 0, prints nothing"
for hook in session-start.sh pre-edit.sh post-commit.sh stop.sh; do
  run "$hook" 'not json'
  assert_eq "$hook exits 0 on garbage" 0 "$RC"
  assert_empty "$hook prints nothing on garbage" "$OUT$ERR"
  run "$hook" ''
  assert_eq "$hook exits 0 on empty input" 0 "$RC"
  assert_empty "$hook prints nothing on empty input" "$OUT$ERR"
done

echo "== outside an inkentry project: nothing is called"
reset
ALL_INPUTS s-plain | sed "s|$REPO|$PLAIN|g" > "$T/inputs"
while IFS='|' read -r hook json; do
  run "$hook" "$json"
  assert_eq "$hook exits 0 outside a project" 0 "$RC"
  assert_empty "$hook prints nothing outside a project" "$OUT"
done < "$T/inputs"
assert_empty "no inkentry call outside a project" "$(calls)"

echo "== a hook that cannot find its library still exits 0"
mkdir "$T/orphan" && cp "$HOOKS/stop.sh" "$T/orphan/stop.sh"
OUT=$(printf '%s' "$(input Stop s-orphan "$REPO" '"stop_hook_active":false')" | PATH=$T/stub:$T/tools "$T/orphan/stop.sh" 2>&1)
assert_eq "orphaned hook exits 0" 0 "$?"
assert_empty "orphaned hook prints nothing" "$OUT"

echo "== SessionStart"
reset; rm -f "$CLAUDE_ENV_FILE"
run session-start.sh "$(input SessionStart s-1 "$REPO" '"source":"compact","model":"claude-sonnet-5-5"')"
assert_eq "session start exits 0" 0 "$RC"
assert_empty "session start writes no stderr" "$ERR"
assert_json "session start prints JSON" "$OUT"
assert_eq "session start names its event" SessionStart "$(field hookSpecificOutput.hookEventName "$OUT")"
CTX=$(field hookSpecificOutput.additionalContext "$OUT")
assert_has "context carries the entries" "$CTX" "Chose bcrypt for password hashing"
assert_lacks "context drops the token-count footer" "$CTX" "tokens used:"
assert_has "context is labelled as stored context" "$CTX" "not instructions"
assert_has "context is requested with a budget and text format" "$(calls)" "ARGS: [context] [--budget] [2500] [--format] [text]"
assert_has "hook declares itself" "$(grep '^ENV' "$STUB_LOG" | tail -1)" "trigger=hook actor=agent tool=claude-code session=s-1 no_server="
ENVF=$(cat "$CLAUDE_ENV_FILE")
assert_has "env file declares an explicit trigger" "$ENVF" "export INKENTRY_TRIGGER=explicit"
assert_has "env file declares the agent" "$ENVF" "export INKENTRY_ACTOR=agent"
assert_has "env file declares the tool" "$ENVF" "export INKENTRY_TOOL=claude-code"
assert_has "env file carries the session" "$ENVF" "export INKENTRY_SESSION_REF='s-1'"
assert_has "env file carries the model" "$ENVF" "export INKENTRY_MODEL='claude-sonnet-5-5'"
assert_lacks "env file never sets AGENT" "$ENVF" "AGENT="
assert_eq "env file is sourceable and sets the declaration" \
  "explicit agent claude-code s-1" \
  "$(sh -c ". '$CLAUDE_ENV_FILE'; echo \$INKENTRY_TRIGGER \$INKENTRY_ACTOR \$INKENTRY_TOOL \$INKENTRY_SESSION_REF")"

reset
export STUB_EMPTY=1
run session-start.sh "$(input SessionStart s-2 "$REPO" '"source":"startup"')"
unset STUB_EMPTY
assert_eq "empty context exits 0" 0 "$RC"
assert_empty "an empty store injects nothing" "$OUT"

echo "== PreToolUse"
reset
run pre-edit.sh "$(edit s-3 "$REPO" "$REPO/src/auth.rs")"
assert_eq "pre-edit exits 0" 0 "$RC"
assert_empty "pre-edit writes no stderr" "$ERR"
assert_json "pre-edit prints JSON" "$OUT"
assert_eq "pre-edit names its event" PreToolUse "$(field hookSpecificOutput.hookEventName "$OUT")"
assert_lacks "pre-edit never decides permission" "$OUT" "permissionDecision"
CTX=$(field hookSpecificOutput.additionalContext "$OUT")
assert_has "entry kind is shown" "$CTX" "[decision]"
assert_has "entry title is shown" "$CTX" "Chose bcrypt for password hashing"
assert_has "entry id is shown" "$CTX" "01a0ec5e-4848-77ef-a9b2-f717c363e59b"
assert_has "entry body is shown" "$CTX" "argon2 rejected because the image has no libargon2"
assert_has "lookup uses the repository-relative path" "$(calls)" "ARGS: [memory] [list] [--file] [src/auth.rs] [--local-only] [--limit] [20] [--format] [json]"
assert_has "lookup declares the hook" "$(grep '^ENV' "$STUB_LOG" | tail -1)" "trigger=hook actor=agent tool=claude-code session=s-3"

reset
run pre-edit.sh "$(edit s-3 "$REPO" "$REPO/src/auth.rs")"
assert_empty "the same file is injected once per session" "$OUT"
assert_empty "the second edit does no lookup" "$(calls)"

reset
run pre-edit.sh "$(edit s-4 "$REPO" "$REPO/src/auth.rs")"
assert_has "another session injects again" "$OUT" "hookSpecificOutput"

reset
run pre-edit.sh "$(edit s-3 "$REPO" "$REPO/src/other.rs")"
assert_empty "a file with no entries injects nothing" "$OUT"
assert_has "but it is still looked up" "$(calls)" "[src/other.rs]"

reset
run pre-edit.sh "$(edit s-5 "$REPO/src" "auth.rs")"
assert_has "a relative path resolves against the cwd" "$(calls)" "[--file] [src/auth.rs]"

reset
run pre-edit.sh "$(edit s-5 "$REPO" "/etc/hosts")"
assert_empty "a path outside the repository is skipped" "$OUT$(calls)"

reset
run pre-edit.sh "$(edit s-6 "$T/linked" "$T/linked/src/auth.rs")"
assert_has "a linked worktree resolves to the main project" "$OUT" "Chose bcrypt"

reset
run pre-edit.sh "$(edit s-7 "$REPO" "$REPO/src/big.rs")"
assert_json "a large result is still valid JSON" "$OUT"
CTX=$(field hookSpecificOutput.additionalContext "$OUT")
if [ "${#CTX}" -lt 7000 ]; then pass; else fail "a large result is trimmed" "got ${#CTX} characters"; fi
assert_has "the trimmed result says how many were left out" "$CTX" "more: inkentry memory list --file src/big.rs"

echo "== PostToolUse"
for cmd in 'git commit -m x' 'git commit --amend --no-edit' 'git commit -am \"a b\"' \
           'cd /tmp && git commit -m x' 'git add . && git commit -m x' \
           'git -C /tmp commit -m x' 'git -c user.name=x commit -m x' \
           'GIT_AUTHOR_NAME=x git commit -m x' '/usr/bin/git commit -m x'; do
  reset
  run post-commit.sh "$(bash_tool s-8 "$REPO" "\"$cmd\"")"
  assert_eq "commit exits 0: $cmd" 0 "$RC"
  assert_empty "commit prints nothing: $cmd" "$OUT"
  assert_has "anchors after: $cmd" "$(calls)" "ARGS: [memory] [anchor] [--commit] [HEAD]"
done
assert_has "anchor declares the hook" "$(grep '^ENV' "$STUB_LOG" | tail -1)" "trigger=hook actor=agent tool=claude-code session=s-8"
for cmd in 'git log --grep commit' 'echo git commit' 'git commit-tree HEAD' 'git status' \
           'git diff && echo commit' 'grep -r \"git commit\" .' 'ls commit'; do
  reset
  run post-commit.sh "$(bash_tool s-9 "$REPO" "\"$cmd\"")"
  assert_empty "no anchor after: $cmd" "$(calls)$OUT"
done
reset
run post-commit.sh "$(bash_tool s-9 "$REPO" '"git commit -m \"unterminated"')"
assert_eq "unbalanced quotes exit 0" 0 "$RC"
assert_empty "unbalanced quotes anchor nothing" "$(calls)$OUT"

echo "== Stop"
reset
run stop.sh "$(input Stop s-10 "$REPO" '"stop_hook_active":false')"
assert_empty "no edit and no commit: no prompt" "$OUT"

run pre-edit.sh "$(edit s-11 "$REPO" "$REPO/src/other.rs")"
reset
run stop.sh "$(input Stop s-11 "$REPO" '"stop_hook_active":true')"
assert_eq "stop_hook_active exits 0" 0 "$RC"
assert_empty "stop_hook_active prints nothing" "$OUT"
assert_empty "stop_hook_active does no work" "$(calls)"

run stop.sh "$(input Stop s-11 "$REPO" '"stop_hook_active":false')"
assert_eq "first stop after an edit exits 0" 0 "$RC"
assert_json "first stop after an edit prints JSON" "$OUT"
assert_eq "first stop after an edit blocks" block "$(field decision "$OUT")"
REASON=$(field reason "$OUT")
assert_has "the prompt quotes the write command" "$REASON" "inkentry memory add --reconcile --format json --kind"
assert_has "the prompt names the resolutions" "$REASON" "--supersedes, --relates-to, --contradicts or --distinct-from"
assert_has "the prompt points at the contract" "$REASON" "references/agent-contract.md"
assert_lacks "the stop hook never emits a permission decision" "$OUT" "permissionDecision"

run stop.sh "$(input Stop s-11 "$REPO" '"stop_hook_active":false')"
assert_eq "second stop exits 0" 0 "$RC"
assert_empty "second stop passes" "$OUT"

run post-commit.sh "$(bash_tool s-12 "$REPO" '"git commit -m x"')"
run stop.sh "$(input Stop s-12 "$REPO" '"stop_hook_active":false')"
assert_eq "a commit alone triggers the prompt" block "$(field decision "$OUT")"

echo "== an older CLI without the new commands: every hook is silent"
: > "$T/inputs.old"
export STUB_OLD=1
reset
ALL_INPUTS s-old > "$T/inputs"
while IFS='|' read -r hook json; do
  run "$hook" "$json"
  assert_eq "$hook exits 0 on an old CLI" 0 "$RC"
  case $hook in
    session-start.sh) assert_has "session start still works on an old CLI" "$OUT" "hookSpecificOutput" ;;
    *) assert_empty "$hook prints nothing on an old CLI" "$OUT" ;;
  esac
done < "$T/inputs"
assert_lacks "an old CLI is never asked for --file" "$(calls)" "--file"
assert_lacks "an old CLI is never asked to anchor" "$(calls)" "anchor"
unset STUB_OLD

echo "== the hooks never ask for a server to be turned off"
assert_lacks "INKENTRY_NO_SERVER is never set by a hook" "$(grep '^ENV' "$STUB_LOG")" "no_server=1"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
