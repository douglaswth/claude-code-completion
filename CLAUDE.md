# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shell completion for the `claude` CLI (Claude Code). Provides bash and PowerShell tab-completion.

## Architecture

Two single-file completion scripts (`claude.bash` and `claude.ps1`) sharing the same design:
- Dynamic help parsing — extracts flags and subcommands from `claude --help` at completion time
- Version-based caching per CLI version; old versions are cleaned up automatically
- Smart completions for flag arguments (models, permission modes, session IDs with message previews, etc.)
- MCP server and plugin name completion for relevant subcommands

Bash-specific: optional `jq` dependency for session JSONL parsing, with grep/sed fallback. PowerShell-specific: rich tooltips on completions, built-in JSON parsing via `ConvertFrom-Json`.

## Testing

Tests use mock `claude` commands to avoid requiring a real installation.

### Bash

Tests use [bashunit](https://bashunit.typeddevs.com/) in `tests/bash/`:

```bash
# Run all tests (installs bashunit automatically if needed)
bash tests/bash/run-tests.sh

# Run with coverage
bash tests/bash/run-tests.sh --coverage
```

Shared test infrastructure lives in `tests/bash/bootstrap.bash`.

### PowerShell

Tests use [Pester](https://pester.dev/) v5+ in `tests/powershell/`:

```bash
# Run all tests
./tests/powershell/Invoke-Tests.ps1

# Run with coverage
./tests/powershell/Invoke-Tests.ps1 -Coverage
```

Shared test infrastructure lives in `tests/powershell/TestHelper.ps1`.

### Coverage Review

After adding or changing tests in **either** shell, run coverage for **both** shells and walk through each uncovered area one at a time with the user. For each area, show the uncovered line(s) marked with `✗` in context of the surrounding source code, explain why it's uncovered, and categorize it:

- **False negative** — coverage instrumentation artifact (e.g., `done < file` redirects, string contents passed to other programs, file-scope declarations)
- **Worth testing** — real uncovered logic that should have a test; add to a todo list
- **Skip** — trivial or defensive code not worth the test complexity

Wait for the user's input on each area before moving to the next.

### Prerequisites

- [bashunit](https://bashunit.typeddevs.com/installation) (for bash tests)
- [Pester](https://pester.dev/docs/introduction/installation) v5+ (for PowerShell tests)

## Documentation

When making changes that affect usage, testing, or installation instructions, update both `CLAUDE.md` and `README.md` to keep them in sync.

## Design Documents

- `docs/plans/2026-03-02-bash-completion-design.md` — design decisions and rationale
