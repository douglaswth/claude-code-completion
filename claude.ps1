# PowerShell completion for the claude CLI (Claude Code)
# https://github.com/anthropics/claude-code

function global:_claude_version {
    $output = claude --version 2>$null
    if ($output) {
        ($output -split '\s')[0]
    }
}

function global:_claude_cache_dir {
    $version = _claude_version
    if ($env:XDG_CACHE_HOME) {
        $base = $env:XDG_CACHE_HOME
    } elseif ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
        $base = $env:LOCALAPPDATA
    } else {
        $base = Join-Path $HOME '.cache'
    }
    Join-Path $base 'claude-code-completion' 'powershell' $version
}

function global:_claude_ensure_cache {
    $dir = _claude_cache_dir
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function global:_claude_cleanup_old_cache {
    if ($env:XDG_CACHE_HOME) {
        $base = $env:XDG_CACHE_HOME
    } elseif ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
        $base = $env:LOCALAPPDATA
    } else {
        $base = Join-Path $HOME '.cache'
    }
    $baseDir = Join-Path $base 'claude-code-completion' 'powershell'

    if (-not (Test-Path $baseDir)) { return }

    $currentVersion = _claude_version
    Get-ChildItem -Path $baseDir -Directory | Where-Object {
        $_.Name -ne $currentVersion
    } | Remove-Item -Recurse -Force
}

function global:_claude_build_cache {
    $cacheDir = _claude_cache_dir
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

    # Parse root level
    $helpOutput = claude --help 2>$null
    $helpLines = @($helpOutput -split "`n")
    Set-Content -Path (Join-Path $cacheDir '_root_help') -Value $helpOutput
    _claude_parse_flags -HelpLines $helpLines | Set-Content -Path (Join-Path $cacheDir '_root_flags')
    _claude_parse_flags_with_args -HelpLines $helpLines | Set-Content -Path (Join-Path $cacheDir '_root_flags_with_args')
    $subcommands = @(_claude_parse_subcommands -HelpLines $helpLines)
    $subcommands | Set-Content -Path (Join-Path $cacheDir '_root_subcommands')

    # Parse each subcommand
    foreach ($subcmd in $subcommands) {
        if ([string]::IsNullOrWhiteSpace($subcmd)) { continue }
        $subHelp = claude $subcmd --help 2>$null
        if (-not $subHelp) { continue }
        $subHelpLines = @($subHelp -split "`n")
        _claude_parse_flags -HelpLines $subHelpLines | Set-Content -Path (Join-Path $cacheDir "${subcmd}_flags")
        _claude_parse_flags_with_args -HelpLines $subHelpLines | Set-Content -Path (Join-Path $cacheDir "${subcmd}_flags_with_args")
        _claude_parse_subcommands -HelpLines $subHelpLines | Set-Content -Path (Join-Path $cacheDir "${subcmd}_subcommands")
    }

    _claude_cleanup_old_cache
}

function global:_claude_parse_flags {
    param([string[]]$HelpLines)
    foreach ($line in $HelpLines) {
        if ($line -match '^\s+(-[a-zA-Z]),?\s+(--[a-zA-Z][-a-zA-Z]*)') {
            $Matches[1]
            $Matches[2]
        } elseif ($line -match '^\s+(--[a-zA-Z][-a-zA-Z]*)') {
            $Matches[1]
        }
    }
}

function global:_claude_parse_flags_with_args {
    param([string[]]$HelpLines)
    foreach ($line in $HelpLines) {
        if ($line -match '^\s+(-[a-zA-Z]),?\s+(--[a-zA-Z][-a-zA-Z]*)\s+[<\[]') {
            $Matches[1]
            $Matches[2]
        } elseif ($line -match '^\s+(--[a-zA-Z][-a-zA-Z]*)\s+[<\[]') {
            $Matches[1]
        }
    }
}

function global:_claude_parse_subcommands {
    param([string[]]$HelpLines)
    $inCommands = $false
    foreach ($line in $HelpLines) {
        if ($line -match '^Commands:') {
            $inCommands = $true
            continue
        }
        if ($inCommands) {
            if ([string]::IsNullOrEmpty($line)) { continue }
            if ($line -notmatch '^\s') { break }
            if ($line -match '^\s+([a-zA-Z][-a-zA-Z]*)') {
                $Matches[1]
            }
        }
    }
}

function global:_claude_complete_flag_arg {
    param([string]$Flag, [string]$WordToComplete)
    # TODO: implement in Task 6
}

function global:_claude_complete_subcmd_arg {
    param([string]$Subcmd, [string]$SubSubcmd, [string]$WordToComplete)
    # TODO: implement in Task 8
}

function global:_claude_complete {
    param(
        [string]$WordToComplete,
        [string[]]$Elements
    )

    $cacheDir = _claude_cache_dir

    # Build cache if needed
    if (-not (Test-Path $cacheDir)) {
        _claude_build_cache
    }

    # Find the subcommand (first non-flag element after 'claude')
    $subcmd = ''
    $subcmdIndex = -1
    for ($i = 1; $i -lt $Elements.Count; $i++) {
        if ($Elements[$i] -notlike '-*') {
            $potential = $Elements[$i]
            $subcmdFile = Join-Path $cacheDir '_root_subcommands'
            if ((Test-Path $subcmdFile) -and ((Get-Content $subcmdFile) -contains $potential)) {
                $subcmd = $potential
                $subcmdIndex = $i
                break
            }
        }
    }

    # Determine the previous element (for flag-argument detection)
    $prev = if ($Elements.Count -ge 2 -and $WordToComplete -eq '') {
        $Elements[-1]
    } elseif ($Elements.Count -ge 3 -and $WordToComplete -ne '') {
        $Elements[-2]
    } else { '' }

    # Check if previous word is a flag that takes an argument
    if ($prev -like '-*') {
        $flagsWithArgsFile = if ($subcmd) {
            Join-Path $cacheDir "${subcmd}_flags_with_args"
        } else {
            Join-Path $cacheDir '_root_flags_with_args'
        }
        if ((Test-Path $flagsWithArgsFile) -and ((Get-Content $flagsWithArgsFile) -contains $prev)) {
            _claude_complete_flag_arg -Flag $prev -WordToComplete $WordToComplete
            return
        }
    }

    if ($subcmd) {
        # Find sub-subcommand
        $subSubcmd = ''
        for ($i = $subcmdIndex + 1; $i -lt $Elements.Count; $i++) {
            if ($Elements[$i] -notlike '-*') {
                $potential = $Elements[$i]
                $subSubFile = Join-Path $cacheDir "${subcmd}_subcommands"
                if ((Test-Path $subSubFile) -and ((Get-Content $subSubFile) -contains $potential)) {
                    $subSubcmd = $potential
                    break
                }
            }
        }

        if ($WordToComplete -like '-*') {
            # Complete subcommand flags
            $flagsFile = Join-Path $cacheDir "${subcmd}_flags"
            if (Test-Path $flagsFile) {
                Get-Content $flagsFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
                }
            }
        } elseif ($subSubcmd) {
            # Complete positional args for sub-subcommands
            _claude_complete_subcmd_arg -Subcmd $subcmd -SubSubcmd $subSubcmd -WordToComplete $WordToComplete
        } else {
            # Complete sub-subcommands
            $subFile = Join-Path $cacheDir "${subcmd}_subcommands"
            if (Test-Path $subFile) {
                Get-Content $subFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'Command', $_)
                }
            }
        }
    } else {
        # Top level
        if ($WordToComplete -like '-*') {
            # Complete flags
            $flagsFile = Join-Path $cacheDir '_root_flags'
            if (Test-Path $flagsFile) {
                Get-Content $flagsFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
                }
            }
        } else {
            # Complete subcommands
            $subFile = Join-Path $cacheDir '_root_subcommands'
            if (Test-Path $subFile) {
                Get-Content $subFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'Command', $_)
                }
            }
        }
    }
}

Register-ArgumentCompleter -CommandName claude -Native -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.ToString() })
    _claude_complete -WordToComplete $wordToComplete -Elements $elements
}
