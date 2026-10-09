# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')

$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4M41ToM42ComposableSourceSuccessionV2Authority.ps1'
& $writer -RepoRoot $repo -Check | Out-Null
$record = Get-MIR4M41ToM42ComposableSourceSuccessionV2Historical -RepoRoot $repo
if ([string]$record.record_sha256 -cne '26D782754CD2FB05715279C9A5AAC0847C54E0AA639839FCCF906D069059FE26' -or
    [string]$record.current.package_source_sha256 -cne '909D8F0F1CA8B59E42CFBED5C854734B57DE40308D2E05752BD8694E1EC1821E' -or
    -not [bool]$record.invariants.factorio_one_exact_engine_proof_required -or
    [bool]$record.invariants.current_mir41_release_operations_authorized) {
  throw '[mir4-m41-m42-succession-v2-historical-binding]'
}
$tampered = $record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$tampered.transition_gate.publication = $true
$tampered.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $tampered
$tamperedSchemaValid = $false
try {
  $tamperedSchemaValid = (ConvertTo-MIR4BootstrapCanonicalJson -Value $tampered) |
    Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m41-to-m42-composable-source-succession-v2.schema.json') -ErrorAction Stop
} catch {
  $tamperedSchemaValid = $false
}
if ($tamperedSchemaValid) {
  throw '[mir4-m41-m42-succession-v2-historical-tamper]'
}
$immutable = $false
try { & $writer -RepoRoot $repo | Out-Null } catch { $immutable = $_.Exception.Message -eq '[mir4-m41-m42-succession-v2-authority-immutable-overwrite]' }
if (-not $immutable) { throw '[mir4-m41-m42-succession-v2-historical-overwrite]' }
[pscustomobject][ordered]@{status='passed';test_id='static.mir4-m41-to-m42-composable-source-succession-v2';historical_receipt=$true;exact_engine_proof_required=$true;release_authority=$false;record_sha256=[string]$record.record_sha256} | ConvertTo-Json -Compress
