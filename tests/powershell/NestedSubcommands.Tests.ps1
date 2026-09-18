# Nesting beyond two levels: the command tree is walked to whatever depth
# `claude --help` actually describes, rather than a fixed subcmd/sub-subcmd
# pair. Mirrors tests/bash/nested_subcommands_test.bash — the two shells must
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
        'plugin enable --help' = @'
Usage: claude plugin enable [options] <plugin>

Options:
  -h, --help          Display help for command
  --enable-force      Force enabling the plugin
'@
        'plugin marketplace remove --help' = @'
Usage: claude plugin marketplace remove [options] <name>

Options:
  -h, --help          Display help for command
  --remove-force      Remove without confirmation
'@
        'hidden-runner --help' = @'
Usage: claude hidden-runner [options]

Connection:
  --api-url <url>     API base URL
  --client-label <label>
                      Observability label sent at registration
'@
        'mcp get --help' = @'
Usage: claude mcp get [options] <name>

Options:
  -h, --help        Display help
  --get-json        Print the server entry as JSON
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

    # Declared before the first completion, because the cache is built once
    # and a later assignment would not be seen by it.
    $script:ClaudeExtraSubcommands = @(
        [pscustomobject]@{ Name='hidden-runner'; Description='Run a hidden runner' }
    )
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

Describe 'Flags at a leaf that takes a positional argument' {
    # Regression: pruning nodes with a required <arg> meant their help was
    # never probed, so their flags were never cached and
    # `claude plugin install -<TAB>` offered nothing at all.

    It 'completes a leaf''s own flags' {
        Get-CompletionText 'claude plugin enable -' | Should -Contain '--enable-force'
    }

    It 'offers the leaf''s flags, not its parent''s' {
        Get-CompletionText 'claude plugin enable -' | Should -Not -Contain '--plugin-scope'
    }

    It 'completes a third-level leaf''s own flags' {
        Get-CompletionText 'claude plugin marketplace remove -' | Should -Contain '--remove-force'
    }

    It 'completes an mcp leaf''s own flags' {
        Get-CompletionText 'claude mcp get -' | Should -Contain '--get-json'
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
    It 'rejects help' {
        _ClaudeNodeIsProbeable -Name 'help' | Should -BeFalse
    }

    It 'accepts everything else' {
        # Including nodes that take a required argument: they cannot be
        # command groups, but their help still lists the flags they accept.
        _ClaudeNodeIsProbeable -Name 'marketplace' | Should -BeTrue
        _ClaudeNodeIsProbeable -Name 'get' | Should -BeTrue
        _ClaudeNodeIsProbeable -Name 'install' | Should -BeTrue
    }

    It 'leaves only help nodes unprobed' {
        Get-CompletionText 'claude plugin ' | Out-Null
        $cacheDir = _ClaudeCacheDir
        Join-Path $cacheDir 'plugin_help_flags' | Should -Not -Exist
        Join-Path $cacheDir 'plugin_enable_flags' | Should -Exist
        Join-Path $cacheDir 'mcp_get_flags' | Should -Exist
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
        # detection only checks for digits, so 0 can reach here — and an
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

Describe 'Hidden subcommands' {
    # A subcommand the CLI implements but omits from `claude --help`. The walk
    # can only learn names from that section, so without the bundled list it is
    # never probed and nothing about it completes.

    It 'offers the hidden subcommand' {
        Get-CompletionText 'claude hidden-' | Should -Contain 'hidden-runner'
    }

    It 'completes the hidden subcommand''s flags' {
        $r = Get-CompletionText 'claude hidden-runner --'
        $r | Should -Contain '--client-label'
        $r | Should -Contain '--api-url'
    }

    It 'carries its description as a tooltip' {
        $r = Invoke-ClaudeCompleter 'claude hidden-'
        ($r | Where-Object { $_.CompletionText -eq 'hidden-runner' }).ToolTip |
            Should -Be 'Run a hidden runner'
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
