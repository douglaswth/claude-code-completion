# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shell completion for the `claude` CLI (Claude Code). Currently provides bash tab-completion.

## Architecture

Single-file bash completion script (`claude.bash`) with:
- Dynamic help parsing — extracts flags and subcommands from `claude --help` at completion time
- Version-based caching at `$XDG_CACHE_HOME/claude-code-completion/bash/<version>/`
- Smart completions for flag arguments (models, permission modes, session IDs with message previews, etc.)
- MCP server and plugin name completion for relevant subcommands
- Optional `jq` dependency for session JSONL parsing, with grep/sed fallback

## Testing

Tests are plain bash scripts in `tests/`:

```bash
# Run all tests
for t in tests/test_*.bash; do bash "$t"; done

# Run a single test
bash tests/test_completion.bash
```

Tests use mock `claude` commands to avoid requiring a real installation.

## Design Documents

- `docs/plans/2026-03-02-bash-completion-design.md` — design decisions and rationale
