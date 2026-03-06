BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
    New-DefaultMockClaude
    $env:XDG_CACHE_HOME = $TestDrive
}

AfterAll {
    $env:XDG_CACHE_HOME = $null
}

Describe 'Script skeleton' {
    It 'defines the _ClaudeComplete function' {
        Get-Command _ClaudeComplete -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'registers an argument completer for claude' {
        # Register-ArgumentCompleter doesn't have a public query API,
        # so we verify _ClaudeComplete is callable and returns without error
        { _ClaudeComplete -WordToComplete '' -Elements @('claude') } | Should -Not -Throw
    }
}
