param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-02T20:00:00+10:00',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/ReleaseApplicationDag.ps1')

function Get-MIR4201AHash([string]$RelativePath) {
  return Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot $RelativePath)
}

$outputRelative = 'releases/migrations/MIR4-M42-01A-CLI-Release-ConvergenceV1.json'
$outputPath = Join-Path $RepoRoot $outputRelative
$schemaPath = Join-Path $RepoRoot 'contracts/repository/mir4-m42-01a-cli-release-convergence-v1.schema.json'
$predecessor = 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
$inventoryPath = 'governance/automation/mir4-command-inventory-v1.json'
$dagPath = 'governance/release/mir4-release-application-dag-v1.json'
$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check
$dagCheck = Test-MIR4ReleaseApplicationDagV1 -RepoRoot $RepoRoot
$record = [pscustomobject][ordered]@{
  schema=1
  kind='MIR4M4201ACliReleaseConvergenceV1'
  status='M42-01A-CLI-RELEASE-CONVERGENCE-COMPLETE'
  recorded_at=$RecordedAt
  programme_id='M42-01A-CLI-RELEASE-CONVERGENCE'
  change_id='MIR4-CHG-2026-0015'
  predecessor_receipt=[pscustomobject][ordered]@{path=$predecessor;sha256=(Get-MIR4201AHash $predecessor)}
  base=[pscustomobject][ordered]@{commit='c4597569a3a5499172d39ef814a80bbb0a9d8978';tree='d8f10537f5655c53565374eb14f02ea213df4271'}
  command_inventory=[pscustomobject][ordered]@{path=$inventoryPath;sha256=(Get-MIR4201AHash $inventoryPath);digest=[string]$inventory.digest;command_count=[int]$inventory.command_count;implementation_file_count=@($inventory.implementation_files).Count;unknown_count=[int]$inventory.summary.unknown;duplicate_command_keys=[int]$inventory.summary.duplicate_command_keys}
  release_application_dag=[pscustomobject][ordered]@{path=$dagPath;sha256=(Get-MIR4201AHash $dagPath);status=[string]$dagCheck.status;node_count=[int]$dagCheck.node_count;publisher_can_build=[bool]$dagCheck.publisher_can_build;production_authorized=[bool]$dagCheck.production_authorized}
  package_source_sha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot
  authorities=@(
    foreach ($path in @(
      'tools/mir.ps1',
      'tools/mir/cli/Invoke-MIRCommandRouter.ps1',
      'tools/mir/cli/Invoke-MIR4ReleaseEngine.ps1',
      'tools/mir/cli/Invoke-MIR4ToolingConvergence.ps1',
      'tools/mir/application/release/ReleaseApplicationDag.ps1',
      'tools/mir/application/tooling/CommandInventory.ps1',
      'tools/commands/mir4/Invoke-MIR4ReleaseWorkflow.ps1',
      'tests/tooling/Test-MIR4CliReleaseConvergence.ps1',
      'validation/tests.yml'
    )) {
      [pscustomobject][ordered]@{path=$path;sha256=(Get-MIR4201AHash $path);package_visible=$false;release_authority=$false}
    }
  )
  invariants=[pscustomobject][ordered]@{one_public_cli=$true;one_command_route_per_key=$true;one_release_application_dag=$true;publisher_cannot_build=$true;independent_verifier_separate=$true;player_executable_sources_unchanged=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;promotion=$false;publication=$false}
  next_fixed_point='M42-01B-TEST-WORKFLOW-CONVERGENCE'
  record_sha256=''
}
$record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
$json = (($record | ConvertTo-Json -Depth 100) + [string][char]10).Replace(([string][char]13+[char]10),[string][char]10).Replace([string][char]13,[string][char]10)
if (-not ($json | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-m42-01a-schema]' }
if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf) -or [IO.File]::ReadAllText($outputPath).Replace(([string][char]13+[char]10),[string][char]10) -cne $json) { throw '[mir4-m42-01a-receipt-stale]' }
  Write-Host '[ok] M42-01A CLI and release convergence receipt is current.'
  return $record
}
[IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))
return $record
