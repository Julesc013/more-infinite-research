[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-16T00:43:00+10:00',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/package/FactorioOneSourceConvergenceAuthority.ps1')

$policy = Get-MIR4FactorioOneSourceConvergenceAuthorityPolicy
$record = New-MIR4FactorioOneSourceConvergenceReceipt -RepoRoot $repo -RecordedAt $RecordedAt
$path = Join-Path $repo $policy.receipt_path
$json = (ConvertTo-MIR4FactorioOneSourceConvergenceCanonicalJson -Value $record) + "`n"
if ($Check) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
      [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n") -cne $json) {
    throw '[mir4-factorio-one-convergence-receipt-stale]'
  }
} elseif (Test-Path -LiteralPath $path -PathType Leaf) {
  if ([IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n") -cne $json) {
    throw '[mir4-factorio-one-convergence-receipt-immutable-overwrite]'
  }
} else {
  [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($false))
}
return [pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$policy.receipt_path;record_sha256=[string]$record.record_sha256;exact_engine_proof_required=$true;release_authority=$false}
