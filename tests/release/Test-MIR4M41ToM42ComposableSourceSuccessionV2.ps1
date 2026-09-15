# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')

function Assert-MIR4M41ToM42SuccessionV2([bool]$Condition, [string]$Code) { if (-not $Condition) { throw "[$Code]" } }
function Copy-MIR4M41ToM42SuccessionV2($Value) { return $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String }
function Assert-MIR4M41ToM42SuccessionV2Rejected([scriptblock]$Action, [string]$Code) { $rejected=$false;try{& $Action}catch{$rejected=$_.Exception.Message.Contains($Code)};Assert-MIR4M41ToM42SuccessionV2 $rejected "mir4-m41-m42-succession-v2-negative-$Code" }

$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4M41ToM42ComposableSourceSuccessionV2Authority.ps1'
& $writer -RepoRoot $repo -Check | Out-Null
$result = Test-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo
Assert-MIR4M41ToM42SuccessionV2 ([string]$result.status -ceq 'passed-historical-mir41-to-current-mir42-factorio-one-source-succession' -and -not [bool]$result.current_release_operations_authorized -and [bool]$result.factorio_one_exact_engine_proof_required) 'mir4-m41-m42-succession-v2-positive'

$record = Read-MIR4M41ToM42ComposableSourceSuccessionV2 -RepoRoot $repo
$inventoryBinding = Get-MIR4M41ToM42ComposableSourceSuccessionV2ToolingInventoryBinding -RepoRoot $repo
Assert-MIR4M41ToM42SuccessionV2 (
  [string]$record.current.tooling_inventory.path -ceq [string]$inventoryBinding.path -and
  [string]$record.current.tooling_inventory.sha256 -ceq [string]$inventoryBinding.sha256 -and
  [string]$record.current.tooling_inventory.hash_mode -ceq [string]$inventoryBinding.hash_mode -and
  [string]$record.current.tooling_inventory.digest -ceq [string]$inventoryBinding.digest -and
  [int]$record.current.tooling_inventory.command_count -eq [int]$inventoryBinding.command_count -and
  [int]$record.current.tooling_inventory.unknown -eq [int]$inventoryBinding.unknown -and
  [int]$record.current.tooling_inventory.duplicate_command_keys -eq [int]$inventoryBinding.duplicate_command_keys
) 'mir4-m41-m42-succession-v2-tooling-inventory-binding'

$inventoryTampered = Copy-MIR4M41ToM42SuccessionV2 $record
$inventoryTampered.current.tooling_inventory.sha256 = ('0' * 64)
$inventoryTampered.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $inventoryTampered
Assert-MIR4M41ToM42SuccessionV2Rejected { Test-MIR4M41ToM42ComposableSourceSuccessionV2 -RepoRoot $repo -SuccessionRecord $inventoryTampered | Out-Null } 'mir4-m41-m42-succession-v2-stale'

$inventoryInvariantTampered = Copy-MIR4M41ToM42SuccessionV2 $record
$inventoryInvariantTampered.current.tooling_inventory.unknown = 1
$inventoryInvariantTampered.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $inventoryInvariantTampered
Assert-MIR4M41ToM42SuccessionV2Rejected { Test-MIR4M41ToM42ComposableSourceSuccessionV2 -RepoRoot $repo -SuccessionRecord $inventoryInvariantTampered | Out-Null } 'mir4-m41-m42-succession-v2-schema'

$tampered = Copy-MIR4M41ToM42SuccessionV2 $record
$tampered.invariants.package_bytes_unchanged = $true
$tampered.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $tampered
Assert-MIR4M41ToM42SuccessionV2Rejected { Test-MIR4M41ToM42ComposableSourceSuccessionV2 -RepoRoot $repo -SuccessionRecord $tampered | Out-Null } 'mir4-m41-m42-succession-v2-schema'

$unknown = Copy-MIR4M41ToM42SuccessionV2 $record
$unknown | Add-Member -NotePropertyName unauthorized_gate -NotePropertyValue $true
$unknown.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $unknown
Assert-MIR4M41ToM42SuccessionV2Rejected { Test-MIR4M41ToM42ComposableSourceSuccessionV2 -RepoRoot $repo -SuccessionRecord $unknown | Out-Null } 'mir4-m41-m42-succession-v2-schema'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-m41-to-m42-composable-source-succession-v2';exact_engine_proof_required=$true;release_authority=$false;tooling_inventory_digest=[string]$result.tooling_inventory_digest;record_sha256=[string]$result.record_sha256} | ConvertTo-Json -Compress
