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
  --from-pr [value]              Resume a session linked to a PR
  --mcp-debug                    [DEPRECATED. Use --debug instead] MCP debug
  -h, --help                     Display help
  -v, --version                  Output the version number

Commands:
  auth                           Manage authentication
  mcp                            Configure MCP servers
  plugin                         Manage plugins
'@
        $helpLines = $helpText -split "`n"
    }

    Context '_ClaudeParseFlags' {
        BeforeAll {
            $flags = @(_ClaudeParseFlags -HelpLines $helpLines)
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

    Context '_ClaudeParseFlagsWithArgs' {
        BeforeAll {
            $flagsWithArgs = @(_ClaudeParseFlagsWithArgs -HelpLines $helpLines)
        }

        It 'includes flags that take values' {
            $flagsWithArgs | Should -Contain '--model'
            $flagsWithArgs | Should -Contain '--add-dir'
        }

        It 'excludes boolean flags' {
            $flagsWithArgs | Should -Not -Contain '--continue'
            $flagsWithArgs | Should -Not -Contain '--print'
        }

        It 'includes optional-arg flags (they still take an argument)' {
            $flagsWithArgs | Should -Contain '--resume'
            $flagsWithArgs | Should -Contain '-r'
        }

        It 'excludes a flag whose description merely starts with a bracket' {
            # --mcp-debug takes no argument; "[DEPRECATED…]" is its description.
            # The single-space placeholder rule must not treat it as an argument.
            $flagsWithArgs | Should -Not -Contain '--mcp-debug'
        }
    }

    Context '_ClaudeParseFlagsWithOptionalArgs' {
        BeforeAll {
            $optionalArgs = @(_ClaudeParseFlagsWithOptionalArgs -HelpLines $helpLines)
        }

        It 'includes [value] flags and their short forms' {
            $optionalArgs | Should -Contain '--resume'
            $optionalArgs | Should -Contain '-r'
        }

        It 'includes a long-only optional-arg flag (no short form)' {
            $optionalArgs | Should -Contain '--from-pr'
        }

        It 'excludes required <value> flags' {
            $optionalArgs | Should -Not -Contain '--model'
            $optionalArgs | Should -Not -Contain '--add-dir'
        }

        It 'excludes a flag whose description merely starts with a bracket' {
            $optionalArgs | Should -Not -Contain '--mcp-debug'
        }
    }

    Context '_ClaudeParseFlagDescriptions' {
        BeforeAll {
            $descriptions = @(_ClaudeParseFlagDescriptions -HelpLines $helpLines)
        }

        It 'extracts description for short+long flag pair' {
            $descriptions | Should -Contain "--continue`tContinue most recent conversation"
            $descriptions | Should -Contain "-c`tContinue most recent conversation"
        }

        It 'extracts description for long-only flag' {
            $descriptions | Should -Contain "--add-dir`tAdditional directories"
        }

        It 'does not include non-flag lines' {
            ($descriptions | Where-Object { $_ -like 'prompt*' }) | Should -BeNullOrEmpty
        }

        It 'strips trailing CR from descriptions when help has CRLF line endings' {
            # Regression: Git's autocrlf checks .ps1 files out with CRLF on
            # Windows runners. The here-string in BeforeAll then carries CRLF,
            # and `-split "`n"` leaves trailing `\r` that the regex's `(\S.+)`
            # capture greedily picks up. The parser must tolerate this.
            $crlfHelp = "  --crlf-flag                    Description with CRLF`r`n"
            $crlfLines = $crlfHelp -split "`n"
            $crlfDescriptions = @(_ClaudeParseFlagDescriptions -HelpLines $crlfLines)
            $crlfDescriptions | Should -Contain "--crlf-flag`tDescription with CRLF"
        }
    }

    Context '_ClaudeParseSubcommands' {
        BeforeAll {
            $subcommands = @(_ClaudeParseSubcommands -HelpLines $helpLines)
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
