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
            $baseDir = Join-Path (Join-Path $script:TestCacheDir 'claude-code-completion') 'powershell'
            New-Item -ItemType Directory -Path (Join-Path $baseDir '0.9.0') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $baseDir '0.8.0') -Force | Out-Null

            _claude_cleanup_old_cache

            Test-Path (Join-Path $baseDir '0.9.0') | Should -BeFalse
            Test-Path (Join-Path $baseDir '0.8.0') | Should -BeFalse
        }

        It 'preserves the current version directory' {
            _claude_ensure_cache
            $dir = _claude_cache_dir
            $baseDir = Join-Path (Join-Path $script:TestCacheDir 'claude-code-completion') 'powershell'
            New-Item -ItemType Directory -Path (Join-Path $baseDir '0.9.0') -Force | Out-Null

            _claude_cleanup_old_cache

            Test-Path $dir | Should -BeTrue
        }
    }

    Context '_claude_build_cache' {
        BeforeEach {
            $script:TestCacheDir = Join-Path ([System.IO.Path]::GetTempPath()) "claude-test-cache-$([guid]::NewGuid())"
            $env:XDG_CACHE_HOME = $script:TestCacheDir

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

        AfterEach {
            if (Test-Path $script:TestCacheDir) {
                Remove-Item -Recurse -Force $script:TestCacheDir
            }
            $env:XDG_CACHE_HOME = $null
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
}
