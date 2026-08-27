param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')))
# MIR4-WHOLE-PLATFORM-COMPATIBILITY-TEST: read-only forwarder; canonical test is under tests/platform.
& (Join-Path $RepoRoot 'tests/platform/Test-MIR4WholePlatform.ps1') -RepoRoot $RepoRoot
