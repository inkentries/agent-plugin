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
write memory without the agent having to remember to. The plugin only wires the
events: each hook is one call to `inkentry hooks agent <event>`, and everything
it does lives in the CLI. So the hooks need nothing but the CLI itself, run
wherever it runs, and need inkentry 1.2.0.

| Event | Command | What it does |
|---|---|---|
| `SessionStart`, every source including `compact` | `inkentry hooks agent session-start` | Adds the project's recorded context to the agent's context, and declares the agent as the caller for the commands it runs itself. |
| `PreToolUse` on `Edit`, `Write`, `MultiEdit` | `inkentry hooks agent pre-edit` | Adds the entries linked to the file about to change, once per file per session. Never decides whether the edit may proceed. |
| `PostToolUse` on `Bash` | `inkentry hooks agent post-commit` | After a `git commit`, attaches the entries written on the way to it to that commit. The git post-commit hook does this too, but git hooks are per clone and often absent. |
| `Stop` | `inkentry hooks agent stop` | Once per session, and only if the session edited a file or committed, asks the agent to record what it decided. |

`inkentry hooks agent` always exits 0 and prints nothing when there is nothing
to say, so a hook never fails or blocks an action; the one exception is by
design, the single `Stop` prompt. Each command ends in `|| exit 0` because a
CLI older than 1.2.0 rejects the subcommand with exit status 2, which Claude
Code would read as "block this action". Its behaviour is documented with the
[`inkentry hooks`](https://github.com/inkentries/inkentry/blob/main/docs/commands.md#inkentry-hooks)
command.

To turn the hooks off, uninstall the plugin or set `disableAllHooks` in Claude
Code's settings. There is no per-hook switch.

## Why CI installs the CLI

The skill and the hooks name commands. The CLI that has them ships from another
repository on another cadence, so this repository can go stale while nothing
here changes. `scripts/check-skill-commands.py` walks the installed binary's
`--help` and fails if the skill or `hooks/hooks.json` names anything it does not have. It
runs on every change and weekly, because the change that breaks this repository
usually happens in the other one.

A command the skill names before its release ships is listed in
`scripts/pending-release.json` with the version that adds it. While the
installed CLI is older, a missing command listed there is skipped. From that
version on it fails like any other, and the entry, now stale, should be deleted.
