[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-15T12:00:00+10:00',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')

$policy = Get-MIR4M41ToM42SourceSuccessionPolicy
if (-not $Check) { throw '[mir4-m41-m42-succession-v1-historical-write-retired]' }
$historical = Test-MIR4M41ToM42ComposableSourceSuccessionV1Historical -RepoRoot $RepoRoot
return [pscustomobject][ordered]@{status='historical-current';path=$policy.output_path;record_sha256=[string]$historical.record_sha256;release_authority=$false}
