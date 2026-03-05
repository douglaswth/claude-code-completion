# claude-code-completion

Shell completion for the `claude` CLI ([Claude Code](https://claude.ai/code)). Provides **bash** and **PowerShell** tab-completion.

## Features

Both shells share the same core capabilities:

- **Dynamic help parsing** — extracts flags and subcommands from `claude --help` at completion time, so completions stay current across CLI updates
- **Version-based caching** — parsed help output is cached per CLI version; old versions are cleaned up automatically
- **Smart flag completions** — context-aware values for `--model`, `--permission-mode`, `--output-format`, `--input-format`, `--effort`, and more
- **Session resume** — `--resume` completes session IDs with message previews from your current project
- **MCP server names** — `claude mcp get/remove` completes server names from `claude mcp list`
- **Plugin names** — `claude plugin enable/disable/uninstall` completes installed plugin names

### Bash

- Cache stored at `$XDG_CACHE_HOME/claude-code-completion/bash/<version>/`
- Optional `jq` dependency for session JSONL parsing, with a `grep`/`sed` fallback

### PowerShell

- **Rich tooltips** — completion results include descriptive tooltips shown by PowerShell's completion UI
- **Built-in JSON parsing** — uses `ConvertFrom-Json` natively, no `jq` dependency needed
- **Cross-platform** — supports PowerShell 5.1 (Windows) and PowerShell 7+ (Windows, macOS, Linux)

## Installation

### Bash

#### Option 1: Source from repo

Add to your `~/.bashrc`:

```bash
source /path/to/claude-code-completion/claude.bash
```

#### Option 2: User-local install

```bash
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
cp claude.bash "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/claude"
```

#### Option 3: System-wide install

```bash
sudo cp claude.bash /usr/share/bash-completion/completions/claude
```

### PowerShell

Add to your PowerShell profile (`$PROFILE`):

```powershell
. /path/to/claude-code-completion/claude.ps1
```

To find or create your profile file:

```powershell
# Show the profile path
$PROFILE

# Create it if it doesn't exist
if (!(Test-Path $PROFILE)) { New-Item -Path $PROFILE -Force }

# Open it for editing
notepad $PROFILE   # Windows
code $PROFILE      # VS Code on any platform
```

## Usage

After installation, press `Tab` to complete:

### Bash

```
claude <TAB>           # subcommands (auth, mcp, plugin, ...)
claude -<TAB>          # flags (--model, --resume, --print, ...)
claude --model <TAB>   # model names (sonnet, opus, haiku, ...)
claude --resume <TAB>  # session IDs with message previews
claude mcp <TAB>       # mcp subcommands (add, get, list, remove)
claude mcp get <TAB>   # configured MCP server names
```

### PowerShell

```powershell
claude <Tab>           # subcommands with tooltip descriptions
claude -<Tab>          # flags with tooltip descriptions
claude --model <Tab>   # model names (sonnet, opus, haiku, ...)
claude --resume <Tab>  # session IDs with message previews
claude mcp <Tab>       # mcp subcommands (add, get, list, remove)
claude mcp get <Tab>   # configured MCP server names
```

## Testing

Both shells have comprehensive test suites that use mock `claude` commands to avoid requiring a real installation.

### Bash

Tests use [bashunit](https://bashunit.typeddevs.com/) in `tests/`:

```bash
# Run all tests
bashunit tests/

# Run a single test file
bashunit tests/completion_test.bash

# Run with coverage
bashunit tests/ --coverage --coverage-paths claude.bash
```

Shared test infrastructure lives in `tests/bootstrap.bash`.

### PowerShell

Tests use [Pester](https://pester.dev/) in `tests/powershell/`:

```powershell
# Run all tests
Invoke-Pester tests/powershell/ -Output Detailed

# Run a single test file
Invoke-Pester tests/powershell/Completion.Tests.ps1 -Output Detailed
```

Shared test infrastructure lives in `tests/powershell/TestHelper.ps1`.

### Prerequisites

- [bashunit](https://bashunit.typeddevs.com/installation) (for bash tests)
- [Pester](https://pester.dev/docs/introduction/installation) v5+ (for PowerShell tests)
