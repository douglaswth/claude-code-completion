# The cache build shells out to `claude` once per node in the command tree,
# and does it while the user is sitting at a prompt. A probe that inherits
# that terminal on stdin can swallow characters the user typed ahead — and on
# a POSIX host, if the shell doing the launching has job control on, the
# kernel stops any background process group that touches the controlling
# terminal, which is how claude.bash came to publish caches with nothing below
# the root. PowerShell never puts its children in a group of their own, so it
# cannot be stopped that way, but the inherited stdin is the same.
#
# Two things make this file unlike the rest of the suite:
#
#   * `claude` is a real executable, not TestHelper's in-process function.
#     _ClaudeCanProbeInParallel gates on CommandType -eq 'Application', and a
#     function is not one — so every function-mock test takes the serial
#     branch and the -Parallel block goes unexercised. Only an on-disk
#     executable reaches it. (A .ps1 would not: PowerShell resolves it as
#     ExternalScript, which fails the same gate. Hence .cmd on Windows, as in
#     VersionCache.Tests.ps1, and an extensionless script elsewhere.)
#
#   * the build runs in a child process, because the property under test is
#     what a probe inherits on stdin, and that means starting it with a known
#     stdin — which Start-Process can do and an in-process call cannot.
#
# Both shims delegate to one PowerShell implementation of the canned help, so
# the help text is written once and reaches the parser byte-for-byte. Emitting
# it from batch would not: cmd's `echo` eats a leading space, and the parser
# keys on the two-space indentation.

Describe 'Cache-build probes and the terminal they were launched from' {
    BeforeAll {
        # Windows PowerShell 5.1 has no $IsWindows, so fall back to the version.
        $script:OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
        $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

        $script:Work = Join-Path $TestDrive "iso-$([guid]::NewGuid())"
        $script:MockBin = Join-Path $script:Work 'bin'
        New-Item -ItemType Directory -Path $script:MockBin -Force | Out-Null
        $script:StdinLog = Join-Path $script:Work 'stdin.log'

        # The canned tree: root, three children, and children of two of them,
        # so the build runs more than one level and more than one probe.
        $impl = @'
# Record anything this probe manages to take off the stdin it inherited.
$stolen = [Console]::In.ReadLine()
if ($null -ne $stolen -and $env:CLAUDE_TEST_STDIN_LOG) {
    Add-Content -Path $env:CLAUDE_TEST_STDIN_LOG -Value $stolen -ErrorAction SilentlyContinue
}

# Emitted line by line rather than from here-strings: this whole script is
# itself inside one, and a nested terminator would close the outer.
switch (($args -join ' ')) {
    '--version' { '1.0.0 (Claude Code)'; break }
    '--help' {
        'Usage: claude [options] [command] [prompt]'
        ''
        'Options:'
        '  -h, --help        Display help'
        ''
        'Commands:'
        '  auth              Manage authentication'
        '  doctor            Check health of auto-updater'
        '  mcp               Configure MCP servers'
        break
    }
    'auth --help' {
        'Usage: claude auth [options] [command]'
        ''
        'Options:'
        '  -h, --help        Display help'
        ''
        'Commands:'
        '  login             Sign in'
        '  logout            Log out'
        break
    }
    'mcp --help' {
        'Usage: claude mcp [options] [command]'
        ''
        'Options:'
        '  -h, --help        Display help'
        ''
        'Commands:'
        '  get <name>        Get server'
        '  list              List servers'
        break
    }
    default {
        # Every leaf still answers, so no probe file comes back empty and
        # gets read as a failure.
        "Usage: claude $($args -join ' ')"
        ''
        'Options:'
        '  -h, --help        Display help'
    }
}
'@
        $implPath = Join-Path $script:MockBin 'claude-impl.ps1'
        Set-Content -Path $implPath -Value $impl

        # Whatever host is running these tests runs the implementation too, so
        # the shim needs nothing from PATH.
        $host_exe = (Get-Process -Id $PID).Path
        if ($script:OnWindows) {
            $script:MockPath = Join-Path $script:MockBin 'claude.cmd'
            Set-Content -Path $script:MockPath -NoNewline -Value (@(
                '@echo off'
                "`"$host_exe`" -NoProfile -File `"$implPath`" %*"
            ) -join "`r`n")
        } else {
            $script:MockPath = Join-Path $script:MockBin 'claude'
            Set-Content -Path $script:MockPath -NoNewline -Value (@(
                '#!/bin/sh'
                "exec `"$host_exe`" -NoProfile -File `"$implPath`" `"`$@`""
            ) -join "`n")
            & chmod 755 $script:MockPath
        }

        # More lines than the tree has nodes, so a theft cannot be masked by
        # the probes running out of input to take.
        $script:Feed = Join-Path $script:Work 'feed.txt'
        Set-Content -Path $script:Feed -Value (0..63 | ForEach-Object { "TYPED-AHEAD-$_" })

        # How `claude` resolved, recorded by the process that actually built
        # the cache. Asserting it in *this* process would answer a different
        # question: a function mock left behind by another test file shadows
        # PATH here, and does not exist in the child at all.
        $script:ProbeInfo = Join-Path $script:Work 'probe-info.txt'
        $script:Builder = Join-Path $script:Work 'build.ps1'
        Set-Content -Path $script:Builder -Value @(
            ". '$($script:Root)/claude.ps1'"
            "Set-Content -Path '$($script:ProbeInfo)' -Value @("
            '    "commandtype=$((Get-Command claude).CommandType)"'
            '    "parallel=$(_ClaudeCanProbeInParallel)"'
            ')'
            '_ClaudeBuildCache'
        )

        $script:CacheHome = Join-Path $script:Work 'cache'
        New-Item -ItemType Directory -Path $script:CacheHome -Force | Out-Null

        $script:OldPath = $env:PATH
        $env:CLAUDE_TEST_STDIN_LOG = $script:StdinLog
        $env:XDG_CACHE_HOME = $script:CacheHome
        $env:PATH = "$($script:MockBin)$([IO.Path]::PathSeparator)$env:PATH"

        Start-Process -FilePath $host_exe `
            -ArgumentList @('-NoProfile', '-File', $script:Builder) `
            -RedirectStandardInput $script:Feed `
            -RedirectStandardOutput (Join-Path $script:Work 'out.log') `
            -RedirectStandardError (Join-Path $script:Work 'err.log') `
            -NoNewWindow -Wait

        $script:CacheDir = Get-ChildItem -Directory -ErrorAction SilentlyContinue `
            -Path (Join-Path (Join-Path $script:CacheHome 'claude-code-completion') 'powershell') |
            Select-Object -First 1
    }

    AfterAll {
        $env:PATH = $script:OldPath
        $env:CLAUDE_TEST_STDIN_LOG = $null
        $env:XDG_CACHE_HOME = $null
    }

    It 'resolves the mock as an Application, so the parallel branch is reachable' {
        # If this ever regresses to a function or a .ps1, the assertions below
        # still pass while testing the serial path only.
        $info = @(Get-Content $script:ProbeInfo)
        $info | Should -Contain 'commandtype=Application'
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # -Parallel is 7+; 5.1 probes serially by design, and then this
            # file is covering the serial branch instead.
            $info | Should -Contain 'parallel=True'
        }
    }

    It 'builds a complete cache' {
        # Also the guard that makes the stdin assertion mean something: if no
        # probe ran, nothing could have been stolen either.
        $script:CacheDir | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $script:CacheDir.FullName 'mcp_flags') | Should -BeTrue
        Test-Path (Join-Path $script:CacheDir.FullName 'auth_login_flags') | Should -BeTrue
    }

    It 'takes nothing from the stdin it was launched with' {
        $stolen = if (Test-Path $script:StdinLog) { @(Get-Content $script:StdinLog) } else { @() }
        $stolen -join ',' | Should -BeExactly ''
    }
}
