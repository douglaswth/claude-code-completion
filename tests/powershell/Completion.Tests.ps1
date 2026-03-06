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

    $env:XDG_CACHE_HOME = $TestDrive
}

AfterAll {
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

    It 'exact subcommand without trailing space still completes as subcommand' {
        # "claude auth" (no trailing space) should offer "auth" as a subcommand,
        # not try to complete auth's children with "auth" as the prefix
        $results = Get-CompletionText 'claude auth'
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
