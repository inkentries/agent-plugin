# inkentry agent skill

The [inkentry](https://github.com/inkentries/inkentry) skill, packaged to the
[Agent Plugins](https://agent-plugins.org/) standard: a portable `plugin.json`
at the root and the skill under `skills/`.

It ships from here rather than from the CLI repository so that guidance can be
corrected without waiting for a binary release. The two version independently.

## Claude Code

Claude Code reads its own manifest rather than the portable one, so it is
supported alongside the standard rather than through it:

```
/plugin marketplace add inkentries/agent-plugin
/plugin install inkentry@inkentry
```

## Other agents

Agent Plugins 1.0.0 defines the package, not the delivery: distribution and
installation are left to each client. The artifact is this repository, and a
client that implements the standard consumes it the way that client does.

Failing that, [`skills/inkentry/SKILL.md`](skills/inkentry/SKILL.md) is plain
Markdown written for an agent operator, and works as context for any agent that
can run a shell.

## Install the CLI too

The plugin carries guidance, not the binary:

```bash
curl -fsSL https://get.inkentry.com/install.sh | sh
```

```powershell
irm https://get.inkentry.com/install.ps1 | iex
```

The skill checks for this and tells the agent to say so, rather than failing at
a shell call.

## Hooks

For Claude Code the plugin also ships hooks (`hooks/hooks.json`) that read and
write memory without the agent having to remember to. Every hook does nothing
when `inkentry` is not on `PATH` or the directory is not inside an inkentry
project. The file lookup, the anchor and the stop prompt also need inkentry
1.2.0, and each checks the installed CLI with `--help` and does nothing on an
older one; the session start needs only `context`, which older CLIs have.

| Event | What it does |
|---|---|
| `SessionStart`, every source including `compact` | Runs `inkentry context --budget 2500 --format text` and adds the result to the agent's context. Also writes the session's caller declaration to `CLAUDE_ENV_FILE`, so every Bash command the agent runs carries it. |
| `PreToolUse` on `Edit`, `Write`, `MultiEdit` | Looks up `inkentry memory list --file <path>` for the file about to change and adds the entries (id, kind, title, body, trimmed) to the agent's context. Never decides whether the edit may proceed. |
| `PostToolUse` on `Bash` | After a `git commit` (including `--amend`), runs `inkentry memory anchor --commit HEAD`, which claims the commit for the entries written on the way to it. The git post-commit hook does this too, but git hooks are per clone and often absent. |
| `Stop` | Once per session, and only if the session edited a file or committed, asks the agent to record what it decided, quoting the `memory add --reconcile` command and pointing at the contract. If nothing qualifies, the agent just stops. |

None of them needs the inference server: `context`, `memory list --file` and
`memory anchor` read and write the local store.

**They never block or fail an action.** Every hook exits 0 whatever happens,
writes nothing to stderr, and has a timeout (15 s for the session start, 5 s for
the file lookup and the anchor, 2 s for stop). The one exception is by design:
the `Stop` hook blocks once, to deliver its prompt.

**Once per session.** Each file's entries are added the first time the session
edits it, and the stop prompt is delivered once. If `stop_hook_active` is set,
because the agent is already continuing after a block, the stop hook exits
straight away.

**The caller declaration.** Hooks run their own commands with
`INKENTRY_TRIGGER=hook INKENTRY_ACTOR=agent INKENTRY_TOOL=claude-code
INKENTRY_SESSION_REF=<session id>`. The commands the agent itself runs get
`INKENTRY_TRIGGER=explicit` with the same actor, tool and session (and
`INKENTRY_MODEL` when Claude Code reports one), exported through
`CLAUDE_ENV_FILE`. `AGENT=true` is never set.

**Where the state is.** One small file per session, holding which files have
been looked up and whether the stop prompt was delivered, under
`$CLAUDE_PLUGIN_DATA/sessions/`. Outside Claude Code, or when that variable is
missing, it falls back to `$TMPDIR/inkentry-agent-hooks-<uid>/sessions/`. Files
older than a week are removed at session start. Nothing is written to the
repository.

**Requirements.** POSIX `sh` and `git`. The hooks read their JSON input with
`python3` because `jq` is not guaranteed; without `python3` they do nothing.

**Turning them off.** Uninstall the plugin, or set `disableAllHooks` in Claude
Code's settings. There is no per-hook switch.

## The agent contract

`skills/inkentry/references/agent-contract.md` is a verbatim copy of
[`docs/agent-contract.md`](https://github.com/inkentries/inkentry/blob/main/docs/agent-contract.md)
in the CLI repository: what an agent records, when, and how it links each entry.
The first line of the copy names the ref it was taken from, and CI fetches that
file and diffs it against the copy, on every change and weekly, so the two
cannot drift apart silently. It points at `main` for now; when inkentry 1.2.0
ships, pin the source line to that release's tag and copy the file again.

## Why CI installs the CLI

The skill and the hooks name commands. The CLI that has them ships from another
repository on another cadence, so this repository can go stale while nothing
here changes. `scripts/check-skill-commands.py` walks the installed binary's
`--help` and fails if the skill or a hook names anything it does not have. It
runs on every change and weekly, because the change that breaks this repository
usually happens in the other one.

A command the skill names before its release ships is listed in
`scripts/pending-release.json` with the version that adds it. While the
installed CLI is older, a missing command listed there is skipped. From that
version on it fails like any other, and the entry, now stale, should be deleted.
`scripts/test-hooks.sh` runs every hook against a stub CLI and runs in CI too.
