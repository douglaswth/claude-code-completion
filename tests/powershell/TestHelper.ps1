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
    _ClaudeComplete -WordToComplete $wordToComplete -Elements $words
}

# Extract just the CompletionText values from completer results.
function Get-CompletionText {
    param([string]$CommandLine)
    Invoke-ClaudeCompleter $CommandLine | ForEach-Object { $_.CompletionText }
}
