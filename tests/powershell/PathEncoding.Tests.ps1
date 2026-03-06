BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
}

Describe 'Path encoding' {
    It 'replaces path separators with dashes' {
        $testDir = Join-Path (Join-Path $TestDrive 'foo') 'bar'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Push-Location $testDir
        try {
            $result = _claude_encoded_cwd
            $result | Should -Not -Match '[/\\]'
            $result | Should -BeLike '*-foo-bar'
        } finally {
            Pop-Location
        }
    }

    It 'encodes current directory without error' {
        $result = _claude_encoded_cwd
        $result | Should -Not -BeNullOrEmpty
    }
}
