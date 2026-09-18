# Nesting beyond two levels: the command tree is walked to whatever depth
# `claude --help` actually describes, rather than a fixed subcmd/sub-subcmd
# pair. Mirrors tests/bash/nested_subcommands_test.bash -- the two shells must
# behave identically here.

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
  deep                           Four-level nesting probe
  mcp                            Configure MCP servers
  plugin                         Manage plugins
'@
        'plugin --help' = @'
Usage: claude plugin [options] [command]

Options:
  -h, --help                           Display help
  --plugin-scope <scope>               Scope for plugin operations

Commands:
  enable [options] <plugin>            Enable a disabled plugin
  eval [options] [target]              Run eval cases (<eval dir>/**/case.yaml
                                       or prompt.md) against a plugin
  help [command]                       display help for command
  list [options]                       List installed plugins
  marketplace                          Manage Claude Code marketplaces
'@
        'plugin marketplace --help' = @'
Usage: claude plugin marketplace [options] [command]

Options:
  -h, --help                  Display help for command
  --marketplace-force         Force the marketplace operation

Commands:
  add [options] <source>      Add a marketplace from a URL, path, or GitHub repo
  list [options]              List all configured marketplaces
  remove [options] <name>     Remove a configured marketplace
  update [options] [name]     Update marketplace(s) from their source
'@
        'plugin eval --help' = @'
Usage: claude plugin eval [options] [command] [target]

Options:
  -h, --help        Display help for command

Commands:
  init [options]    Scaffold an eval suite
'@
        'plugin marketplace list --json' = '[{"name":"claude-plugins-official","source":"github"},{"name":"community-marketplace","source":"git"}]'
        'mcp --help' = @'
Usage: claude mcp [options] [command]

Options:
  -h, --help                Display help

Commands:
  get <name>                Get server
  list                      List servers
'@
        'deep --help' = @'
Usage: claude deep [options] [command]

Options:
  -h, --help        Display help

Commands:
  one               Level one
'@
        'deep one --help' = @'
Usage: claude deep one [options] [command]

Options:
  -h, --help        Display help

Commands:
  two               Level two
'@
        'deep one two --help' = @'
Usage: claude deep one two [options] [command]

Options:
  -h, --help        Display help

Commands:
  three             Level three
'@
        'deep one two three --help' = @'
Usage: claude deep one two three [options]

Options:
  -h, --help            Display help
  --bottom-flag         A flag only the deepest node has
'@
    }

    $env:XDG_CACHE_HOME = $TestDrive
}

AfterAll {
    $env:XDG_CACHE_HOME = $null
}

Describe 'Third-level subcommand completion' {
    It 'completes plugin marketplace subcommands' {
        $results = Get-CompletionText 'claude plugin marketplace '
        $results | Should -Contain 'add'
        $results | Should -Contain 'list'
        $results | Should -Contain 'remove'
        $results | Should -Contain 'update'
    }

    It 'filters third-level subcommands by prefix' {
        $results = Get-CompletionText 'claude plugin marketplace re'
        $results | Should -Contain 'remove'
        $results | Should -Not -Contain 'add'
    }

    It 'carries tooltips at the third level' {
        $results = Invoke-ClaudeCompleter 'claude plugin marketplace '
        $remove = $results | Where-Object { $_.CompletionText -eq 'remove' }
        $remove.ToolTip | Should -Be 'Remove a configured marketplace'
    }

    It 'probes a group whose description contains angle brackets' {
        $results = Get-CompletionText 'claude plugin eval '
        $results | Should -Contain 'init'
    }
}

Describe 'Depth is not hardcoded' {
    It 'completes a fourth level' {
        $results = Get-CompletionText 'claude deep one two '
        $results | Should -Contain 'three'
    }

    It 'completes flags at a fourth level' {
        $results = Get-CompletionText 'claude deep one two three -'
        $results | Should -Contain '--bottom-flag'
    }
}

Describe 'Flag scope follows the resolved path' {
    It 'offers the deepest node flags, not its parent''s' {
        $results = Get-CompletionText 'claude plugin marketplace -'
        $results | Should -Contain '--marketplace-force'
        $results | Should -Not -Contain '--plugin-scope'
    }
}

Describe 'Third-level positional arguments' {
    It 'completes marketplace names for remove' {
        $results = Get-CompletionText 'claude plugin marketplace remove '
        $results | Should -Contain 'claude-plugins-official'
        $results | Should -Contain 'community-marketplace'
    }

    It 'completes marketplace names for update' {
        $results = Get-CompletionText 'claude plugin marketplace update '
        $results | Should -Contain 'claude-plugins-official'
    }
}

Describe 'Pruning' {
    It 'rejects help and required-argument nodes' {
        _ClaudeNodeIsProbeable -Name 'help' -Term 'help [command]' | Should -BeFalse
        _ClaudeNodeIsProbeable -Name 'get' -Term 'get <name>' | Should -BeFalse
    }

    It 'accepts real command groups' {
        _ClaudeNodeIsProbeable -Name 'marketplace' -Term 'marketplace' | Should -BeTrue
        _ClaudeNodeIsProbeable -Name 'eval' -Term 'eval [options] [target]' | Should -BeTrue
    }

    It 'never probes a pruned node' {
        Get-CompletionText 'claude plugin ' | Out-Null
        $cacheDir = _ClaudeCacheDir
        Join-Path $cacheDir 'plugin_enable_subcommands' | Should -Not -Exist
        Join-Path $cacheDir 'plugin_help_subcommands' | Should -Not -Exist
        Join-Path $cacheDir 'mcp_get_subcommands' | Should -Not -Exist
    }

    It 'does not publish the raw help staging dir' {
        Get-CompletionText 'claude plugin ' | Out-Null
        Join-Path (_ClaudeCacheDir) '.raw' | Should -Not -Exist
    }
}

Describe 'Probe concurrency' {
    It 'is twice the core count' {
        _ClaudeProbeConcurrency -Cores 4 | Should -Be 8
    }

    It 'floors at two' {
        # A single-core container must not launch eight Node processes.
        _ClaudeProbeConcurrency -Cores 1 | Should -Be 2
    }

    It 'caps at sixteen' {
        # Each probe costs real memory, so a very wide machine is still bounded.
        _ClaudeProbeConcurrency -Cores 64 | Should -Be 16
    }

    It 'detects a positive core count' {
        _ClaudeProbeConcurrency | Should -BeGreaterOrEqual 2
    }

    It 'clamps a zero core count' {
        # NUMBER_OF_PROCESSORS is an ordinary environment variable that
        # detection only checks for digits, so 0 can reach here -- and an
        # unclamped 0 divides by zero in the bash build loop's throttle.
        _ClaudeProbeConcurrency -Cores 0 | Should -Be 2
    }
}

Describe 'Cache build housekeeping' {
    It 'removes a staging dir left behind by an interrupted build' {
        # The atomic build-then-rename guarantee rests on this: a crashed
        # build leaves .tmp.<pid> behind, and the next build must clear it
        # rather than merge into it. bash rm -rf's unconditionally, so this
        # branch exists only in PowerShell.
        $stale = "$(_ClaudeCacheDir).tmp.$PID"
        New-Item -ItemType Directory -Path $stale -Force | Out-Null
        Set-Content -Path (Join-Path $stale 'stale_marker') -Value 'from a crashed build'

        _ClaudeBuildCache

        $stale | Should -Not -Exist
        Join-Path (_ClaudeCacheDir) 'stale_marker' | Should -Not -Exist
        Join-Path (_ClaudeCacheDir) '_root_help' | Should -Exist
    }

    It 'honours an explicit concurrency override' {
        $script:ClaudeProbeConcurrency = 3
        try {
            _ClaudeBuildCache
            Join-Path (_ClaudeCacheDir) 'plugin_marketplace_subcommands' | Should -Exist
        } finally {
            $script:ClaudeProbeConcurrency = $null
        }
    }
}

Describe 'Existing behaviour is unchanged' {
    It 'still completes the second level' {
        $results = Get-CompletionText 'claude plugin '
        $results | Should -Contain 'marketplace'
        $results | Should -Contain 'eval'
        $results | Should -Contain 'list'
    }

    It 'still completes the root level' {
        $results = Get-CompletionText 'claude '
        $results | Should -Contain 'plugin'
        $results | Should -Contain 'mcp'
    }

    It 'offers nothing for a leaf with no subcommands' {
        $results = Get-CompletionText 'claude mcp list '
        $results | Should -BeNullOrEmpty
    }
}
