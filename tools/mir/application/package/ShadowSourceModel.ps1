Set-StrictMode -Version Latest

$mir4HistoricalShadowSourceModelLoadRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4HistoricalShadowSourceModelLoadRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}

function Get-MIR4HistoricalShadowSourceModelReceipt {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $relative = 'releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json'
  $path = Join-Path $repo $relative
  $schema = Join-Path $repo 'contracts/repository/mir4-m41-f2b-shadow-source-model-authority-evolution-v1.schema.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
      -not ((Get-Content -Raw -LiteralPath $path) | Test-Json -SchemaFile $schema)) {
    throw '[mir4-historical-shadow-source-model-receipt-schema]'
  }
  $receipt = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$receipt.kind -cne 'MIR4M41F2BShadowSourceModelAuthorityEvolutionV1' -or
      [string]$receipt.status -cne 'M41-F2B-SHADOW-SOURCE-MODEL-COMPLETE-NO-EDITABLE-SOURCE-NO-CUTOVER' -or
      [string]$receipt.predecessor_receipt.path -cne 'releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json' -or
      [string]$receipt.predecessor_receipt.sha256 -cne '84209EA8150D0E2C93164E6A2667F9FD4CD347B031171CE0F55901D483664A48') {
    throw '[mir4-historical-shadow-source-model-receipt-content]'
  }
  return $receipt
}

function Test-MIR4HistoricalShadowSourceModelReceipt {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $receipt = Get-MIR4HistoricalShadowSourceModelReceipt -RepoRoot $RepoRoot
  if (@($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0 -or
      -not [bool]$receipt.invariants.no_editable_source_created -or
      -not [bool]$receipt.invariants.runtime_replay_pending) {
    throw '[mir4-historical-shadow-source-model-receipt-gate]'
  }
  return [pscustomobject][ordered]@{
    status = 'passed-historical-shadow-source-model-receipt'
    receipt = 'releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json'
    binding_count = [int]$receipt.source_model_proof.binding_count
    target_count = [int]$receipt.source_model_proof.target_count
    historical_only = $true
    release_authority = $false
  }
}
