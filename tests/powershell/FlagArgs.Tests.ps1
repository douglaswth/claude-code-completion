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
  --model <model>                Model for session (default: 'claude-test-9-99').
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

    $env:XDG_CACHE_HOME = $TestDrive
}

AfterAll {
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
        $results | Should -Contain 'auto'
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
        $results | Should -Contain 'max'
    }

    It 'completes input format choices' {
        $results = Get-CompletionText 'claude --input-format '
        $results | Should -Contain 'text'
        $results | Should -Contain 'stream-json'
    }

    It 'extracts model IDs from help text without trailing punctuation' {
        $results = Get-CompletionText 'claude --model '
        $results | Should -Contain 'claude-test-9-99'
        $results | Should -Not -Contain "claude-test-9-99')."
    }

    It 'filters model completions by partial input' {
        $results = Get-CompletionText 'claude --model so'
        $results | Should -Contain 'sonnet'
        $results | Should -Not -Contain 'opus'
    }
}

Describe 'Filesystem flag completion' {
    BeforeAll {
        $script:CompDir = (Get-Item $TestDrive).FullName
        New-Item -ItemType Directory -Path (Join-Path $script:CompDir 'subdir_one') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:CompDir 'subdir_two') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:CompDir 'file_alpha.txt') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:CompDir 'file_beta.log') -Force | Out-Null
    }

    It 'add-dir completes directories only' {
        $results = Get-CompletionText "claude --add-dir $($script:CompDir)/"
        $results | Should -Contain (Join-Path $script:CompDir 'subdir_one')
        $results | Should -Contain (Join-Path $script:CompDir 'subdir_two')
        $results | Should -Not -Contain (Join-Path $script:CompDir 'file_alpha.txt')
    }

    It 'plugin-dir completes directories only' {
        $results = Get-CompletionText "claude --plugin-dir $($script:CompDir)/"
        $results | Should -Contain (Join-Path $script:CompDir 'subdir_one')
        $results | Should -Contain (Join-Path $script:CompDir 'subdir_two')
        $results | Should -Not -Contain (Join-Path $script:CompDir 'file_alpha.txt')
    }

    It 'debug-file completes files only' {
        $results = Get-CompletionText "claude --debug-file $($script:CompDir)/"
        $results | Should -Contain (Join-Path $script:CompDir 'file_alpha.txt')
        $results | Should -Contain (Join-Path $script:CompDir 'file_beta.log')
        $results | Should -Not -Contain (Join-Path $script:CompDir 'subdir_one')
    }
}
