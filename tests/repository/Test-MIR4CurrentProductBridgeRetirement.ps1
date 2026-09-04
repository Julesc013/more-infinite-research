param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/repository/BridgeRetirement.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/repository/RepositoryCharacterization.ps1')
. (Join-Path $RepoRoot 'tools/mir/domain/repository/RepositoryFixedPoint.ps1')

function Assert-MIR4BridgeRetirement {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Message)
  if (-not $Condition) { throw "[mir4-current-product-bridge-retirement] $Message" }
}

$fixedPoint = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $RepoRoot
Assert-MIR4BridgeRetirement ([string]$fixedPoint.state -ceq 'MIR41-CURRENT-PRODUCT-BRIDGES-RETIRED') 'fixed point state'
Assert-MIR4BridgeRetirement ([bool]$fixedPoint.physical_cutover) 'physical cutover'
Assert-MIR4BridgeRetirement (-not [bool]$fixedPoint.current_package_source_remains_authoritative) 'legacy package source authority'
Assert-MIR4BridgeRetirement (@($fixedPoint.visible_roots | Where-Object { [string]$_.mode -like 'shadow-*' }).Count -eq 0) 'shadow root modes remain'

$authority = Get-MIR4CurrentProductBridgeRetirementAuthority -RepoRoot $RepoRoot
$bridges = @($authority.bridge_dispositions)
Assert-MIR4BridgeRetirement ($bridges.Count -eq 49) 'bridge count'
Assert-MIR4BridgeRetirement (@($bridges | Where-Object { [string]$_.disposition -ceq 'retired-reassigned' }).Count -eq 1) 'retired bridge count'
Assert-MIR4BridgeRetirement (@($bridges | Where-Object { [string]$_.disposition -ceq 'retained-historical-compatibility' }).Count -eq 48) 'historical bridge count'
Assert-MIR4BridgeRetirement (@($bridges | Where-Object { [bool]$_.writable -or [bool]$_.package_visible -or [bool]$_.current_semantic_use -or [bool]$_.current_authority -or [bool]$_.deletion_authorized }).Count -eq 0) 'bridge authority boundary'
Assert-MIR4BridgeRetirement (@($bridges | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.owner) -or [string]::IsNullOrWhiteSpace([string]$_.proof) -or [string]::IsNullOrWhiteSpace([string]$_.expiry_condition) -or [string]::IsNullOrWhiteSpace([string]$_.rollback) }).Count -eq 0) 'unowned or unbounded bridge'
$readme = @($bridges | Where-Object { [string]$_.path -ceq 'README.md' })
Assert-MIR4BridgeRetirement ($readme.Count -eq 1 -and [string]$readme[0].disposition -ceq 'retired-reassigned') 'README disposition'

$packageIdentityText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
Assert-MIR4BridgeRetirement (-not $packageIdentityText.Contains("Join-Path `$RepoRoot 'info.json'")) 'implicit root package fallback remains'
Assert-MIR4BridgeRetirement (-not $packageIdentityText.Contains("Join-Path `$RepoRoot 'scripts'")) 'implicit scripts command fallback remains'

$contextPath = Join-Path $RepoRoot 'spec/execution/mir4-4.1-development-context-v1.json'
$contextRaw = Get-Content -Raw -LiteralPath $contextPath
Assert-MIR4BridgeRetirement ($contextRaw | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-development-execution-context-v1.schema.json')) 'development context schema'
$context = $contextRaw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4BridgeRetirement (Test-MIR4BootstrapRecordHash -Record $context) 'development context record hash'
Assert-MIR4BridgeRetirement (-not [bool]$context.historical_context.current_authority) 'historical M4C01 authority'

foreach ($profileName in @('factorio-2.1.json','factorio-2.0.json','factorio-1.1.json','factorio-1.0.json')) {
  $profile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation/profiles/$profileName") | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4BridgeRetirement ($null -eq $profile.PSObject.Properties['release_authority']) "$profileName release authority"
  Assert-MIR4BridgeRetirement ($null -eq $profile.PSObject.Properties['release_authority_mode']) "$profileName release authority mode"
  Assert-MIR4BridgeRetirement ([string]$profile.execution_context -ceq 'spec/execution/mir4-4.1-development-context-v1.json') "$profileName execution context"
}

[void](Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization')
[void](Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization' -Check)
$bridgeReport = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'build/reports/repository-characterization/bridge-expiry.json') | ConvertFrom-Json -Depth 100 -DateKind String
foreach ($name in @('current_product','dual_write_authority','package_authority_bridge','release_current_state_authority_bridge','runtime_state_migration_authority_bridge','public_claim_authority_bridge','unowned','unbounded')) {
  Assert-MIR4BridgeRetirement ([int]$bridgeReport.summary.$name -eq 0) "characterization $name"
}

$receiptPath = Join-Path $RepoRoot 'releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
$receiptRaw = Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4BridgeRetirement ($receiptRaw | Test-Json -SchemaFile (Join-Path $RepoRoot 'contracts/repository/mir4-m41-current-product-bridge-retirement-v1.schema.json')) 'receipt schema'
$receipt = $receiptRaw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4BridgeRetirement (Test-MIR4BootstrapRecordHash -Record $receipt) 'receipt record hash'
Assert-MIR4BridgeRetirement ([string]$receipt.status -ceq 'M41-CURRENT-PRODUCT-BRIDGES-RETIRED-PRIVATE-QUALIFICATION-PENDING') 'receipt status'
Assert-MIR4BridgeRetirement (@($receipt.evolved_bindings).Count -gt 0) 'receipt evolved bindings'
Assert-MIR4BridgeRetirement (@($receipt.current_authorities).Count -gt 0) 'receipt current authorities'
Assert-MIR4BridgeRetirement (@($receipt.evolved_bindings | Where-Object { [bool]$_.package_visible -or [bool]$_.release_authority }).Count -eq 0) 'evolved binding authority firewall'
Assert-MIR4BridgeRetirement (@($receipt.current_authorities | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.path) -or [string]::IsNullOrWhiteSpace([string]$_.sha256) }).Count -eq 0) 'current authority identity'

& (Join-Path $RepoRoot 'tools/commands/mir4/Update-MIR4M41CurrentProductBridgeRetirementAuthority.ps1') -RepoRoot $RepoRoot -Check | Out-Null
& (Join-Path $RepoRoot 'tools/commands/mir4/Update-MIR4M41CurrentProductBridgeRetirementReceipt.ps1') -RepoRoot $RepoRoot -Check | Out-Null

[pscustomobject][ordered]@{
  status = 'passed'
  fixed_point = [string]$fixedPoint.state
  declared_bridges = $bridges.Count
  current_product_bridges = [int]$authority.summary.current_product
  receipt_record_sha256 = [string]$receipt.record_sha256
}
