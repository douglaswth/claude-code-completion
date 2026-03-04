# claude-code-completion

Shell completion for the `claude` CLI ([Claude Code](https://claude.ai/code)). Currently provides **bash** tab-completion.

## Features

- **Dynamic help parsing** — extracts flags and subcommands from `claude --help` at completion time, so completions stay current across CLI updates
- **Version-based caching** — parsed help output is cached per CLI version at `$XDG_CACHE_HOME/claude-code-completion/bash/<version>/`; old versions are cleaned up automatically
- **Smart flag completions** — context-aware values for `--model`, `--permission-mode`, `--output-format`, `--input-format`, `--effort`, and more
- **Session resume** — `--resume` completes session IDs with message previews from your current project
- **MCP server names** — `claude mcp get/remove` completes server names from `claude mcp list`
- **Plugin names** — `claude plugin enable/disable/uninstall` completes installed plugin names
- **Optional `jq` dependency** — uses `jq` for session JSONL parsing when available, with a `grep`/`sed` fallback

## Installation

### Option 1: Source from repo

Add to your `~/.bashrc`:

```bash
source /path/to/claude-code-completion/claude.bash
```

### Option 2: User-local install

```bash
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
cp claude.bash "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/claude"
```

### Option 3: System-wide install

```bash
sudo cp claude.bash /usr/share/bash-completion/completions/claude
```

## Usage

After installation, press `Tab` to complete:

```
claude <TAB>           # subcommands (auth, mcp, plugin, ...)
claude -<TAB>          # flags (--model, --resume, --print, ...)
claude --model <TAB>   # model names (sonnet, opus, haiku, ...)
claude --resume <TAB>  # session IDs with message previews
claude mcp <TAB>       # mcp subcommands (add, get, list, remove)
claude mcp get <TAB>   # configured MCP server names
```

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

### Prerequisites

- [bashunit](https://bashunit.typeddevs.com/installation)
