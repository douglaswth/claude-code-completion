# Bash Completion for Claude Code — Design

## Overview

A single bash completion script (`claude.bash`) providing tab-completion for the `claude` CLI. Dynamically parses help output with version-based caching for performance.

## Architecture

Single monolithic bash script with a `_claude` completion function registered via `complete -F _claude claude`. No external dependencies beyond standard tools; optional `jq` for better JSON parsing.

## Help Parsing & Caching

- On first completion, run `claude --version` and check for cached data
- If cache miss, parse `claude --help` and each subcommand's `--help` to extract:
  - Flags (long/short forms, whether they take arguments — detected by `<value>` in help)
  - Subcommand names and sub-subcommands
- Cache location: `$XDG_CACHE_HOME/claude-code-completion/bash/<version>/`
  - `bash/` prefix reserves space for future shell support (zsh, fish)
  - One file per data type per command level (e.g., `_root_flags`, `mcp_subcommands`)
- Cache invalidation: version-based only. On version change, rebuild cache and delete old version directories within `bash/`

## Completion Logic

### Top-level behavior

- `claude <TAB>` — subcommands only (auth, doctor, install, mcp, plugin, setup-token, update)
- `claude -<TAB>` — flags only
- Same pattern applies within subcommands

### Smart flag completions

| Flag | Completion source |
|------|-------------------|
| `--model` | Merged set: stable aliases (sonnet, opus, haiku) + help-parsed model IDs + hardcoded model list |
| `--permission-mode` | Known choices: acceptEdits, bypassPermissions, default, delegate, dontAsk, plan |
| `--output-format` | text, json, stream-json |
| `--input-format` | text, stream-json |
| `--effort` | low, medium, high |
| `--resume` / `-r` | Session ID completion (see below) |
| `--debug-file`, `--mcp-config`, `--settings`, `--plugin-dir` | File path completion |
| `--add-dir` | Directory-only completion |

### Subcommand-specific completions

- `claude mcp get/remove <name>` — complete MCP server names from `claude mcp list`
- `claude plugin uninstall/enable/disable <name>` — complete plugin names from `claude plugin list`

## Session ID Completion (`--resume`)

1. Encode the current working directory: replace `/` with `-` (e.g., `/home/user/project` becomes `-home-user-project`)
2. List `*.jsonl` files in `~/.claude/projects/<encoded-cwd>/`
3. For each session file, extract metadata:
   - Session ID (UUID from filename)
   - Timestamp of most recent entry
   - First real user message (skip IDE metadata lines containing `<ide_` or `<command-`)
4. Display UUIDs with timestamp and message preview, sorted by most recent first
5. Limit to 10 most recently modified files if many sessions exist

### JSONL parsing

- Prefer `jq` if available (`command -v jq`), fall back to `grep`/`sed`
- JSONL format (one JSON object per line) makes line-based grep viable as fallback
- Top-level `"type"` field values: `queue-operation`, `file-history-snapshot`, `progress`, `user`, `assistant`
- Filter for `{"type":"user"` lines (no space after colon in practice)

## Installation

Three options (all documented):

1. **Source from repo:** `source /path/to/claude-code-completion/claude.bash` in `.bashrc`
2. **User-local install:** copy to `$XDG_DATA_HOME/bash-completion/completions/claude` (defaults to `~/.local/share/bash-completion/completions/claude`)
3. **System-wide install:** copy to `/usr/share/bash-completion/completions/claude`
