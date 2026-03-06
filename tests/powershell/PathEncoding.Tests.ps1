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
            $result = _ClaudeEncodedCwd
            $result | Should -Not -Match '[/\\]'
            $result | Should -BeLike '*-foo-bar'
        } finally {
            Pop-Location
        }
    }

    It 'encodes current directory without error' {
        $result = _ClaudeEncodedCwd
        $result | Should -Not -BeNullOrEmpty
    }

    It 'resolves symlinks in path' -Skip:($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
        $realDir = Join-Path (Join-Path $TestDrive 'real') 'project'
        $linkDir = Join-Path $TestDrive 'link'
        New-Item -ItemType Directory -Path $realDir -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path $linkDir -Target (Join-Path $TestDrive 'real') | Out-Null
        Push-Location (Join-Path $linkDir 'project')
        try {
            $result = _ClaudeEncodedCwd
            $result | Should -BeLike '*-real-project'
            $result | Should -Not -BeLike '*-link-*'
        } finally {
            Pop-Location
            Remove-Item $linkDir -Force
        }
    }
}
