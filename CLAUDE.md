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

Tests use [bashunit](https://bashunit.typeddevs.com/) in `tests/`:

```bash
# Run all tests
bashunit tests/

# Run a single test file
bashunit tests/completion_test.bash

# Run with coverage
bashunit tests/ --coverage --coverage-paths claude.bash
```

Tests use mock `claude` commands to avoid requiring a real installation. Shared test infrastructure lives in `tests/bootstrap.bash`.

### Coverage Review

After adding or changing tests, run coverage and walk through each uncovered area one at a time with the user. For each area, show the uncovered line(s) marked with `✗` in context of the surrounding source code, explain why it's uncovered, and categorize it:

- **False negative** — coverage instrumentation artifact (e.g., `done < file` redirects, string contents passed to other programs, file-scope declarations)
- **Worth testing** — real uncovered logic that should have a test; add to a todo list
- **Skip** — trivial or defensive code not worth the test complexity

Wait for the user's input on each area before moving to the next.

### Prerequisites

- [bashunit](https://bashunit.typeddevs.com/installation)

## Documentation

When making changes that affect usage, testing, or installation instructions, update both `CLAUDE.md` and `README.md` to keep them in sync.

## Design Documents

- `docs/plans/2026-03-02-bash-completion-design.md` — design decisions and rationale
