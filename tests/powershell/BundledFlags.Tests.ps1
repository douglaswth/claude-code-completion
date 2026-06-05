BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
    New-DefaultMockClaude
}

Describe 'Bundled flag data structure' {
    It 'defines the ClaudeExtraFlags array' {
        ($null -ne $script:ClaudeExtraFlags) | Should -BeTrue
    }

    It 'is initialized as an array' {
        ,$script:ClaudeExtraFlags | Should -BeOfType ([System.Array])
    }

    It 'entries have the expected five-property schema' {
        $expectedProps = 'ArgType', 'Description', 'Name', 'Scope', 'TakesArg'
        foreach ($entry in $script:ClaudeExtraFlags) {
            ($entry.PSObject.Properties.Name | Sort-Object) -join ',' |
                Should -Be ($expectedProps -join ',')
        }
    }
}

Describe 'Bundled flag cache merging' {
    BeforeEach {
        $script:TestCacheDir = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        $env:XDG_CACHE_HOME = $script:TestCacheDir
        # Snapshot and clear the bundled list for each test
        $script:OriginalExtraFlags = $script:ClaudeExtraFlags
        $script:ClaudeExtraFlags = @()
    }

    AfterEach {
        $env:XDG_CACHE_HOME = $null
        $script:ClaudeExtraFlags = $script:OriginalExtraFlags
    }

    It 'adds a bundled root flag to _root_flags' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-root'; TakesArg='none'; ArgType='none'; Description='A bundled root flag' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir '_root_flags') | Should -Contain '--bundled-root'
    }

    It 'scopes bundled subcommand flag to its subcommand only' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='mcp'; Name='--bundled-mcp'; TakesArg='none'; ArgType='none'; Description='A bundled mcp flag' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir 'mcp_flags') | Should -Contain '--bundled-mcp'
        Get-Content (Join-Path $cacheDir '_root_flags') | Should -Not -Contain '--bundled-mcp'
    }

    It 'puts a required-arg bundled flag into _flags_with_args' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-arg'; TakesArg='required'; ArgType='dir'; Description='Takes a dir' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir '_root_flags_with_args') | Should -Contain '--bundled-arg'
        Get-Content (Join-Path $cacheDir '_root_flags_with_optional_args') | Should -Not -Contain '--bundled-arg'
    }

    It 'keeps a takes_arg=none bundled flag out of _flags_with_args' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-bool'; TakesArg='none'; ArgType='none'; Description='Boolean' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir '_root_flags_with_args') | Should -Not -Contain '--bundled-bool'
    }

    It 'puts an optional-arg bundled flag into both _flags_with_args and _flags_with_optional_args' {
        # e.g. --remote-control on versions that hide it from --help.
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-opt'; TakesArg='optional'; ArgType='unknown'; Description='Optional arg' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir '_root_flags_with_args') | Should -Contain '--bundled-opt'
        Get-Content (Join-Path $cacheDir '_root_flags_with_optional_args') | Should -Contain '--bundled-opt'
    }

    It 'dedupes bundled flag against --help-derived entry' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--model'; TakesArg='required'; ArgType='unknown'; Description='Stale bundled entry' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        $occurrences = (Get-Content (Join-Path $cacheDir '_root_flags') | Where-Object { $_ -eq '--model' }).Count
        $occurrences | Should -Be 1
    }

    It 'records bundled description in _flag_descriptions' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-desc'; TakesArg='none'; ArgType='none'; Description='Descriptive text' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        $content = Get-Content (Join-Path $cacheDir '_root_flag_descriptions') -Raw
        $content | Should -Match '--bundled-desc'
        $content | Should -Match 'Descriptive text'
    }
}

Describe 'Bundled arg-type completion' {
    BeforeEach {
        $script:TestCacheDir = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        $env:XDG_CACHE_HOME = $script:TestCacheDir
        $script:OriginalExtraFlags = $script:ClaudeExtraFlags
        $script:ClaudeExtraFlags = @()
    }

    AfterEach {
        $env:XDG_CACHE_HOME = $null
        $script:ClaudeExtraFlags = $script:OriginalExtraFlags
    }

    It 'completes choices for arg_type=choice:a,b,c' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--my-choice'; TakesArg='required'; ArgType='choice:alpha,beta,gamma'; Description='Choice flag' }
        )
        _ClaudeBuildCache
        $results = Get-CompletionText 'claude --my-choice '
        $results | Should -Contain 'alpha'
        $results | Should -Contain 'beta'
        $results | Should -Contain 'gamma'
    }

    It 'sidecar file written for bundled arg_type entries' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--my-dir'; TakesArg='required'; ArgType='dir'; Description='Dir flag' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        $content = Get-Content (Join-Path $cacheDir '_root_flag_arg_types') -Raw
        $content | Should -Match '--my-dir\tdir'
    }

    It 'dir arg-type completes against absolute path prefix' {
        # Regression: the dispatch must use -Path/$_.FullName like the named
        # --add-dir/--plugin-dir arms, not -Filter/$_.Name (which would only
        # work for bare leaf prefixes in the current directory).
        $tmp = Join-Path $TestDrive "dirtest-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'subdir') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $tmp 'file.txt') -Force | Out-Null
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--my-dir'; TakesArg='required'; ArgType='dir'; Description='Dir flag' }
        )
        _ClaudeBuildCache
        $results = Get-CompletionText "claude --my-dir $tmp/"
        $results | Should -Contain (Join-Path $tmp 'subdir')
        $results | Should -Not -Contain (Join-Path $tmp 'file.txt')
    }
}
