# PowerShell Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Port the bash tab-completion for the `claude` CLI to PowerShell, supporting 5.1+ and 7+, with rich tooltips as a PowerShell-native enhancement.

**Architecture:** Single `claude.ps1` script with helper functions and `Register-ArgumentCompleter -Native`. Pester 5 test suite in `tests/powershell/`. Same caching, help-parsing, and session-resume approach as the bash version.

**Tech Stack:** PowerShell 5.1+/7+, Pester 5 for testing

---

### Task 1: Test infrastructure and script skeleton

**Files:**
- Create: `tests/powershell/TestHelper.ps1`
- Create: `claude.ps1`
- Create: `tests/powershell/Skeleton.Tests.ps1`

**Step 1: Create `claude.ps1` skeleton**

```powershell
# PowerShell completion for the claude CLI (Claude Code)
# https://github.com/anthropics/claude-code

function _claude_complete {
    param(
        [string]$WordToComplete,
        [string[]]$Elements
    )
    # TODO: implement
}

Register-ArgumentCompleter -CommandName claude -Native -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.ToString() })
    _claude_complete -WordToComplete $wordToComplete -Elements $elements
}
```

**Step 2: Create `tests/powershell/TestHelper.ps1`**

Shared test infrastructure — mock claude, completer simulation helper.

```powershell
# Shared test infrastructure for Pester tests

$Script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Initialize-ClaudeTests {
    # Source the completion script
    . "$Script:ProjectRoot/claude.ps1"
}

# Create a mock claude function with canned help output.
# Call this AFTER Initialize-ClaudeTests so it shadows any real claude.
function New-MockClaude {
    param([hashtable]$Responses)

    # Build a function that dispatches on the joined argument string
    $body = 'param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)' + "`n"
    $body += '$key = ($Arguments -join " ").Trim()' + "`n"
    $body += 'switch ($key) {' + "`n"
    foreach ($k in $Responses.Keys) {
        $escaped = $Responses[$k] -replace "'", "''"
        $body += "    '$k' { '$escaped' }`n"
    }
    $body += '}'
    $fn = [scriptblock]::Create($body)
    Set-Item -Path function:global:claude -Value $fn
}

# Default mock with basic --version and --help
function New-DefaultMockClaude {
    New-MockClaude @{
        '--version' = '1.0.0 (Claude Code)'
        '--help' = @'
Usage: claude [options] [command] [prompt]

Options:
  --add-dir <directories...>     Additional directories
  -c, --continue                 Continue most recent conversation
  --model <model>                Model for session
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
'@
    }
}

# Simulate tab completion for a command line string.
# Returns CompletionResult objects (or nothing if no matches).
function Invoke-ClaudeCompleter {
    param([string]$CommandLine)

    $words = @($CommandLine.Trim() -split '\s+')
    if ($CommandLine.EndsWith(' ')) {
        $wordToComplete = ''
    } else {
        $wordToComplete = $words[-1]
    }
    _claude_complete -WordToComplete $wordToComplete -Elements $words
}

# Extract just the CompletionText values from completer results.
function Get-CompletionText {
    param([string]$CommandLine)
    Invoke-ClaudeCompleter $CommandLine | ForEach-Object { $_.CompletionText }
}
```

**Step 3: Create `tests/powershell/Skeleton.Tests.ps1`**

```powershell
BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
}

Describe 'Script skeleton' {
    It 'defines the _claude_complete function' {
        Get-Command _claude_complete -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'registers an argument completer for claude' {
        # Register-ArgumentCompleter doesn't have a public query API,
        # so we verify _claude_complete is callable and returns without error
        { _claude_complete -WordToComplete '' -Elements @('claude') } | Should -Not -Throw
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/ -Output Detailed"`
Expected: 2 tests PASS

**Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/TestHelper.ps1 tests/powershell/Skeleton.Tests.ps1
git commit -m "feat(ps): add script skeleton and test infrastructure"
```

---

### Task 2: Help parsing functions

**Files:**
- Modify: `claude.ps1`
- Create: `tests/powershell/HelpParsing.Tests.ps1`

**Step 1: Write failing tests**

```powershell
BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
}

Describe 'Help parsing' {
    BeforeAll {
        $helpText = @'
Usage: claude [options] [command] [prompt]

Arguments:
  prompt                         Your prompt

Options:
  --add-dir <directories...>     Additional directories
  -c, --continue                 Continue most recent conversation
  --model <model>                Model for session
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation by session ID
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
  plugin                         Manage plugins
'@
        $helpLines = $helpText -split "`n"
    }

    Context '_claude_parse_flags' {
        BeforeAll {
            $flags = @(_claude_parse_flags -HelpLines $helpLines)
        }

        It 'extracts long flags' {
            $flags | Should -Contain '--model'
            $flags | Should -Contain '--continue'
            $flags | Should -Contain '--print'
        }

        It 'extracts short flags' {
            $flags | Should -Contain '-c'
            $flags | Should -Contain '-p'
            $flags | Should -Contain '-r'
        }
    }

    Context '_claude_parse_flags_with_args' {
        BeforeAll {
            $flagsWithArgs = @(_claude_parse_flags_with_args -HelpLines $helpLines)
        }

        It 'includes flags that take values' {
            $flagsWithArgs | Should -Contain '--model'
            $flagsWithArgs | Should -Contain '--add-dir'
        }

        It 'excludes boolean flags' {
            $flagsWithArgs | Should -Not -Contain '--continue'
            $flagsWithArgs | Should -Not -Contain '--print'
        }
    }

    Context '_claude_parse_subcommands' {
        BeforeAll {
            $subcommands = @(_claude_parse_subcommands -HelpLines $helpLines)
        }

        It 'extracts subcommand names' {
            $subcommands | Should -Contain 'auth'
            $subcommands | Should -Contain 'mcp'
            $subcommands | Should -Contain 'plugin'
        }

        It 'does not include non-command text' {
            $subcommands | Should -Not -Contain 'prompt'
            $subcommands | Should -Not -Contain 'Options:'
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/HelpParsing.Tests.ps1 -Output Detailed"`
Expected: FAIL — functions not defined

**Step 3: Implement in `claude.ps1`**

Add before `_claude_complete`:

```powershell
function _claude_parse_flags {
    param([string[]]$HelpLines)
    foreach ($line in $HelpLines) {
        if ($line -match '^\s+(-[a-zA-Z]),?\s+(--[a-zA-Z][-a-zA-Z]*)') {
            $Matches[1]
            $Matches[2]
        } elseif ($line -match '^\s+(--[a-zA-Z][-a-zA-Z]*)') {
            $Matches[1]
        }
    }
}

function _claude_parse_flags_with_args {
    param([string[]]$HelpLines)
    foreach ($line in $HelpLines) {
        if ($line -match '^\s+(-[a-zA-Z]),?\s+(--[a-zA-Z][-a-zA-Z]*)\s+[<\[]') {
            $Matches[1]
            $Matches[2]
        } elseif ($line -match '^\s+(--[a-zA-Z][-a-zA-Z]*)\s+[<\[]') {
            $Matches[1]
        }
    }
}

function _claude_parse_subcommands {
    param([string[]]$HelpLines)
    $inCommands = $false
    foreach ($line in $HelpLines) {
        if ($line -match '^Commands:') {
            $inCommands = $true
            continue
        }
        if ($inCommands) {
            if ([string]::IsNullOrEmpty($line)) { continue }
            if ($line -notmatch '^\s') { break }
            if ($line -match '^\s+([a-zA-Z][-a-zA-Z]*)') {
                $Matches[1]
            }
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/HelpParsing.Tests.ps1 -Output Detailed"`
Expected: All PASS

**Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/HelpParsing.Tests.ps1
git commit -m "feat(ps): add help parsing functions"
```

---

### Task 3: Version detection and cache directory

**Files:**
- Modify: `claude.ps1`
- Create: `tests/powershell/Cache.Tests.ps1`

**Step 1: Write failing tests**

```powershell
BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
    New-DefaultMockClaude
}

Describe 'Cache management' {
    BeforeEach {
        $script:TestCacheDir = Join-Path ([System.IO.Path]::GetTempPath()) "claude-test-cache-$([guid]::NewGuid())"
        $env:XDG_CACHE_HOME = $script:TestCacheDir
    }

    AfterEach {
        if (Test-Path $script:TestCacheDir) {
            Remove-Item -Recurse -Force $script:TestCacheDir
        }
        $env:XDG_CACHE_HOME = $null
    }

    Context '_claude_version' {
        It 'returns the version string' {
            _claude_version | Should -Be '1.0.0'
        }
    }

    Context '_claude_cache_dir' {
        It 'returns path under XDG_CACHE_HOME' {
            $dir = _claude_cache_dir
            $dir | Should -BeLike "$script:TestCacheDir*"
        }

        It 'includes powershell subdirectory' {
            $dir = _claude_cache_dir
            $dir | Should -BeLike '*powershell*'
        }

        It 'includes version component' {
            $dir = _claude_cache_dir
            $dir | Should -BeLike '*1.0.0*'
        }
    }

    Context '_claude_ensure_cache' {
        It 'creates the cache directory' {
            _claude_ensure_cache
            $dir = _claude_cache_dir
            Test-Path $dir | Should -BeTrue
        }
    }

    Context '_claude_cleanup_old_cache' {
        It 'removes old version directories' {
            _claude_ensure_cache
            $baseDir = Join-Path $script:TestCacheDir 'claude-code-completion' 'powershell'
            New-Item -ItemType Directory -Path (Join-Path $baseDir '0.9.0') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $baseDir '0.8.0') -Force | Out-Null

            _claude_cleanup_old_cache

            Test-Path (Join-Path $baseDir '0.9.0') | Should -BeFalse
            Test-Path (Join-Path $baseDir '0.8.0') | Should -BeFalse
        }

        It 'preserves the current version directory' {
            _claude_ensure_cache
            $dir = _claude_cache_dir
            $baseDir = Join-Path $script:TestCacheDir 'claude-code-completion' 'powershell'
            New-Item -ItemType Directory -Path (Join-Path $baseDir '0.9.0') -Force | Out-Null

            _claude_cleanup_old_cache

            Test-Path $dir | Should -BeTrue
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Cache.Tests.ps1 -Output Detailed"`
Expected: FAIL — functions not defined

**Step 3: Implement in `claude.ps1`**

Add before the parsing functions:

```powershell
function _claude_version {
    $output = claude --version 2>$null
    if ($output) {
        ($output -split '\s')[0]
    }
}

function _claude_cache_dir {
    $version = _claude_version
    if ($env:XDG_CACHE_HOME) {
        $base = $env:XDG_CACHE_HOME
    } elseif ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
        $base = $env:LOCALAPPDATA
    } else {
        $base = Join-Path $HOME '.cache'
    }
    Join-Path $base 'claude-code-completion' 'powershell' $version
}

function _claude_ensure_cache {
    $dir = _claude_cache_dir
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function _claude_cleanup_old_cache {
    if ($env:XDG_CACHE_HOME) {
        $base = $env:XDG_CACHE_HOME
    } elseif ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
        $base = $env:LOCALAPPDATA
    } else {
        $base = Join-Path $HOME '.cache'
    }
    $baseDir = Join-Path $base 'claude-code-completion' 'powershell'

    if (-not (Test-Path $baseDir)) { return }

    $currentVersion = _claude_version
    Get-ChildItem -Path $baseDir -Directory | Where-Object {
        $_.Name -ne $currentVersion
    } | Remove-Item -Recurse -Force
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Cache.Tests.ps1 -Output Detailed"`
Expected: All PASS

**Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/Cache.Tests.ps1
git commit -m "feat(ps): add version detection and cache management"
```

---

### Task 4: Cache build

**Files:**
- Modify: `claude.ps1`
- Modify: `tests/powershell/Cache.Tests.ps1`

**Step 1: Write failing tests**

Append to `Cache.Tests.ps1`, inside the outer `Describe` block:

```powershell
    Context '_claude_build_cache' {
        BeforeAll {
            # Use a mock with subcommand help too
            New-MockClaude @{
                '--version' = '1.0.0 (Claude Code)'
                '--help' = @'
Usage: claude [options] [command] [prompt]

Options:
  --add-dir <directories...>     Additional directories
  -c, --continue                 Continue most recent conversation
  --model <model>                Model for session
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
'@
                'auth --help' = @'
Usage: claude auth [options] [command]

Options:
  -h, --help        Display help

Commands:
  login [options]   Sign in
  logout            Log out
  status [options]  Show status
'@
                'mcp --help' = @'
Usage: claude mcp [options] [command]

Options:
  -h, --help        Display help

Commands:
  add [options] <name> <commandOrUrl> [args...]  Add server
  get <name>                                     Get server
  list                                           List servers
  remove [options] <name>                        Remove server
'@
            }
            _claude_build_cache
            $script:CacheDir = _claude_cache_dir
        }

        It 'creates root flags file' {
            Join-Path $script:CacheDir '_root_flags' | Should -Exist
        }

        It 'root flags contains --model' {
            Get-Content (Join-Path $script:CacheDir '_root_flags') | Should -Contain '--model'
        }

        It 'root flags contains -p' {
            Get-Content (Join-Path $script:CacheDir '_root_flags') | Should -Contain '-p'
        }

        It 'creates root subcommands file' {
            Join-Path $script:CacheDir '_root_subcommands' | Should -Exist
        }

        It 'root subcommands contains auth' {
            Get-Content (Join-Path $script:CacheDir '_root_subcommands') | Should -Contain 'auth'
        }

        It 'root subcommands contains mcp' {
            Get-Content (Join-Path $script:CacheDir '_root_subcommands') | Should -Contain 'mcp'
        }

        It 'creates flags-with-args file' {
            Join-Path $script:CacheDir '_root_flags_with_args' | Should -Exist
        }

        It 'flags with args contains --model' {
            Get-Content (Join-Path $script:CacheDir '_root_flags_with_args') | Should -Contain '--model'
        }

        It 'flags with args excludes --continue' {
            Get-Content (Join-Path $script:CacheDir '_root_flags_with_args') | Should -Not -Contain '--continue'
        }

        It 'creates mcp subcommands file' {
            Join-Path $script:CacheDir 'mcp_subcommands' | Should -Exist
        }

        It 'mcp subcommands contains add' {
            Get-Content (Join-Path $script:CacheDir 'mcp_subcommands') | Should -Contain 'add'
        }
    }
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Cache.Tests.ps1 -Output Detailed"`
Expected: FAIL — `_claude_build_cache` not defined

**Step 3: Implement in `claude.ps1`**

Add after `_claude_cleanup_old_cache`:

```powershell
function _claude_build_cache {
    $cacheDir = _claude_cache_dir
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

    # Parse root level
    $helpOutput = claude --help 2>$null
    $helpLines = @($helpOutput -split "`n")
    Set-Content -Path (Join-Path $cacheDir '_root_help') -Value $helpOutput
    _claude_parse_flags -HelpLines $helpLines | Set-Content -Path (Join-Path $cacheDir '_root_flags')
    _claude_parse_flags_with_args -HelpLines $helpLines | Set-Content -Path (Join-Path $cacheDir '_root_flags_with_args')
    $subcommands = @(_claude_parse_subcommands -HelpLines $helpLines)
    $subcommands | Set-Content -Path (Join-Path $cacheDir '_root_subcommands')

    # Parse each subcommand
    foreach ($subcmd in $subcommands) {
        if ([string]::IsNullOrWhiteSpace($subcmd)) { continue }
        $subHelp = claude $subcmd --help 2>$null
        if (-not $subHelp) { continue }
        $subHelpLines = @($subHelp -split "`n")
        _claude_parse_flags -HelpLines $subHelpLines | Set-Content -Path (Join-Path $cacheDir "${subcmd}_flags")
        _claude_parse_flags_with_args -HelpLines $subHelpLines | Set-Content -Path (Join-Path $cacheDir "${subcmd}_flags_with_args")
        _claude_parse_subcommands -HelpLines $subHelpLines | Set-Content -Path (Join-Path $cacheDir "${subcmd}_subcommands")
    }

    _claude_cleanup_old_cache
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Cache.Tests.ps1 -Output Detailed"`
Expected: All PASS

**Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/Cache.Tests.ps1
git commit -m "feat(ps): add cache build from help output"
```

---

### Task 5: Top-level completion

**Files:**
- Modify: `claude.ps1`
- Create: `tests/powershell/Completion.Tests.ps1`

**Step 1: Write failing tests**

```powershell
BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests

    New-MockClaude @{
        '--version' = '1.0.0 (Claude Code)'
        '--help' = @'
Usage: claude [options] [command] [prompt]

Options:
  --add-dir <directories...>     Additional directories
  -c, --continue                 Continue most recent conversation
  --model <model>                Model for session
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
'@
        'auth --help' = @'
Usage: claude auth [options] [command]

Options:
  -h, --help        Display help

Commands:
  login [options]   Sign in
  logout            Log out
  status [options]  Show status
'@
        'mcp --help' = @'
Usage: claude mcp [options] [command]

Options:
  -h, --help        Display help

Commands:
  add [options] <name> <commandOrUrl> [args...]  Add server
  get <name>                                     Get server
  list                                           List servers
  remove [options] <name>                        Remove server
'@
    }

    $env:XDG_CACHE_HOME = Join-Path ([System.IO.Path]::GetTempPath()) "claude-test-$([guid]::NewGuid())"
}

AfterAll {
    if ($env:XDG_CACHE_HOME -and (Test-Path $env:XDG_CACHE_HOME)) {
        Remove-Item -Recurse -Force $env:XDG_CACHE_HOME
    }
    $env:XDG_CACHE_HOME = $null
}

Describe 'Top-level completion' {
    It 'bare claude shows subcommands' {
        $results = Get-CompletionText 'claude '
        $results | Should -Contain 'auth'
        $results | Should -Contain 'mcp'
    }

    It 'bare claude does not show flags' {
        $results = Get-CompletionText 'claude '
        $results | Should -Not -Contain '--model'
    }

    It 'dash shows flags' {
        $results = Get-CompletionText 'claude -'
        $results | Should -Contain '--model'
        $results | Should -Contain '-p'
    }

    It 'double dash shows long flags' {
        $results = Get-CompletionText 'claude --'
        $results | Should -Contain '--model'
    }

    It 'partial subcommand completes' {
        $results = Get-CompletionText 'claude au'
        $results | Should -Contain 'auth'
    }
}

Describe 'Subcommand completion' {
    It 'auth subcommand shows auth sub-subcommands' {
        $results = Get-CompletionText 'claude auth '
        $results | Should -Contain 'login'
        $results | Should -Contain 'logout'
    }

    It 'mcp subcommand shows mcp sub-subcommands' {
        $results = Get-CompletionText 'claude mcp '
        $results | Should -Contain 'add'
        $results | Should -Contain 'list'
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Completion.Tests.ps1 -Output Detailed"`
Expected: FAIL — `_claude_complete` returns nothing

**Step 3: Implement `_claude_complete` core in `claude.ps1`**

Replace the placeholder `_claude_complete`:

```powershell
function _claude_complete {
    param(
        [string]$WordToComplete,
        [string[]]$Elements
    )

    $cacheDir = _claude_cache_dir

    # Build cache if needed
    if (-not (Test-Path $cacheDir)) {
        _claude_build_cache
    }

    # Find the subcommand (first non-flag element after 'claude')
    $subcmd = ''
    $subcmdIndex = -1
    for ($i = 1; $i -lt $Elements.Count; $i++) {
        if ($Elements[$i] -notlike '-*') {
            $potential = $Elements[$i]
            $subcmdFile = Join-Path $cacheDir '_root_subcommands'
            if ((Test-Path $subcmdFile) -and ((Get-Content $subcmdFile) -contains $potential)) {
                $subcmd = $potential
                $subcmdIndex = $i
                break
            }
        }
    }

    # Determine the previous element (for flag-argument detection)
    $prev = if ($Elements.Count -ge 2 -and $WordToComplete -eq '') {
        $Elements[-1]
    } elseif ($Elements.Count -ge 3 -and $WordToComplete -ne '') {
        $Elements[-2]
    } else { '' }

    # Check if previous word is a flag that takes an argument
    if ($prev -like '-*') {
        $flagsWithArgsFile = if ($subcmd) {
            Join-Path $cacheDir "${subcmd}_flags_with_args"
        } else {
            Join-Path $cacheDir '_root_flags_with_args'
        }
        if ((Test-Path $flagsWithArgsFile) -and ((Get-Content $flagsWithArgsFile) -contains $prev)) {
            _claude_complete_flag_arg -Flag $prev -WordToComplete $WordToComplete
            return
        }
    }

    if ($subcmd) {
        # Find sub-subcommand
        $subSubcmd = ''
        for ($i = $subcmdIndex + 1; $i -lt $Elements.Count; $i++) {
            if ($Elements[$i] -notlike '-*') {
                $potential = $Elements[$i]
                $subSubFile = Join-Path $cacheDir "${subcmd}_subcommands"
                if ((Test-Path $subSubFile) -and ((Get-Content $subSubFile) -contains $potential)) {
                    $subSubcmd = $potential
                    break
                }
            }
        }

        if ($WordToComplete -like '-*') {
            # Complete subcommand flags
            $flagsFile = Join-Path $cacheDir "${subcmd}_flags"
            if (Test-Path $flagsFile) {
                Get-Content $flagsFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
                }
            }
        } elseif ($subSubcmd) {
            # Complete positional args for sub-subcommands
            _claude_complete_subcmd_arg -Subcmd $subcmd -SubSubcmd $subSubcmd -WordToComplete $WordToComplete
        } else {
            # Complete sub-subcommands
            $subFile = Join-Path $cacheDir "${subcmd}_subcommands"
            if (Test-Path $subFile) {
                Get-Content $subFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'Command', $_)
                }
            }
        }
    } else {
        # Top level
        if ($WordToComplete -like '-*') {
            # Complete flags
            $flagsFile = Join-Path $cacheDir '_root_flags'
            if (Test-Path $flagsFile) {
                Get-Content $flagsFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
                }
            }
        } else {
            # Complete subcommands
            $subFile = Join-Path $cacheDir '_root_subcommands'
            if (Test-Path $subFile) {
                Get-Content $subFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'Command', $_)
                }
            }
        }
    }
}
```

Also add stub functions for flag args and subcommand args (to be implemented later):

```powershell
function _claude_complete_flag_arg {
    param([string]$Flag, [string]$WordToComplete)
    # TODO: implement in Task 7
}

function _claude_complete_subcmd_arg {
    param([string]$Subcmd, [string]$SubSubcmd, [string]$WordToComplete)
    # TODO: implement in Task 9
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Completion.Tests.ps1 -Output Detailed"`
Expected: All PASS

**Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/Completion.Tests.ps1
git commit -m "feat(ps): add top-level and subcommand completion logic"
```

---

### Task 6: Flag argument completion

**Files:**
- Modify: `claude.ps1`
- Create: `tests/powershell/FlagArgs.Tests.ps1`

**Step 1: Write failing tests**

```powershell
BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests

    New-MockClaude @{
        '--version' = '1.0.0 (Claude Code)'
        '--help' = @'
Usage: claude [options] [command] [prompt]

Options:
  --add-dir <directories...>     Additional directories
  -c, --continue                 Continue most recent conversation
  --debug-file <file>            Debug output file
  --effort <level>               Effort level (low, medium, high)
  --input-format <format>        Input format (choices: "text", "stream-json")
  --model <model>                Model for session
  --output-format <format>       Output format (choices: "text", "json", "stream-json")
  --permission-mode <mode>       Permission mode
  --plugin-dir <directory>       Plugin directory
  -p, --print                    Print response and exit
  -r, --resume [value]           Resume a conversation
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
'@
        'auth --help' = 'Usage: claude auth'
        'mcp --help' = 'Usage: claude mcp'
    }

    $env:XDG_CACHE_HOME = Join-Path ([System.IO.Path]::GetTempPath()) "claude-test-$([guid]::NewGuid())"
}

AfterAll {
    if ($env:XDG_CACHE_HOME -and (Test-Path $env:XDG_CACHE_HOME)) {
        Remove-Item -Recurse -Force $env:XDG_CACHE_HOME
    }
    $env:XDG_CACHE_HOME = $null
}

Describe 'Flag argument completion' {
    It 'completes model aliases' {
        $results = Get-CompletionText 'claude --model '
        $results | Should -Contain 'sonnet'
        $results | Should -Contain 'opus'
        $results | Should -Contain 'haiku'
    }

    It 'completes permission mode choices' {
        $results = Get-CompletionText 'claude --permission-mode '
        $results | Should -Contain 'default'
        $results | Should -Contain 'plan'
    }

    It 'completes output format choices' {
        $results = Get-CompletionText 'claude --output-format '
        $results | Should -Contain 'text'
        $results | Should -Contain 'json'
        $results | Should -Contain 'stream-json'
    }

    It 'completes effort levels' {
        $results = Get-CompletionText 'claude --effort '
        $results | Should -Contain 'low'
        $results | Should -Contain 'medium'
        $results | Should -Contain 'high'
    }

    It 'completes input format choices' {
        $results = Get-CompletionText 'claude --input-format '
        $results | Should -Contain 'text'
        $results | Should -Contain 'stream-json'
    }

    It 'filters model completions by partial input' {
        $results = Get-CompletionText 'claude --model so'
        $results | Should -Contain 'sonnet'
        $results | Should -Not -Contain 'opus'
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/FlagArgs.Tests.ps1 -Output Detailed"`
Expected: FAIL — `_claude_complete_flag_arg` is a stub

**Step 3: Implement `_claude_complete_flag_arg` in `claude.ps1`**

Add the known models list and replace the stub:

```powershell
$script:_claude_known_models = @(
    'sonnet', 'opus', 'haiku',
    'claude-sonnet-4-5-20250514',
    'claude-sonnet-4-6',
    'claude-opus-4-5-20250514',
    'claude-opus-4-6',
    'claude-haiku-4-5-20251001'
)

function _claude_complete_flag_arg {
    param([string]$Flag, [string]$WordToComplete)

    switch ($Flag) {
        '--model' {
            $models = @($script:_claude_known_models)
            $cacheDir = _claude_cache_dir
            $helpFile = Join-Path $cacheDir '_root_help'
            if (Test-Path $helpFile) {
                foreach ($line in Get-Content $helpFile) {
                    if ($line -match '(claude-[a-z]+-[0-9][^\s]*)') {
                        $models += $Matches[1]
                    }
                }
            }
            $models | Select-Object -Unique | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        '--permission-mode' {
            @('acceptEdits', 'bypassPermissions', 'default', 'dontAsk', 'plan') |
                Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        '--output-format' {
            @('text', 'json', 'stream-json') |
                Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        '--input-format' {
            @('text', 'stream-json') |
                Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        '--effort' {
            @('low', 'medium', 'high') |
                Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        { $_ -in '--resume', '-r' } {
            _claude_complete_sessions -WordToComplete $WordToComplete
        }
        { $_ -in '--add-dir', '--plugin-dir' } {
            Get-ChildItem -Path "$WordToComplete*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, 'ProviderContainer', $_.FullName)
            }
        }
        { $_ -in '--debug-file', '--mcp-config', '--settings' } {
            Get-ChildItem -Path "$WordToComplete*" -File -ErrorAction SilentlyContinue | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, 'ProviderItem', $_.FullName)
            }
        }
        default {
            # Unknown flag arg — default to file completion
            Get-ChildItem -Path "$WordToComplete*" -ErrorAction SilentlyContinue | ForEach-Object {
                $type = if ($_.PSIsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
                [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, $type, $_.FullName)
            }
        }
    }
}
```

Also add a stub for `_claude_complete_sessions` (implemented in Task 7):

```powershell
function _claude_complete_sessions {
    param([string]$WordToComplete)
    # TODO: implement in Task 7
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/FlagArgs.Tests.ps1 -Output Detailed"`
Expected: All PASS

**Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/FlagArgs.Tests.ps1
git commit -m "feat(ps): add flag argument completion"
```

---

### Task 7: Session resume completion

**Files:**
- Modify: `claude.ps1`
- Create: `tests/powershell/SessionResume.Tests.ps1`

**Step 1: Write failing tests**

```powershell
BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
    New-DefaultMockClaude

    $env:XDG_CACHE_HOME = Join-Path ([System.IO.Path]::GetTempPath()) "claude-test-$([guid]::NewGuid())"

    # Create fake session files
    $script:MockHome = Join-Path ([System.IO.Path]::GetTempPath()) "claude-mock-home-$([guid]::NewGuid())"
    $script:OriginalHome = $HOME
    $env:HOME = $script:MockHome

    $projDir = Join-Path $script:MockHome '.claude' 'projects' '-home-user-myproject'
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null

    # Session 1: older
    @'
{"type":"queue-operation","timestamp":"2026-02-01T10:00:00.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}]},"timestamp":"2026-02-01T10:00:01.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"assistant","timestamp":"2026-02-01T10:00:05.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
'@ | Set-Content (Join-Path $projDir 'aaaaaaaa-1111-1111-1111-111111111111.jsonl')

    Start-Sleep -Seconds 1

    # Session 2: newer, with IDE metadata in first user message
    @'
{"type":"queue-operation","timestamp":"2026-03-01T15:00:00.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_opened_file>Some IDE stuff</ide_opened_file>"}]},"timestamp":"2026-03-01T15:00:01.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add the new feature"}]},"timestamp":"2026-03-01T15:00:02.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"assistant","timestamp":"2026-03-01T15:00:10.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
'@ | Set-Content (Join-Path $projDir 'bbbbbbbb-2222-2222-2222-222222222222.jsonl')

    # Override _claude_encoded_cwd to match our fake project
    function global:_claude_encoded_cwd { '-home-user-myproject' }
}

AfterAll {
    $env:HOME = $script:OriginalHome
    if (Test-Path $script:MockHome) { Remove-Item -Recurse -Force $script:MockHome }
    if ($env:XDG_CACHE_HOME -and (Test-Path $env:XDG_CACHE_HOME)) {
        Remove-Item -Recurse -Force $env:XDG_CACHE_HOME
    }
    $env:XDG_CACHE_HOME = $null
}

Describe 'Session message extraction' {
    It 'extracts simple user message' {
        $projDir = Join-Path $script:MockHome '.claude' 'projects' '-home-user-myproject'
        $msg = _claude_session_message -FilePath (Join-Path $projDir 'aaaaaaaa-1111-1111-1111-111111111111.jsonl')
        $msg | Should -Be 'Fix the login bug'
    }

    It 'skips IDE metadata messages' {
        $projDir = Join-Path $script:MockHome '.claude' 'projects' '-home-user-myproject'
        $msg = _claude_session_message -FilePath (Join-Path $projDir 'bbbbbbbb-2222-2222-2222-222222222222.jsonl')
        $msg | Should -Be 'Add the new feature'
    }
}

Describe 'Session completion' {
    It 'finds both sessions' {
        $results = @(_claude_complete_sessions -WordToComplete '')
        $results.Count | Should -Be 2
    }

    It 'session 1 UUID present' {
        $results = _claude_complete_sessions -WordToComplete ''
        $results.CompletionText | Should -Contain 'aaaaaaaa-1111-1111-1111-111111111111'
    }

    It 'session 2 UUID present' {
        $results = _claude_complete_sessions -WordToComplete ''
        $results.CompletionText | Should -Contain 'bbbbbbbb-2222-2222-2222-222222222222'
    }

    It 'partial UUID filters results' {
        $results = @(_claude_complete_sessions -WordToComplete 'aaa')
        $results.Count | Should -Be 1
    }

    It 'no-match returns empty' {
        $results = @(_claude_complete_sessions -WordToComplete 'zzz')
        $results.Count | Should -Be 0
    }

    It 'tooltip contains message text' {
        $results = _claude_complete_sessions -WordToComplete 'aaa'
        $results[0].ToolTip | Should -Be 'Fix the login bug'
    }
}

Describe 'Path encoding' {
    It 'encodes Unix paths by replacing / with -' {
        $result = _claude_encoded_cwd
        $result | Should -Not -BeNullOrEmpty
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/SessionResume.Tests.ps1 -Output Detailed"`
Expected: FAIL — `_claude_session_message` and `_claude_complete_sessions` not implemented

**Step 3: Implement in `claude.ps1`**

Replace the `_claude_complete_sessions` stub and add new functions:

```powershell
function _claude_encoded_cwd {
    $cwd = $pwd.Path
    if ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
        $cwd -replace '[:\\/]', '-'
    } else {
        $cwd.Replace('/', '-')
    }
}

function _claude_session_message {
    param([string]$FilePath)
    foreach ($line in Get-Content -Path $FilePath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
        } catch {
            continue
        }
        if ($obj.type -ne 'user') { continue }

        $content = $obj.message.content
        $text = $null
        if ($content -is [string]) {
            $text = $content
        } elseif ($content -is [array] -or $content.Count -gt 0) {
            foreach ($item in $content) {
                if ($item.type -eq 'text') {
                    $text = $item.text
                    break
                }
            }
        }
        if (-not $text) { continue }
        if ($text -match '<ide_' -or $text -match '<command-') { continue }

        return $text
    }
}

function _claude_complete_sessions {
    param([string]$WordToComplete)

    $encodedCwd = _claude_encoded_cwd
    $sessionDir = Join-Path $HOME '.claude' 'projects' $encodedCwd

    if (-not (Test-Path $sessionDir)) { return }

    $files = Get-ChildItem -Path $sessionDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10

    foreach ($file in $files) {
        $sessionId = $file.BaseName
        if ($sessionId -like "$WordToComplete*") {
            $msg = _claude_session_message -FilePath $file.FullName
            if (-not $msg) { $msg = '(session)' }
            $listText = if ($msg.Length -gt 40) { $msg.Substring(0, 39) + [char]0x2026 } else { $msg }
            [System.Management.Automation.CompletionResult]::new(
                $sessionId,
                "$sessionId  $listText",
                'ParameterValue',
                $msg
            )
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/SessionResume.Tests.ps1 -Output Detailed"`
Expected: All PASS

**Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/SessionResume.Tests.ps1
git commit -m "feat(ps): add session resume completion with message previews"
```

---

### Task 8: MCP server and plugin name completion

**Files:**
- Modify: `claude.ps1`
- Create: `tests/powershell/SubcommandArgs.Tests.ps1`

**Step 1: Write failing tests**

```powershell
BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests

    New-MockClaude @{
        '--version' = '1.0.0 (Claude Code)'
        '--help' = @'
Usage: claude [options] [command] [prompt]

Options:
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  mcp                            Configure MCP servers
  plugin                         Manage plugins
'@
        'mcp --help' = @'
Usage: claude mcp [options] [command]

Options:
  -h, --help                                     Display help
  -s, --scope <scope>                            Scope for server

Commands:
  get <name>                                     Get server
  list                                           List servers
  remove [options] <name>                        Remove server
'@
        'plugin --help' = @'
Usage: claude plugin [options] [command]

Options:
  -h, --help                           Display help

Commands:
  disable [options] [plugin]           Disable a plugin
  enable [options] <plugin>            Enable a plugin
  list [options]                       List installed plugins
  uninstall|remove [options] <plugin>  Uninstall a plugin
'@
        'mcp list' = @'
Checking MCP server health...

my-sentry: https://mcp.sentry.dev/mcp - Connected
my-github: /usr/bin/gh-mcp (stdio) - Connected
'@
        'plugin list --json' = '[{"name":"superpowers","version":"4.3.1","enabled":true},{"name":"my-plugin","version":"1.0.0","enabled":false}]'
    }

    $env:XDG_CACHE_HOME = Join-Path ([System.IO.Path]::GetTempPath()) "claude-test-$([guid]::NewGuid())"
}

AfterAll {
    if ($env:XDG_CACHE_HOME -and (Test-Path $env:XDG_CACHE_HOME)) {
        Remove-Item -Recurse -Force $env:XDG_CACHE_HOME
    }
    $env:XDG_CACHE_HOME = $null
}

Describe 'MCP server name completion' {
    It 'mcp get completes server names' {
        $results = Get-CompletionText 'claude mcp get '
        $results | Should -Contain 'my-sentry'
        $results | Should -Contain 'my-github'
    }

    It 'mcp remove completes server names' {
        $results = Get-CompletionText 'claude mcp remove '
        $results | Should -Contain 'my-sentry'
    }
}

Describe 'Plugin name completion' {
    It 'plugin disable completes plugin names' {
        $results = Get-CompletionText 'claude plugin disable '
        $results | Should -Contain 'superpowers'
        $results | Should -Contain 'my-plugin'
    }

    It 'plugin enable completes plugin names' {
        $results = Get-CompletionText 'claude plugin enable '
        $results | Should -Contain 'superpowers'
    }

    It 'plugin uninstall completes plugin names' {
        $results = Get-CompletionText 'claude plugin uninstall '
        $results | Should -Contain 'superpowers'
    }
}

Describe 'Subcommand flags' {
    It 'mcp dash shows subcommand flags' {
        $results = Get-CompletionText 'claude mcp -'
        $results | Should -Contain '--help'
        $results | Should -Contain '--scope'
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/SubcommandArgs.Tests.ps1 -Output Detailed"`
Expected: FAIL — `_claude_complete_subcmd_arg` is a stub

**Step 3: Implement in `claude.ps1`**

Replace the `_claude_complete_subcmd_arg` stub and add helper functions:

```powershell
function _claude_mcp_server_names {
    $output = claude mcp list 2>$null
    if (-not $output) { return }
    foreach ($line in ($output -split "`n")) {
        if ($line -match ':' -and $line -notmatch '^Checking|^$') {
            ($line -split ':')[0].Trim()
        }
    }
}

function _claude_plugin_names {
    $output = claude plugin list --json 2>$null
    if (-not $output) { return }
    try {
        $plugins = $output | ConvertFrom-Json
        foreach ($p in $plugins) {
            $p.name
        }
    } catch {}
}

function _claude_complete_subcmd_arg {
    param([string]$Subcmd, [string]$SubSubcmd, [string]$WordToComplete)

    $key = "$Subcmd/$SubSubcmd"
    switch ($key) {
        { $_ -in 'mcp/get', 'mcp/remove' } {
            $names = @(_claude_mcp_server_names)
            $names | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        { $_ -in 'plugin/disable', 'plugin/enable', 'plugin/uninstall', 'plugin/remove' } {
            $names = @(_claude_plugin_names)
            $names | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/SubcommandArgs.Tests.ps1 -Output Detailed"`
Expected: All PASS

**Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/SubcommandArgs.Tests.ps1
git commit -m "feat(ps): add MCP server and plugin name completion"
```

---

### Task 9: Documentation and CI

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `.github/workflows/test.yml`

**Step 1: Update `README.md`**

- Change the subtitle from "Currently provides **bash** tab-completion" to "Provides **bash** and **PowerShell** tab-completion"
- Add a PowerShell section under Features mentioning rich tooltips and built-in JSON parsing
- Add PowerShell installation instructions (dot-source `claude.ps1` in `$PROFILE`)
- Add PowerShell usage examples
- Add PowerShell testing section with Pester commands
- Add Pester to prerequisites

**Step 2: Update `CLAUDE.md`**

- Update Architecture section to mention `claude.ps1`
- Add PowerShell testing commands
- Add Pester to prerequisites

**Step 3: Update `.github/workflows/test.yml`**

Add a `powershell` job:

```yaml
  powershell:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    steps:
      - uses: actions/checkout@v4

      - name: Install Pester
        shell: pwsh
        run: |
          Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser

      - name: Run tests
        shell: pwsh
        run: Invoke-Pester tests/powershell/ -Output Detailed -EnableExit
```

**Step 4: Run all tests to verify nothing broke**

Run: `pwsh -Command "Invoke-Pester tests/powershell/ -Output Detailed"`
Run: `bashunit tests/`
Expected: All PASS

**Step 5: Commit**

```bash
git add README.md CLAUDE.md .github/workflows/test.yml
git commit -m "docs: add PowerShell completion to documentation and CI"
```
