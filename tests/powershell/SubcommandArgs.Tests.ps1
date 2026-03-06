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

Describe 'Sub-subcommand detection with intervening flags' {
    It 'finds sub-subcommand after flags' {
        $results = Get-CompletionText 'claude mcp --scope user get '
        $results | Should -Contain 'my-sentry'
        $results | Should -Contain 'my-github'
    }
}

Describe 'Subcommand flag with args' {
    BeforeAll {
        $script:CompDir = (Get-Item $TestDrive).FullName
        New-Item -ItemType File -Path (Join-Path $script:CompDir 'config.json') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:CompDir 'data.txt') -Force | Out-Null
    }

    It 'subcommand flag with args completes files' {
        $results = Get-CompletionText "claude mcp add --scope $($script:CompDir)/"
        $results | Should -Contain (Join-Path $script:CompDir 'config.json')
    }
}
