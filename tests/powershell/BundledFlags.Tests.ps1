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
            [pscustomobject]@{ Scope='_root'; Name='--bundled-root'; TakesArg=$false; ArgType='none'; Description='A bundled root flag' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir '_root_flags') | Should -Contain '--bundled-root'
    }

    It 'scopes bundled subcommand flag to its subcommand only' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='mcp'; Name='--bundled-mcp'; TakesArg=$false; ArgType='none'; Description='A bundled mcp flag' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir 'mcp_flags') | Should -Contain '--bundled-mcp'
        Get-Content (Join-Path $cacheDir '_root_flags') | Should -Not -Contain '--bundled-mcp'
    }

    It 'puts takes_arg=true bundled flag into _flags_with_args' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-arg'; TakesArg=$true; ArgType='dir'; Description='Takes a dir' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir '_root_flags_with_args') | Should -Contain '--bundled-arg'
    }

    It 'dedupes bundled flag against --help-derived entry' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--model'; TakesArg=$true; ArgType='unknown'; Description='Stale bundled entry' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        $occurrences = (Get-Content (Join-Path $cacheDir '_root_flags') | Where-Object { $_ -eq '--model' }).Count
        $occurrences | Should -Be 1
    }

    It 'records bundled description in _flag_descriptions' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-desc'; TakesArg=$false; ArgType='none'; Description='Descriptive text' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        $content = Get-Content (Join-Path $cacheDir '_root_flag_descriptions') -Raw
        $content | Should -Match '--bundled-desc'
        $content | Should -Match 'Descriptive text'
    }
}
