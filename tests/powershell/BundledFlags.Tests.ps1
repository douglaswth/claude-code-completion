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
