Set-StrictMode -Version Latest

$mir4BridgeRetirementRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4BridgeRetirementRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}

$script:MIR4BridgeRetirementAuthorityPath = 'governance/repository/migrations/current-product-bridge-retirement-v1.json'
$script:MIR4BridgeRetirementAuthoritySchemaPath = 'contracts/repository/mir4-current-product-bridge-retirement-v1.schema.json'

function Get-MIR4CurrentProductBridgeRetirementAuthority {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4BridgeRetirementAuthorityPath
  $raw = Get-Content -Raw -LiteralPath $path
  if (-not ($raw | Test-Json -SchemaFile (Join-Path $repo $script:MIR4BridgeRetirementAuthoritySchemaPath))) {
    throw '[mir4-bridge-retirement-authority-schema]'
  }
  $authority = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $authority)) { throw '[mir4-bridge-retirement-authority-record-hash]' }
  $bridges = @($authority.bridge_dispositions)
  $keys = @($bridges | ForEach-Object { "$([string]$_.migration_id)|$([string]$_.path)" })
  if ($bridges.Count -ne 49 -or @($keys | Sort-Object -Unique).Count -ne 49) { throw '[mir4-bridge-retirement-authority-bridge-set]' }
  if (@($bridges | Where-Object { [bool]$_.writable -or [bool]$_.package_visible -or [bool]$_.current_semantic_use -or [bool]$_.current_authority -or [bool]$_.deletion_authorized }).Count -ne 0) {
    throw '[mir4-bridge-retirement-current-authority]'
  }
  foreach ($name in @('current_product','dual_write_authority','package_authority_bridge','release_current_state_authority_bridge','runtime_state_migration_authority_bridge','public_claim_authority_bridge','unowned','unbounded')) {
    if ([int]$authority.summary.$name -ne 0) { throw "[mir4-bridge-retirement-summary] $name" }
  }
  if (@($authority.transition_gate.PSObject.Properties | Where-Object { $_.Name -ne 'bridge_retirement' -and [bool]$_.Value }).Count -ne 0) {
    throw '[mir4-bridge-retirement-release-firewall]'
  }
  return $authority
}
