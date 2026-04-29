# PowerShell completion for the claude CLI (Claude Code)
# https://github.com/anthropics/claude-code

function global:_ClaudeVersion {
    $output = claude --version 2>$null
    if ($output) {
        ($output -split '\s')[0]
    }
}

function global:_ClaudeCacheBase {
    if ($env:XDG_CACHE_HOME) {
        $env:XDG_CACHE_HOME
    } elseif ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
        $env:LOCALAPPDATA
    } else {
        Join-Path $HOME '.cache'
    }
}

function global:_ClaudeCacheDir {
    $version = _ClaudeVersion
    $base = _ClaudeCacheBase
    Join-Path (Join-Path (Join-Path $base 'claude-code-completion') 'powershell') $version
}

function global:_ClaudeEnsureCache {
    $dir = _ClaudeCacheDir
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function global:_ClaudeCleanupOldCache {
    $baseDir = Join-Path (Join-Path (_ClaudeCacheBase) 'claude-code-completion') 'powershell'

    if (-not (Test-Path $baseDir)) { return }

    $currentVersion = _ClaudeVersion
    Get-ChildItem -Path $baseDir -Directory | Where-Object {
        $_.Name -ne $currentVersion
    } | Remove-Item -Recurse -Force
}

function global:_ClaudeBuildCache {
    $cacheDir = _ClaudeCacheDir
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

    # Parse root level
    $helpOutput = claude --help 2>$null
    $helpLines = @($helpOutput -split "`n")
    Set-Content -Path (Join-Path $cacheDir '_root_help') -Value $helpOutput
    Set-Content -Path (Join-Path $cacheDir '_root_flags') -Value @(_ClaudeParseFlags -HelpLines $helpLines)
    Set-Content -Path (Join-Path $cacheDir '_root_flags_with_args') -Value @(_ClaudeParseFlagsWithArgs -HelpLines $helpLines)
    Set-Content -Path (Join-Path $cacheDir '_root_flag_descriptions') -Value @(_ClaudeParseFlagDescriptions -HelpLines $helpLines)
    $subcommands = @(_ClaudeParseSubcommands -HelpLines $helpLines)
    Set-Content -Path (Join-Path $cacheDir '_root_subcommands') -Value $subcommands

    # Parse each subcommand
    foreach ($subcmd in $subcommands) {
        if ([string]::IsNullOrWhiteSpace($subcmd)) { continue }
        $subHelp = claude $subcmd --help 2>$null
        if (-not $subHelp) { continue }
        $subHelpLines = @($subHelp -split "`n")
        Set-Content -Path (Join-Path $cacheDir "${subcmd}_flags") -Value @(_ClaudeParseFlags -HelpLines $subHelpLines)
        Set-Content -Path (Join-Path $cacheDir "${subcmd}_flags_with_args") -Value @(_ClaudeParseFlagsWithArgs -HelpLines $subHelpLines)
        Set-Content -Path (Join-Path $cacheDir "${subcmd}_flag_descriptions") -Value @(_ClaudeParseFlagDescriptions -HelpLines $subHelpLines)
        Set-Content -Path (Join-Path $cacheDir "${subcmd}_subcommands") -Value @(_ClaudeParseSubcommands -HelpLines $subHelpLines)
    }

    _ClaudeCleanupOldCache
}

function global:_ClaudeParseFlags {
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

function global:_ClaudeParseFlagsWithArgs {
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

function global:_ClaudeParseSubcommands {
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

function global:_ClaudeParseFlagDescriptions {
    param([string[]]$HelpLines)
    foreach ($line in $HelpLines) {
        if ($line -match '^\s+(-[a-zA-Z]),?\s+(--[a-zA-Z][-a-zA-Z]*)\s+.*?\s{2,}(\S.+)') {
            $desc = $Matches[3].TrimEnd()
            "$($Matches[1])`t$desc"
            "$($Matches[2])`t$desc"
        } elseif ($line -match '^\s+(--[a-zA-Z][-a-zA-Z]*).*?\s{2,}(\S.+)') {
            "$($Matches[1])`t$($Matches[2].TrimEnd())"
        }
    }
}

$script:_ClaudeKnownModels = @(
    'sonnet', 'opus', 'haiku',
    'claude-sonnet-4-5-20250514',
    'claude-sonnet-4-6',
    'claude-opus-4-5-20250514',
    'claude-opus-4-6',
    'claude-opus-4-7',
    'claude-haiku-4-5-20251001'
)

function global:_ClaudeCompleteFlagArg {
    param([string]$Flag, [string]$WordToComplete)

    switch ($Flag) {
        '--model' {
            $models = @($script:_ClaudeKnownModels)
            $cacheDir = _ClaudeCacheDir
            $helpFile = Join-Path $cacheDir '_root_help'
            if (Test-Path $helpFile) {
                foreach ($line in Get-Content $helpFile) {
                    if ($line -match '(claude-[a-z]+-[0-9][a-z0-9-]*)') {
                        $models += $Matches[1]
                    }
                }
            }
            $models | Select-Object -Unique | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        '--permission-mode' {
            @('acceptEdits', 'auto', 'bypassPermissions', 'default', 'dontAsk', 'plan') |
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
            @('low', 'medium', 'high', 'max') |
                Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
        { $_ -in '--resume', '-r' } {
            _ClaudeCompleteSessions -WordToComplete $WordToComplete
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

function global:_ClaudeResolveSymlinks {
    # Resolve symlinks in a Unix path by walking each component.
    # Needed because $pwd.Path preserves symlinks (e.g. /home -> /usr/home on
    # FreeBSD) but the Claude CLI stores sessions under the real path.
    param([string]$Path)
    $parts = $Path.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
    $resolved = ''
    foreach ($part in $parts) {
        $resolved += "/$part"
        $item = Get-Item -LiteralPath $resolved -ErrorAction SilentlyContinue
        if ($item.LinkTarget) {
            $target = $item.LinkTarget
            if (-not [System.IO.Path]::IsPathRooted($target)) {
                $parent = [System.IO.Path]::GetDirectoryName($resolved)
                $target = [System.IO.Path]::GetFullPath(
                    [System.IO.Path]::Combine($parent, $target))
            }
            $resolved = $target
        }
    }
    return $resolved
}

function global:_ClaudeEncodedCwd {
    # Encodes CWD to match Claude CLI's project directory naming.
    # Windows: C:\Users\foo → C--Users-foo (colon and backslashes become dashes)
    # Unix: /home/foo → -home-foo (slashes become dashes; colons preserved)
    if ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
        $pwd.Path -replace '[:\\/]', '-'
    } else {
        (_ClaudeResolveSymlinks $pwd.Path).Replace('/', '-')
    }
}

function global:_ClaudeSessionMessage {
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

function global:_ClaudeCompleteSessions {
    param([string]$WordToComplete)

    $encodedCwd = _ClaudeEncodedCwd
    # $env:HOME is checked first for testability ($HOME is immutable after startup)
    $homeDir = if ($env:HOME) { $env:HOME } else { $HOME }
    $sessionDir = Join-Path (Join-Path (Join-Path $homeDir '.claude') 'projects') $encodedCwd

    if (-not (Test-Path $sessionDir)) { return }

    $files = Get-ChildItem -Path $sessionDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10

    foreach ($file in $files) {
        $sessionId = $file.BaseName
        if ($sessionId -like "$WordToComplete*") {
            $msg = _ClaudeSessionMessage -FilePath $file.FullName
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

function global:_ClaudeMcpServerNames {
    $output = claude mcp list 2>$null
    if (-not $output) { return }
    foreach ($line in ($output -split "`n")) {
        if ($line -match ':' -and $line -notmatch '^Checking|^$') {
            ($line -split ':')[0].Trim()
        }
    }
}

function global:_ClaudePluginNames {
    $output = claude plugin list --json 2>$null
    if (-not $output) { return }
    try {
        $plugins = $output | ConvertFrom-Json
        foreach ($p in $plugins) {
            $p.name
        }
    } catch {}
}

function global:_ClaudeCompleteSubcmdArg {
    param([string]$Subcmd, [string]$SubSubcmd, [string]$WordToComplete)

    $key = "$Subcmd/$SubSubcmd"
    switch ($key) {
        { $_ -in 'mcp/get', 'mcp/remove' } {
            $names = @(_ClaudeMcpServerNames)
            $names | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        { $_ -in 'plugin/disable', 'plugin/enable', 'plugin/uninstall', 'plugin/remove' } {
            $names = @(_ClaudePluginNames)
            $names | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }
}

function global:_ClaudeComplete {
    param(
        [string]$WordToComplete,
        [string[]]$Elements
    )

    $cacheDir = _ClaudeCacheDir

    # Build cache if needed
    if (-not (Test-Path $cacheDir)) {
        _ClaudeBuildCache
    }

    # Find the subcommand (first non-flag element after 'claude')
    # Exclude the word being completed — matches bash behavior (i < cword)
    $subcmd = ''
    $subcmdIndex = -1
    $loopLimit = if ($WordToComplete -ne '') { $Elements.Count - 1 } else { $Elements.Count }
    for ($i = 1; $i -lt $loopLimit; $i++) {
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
            _ClaudeCompleteFlagArg -Flag $prev -WordToComplete $WordToComplete
            return
        }
    }

    if ($subcmd) {
        # Find sub-subcommand (also exclude the word being completed)
        $subSubcmd = ''
        for ($i = $subcmdIndex + 1; $i -lt $loopLimit; $i++) {
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
                $descFile = Join-Path $cacheDir "${subcmd}_flag_descriptions"
                $descriptions = @{}
                if (Test-Path $descFile) {
                    Get-Content $descFile | ForEach-Object {
                        $parts = $_ -split "`t", 2
                        if ($parts.Count -eq 2) { $descriptions[$parts[0]] = $parts[1] }
                    }
                }
                Get-Content $flagsFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    $tooltip = if ($descriptions.ContainsKey($_)) { $descriptions[$_] } else { $_ }
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $tooltip)
                }
            }
        } elseif ($subSubcmd) {
            # Complete positional args for sub-subcommands
            _ClaudeCompleteSubcmdArg -Subcmd $subcmd -SubSubcmd $subSubcmd -WordToComplete $WordToComplete
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
                $descFile = Join-Path $cacheDir '_root_flag_descriptions'
                $descriptions = @{}
                if (Test-Path $descFile) {
                    Get-Content $descFile | ForEach-Object {
                        $parts = $_ -split "`t", 2
                        if ($parts.Count -eq 2) { $descriptions[$parts[0]] = $parts[1] }
                    }
                }
                Get-Content $flagsFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                    $tooltip = if ($descriptions.ContainsKey($_)) { $descriptions[$_] } else { $_ }
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $tooltip)
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
    _ClaudeComplete -WordToComplete $wordToComplete -Elements $elements
}
