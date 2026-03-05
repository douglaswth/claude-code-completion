BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
}

Describe 'Script skeleton' {
    It 'defines the _claude_complete function' {
        Get-Command _claude_complete -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'registers an argument completer for claude' {
        # Register-ArgumentCompleter doesn't have a public query API,
        # so we verify _claude_complete is callable and returns without error
        { _claude_complete -WordToComplete '' -Elements @('claude') } | Should -Not -Throw
    }
}
