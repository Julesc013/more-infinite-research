param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot = 'build/results/mir4-t15/supply-chain',
  [string]$ArtifactMapPath,
  [switch]$RequireClean,
  [string]$OfficialSpdxSchemaPath
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/SupplyChain.ps1')

$output = if ([IO.Path]::IsPathRooted($OutputRoot)) {
  [IO.Path]::GetFullPath($OutputRoot)
} else {
  Assert-MIR4DescendantPath -Root $repo -Path (Join-Path $repo $OutputRoot)
}
if (-not (Test-Path -LiteralPath $output -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $output | Out-Null
}

$artifacts = @{}
if (-not [string]::IsNullOrWhiteSpace($ArtifactMapPath)) {
  $artifactMap = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $ArtifactMapPath).Path) | ConvertFrom-Json -Depth 20
  foreach ($property in $artifactMap.PSObject.Properties) {
    $artifacts[[string]$property.Name] = [string]$property.Value
  }
}

$inventory = New-MIR4ComponentInventoryV1 -RepoRoot $repo -ArtifactPaths $artifacts -RequireClean:$RequireClean
if (-not (Test-MIR4ComponentInventoryV1 -Inventory $inventory -RepoRoot $repo)) {
  throw '[mir4-supply-chain-inventory-verification]'
}
$spdx301 = New-MIR4Spdx301Document -Inventory $inventory
$spdx23 = New-MIR4Spdx23CompatibilityDocument -Inventory $inventory
$provenance = New-MIR4SlsaProvenanceV1 -Inventory $inventory

if (-not (Test-MIR4Spdx301Document -Document $spdx301 -Inventory $inventory -RepoRoot $repo -OfficialSchemaPath $OfficialSpdxSchemaPath)) {
  throw '[mir4-supply-chain-spdx-3.0.1-verification]'
}
if (-not (Test-MIR4Spdx23CompatibilityDocument -Document $spdx23 -RepoRoot $repo)) {
  throw '[mir4-supply-chain-spdx-2.3-verification]'
}
if (-not (Test-MIR4SlsaProvenanceV1 -Statement $provenance -RepoRoot $repo)) {
  throw '[mir4-supply-chain-slsa-verification]'
}

$paths = [ordered]@{
  inventory = Join-Path $output 'component-inventory.json'
  spdx301 = Join-Path $output 'sbom.spdx-3.0.1.json'
  spdx23 = Join-Path $output 'sbom.spdx-2.3.json'
  provenance = Join-Path $output 'provenance.slsa-v1.json'
}
Write-MIR4SupplyChainRecord -Record $inventory -Path $paths.inventory
Write-MIR4SupplyChainRecord -Record $spdx301 -Path $paths.spdx301
Write-MIR4SupplyChainRecord -Record $spdx23 -Path $paths.spdx23
Write-MIR4SupplyChainRecord -Record $provenance -Path $paths.provenance

$outputs = @(
  foreach ($entry in $paths.GetEnumerator()) {
    $item = Get-Item -LiteralPath $entry.Value
    [pscustomobject][ordered]@{
      id = [string]$entry.Key
      path = [IO.Path]::GetRelativePath($output, $item.FullName).Replace('\', '/')
      bytes = [long]$item.Length
      sha256 = (Get-MIR4Sha256File -Path $item.FullName).ToUpperInvariant()
    }
  }
)
$result = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4SupplyChainProjectionResultV1'
  programme_id = 'M4C02-09-24H'
  turn = 'T15'
  source_commit = [string]$inventory.source.commit
  source_tree = [string]$inventory.source.tree
  working_tree_clean = [bool]$inventory.source.working_tree_clean
  component_inventory_root = [string]$inventory.record_sha256
  outputs = $outputs
  transition_authority = [pscustomobject][ordered]@{
    source_freeze = $false
    production_signing = $false
    publication = $false
  }
  record_sha256 = $null
}
$result.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $result
$resultPath = Join-Path $output 'projection-result.json'
Write-MIR4SupplyChainRecord -Record $result -Path $resultPath
$result
