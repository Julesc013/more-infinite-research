[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-16T00:43:00+10:00',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')

# V2 records the prior Factorio-1 convergence. It is an immutable predecessor
# of the V3 progression-source successor and must never be regenerated using
# the later package identities.
$record = Get-MIR4M41ToM42ComposableSourceSuccessionV2Historical -RepoRoot $repo
$policy = Get-MIR4M41ToM42ComposableSourceSuccessionV2Policy
$path = Join-Path $repo $policy.output_path
$json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + "`n"
if ($Check) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n") -cne $json) {
    throw '[mir4-m41-m42-succession-v2-stale]'
  }
} else {
  throw '[mir4-m41-m42-succession-v2-authority-immutable-overwrite]'
}
return [pscustomobject][ordered]@{status='historical-immutable';path=$policy.output_path;record_sha256=[string]$record.record_sha256;exact_engine_proof_required=$true;release_authority=$false}
