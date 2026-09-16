# MIR4-CANONICAL-EXECUTABLE-TEST
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/mir/application/package/ShadowSourceModel.ps1')

function Assert-MIR4HistoricalShadowSourceModel([bool]$Condition,[string]$Id) {
  if (-not $Condition) { throw "[$Id]" }
}

$result = Test-MIR4HistoricalShadowSourceModelReceipt -RepoRoot $repo
Assert-MIR4HistoricalShadowSourceModel ([string]$result.status -ceq 'passed-historical-shadow-source-model-receipt') 'mir4-shadow-source-model-historical-status'
Assert-MIR4HistoricalShadowSourceModel ([int]$result.binding_count -eq 406 -and [int]$result.target_count -eq 4) 'mir4-shadow-source-model-historical-identity'
Assert-MIR4HistoricalShadowSourceModel ([bool]$result.historical_only -and -not [bool]$result.release_authority) 'mir4-shadow-source-model-historical-firewall'
$result | ConvertTo-Json -Depth 10
