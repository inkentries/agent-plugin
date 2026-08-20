# Harvest from git history or Claude Code history

```bash
inkentry harvest                    # analyse HEAD~10..HEAD
inkentry harvest --git-range v0.1.0..HEAD
inkentry harvest --branch main      # full branch history
inkentry harvest --source claude-code --confirm  # extract from ~/.claude/history.jsonl
inkentry harvest --source failures  # extract antipatterns from revert/bugfix commits
inkentry harvest --source failures --git-range v0.4.0..HEAD
```


Extracts decisions, requirements, and non-obvious notes. From git, analyzes commit messages.
From `claude-code`, reads agent session transcripts from `~/.claude/history.jsonl`.
Run at the start of a session on a new repo, or after a batch of significant commits.
Requires `llm_model` in config. The `--source claude-code` requires `--confirm` flag.
