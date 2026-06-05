BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
}

Describe '_ClaudeVersion' {
    BeforeEach {
        # Back the `claude` command with a real on-disk executable whose
        # --version invocations are counted (each appends one byte to a
        # file). This lets us prove the result is memoized (no Node respawn
        # per tab) and that a realistic binary change — a new mtime, as an
        # upgrade would produce — correctly invalidates the memo.
        #
        # Windows can't run a `#!/bin/sh` script, so emit a `.cmd` batch mock
        # there and a shell script everywhere else. (Windows PowerShell 5.1
        # lacks $IsWindows, so fall back to the PS version for detection.)
        $script:OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
        $script:ExeDir = Join-Path $TestDrive "bin-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:ExeDir | Out-Null
        $script:Counter = Join-Path $script:ExeDir 'calls'
        if ($script:OnWindows) {
            $script:Exe = Join-Path $script:ExeDir 'claude.cmd'
            # `<nul set /p=x` appends exactly one byte (no newline), so the
            # counter length equals the invocation count.
            @"
@echo off
if "%~1"=="--version" goto version
if "%~1"=="--help" goto help
goto :eof
:version
<nul set /p=x>>"$($script:Counter)"
echo 1.0.0 (Claude Code)
goto :eof
:help
echo Usage: claude
goto :eof
"@ | Set-Content -Path $script:Exe
        } else {
            $script:Exe = Join-Path $script:ExeDir 'claude'
            @"
#!/bin/sh
case "`$*" in
  "--version") printf 'x' >> "$($script:Counter)"; echo "1.0.0 (Claude Code)";;
  "--help") echo "Usage: claude";;
esac
"@ | Set-Content -Path $script:Exe -NoNewline
            chmod +x $script:Exe
        }
        # Force `claude` to resolve to this mock executable: drop any function
        # mock left by other test files, and restrict PATH to only this dir so
        # the real installed CLI can't win. NOTE: a `global:`-qualified Function
        # provider path is NOT honored by Remove-Item, so remove via the
        # unqualified `function:claude`.
        if (Test-Path function:claude) { Remove-Item function:claude }
        $script:OldPath = $env:PATH
        $env:PATH = $script:ExeDir
    }

    AfterEach {
        $env:PATH = $script:OldPath
    }

    It 'returns the parsed version' {
        _ClaudeVersion | Should -Be '1.0.0'
    }

    It 'invokes claude --version only once across repeated calls' {
        _ClaudeVersion > $null
        _ClaudeVersion > $null
        _ClaudeVersion > $null
        (Get-Content $script:Counter -Raw).Length | Should -Be 1
    }

    It 'reinvokes after the binary mtime changes' {
        _ClaudeVersion > $null
        (Get-Content $script:Counter -Raw).Length | Should -Be 1
        # Simulate an upgrade: the binary on disk is rewritten (new mtime).
        (Get-Item $script:Exe).LastWriteTime = (Get-Date).AddYears(5)
        _ClaudeVersion > $null
        (Get-Content $script:Counter -Raw).Length | Should -Be 2
    }
}

Describe '_ClaudeVersion when claude is not resolvable' {
    BeforeEach {
        # No `claude` at all: drop any function mock and restrict PATH to an
        # empty dir so Get-Command returns nothing. _ClaudeVersion must
        # degrade gracefully rather than throw.
        if (Test-Path function:claude) { Remove-Item function:claude }
        $script:OldPath = $env:PATH
        $script:EmptyDir = Join-Path $TestDrive "empty-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:EmptyDir | Out-Null
        $env:PATH = $script:EmptyDir
    }

    AfterEach {
        $env:PATH = $script:OldPath
    }

    It 'returns nothing and does not throw when no claude command exists' {
        # A throw would surface here as a test error; the assertion covers the
        # graceful-degradation return value.
        _ClaudeVersion | Should -BeNullOrEmpty
    }
}
