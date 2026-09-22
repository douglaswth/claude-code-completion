# PowerShell completion for the claude CLI (Claude Code)
# https://github.com/anthropics/claude-code

# Cache schema version. Bump on any change to bundled-flag data, sidecar
# file format, or cache layout. Bumps invalidate existing caches for the
# same CLI version.
$script:ClaudeCacheVersion = 11

# Maximum concurrent `claude ... --help` probes during a cache build. Each is
# a Node cold start, so the per-level fan-out is batched rather than unbounded.
# Left null so it is derived from the core count per build by
# _ClaudeProbeConcurrency; set it to pin a value (the test suite does).
$script:ClaudeProbeConcurrency = $null

# Safety valve on the command-tree walk. Nothing in the CLI approaches this;
# it exists so a pathological help output can never spin the build forever.
$script:ClaudeMaxDepth = 6

# Bundled flags last extended through CHANGELOG version: 2.1.276
# (The skill at .claude/skills/refresh-bundled-flags/ updates this marker.)
#
# Each entry has fields: Scope, Name, TakesArg, ArgType, Description
#   Scope       — '_root' or a subcommand name (mcp, plugin, agents, …)
#   Name        — flag form (e.g. --foo). Short forms are separate entries.
#   TakesArg    — 'none' | 'required' | 'optional'
#                 (required = <value>; optional = [value], may be omitted)
#   ArgType     — 'none' | 'file' | 'dir' | 'choice:a,b,c' | 'unknown'
#   Description — short text
# Subcommands the CLI implements but omits from the "Commands:" section of
# `claude --help`. The walk can only learn command names from that section, so
# without this the node is never probed, none of its flags are cached, and
# nothing about it can be completed. Bundling its *flags* instead would be
# inert: the merge skips any scope that was never probed.
#
# Names are added optimistically, exactly as bundled flags are. If one ever
# disappears upstream, its probe returns nothing and no cache files are
# written, so only the bare name is offered.
# Keep this list and _CLAUDE_EXTRA_SUBCOMMANDS in claude.bash in sync.
$script:ClaudeExtraSubcommands = @(
    [pscustomobject]@{ Name='self-hosted-runner'; Description='Run a self-hosted Claude Code runner' }
)

$script:ClaudeExtraFlags = @(
    [pscustomobject]@{ Scope='_root'; Name='--append-subagent-system-prompt'; TakesArg='required'; ArgType='unknown'; Description='Text appended to the subagent system prompt' }
    [pscustomobject]@{ Scope='_root'; Name='--append-subagent-system-prompt-file'; TakesArg='required'; ArgType='file'; Description='Read the subagent system prompt from a file' }
    [pscustomobject]@{ Scope='_root'; Name='--append-system-prompt-file'; TakesArg='required'; ArgType='file'; Description='Read text appended to the system prompt from a file' }
    [pscustomobject]@{ Scope='_root'; Name='--background'; TakesArg='none'; ArgType='none'; Description='Run the session in the background' }
    [pscustomobject]@{ Scope='_root'; Name='--bg'; TakesArg='none'; ArgType='none'; Description='Run the session in the background' }
    [pscustomobject]@{ Scope='_root'; Name='--capacity'; TakesArg='required'; ArgType='unknown'; Description='Max concurrent sessions for --remote-control' }
    [pscustomobject]@{ Scope='_root'; Name='--channels'; TakesArg='required'; ArgType='unknown'; Description='Approved channel servers for this session' }
    [pscustomobject]@{ Scope='_root'; Name='--cowork'; TakesArg='none'; ArgType='none'; Description='Enable co-worker mode (user-scope only)' }
    [pscustomobject]@{ Scope='_root'; Name='--create-session-in-dir'; TakesArg='none'; ArgType='none'; Description='Pre-create a session in the current directory (--remote-control)' }
    [pscustomobject]@{ Scope='_root'; Name='--dangerously-load-development-channels'; TakesArg='none'; ArgType='none'; Description='Allow loading MCP channel servers not on the approved allowlist' }
    [pscustomobject]@{ Scope='_root'; Name='--dump-environment-variables'; TakesArg='none'; ArgType='none'; Description='Dump env vars as JSON and quit (debugging)' }
    [pscustomobject]@{ Scope='_root'; Name='--exec'; TakesArg='required'; ArgType='unknown'; Description='Command to execute in a background session (with --bg)' }
    [pscustomobject]@{ Scope='_root'; Name='--handle-uri'; TakesArg='required'; ArgType='unknown'; Description='Handle a URI (used by OS protocol handler registration)' }
    [pscustomobject]@{ Scope='_root'; Name='--max-thinking-tokens'; TakesArg='required'; ArgType='unknown'; Description='Maximum thinking tokens budget' }
    [pscustomobject]@{ Scope='_root'; Name='--multi-turn'; TakesArg='none'; ArgType='none'; Description='Enable multi-turn conversation mode' }
    [pscustomobject]@{ Scope='_root'; Name='--multi-turn-context'; TakesArg='required'; ArgType='unknown'; Description='Context for multi-turn mode' }
    [pscustomobject]@{ Scope='_root'; Name='--multi-turn-model'; TakesArg='required'; ArgType='unknown'; Description='Model override for multi-turn mode' }
    [pscustomobject]@{ Scope='_root'; Name='--no-create-session-in-dir'; TakesArg='none'; ArgType='none'; Description='Do not pre-create a session in the current directory (--remote-control)' }
    [pscustomobject]@{ Scope='_root'; Name='--plan-mode-instructions'; TakesArg='required'; ArgType='unknown'; Description='Custom instructions for plan mode (only with --print)' }
    [pscustomobject]@{ Scope='_root'; Name='--plan-mode-required'; TakesArg='none'; ArgType='none'; Description='Require plan mode for the session' }
    [pscustomobject]@{ Scope='_root'; Name='--remote-control'; TakesArg='optional'; ArgType='unknown'; Description='Connect local environment to claude.ai/code for remote sessions' }
    [pscustomobject]@{ Scope='_root'; Name='--resume-session-at'; TakesArg='required'; ArgType='unknown'; Description='Resume a session from a specific message ID (requires --resume)' }
    [pscustomobject]@{ Scope='_root'; Name='--rewind-files'; TakesArg='required'; ArgType='unknown'; Description='Rewind files to a given message ID (requires --resume)' }
    [pscustomobject]@{ Scope='_root'; Name='--session-mirror'; TakesArg='none'; ArgType='none'; Description='Mirror local sessions to claude.ai as view-only' }
    [pscustomobject]@{ Scope='_root'; Name='--spawn'; TakesArg='required'; ArgType='choice:same-dir,worktree,session'; Description='Spawn mode for --remote-control sessions' }
    [pscustomobject]@{ Scope='_root'; Name='--system-prompt-file'; TakesArg='required'; ArgType='file'; Description='Read the system prompt from a file' }
    [pscustomobject]@{ Scope='_root'; Name='--teleport'; TakesArg='optional'; ArgType='unknown'; Description='Resume a teleport session, optionally specify session ID' }
    [pscustomobject]@{ Scope='_root'; Name='--thinking'; TakesArg='required'; ArgType='choice:enabled,adaptive,disabled'; Description='Thinking mode: enabled (adaptive) or disabled' }
    [pscustomobject]@{ Scope='_root'; Name='--thinking-display'; TakesArg='required'; ArgType='unknown'; Description='Control how thinking content is displayed' }
)

function global:_ClaudeVersion {
    # `claude --version` is a slow Node cold start (~1.5s), so memoize the
    # result per session. Key on the resolved executable's path + mtime: an
    # upgrade (new path, or the same path rewritten) changes the key and
    # forces a refresh, but repeated tab presses do not respawn Node.
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $cmd) { return }
    $src = $cmd.Source
    $mtime = if ($src -and (Test-Path -LiteralPath $src)) {
        (Get-Item -LiteralPath $src).LastWriteTimeUtc.Ticks
    } else { 0 }
    $key = "${src}:${mtime}"
    if ($script:ClaudeVersionKey -eq $key -and $null -ne $script:ClaudeVersionCache) {
        return $script:ClaudeVersionCache
    }
    $output = $null | claude --version 2>$null
    $version = if ($output) { ($output -split '\s')[0] }
    $script:ClaudeVersionCache = $version
    $script:ClaudeVersionKey = $key
    $version
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
    $key = "$version-c$($script:ClaudeCacheVersion)"
    Join-Path (Join-Path (Join-Path $base 'claude-code-completion') 'powershell') $key
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

    $currentKey = "$(_ClaudeVersion)-c$($script:ClaudeCacheVersion)"
    Get-ChildItem -Path $baseDir -Directory | Where-Object {
        $_.Name -ne $currentKey
    } | Remove-Item -Recurse -Force
}

function global:_ClaudeProbeConcurrency {
    # How many probes to run at once, from the core count.
    # -Cores is detected when omitted: [Environment]::ProcessorCount reports
    # logical processors (hyperthreads included) on Windows PowerShell 5.1 and
    # PowerShell 7+, on every platform, and honours container CPU limits.
    #
    # Probes are CPU-bound Node cold starts with some process-spawn I/O, so
    # mild oversubscription helps. A very wide machine is still capped, since
    # each probe costs real memory.
    # Mirrors _claude_probe_concurrency in claude.bash.
    # -1 rather than 0 marks "not supplied", so an explicit 0 clamps to one
    # core exactly as it does in claude.bash instead of silently re-detecting.
    param([int]$Cores = -1)
    if ($Cores -lt 0) { $Cores = [Environment]::ProcessorCount }
    # Clamp the core count, not the result — mirrors _claude_probe_concurrency.
    if ($Cores -lt 1) { $Cores = 1 }
    $concurrency = $Cores * 2
    if ($concurrency -gt 16) { $concurrency = 16 }
    return $concurrency
}

function global:_ClaudeNodeIsProbeable {
    # Decide whether a node listed in a "Commands:" section is worth spending a
    # `--help` probe on. Every node is, except Commander's built-in help
    # command, which is always a leaf and whose only flag is --help itself.
    #
    # Every other node is probed even when it cannot be a command group,
    # because its help still carries the flags *it* accepts. Skipping those
    # left `claude plugin install -<TAB>` with nothing to offer.
    # Mirrors _claude_node_is_probeable in claude.bash.
    param([string]$Name)
    if ($Name -eq 'help') { return $false }
    return $true
}

function global:_ClaudeCanProbeInParallel {
    # ForEach-Object -Parallel is PowerShell 7+, and each iteration runs in a
    # fresh runspace that inherits neither this script's functions nor the
    # session's aliases. A `claude` that is not a plain external executable —
    # a wrapper function, or a test mock — would therefore resolve to
    # something else or to nothing at all inside the parallel block, so those
    # sessions probe serially instead. Both paths write identical files.
    if ($PSVersionTable.PSVersion.Major -lt 7) { return $false }
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    return ($null -ne $cmd -and $cmd.CommandType -eq 'Application')
}

function global:_ClaudeParseNode {
    # Write every per-node cache file for one command path from its captured
    # help text.
    param([string]$BuildDir, [string]$Key, [string[]]$HelpLines)
    Set-Content -Path (Join-Path $BuildDir "${Key}_flags") -Value @(_ClaudeParseFlags -HelpLines $HelpLines)
    Set-Content -Path (Join-Path $BuildDir "${Key}_flags_with_args") -Value @(_ClaudeParseFlagsWithArgs -HelpLines $HelpLines)
    Set-Content -Path (Join-Path $BuildDir "${Key}_flags_with_optional_args") -Value @(_ClaudeParseFlagsWithOptionalArgs -HelpLines $HelpLines)
    Set-Content -Path (Join-Path $BuildDir "${Key}_flag_descriptions") -Value @(_ClaudeParseFlagDescriptions -HelpLines $HelpLines)
    Set-Content -Path (Join-Path $BuildDir "${Key}_subcommands") -Value @(_ClaudeParseSubcommands -HelpLines $HelpLines)
    Set-Content -Path (Join-Path $BuildDir "${Key}_subcommand_descriptions") -Value @(_ClaudeParseSubcommandDescriptions -HelpLines $HelpLines)
}

function global:_ClaudeBuildCache {
    $cacheDir = _ClaudeCacheDir
    # Build into a private staging dir, then publish atomically with a
    # rename. The real version dir therefore only ever exists fully built —
    # a crashed or interrupted build can never leave a partial/empty cache
    # that later reads would mistake for complete.
    $buildDir = "$cacheDir.tmp.$PID"
    if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    # Raw help text is staged inside the build dir (so a crash cannot strand
    # it elsewhere) and removed again before the cache is published.
    $rawDir = Join-Path $buildDir '.raw'
    New-Item -ItemType Directory -Path $rawDir -Force | Out-Null

    $rootHelp = $null | claude --help 2>$null
    Set-Content -Path (Join-Path $rawDir '_root') -Value $rootHelp
    Set-Content -Path (Join-Path $buildDir '_root_help') -Value $rootHelp

    # Walk the command tree one depth at a time, so the nesting we support is
    # whatever `claude --help` actually describes rather than a fixed number
    # of levels. Per level: parse the help text already captured for its
    # nodes, collect the children worth probing, then fetch that next level.
    #
    # Only the fetch is parallel. Parsing stays serial and in-process because
    # -Parallel runs each iteration in a runspace that cannot see these
    # functions, and both shells must produce identical caches — see
    # docs/plans/2026-09-17-nested-subcommand-completion.md.
    #
    # Cache keys are the command path joined by '_' (plugin_marketplace_flags).
    # That is unambiguous because claude's command names separate words with
    # '-' and never '_'.
    $level = @([pscustomobject]@{ Key = '_root'; Path = '' })
    $depth = 0
    $canParallel = _ClaudeCanProbeInParallel
    $concurrency = if ($null -ne $script:ClaudeProbeConcurrency) {
        $script:ClaudeProbeConcurrency
    } else {
        _ClaudeProbeConcurrency
    }
    while ($level.Count -gt 0 -and $depth -lt $script:ClaudeMaxDepth) {
        $next = [System.Collections.ArrayList]::new()
        foreach ($node in $level) {
            $rawFile = Join-Path $rawDir $node.Key
            # An empty file means the probe failed; leaving the node unparsed
            # keeps stray empty cache files from looking like real answers.
            if (-not (Test-Path $rawFile)) { continue }
            if ((Get-Item $rawFile).Length -eq 0) { continue }
            $helpLines = @(Get-Content $rawFile)
            _ClaudeParseNode -BuildDir $buildDir -Key $node.Key -HelpLines $helpLines
            foreach ($name in @(_ClaudeParseSubcommands -HelpLines $helpLines)) {
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if (-not (_ClaudeNodeIsProbeable -Name $name)) { continue }
                $childKey = if ($node.Key -eq '_root') { $name } else { "$($node.Key)_$name" }
                $childPath = if ($node.Path) { "$($node.Path) $name" } else { $name }
                [void]$next.Add([pscustomobject]@{ Key = $childKey; Path = $childPath })
            }

            # Hidden subcommands are children of the root and of nothing else.
            if ($node.Key -eq '_root') {
                $rootSubFile = Join-Path $buildDir '_root_subcommands'
                foreach ($extra in $script:ClaudeExtraSubcommands) {
                    if (-not $extra) { continue }
                    $known = @(Get-Content $rootSubFile -ErrorAction SilentlyContinue)
                    # --help wins on overlap, as it does for bundled flags.
                    if ($known -contains $extra.Name) { continue }
                    Add-Content -Path $rootSubFile -Value $extra.Name
                    Add-Content -Path (Join-Path $buildDir '_root_subcommand_descriptions') `
                        -Value "$($extra.Name)`t$($extra.Description)"
                    [void]$next.Add([pscustomobject]@{ Key = $extra.Name; Path = $extra.Name })
                }
            }
        }

        if ($next.Count -gt 0) {
            if ($canParallel) {
                $next | ForEach-Object -ThrottleLimit $concurrency -Parallel {
                    $words = @($_.Path -split ' ' | Where-Object { $_ })
                    $out = $null | & claude @words --help 2>$null
                    Set-Content -Path (Join-Path $using:rawDir $_.Key) -Value $out
                }
            } else {
                foreach ($node in $next) {
                    $words = @($node.Path -split ' ' | Where-Object { $_ })
                    $out = $null | claude @words --help 2>$null
                    Set-Content -Path (Join-Path $rawDir $node.Key) -Value $out
                }
            }
        }

        $level = @($next)
        $depth++
    }

    # Merge bundled flags into the cache files (skip ones already present from --help).
    foreach ($entry in $script:ClaudeExtraFlags) {
        if (-not $entry) { continue }
        $flagsFile = Join-Path $buildDir "$($entry.Scope)_flags"
        if (-not (Test-Path $flagsFile)) { continue }
        $existing = @(Get-Content $flagsFile)
        if ($existing -contains $entry.Name) { continue }
        Add-Content -Path $flagsFile -Value $entry.Name
        if ($entry.TakesArg -ne 'none') {
            Add-Content -Path (Join-Path $buildDir "$($entry.Scope)_flags_with_args") -Value $entry.Name
        }
        if ($entry.TakesArg -eq 'optional') {
            Add-Content -Path (Join-Path $buildDir "$($entry.Scope)_flags_with_optional_args") -Value $entry.Name
        }
        Add-Content -Path (Join-Path $buildDir "$($entry.Scope)_flag_descriptions") -Value "$($entry.Name)`t$($entry.Description)"
        Add-Content -Path (Join-Path $buildDir "$($entry.Scope)_flag_arg_types") -Value "$($entry.Name)`t$($entry.ArgType)"
    }

    # Publish atomically: drop the raw staging dir and any stale/partial
    # cache, then rename into place.
    if (Test-Path $rawDir) { Remove-Item -Recurse -Force $rawDir }
    if (Test-Path $cacheDir) { Remove-Item -Recurse -Force $cacheDir }
    Move-Item -Path $buildDir -Destination $cacheDir

    # Clean up old versions (also sweeps any *.tmp.* from crashed builds).
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
    # Flags that take an argument (required <value> or optional [value]). The
    # placeholder follows the flag after a SINGLE space; a 2+ space gap instead
    # introduces the description (e.g. "--mcp-debug   [DEPRECATED…]"), which must
    # not be mistaken for an argument.
    param([string[]]$HelpLines)
    foreach ($line in $HelpLines) {
        if ($line -match '^\s+(-[a-zA-Z]),?\s+(--[a-zA-Z][-a-zA-Z]*)\s[<\[]') {
            $Matches[1]
            $Matches[2]
        } elseif ($line -match '^\s+(--[a-zA-Z][-a-zA-Z]*)\s[<\[]') {
            $Matches[1]
        }
    }
}

function global:_ClaudeParseFlagsWithOptionalArgs {
    # Flags whose argument is OPTIONAL — shown as [value], not <value>. Same
    # single-space rule as _ClaudeParseFlagsWithArgs so a description beginning
    # with '[' is not mistaken for an optional argument.
    param([string[]]$HelpLines)
    foreach ($line in $HelpLines) {
        if ($line -match '^\s+(-[a-zA-Z]),?\s+(--[a-zA-Z][-a-zA-Z]*)\s\[') {
            $Matches[1]
            $Matches[2]
        } elseif ($line -match '^\s+(--[a-zA-Z][-a-zA-Z]*)\s\[') {
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
            # A real command entry sits at the 2-space term column and is a
            # two-column "name  <gap>  description" row. Anchoring on exactly
            # two leading spaces rejects wrapped description lines (indented to
            # the deep help column) and example/code lines (indented 4+);
            # requiring a 2+ space gap before the description rejects bare
            # sub-headings like "Examples:" that have no description column.
            if ($line -match '^  ([a-zA-Z][-a-zA-Z]*).*  +\S') {
                $Matches[1]
            }
        }
    }
}

function global:_ClaudeParseSubcommandDescriptions {
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
            # Same row anchoring as _ClaudeParseSubcommands; the description
            # is the text after the first 2+ space gap (lazy .*?), which
            # skips alias forms ("update|upgrade") and argument placeholders
            # ("[options] <name>"). Wrapped descriptions keep only their
            # first line, matching _ClaudeParseFlagDescriptions.
            if ($line -match '^  ([a-zA-Z][-a-zA-Z]*).*?\s{2,}(\S.+)') {
                "$($Matches[1])`t$($Matches[2].TrimEnd())"
            }
        }
    }
}

function global:_ClaudeCompletionsWithTooltips {
    # Emit CompletionResults for the values in $ListFile that match
    # $WordToComplete, with tooltips looked up in $DescFile (falling back to
    # the value itself when no description is known).
    param(
        [string]$ListFile,
        [string]$DescFile,
        [string]$WordToComplete,
        [string]$ResultType
    )
    $descriptions = @{}
    if (Test-Path $DescFile) {
        Get-Content $DescFile | ForEach-Object {
            $parts = $_ -split "`t", 2
            if ($parts.Count -eq 2) { $descriptions[$parts[0]] = $parts[1] }
        }
    }
    Get-Content $ListFile | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
        $tooltip = if ($descriptions.ContainsKey($_)) { $descriptions[$_] } else { $_ }
        [System.Management.Automation.CompletionResult]::new($_, $_, $ResultType, $tooltip)
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

# Hardcoded model IDs (update when new models are released).
# Order is the display order, following Anthropic's canonical catalog order:
# documented aliases first (each [1m] variant next to its base alias), then
# capability tier descending (fable, opus, sonnet, haiku) with each tier's
# versions newest-first. Alias set per code.claude.com/docs/en/model-config.
# PowerShell shows completions in the order they are returned; bash needs
# `compopt -o nosort` (see _claude_model_candidates callers in claude.bash).
# Keep this list and _CLAUDE_KNOWN_MODELS in claude.bash in sync.
$script:_ClaudeKnownModels = @(
    'best',
    'fable', 'fable[1m]',
    'opus', 'opus[1m]',
    'sonnet', 'sonnet[1m]',
    'haiku',
    'opusplan', 'opusplan[1m]',
    'claude-fable-5-1',
    'claude-fable-5',
    'claude-opus-5-5',
    'claude-opus-5',
    'claude-opus-4-8',
    'claude-opus-4-7',
    'claude-opus-4-6',
    'claude-opus-4-5-20251101',
    'claude-sonnet-5',
    'claude-sonnet-4-6',
    'claude-sonnet-4-5-20250929',
    'claude-haiku-4-5-20251001'
)

function global:_ClaudeLookupArgType {
    param([string]$Flag, [string]$Scope)
    $cacheDir = _ClaudeCacheDir
    $file = Join-Path $cacheDir "${Scope}_flag_arg_types"
    if (-not (Test-Path $file)) { return $null }
    foreach ($line in Get-Content $file) {
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2 -and $parts[0] -eq $Flag) {
            return $parts[1]
        }
    }
    return $null
}

function global:_ClaudeModelCandidates {
    # Return --model completions. A model matches when it starts with
    # $WordToComplete OR with "claude-$WordToComplete", so an alias stem
    # (opus/sonnet/haiku/fable) also reaches its claude-<family>-* versions.
    param([string]$WordToComplete)
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
    # Ordinal StartsWith rather than -like: the [1m] aliases contain [ and ],
    # which -like would read as a wildcard character class.
    $models | Select-Object -Unique | Where-Object {
        $_.StartsWith($WordToComplete, [System.StringComparison]::Ordinal) -or
        $_.StartsWith("claude-$WordToComplete", [System.StringComparison]::Ordinal)
    }
}

function global:_ClaudeCompleteFlagArg {
    param([string]$Flag, [string]$WordToComplete, [string]$Scope = '_root')

    switch ($Flag) {
        '--model' {
            _ClaudeModelCandidates -WordToComplete $WordToComplete | ForEach-Object {
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
            $argType = _ClaudeLookupArgType -Flag $Flag -Scope $Scope
            switch -Wildcard ($argType) {
                'dir' {
                    Get-ChildItem -Path "$WordToComplete*" -Directory -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, 'ProviderContainer', $_.FullName)
                        }
                }
                'choice:*' {
                    $choices = $argType.Substring('choice:'.Length) -split ','
                    $choices | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                    }
                }
                'none' { }
                default {
                    Get-ChildItem -Path "$WordToComplete*" -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            $type = if ($_.PSIsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
                            [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, $type, $_.FullName)
                        }
                }
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

    # Sorted newest-first. The 10-session cap is applied *after* the prefix
    # filter below, so a unique match older than the 10 newest sessions is
    # still reachable.
    $files = Get-ChildItem -Path $sessionDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    $emitted = 0
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
            # Files are newest-first, so the first 10 matches are the 10 newest.
            $emitted++
            if ($emitted -ge 10) { break }
        }
    }
}

function global:_ClaudeMcpServerNames {
    $output = $null | claude mcp list 2>$null
    if (-not $output) { return }
    foreach ($line in ($output -split "`n")) {
        if ($line -match ':' -and $line -notmatch '^Checking|^$') {
            ($line -split ':')[0].Trim()
        }
    }
}

function global:_ClaudePluginNames {
    $output = $null | claude plugin list --json 2>$null
    if (-not $output) { return }
    try {
        $plugins = $output | ConvertFrom-Json
        foreach ($p in $plugins) {
            $p.name
        }
    } catch {}
}

function global:_ClaudeMarketplaceNames {
    $output = $null | claude plugin marketplace list --json 2>$null
    if (-not $output) { return }
    try {
        $marketplaces = $output | ConvertFrom-Json
        foreach ($m in $marketplaces) {
            $m.name
        }
    } catch {}
}

function global:_ClaudeCompleteSubcmdArg {
    # Complete a positional argument for a resolved command path.
    # -Path is the command path joined by '/', e.g. plugin/marketplace/remove.
    param([string]$Path, [string]$WordToComplete)

    switch ($Path) {
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
        { $_ -in 'plugin/marketplace/remove', 'plugin/marketplace/update' } {
            $names = @(_ClaudeMarketplaceNames)
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

    # Build cache if needed. Gate on a populated cache (the _root_help
    # sentinel), not bare directory existence: an interrupted build or a
    # leftover empty dir must trigger a rebuild rather than serve an empty
    # cache. Atomic publish guarantees _root_help only appears fully built.
    if (-not (Test-Path (Join-Path $cacheDir '_root_help'))) {
        _ClaudeBuildCache
    }

    # Resolve the command path: walk the elements left to right, extending the
    # path whenever the next non-flag element is a subcommand of the path so
    # far. Elements that match nothing are skipped rather than ending the walk,
    # so a flag's argument ("claude mcp --scope user get") cannot hide the
    # subcommand that follows it.
    # The word being completed is excluded — matches bash behavior (i < cword).
    $key = '_root'
    $cmdPath = @()
    $loopLimit = if ($WordToComplete -ne '') { $Elements.Count - 1 } else { $Elements.Count }
    for ($i = 1; $i -lt $loopLimit; $i++) {
        if ($Elements[$i] -like '-*') { continue }
        $subsFile = Join-Path $cacheDir "${key}_subcommands"
        # No list for this node means it was pruned as a leaf: nothing deeper
        # can match, so stop rather than mistaking a positional argument for a
        # subcommand.
        if (-not (Test-Path $subsFile)) { break }
        $potential = $Elements[$i]
        if ((Get-Content $subsFile) -contains $potential) {
            $cmdPath += $potential
            $key = if ($key -eq '_root') { $potential } else { "${key}_$potential" }
        }
    }

    # Determine the previous element (for flag-argument detection)
    $prev = if ($Elements.Count -ge 2 -and $WordToComplete -eq '') {
        $Elements[-1]
    } elseif ($Elements.Count -ge 3 -and $WordToComplete -ne '') {
        $Elements[-2]
    } else { '' }

    # Check if previous word is a flag that takes an argument. Flag scope is
    # the resolved path, so a nested node's flags win over its parent's.
    if ($prev -like '-*') {
        $flagsWithArgsFile = Join-Path $cacheDir "${key}_flags_with_args"
        $optionalArgsFile = Join-Path $cacheDir "${key}_flags_with_optional_args"
        if ((Test-Path $flagsWithArgsFile) -and ((Get-Content $flagsWithArgsFile) -contains $prev)) {
            # For optional-arg flags, a current word that already starts with '-'
            # means the user is typing the next flag, not the argument — fall
            # through to normal flag/subcommand completion. Otherwise (empty or
            # non-dash word) complete the flag's argument.
            $isOptional = (Test-Path $optionalArgsFile) -and ((Get-Content $optionalArgsFile) -contains $prev)
            if (-not ($isOptional -and $WordToComplete -like '-*')) {
                _ClaudeCompleteFlagArg -Flag $prev -WordToComplete $WordToComplete -Scope $key
                return
            }
        }
    }

    $subFile = Join-Path $cacheDir "${key}_subcommands"
    $hasSubcommands = (Test-Path $subFile) -and ((Get-Item $subFile).Length -gt 0)

    if ($WordToComplete -like '-*') {
        # Complete flags for the resolved node
        $flagsFile = Join-Path $cacheDir "${key}_flags"
        if (Test-Path $flagsFile) {
            _ClaudeCompletionsWithTooltips -ListFile $flagsFile `
                -DescFile (Join-Path $cacheDir "${key}_flag_descriptions") `
                -WordToComplete $WordToComplete -ResultType 'ParameterName'
        }
    } elseif ($hasSubcommands) {
        # Complete this node's subcommands. The file exists but is empty for a
        # probed leaf, which must fall through to positional-argument
        # completion instead of offering nothing.
        _ClaudeCompletionsWithTooltips -ListFile $subFile `
            -DescFile (Join-Path $cacheDir "${key}_subcommand_descriptions") `
            -WordToComplete $WordToComplete -ResultType 'Command'
    } elseif ($cmdPath.Count -gt 0) {
        # Complete positional args for the resolved leaf
        _ClaudeCompleteSubcmdArg -Path ($cmdPath -join '/') -WordToComplete $WordToComplete
    }
}

Register-ArgumentCompleter -CommandName claude -Native -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.ToString() })
    _ClaudeComplete -WordToComplete $wordToComplete -Elements $elements
}
