#!/usr/bin/env pwsh
# Test runner script — used by CI to invoke Pester under different shells.
param([switch]$Coverage)

$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Output.Verbosity = 'Detailed'
$config.Run.Exit = $true

if ($Coverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @(Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'claude.ps1')
}

Invoke-Pester -Configuration $config
