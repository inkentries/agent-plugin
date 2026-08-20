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

## Why CI installs the CLI

The skill names commands. The CLI that has them ships from another repository
on another cadence, so this repository can go stale while nothing here changes.
`scripts/check-skill-commands.py` walks the installed binary's `--help` and
fails if the skill names anything it does not have. It runs on every change and
weekly, because the change that breaks this repository usually happens in the
other one.
