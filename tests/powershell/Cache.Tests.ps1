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
