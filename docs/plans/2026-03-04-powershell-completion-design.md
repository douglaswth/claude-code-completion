# PowerShell Completion for Claude Code — Design

## Overview

A single PowerShell script (`claude.ps1`) providing tab-completion for the `claude` CLI. Ports all functionality from the existing `claude.bash` with PowerShell-native enhancements (rich tooltips, built-in JSON parsing). Supports PowerShell 5.1+ (Windows PowerShell) and PowerShell 7+ (cross-platform).

## Architecture

Single `.ps1` script that defines helper functions and registers a native argument completer via `Register-ArgumentCompleter -CommandName claude -Native`. No module packaging — mirrors the `claude.bash` approach.

### Registration

```powershell
Register-ArgumentCompleter -CommandName claude -Native -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    # Returns [System.Management.Automation.CompletionResult] objects
}
```

The `-Native` parameter tells PowerShell this completes a native (non-PowerShell) command. `$commandAst` provides the full command line typed so far.

### CompletionResult Objects

Each completion returns a `[CompletionResult]` with four fields:

| Field | Purpose |
|-------|---------|
| `CompletionText` | What gets inserted |
| `ListItemText` | What appears in the completion menu |
| `ResultType` | `ParameterValue`, `ParameterName`, `Command`, `Text` |
| `ToolTip` | Extended description shown on hover/selection |

This is a key enhancement over bash, which can only show short aligned descriptions. PowerShell tooltips can show full flag descriptions, complete session message previews, etc.

## Help Parsing & Caching

### Parsing

Same regex patterns as the bash version, using PowerShell's `-match` operator:

- **Flags:** Match lines like `  -m, --model` — extract both short and long forms
- **Flags with args:** Detect flags that take values via `<value>` or `[value]` after the flag
- **Subcommands:** Find the `Commands:` section and extract command names

### Cache Structure

Identical layout to bash, under a `powershell/` subdirectory:

```
$CACHE_DIR/claude-code-completion/powershell/<version>/
  _root_help
  _root_flags
  _root_flags_with_args
  _root_subcommands
  mcp_flags
  mcp_subcommands
  ...
```

**Cache directory location:**
- Unix: `$env:XDG_CACHE_HOME` or `$HOME/.cache`
- Windows: `$env:LOCALAPPDATA`

**Format:** One item per line (plain text). Simple and debuggable, consistent with the bash version.

**Invalidation:** Version-based only. On version change, rebuild cache and delete old version directories under `powershell/`. Uses `Set-Content`/`Get-Content` instead of `echo`/`cat`.

## Completion Logic

### Command-line parsing

Walk `$commandAst.CommandElements` to determine:
1. The subcommand (first non-flag element after `claude`)
2. The sub-subcommand (first non-flag element after the subcommand)
3. Whether the cursor follows a flag that takes an argument

### Completion scenarios

| Context | Completions |
|---------|-------------|
| `claude <TAB>` | Subcommands from cache |
| `claude -<TAB>` | Root flags from cache |
| `claude mcp <TAB>` | Sub-subcommands from cache |
| `claude mcp -<TAB>` | Subcommand flags from cache |
| `claude --model <TAB>` | Model names (hardcoded + help-parsed) |
| `claude --permission-mode <TAB>` | Known permission modes |
| `claude --output-format <TAB>` | text, json, stream-json |
| `claude --input-format <TAB>` | text, stream-json |
| `claude --effort <TAB>` | low, medium, high |
| `claude --resume <TAB>` | Session IDs with message preview tooltips |
| `claude --add-dir <TAB>` | Directory completion |
| `claude --debug-file/--mcp-config/--settings <TAB>` | File completion |
| `claude mcp get/remove <TAB>` | MCP server names |
| `claude plugin disable/enable/uninstall <TAB>` | Plugin names |

### Smart flag completions

Same value sets as the bash version. Each completion includes a descriptive `ToolTip`.

### Subcommand-specific completions

- `claude mcp get/remove <name>` — names from `claude mcp list`
- `claude plugin uninstall/enable/disable <name>` — names from `claude plugin list --json`

## Session Resume Completion

### Path encoding (platform-aware)

The `claude` CLI encodes the working directory by replacing path separators (and drive letter colons on Windows) with `-`:

- Unix: `/home/user/project` → `-home-user-project`
- Windows: `C:\Users\douglas` → `C--Users-douglas`

```powershell
if ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
    # Windows: replace ':', '\', '/'
    $encoded = $pwd.Path -replace '[:\\/]', '-'
} else {
    # Unix: replace '/' only (preserves colons in directory names)
    $encoded = $pwd.Path.Replace('/', '-')
}
```

### Session discovery

1. List `*.jsonl` files in `~/.claude/projects/<encoded-cwd>/`
2. Sort by `LastWriteTime` descending, limit to 10
3. For each file, extract first real user message via `ConvertFrom-Json`
4. Filter out IDE metadata lines (`<ide_`, `<command-`)

### Key improvement over bash

No `jq`/`grep` fallback split. PowerShell's built-in `ConvertFrom-Json` handles JSON parsing on both 5.1 and 7+, giving us one code path.

### CompletionResult for sessions

- `CompletionText` = session UUID
- `ListItemText` = truncated message preview
- `ToolTip` = full first user message

## Installation

Add to PowerShell profile (`$PROFILE`):

```powershell
. /path/to/claude-code-completion/claude.ps1
```

## Testing

### Framework

[Pester](https://pester.dev/) — the standard PowerShell testing framework.

### Test files

```
tests/
  Completion.Tests.ps1        # Top-level completion logic
  HelpParsing.Tests.ps1       # Flag/subcommand parsing
  Cache.Tests.ps1             # Cache creation, invalidation, cleanup
  FlagArgs.Tests.ps1          # Smart flag argument completion
  SessionResume.Tests.ps1     # Session ID completion with message extraction
  SubcommandArgs.Tests.ps1    # MCP/plugin name completion
```

### Mocking

Pester's `Mock` command replaces `claude` invocations with canned help output, same strategy as the bashunit tests. Filesystem access is also mocked for session tests.

### Running

```powershell
Invoke-Pester tests/
```

## Compatibility

| Aspect | Requirement |
|--------|-------------|
| PowerShell 5.1+ | Windows PowerShell (ships with Windows 10/11) |
| PowerShell 7+ | Cross-platform (pwsh on Windows, macOS, Linux) |

### 5.1 considerations

- No `$IsWindows` — use `$PSVersionTable.PSVersion.Major -le 5` as equivalent
- No `&&` operator — use semicolons or separate statements
- `ConvertFrom-Json` lacks `-Depth` and `-AsHashtable` — not needed for our use case

## Differences from Bash Version

| Aspect | Bash | PowerShell |
|--------|------|------------|
| File | `claude.bash` | `claude.ps1` |
| Registration | `complete -F _claude claude` | `Register-ArgumentCompleter -Native` |
| Completion output | `COMPREPLY` array of strings | `CompletionResult` objects with tooltips |
| JSON parsing | `jq` or `grep`/`sed` fallback | `ConvertFrom-Json` (built-in, one code path) |
| Path encoding | Replace `/` with `-` | Platform-aware: also `:` and `\` on Windows |
| Description display | Aligned `# description` hack | Native `ToolTip` field |
| Cache subdir | `bash/` | `powershell/` |
| Min version | Bash 3.2+ | PowerShell 5.1+ |
| Testing | bashunit | Pester |
