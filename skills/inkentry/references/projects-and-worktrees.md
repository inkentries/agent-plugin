# Projects, worktrees and the local server

### Status & registry

```bash
inkentry status --format text|json|jsonl   # index health, machine-readable
inkentry status                 # index health for current project
inkentry status --all           # all registered projects
inkentry status --list          # one-line table
inkentry status --format json   # machine-readable output

inkentry autoclean              # remove stale registry entries (deleted/moved projects)
inkentry link <path>            # include another project's index in searches
inkentry unlink <path>
```

---

### Git worktrees

Read/query commands (`context`, `search`, `memory list`,
`memory show`, `plumbing graph-edges`, `status`) run from a linked worktree resolve to the
main worktree's shared index automatically, with no setup step. Nothing is
written into the worktree:

```bash
git worktree add ../my-feature my-feature-branch
cd ../my-feature
inkentry context    # resolves to the main worktree's index; no init needed
```

`memory add` is a write, not a read/query command, but it resolves the same
way: an entry recorded from a linked worktree lands in the main worktree's
shared `<main-worktree>/.inkentry/memory.db`, and its git-notes write-through
appends to the repo's shared `refs/notes/inkentry`. There is no separate
per-worktree memory store, so recording memory from a worktree needs no setup
and stays in one place.

`inkentry index .` from a worktree is optional. Run it only to refresh the
shared index with files you changed in that worktree; it re-indexes into the
shared `<main-worktree>/.inkentry/index.db`.

`inkentry autoclean` prunes stale registry entries (e.g. after a worktree or
project directory is removed). It does not write to or clean anything inside
the worktree.

---

### Server daemon

```bash
inkentry server start           # start the local daemon (idempotent; auto-binds 127.0.0.1:4655)
inkentry server status          # PID, port, instance id, uptime
inkentry server logs            # last 50 lines of the server log
inkentry server stop            # stop the daemon (SIGTERM)
```

State lives under `~/.local/state/inkentry/` (`server.pid`, `server.port`, `server.instance_id`, `server.log`).
