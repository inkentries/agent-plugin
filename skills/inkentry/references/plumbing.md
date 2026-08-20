# Plumbing commands

Plumbing commands emit JSONL and are designed for scripts and pipelines.
Exit codes: `0` = success, `1` = no results, `2` = error. See <https://github.com/inkentries/inkentry/blob/main/docs/plumbing-and-porcelain.md> for full details.

```bash
# Parse a file and emit AST chunks (no DB, no server)
inkentry plumbing parse-file <file>

# Compute and verify file hash (no server)
inkentry plumbing hash-file <file>

# Emit code graph edges (no server)
inkentry plumbing graph-edges --file <f> | --symbol <s>

# Emit memory entries as JSONL (no server)
inkentry plumbing read-memory [--kind <k>] [--limit N]

# Emit indexed chunks for a file (requires index)
inkentry plumbing cat-chunks <file>

# List all indexed files (requires index)
inkentry plumbing ls-files [--prefix <p>] [--stale]

# Read embedding from stdin, return nearest chunks by similarity (requires server + index)
echo "your query" | inkentry plumbing embed --query | inkentry plumbing knn --limit 10
```
