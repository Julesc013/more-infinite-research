[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/package/ShadowSourceModel.ps1')

if (-not $Check) {
  throw '[mir4-historical-shadow-source-model-receipt-immutable]'
}

$receipt = Get-MIR4HistoricalShadowSourceModelReceipt -RepoRoot $repo
if (@($receipt.current_authorities).Count -lt 6 -or
    [int]$receipt.source_model_proof.binding_count -ne 406 -or
    [int]$receipt.source_model_proof.target_count -ne 4 -or
    [int]$receipt.source_model_proof.omission_count -ne 264) {
  throw '[mir4-historical-shadow-source-model-receipt-identity]'
}

[pscustomobject][ordered]@{
  status = 'current-historical-receipt'
  path = 'releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json'
  historical_only = $true
  release_authority = $false
}
