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

$script:_claude_known_models = @(
    'sonnet', 'opus', 'haiku',
    'claude-sonnet-4-5-20250514',
    'claude-sonnet-4-6',
    'claude-opus-4-5-20250514',
    'claude-opus-4-6',
    'claude-haiku-4-5-20251001'
)

function global:_claude_complete_flag_arg {
    param([string]$Flag, [string]$WordToComplete)

    switch ($Flag) {
        '--model' {
            $models = @($script:_claude_known_models)
            $cacheDir = _claude_cache_dir
            $helpFile = Join-Path $cacheDir '_root_help'
            if (Test-Path $helpFile) {
                foreach ($line in Get-Content $helpFile) {
                    if ($line -match '(claude-[a-z]+-[0-9][^\s]*)') {
                        $models += $Matches[1]
                    }
                }
            }
            $models | Select-Object -Unique | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        '--permission-mode' {
            @('acceptEdits', 'bypassPermissions', 'default', 'dontAsk', 'plan') |
                Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        '--output-format' {
            @('text', 'json', 'stream-json') |
                Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        '--input-format' {
            @('text', 'stream-json') |
                Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        '--effort' {
            @('low', 'medium', 'high') |
                Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        { $_ -in '--resume', '-r' } {
            _claude_complete_sessions -WordToComplete $WordToComplete
        }
        { $_ -in '--add-dir', '--plugin-dir' } {
            Get-ChildItem -Path "$WordToComplete*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, 'ProviderContainer', $_.FullName)
            }
        }
        { $_ -in '--debug-file', '--mcp-config', '--settings' } {
            Get-ChildItem -Path "$WordToComplete*" -File -ErrorAction SilentlyContinue | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, 'ProviderItem', $_.FullName)
            }
        }
        default {
            # Unknown flag arg — default to file completion
            Get-ChildItem -Path "$WordToComplete*" -ErrorAction SilentlyContinue | ForEach-Object {
                $type = if ($_.PSIsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
                [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, $type, $_.FullName)
            }
        }
    }
}

function global:_claude_encoded_cwd {
    $cwd = $pwd.Path
    if ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
        $cwd -replace '[:\\/]', '-'
    } else {
        $cwd.Replace('/', '-')
    }
}

function global:_claude_session_message {
    param([string]$FilePath)
    foreach ($line in Get-Content -Path $FilePath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
        } catch {
            continue
        }
        if ($obj.type -ne 'user') { continue }

        $content = $obj.message.content
        $text = $null
        if ($content -is [string]) {
            $text = $content
        } elseif ($content -is [array] -or $content.Count -gt 0) {
            foreach ($item in $content) {
                if ($item.type -eq 'text') {
                    $text = $item.text
                    break
                }
            }
        }
        if (-not $text) { continue }
        if ($text -match '<ide_' -or $text -match '<command-') { continue }

        return $text
    }
}

function global:_claude_complete_sessions {
    param([string]$WordToComplete)

    $encodedCwd = _claude_encoded_cwd
    $homeDir = if ($env:HOME) { $env:HOME } else { $HOME }
    $sessionDir = Join-Path $homeDir '.claude' 'projects' $encodedCwd

    if (-not (Test-Path $sessionDir)) { return }

    $files = Get-ChildItem -Path $sessionDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10

    foreach ($file in $files) {
        $sessionId = $file.BaseName
        if ($sessionId -like "$WordToComplete*") {
            $msg = _claude_session_message -FilePath $file.FullName
            if (-not $msg) { $msg = '(session)' }
            $listText = if ($msg.Length -gt 40) { $msg.Substring(0, 39) + [char]0x2026 } else { $msg }
            [System.Management.Automation.CompletionResult]::new(
                $sessionId,
                "$sessionId  $listText",
                'ParameterValue',
                $msg
            )
        }
    }
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
