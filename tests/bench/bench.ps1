#!/usr/bin/env pwsh
# Times the cache build on this branch against a baseline ref, and reports the
# machine and which probe path was taken. Driven by
# .github/workflows/bench.yml; runnable locally.
#
# Deliberately free of PowerShell 7-only syntax (no ternary, no ??, no &&/||
# pipeline chains): Windows PowerShell 5.1 parses the whole file before running
# any of it, so such syntax would break the 5.1 job even in a branch it never
# executes.
#
# Every timed build runs in its own child process with its own
# XDG_CACHE_HOME — which _ClaudeCacheBase honours ahead of LOCALAPPDATA on
# Windows — so a run never reads a cache another run published.

$ErrorActionPreference = 'Stop'

$baselineRef = $env:BASELINE_REF
if (-not $baselineRef) { $baselineRef = 'main' }
$reps = $env:BENCH_REPS
if (-not $reps) { $reps = 3 }
$reps = [int]$reps

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot

if ($PSVersionTable.PSVersion.Major -ge 6) {
    $shellExe = 'pwsh'
} else {
    $shellExe = 'powershell'
}

$baselineScript = Join-Path ([System.IO.Path]::GetTempPath()) 'claude-baseline.ps1'
git show "${baselineRef}:claude.ps1" | Set-Content -Path $baselineScript

. ./claude.ps1
$cores = [Environment]::ProcessorCount
$concurrency = _ClaudeProbeConcurrency
$parallel = _ClaudeCanProbeInParallel

# Settle the auto-updater before timing anything. A native install updates
# itself when invoked, and a cache build invokes it ~38 times, so a pending
# update must land here rather than inside a timed run. There is no documented
# way to disable it in user scope.
claude --help *> $null

$versionBefore = (claude --version 2>$null | Select-Object -First 1)

function Invoke-TimedBuild {
    param([string]$ScriptPath)
    $cache = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $env:XDG_CACHE_HOME = $cache
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $shellExe -NoProfile -Command ". '$ScriptPath'; _ClaudeBuildCache" *> $null
    $sw.Stop()
    $env:XDG_CACHE_HOME = $null
    Remove-Item -Recurse -Force $cache -ErrorAction SilentlyContinue
    return [math]::Round($sw.Elapsed.TotalSeconds, 2)
}

$baselineTimes = @()
$branchTimes = @()
for ($rep = 1; $rep -le $reps; $rep++) {
    # Interleaved so a machine that slows down partway through penalizes both
    # variants equally rather than whichever ran last.
    $baselineTimes += Invoke-TimedBuild -ScriptPath $baselineScript
    $branchTimes += Invoke-TimedBuild -ScriptPath (Join-Path $projectRoot 'claude.ps1')
}

$versionAfter = (claude --version 2>$null | Select-Object -First 1)

$baselineMean = [math]::Round(($baselineTimes | Measure-Object -Average).Average, 2)
$branchMean = [math]::Round(($branchTimes | Measure-Object -Average).Average, 2)

$lines = @()
$lines += "### $shellExe $($PSVersionTable.PSVersion) — $cores cores, concurrency $concurrency, parallel probes: $parallel"
$lines += ''
$lines += '| Variant | Mean | Runs |'
$lines += '| --- | --- | --- |'
$lines += "| ``$baselineRef`` (baseline) | ${baselineMean}s | $($baselineTimes -join ' ') |"
$lines += "| this branch | ${branchMean}s | $($branchTimes -join ' ') |"
$lines += ''
$lines += "CLI before: ``$versionBefore`` · after: ``$versionAfter``"
if ($versionBefore -ne $versionAfter) {
    $lines += ''
    $lines += '> **The CLI updated itself mid-run — these timings are not comparable.**'
}

$lines | ForEach-Object { Write-Host $_ }
if ($env:GITHUB_STEP_SUMMARY) {
    $lines | Add-Content -Path $env:GITHUB_STEP_SUMMARY
}

Remove-Item -Force $baselineScript -ErrorAction SilentlyContinue

# A version change invalidates the comparison, so fail rather than publish
# numbers that look authoritative and are not.
if ($versionBefore -ne $versionAfter) { exit 1 }
