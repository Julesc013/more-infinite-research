[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/repository/RepositoryCharacterization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/ShadowSourceModel.ps1')

$outputRelative = 'releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json'
$schemaRelative = 'contracts/repository/mir4-m41-f2b-shadow-source-model-authority-evolution-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json'
$predecessorSha256 = '84209EA8150D0E2C93164E6A2667F9FD4CD347B031171CE0F55901D483664A48'
$expectedPackage = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$expectedReadme = 'DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'

$stateArguments = @{
  RepoRoot=$RepoRoot;IncludeT17MachinePreparation=$true;IncludeRepositoryMigration=$true;IncludeCanonicalizationMigration=$true;IncludeDiagnosticsMigration=$true
  IncludeTargetKeyMigration=$true;IncludeWholePlatformMigration=$true;IncludeTechnologyAcceptanceMigration=$true;IncludeTargetCompilerMigration=$true
  IncludeSemanticCompilerPolicyMigration=$true;IncludeRuntimeContinuityMigration=$true;IncludeModuleSdkMepMigration=$true;IncludeProcessIRExactMigration=$true
  IncludeInspectorCompatibilityMigration=$true;IncludeAssuranceOfflineCustodyMigration=$true;IncludeHistoricalToolingMigration=$true;IncludeReleaseToolingMigration=$true
  IncludeF210QualificationPolicyEvolution=$true;IncludeFinalMileToolingEvolution=$true;IncludeFinalReleaseClosureEvolution=$true;IncludePostReleasePackageBaselineEvolution=$true
  IncludePostReleaseAutomationCutover=$true;IncludePostReleaseBranchOperatingModel=$true;IncludePostReleasePatchLaneRehearsal=$true;IncludeM4103ChangeReleaseAuthority=$true
  IncludeM4105AM4200ACharacterizationAuthority=$true;IncludeM41F0TruthReconciliationAuthority=$true;IncludeM41F1GoldenBaselineAuthority=$true
  IncludeM41F2AShadowMaterializerAuthority=$true
}
$state = Get-MIR4PreFreezeAuthorityState @stateArguments
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) { throw '[mir4-m41-f2b-predecessor]' }
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackage) { throw '[mir4-m41-f2b-package-source]' }
if ((Get-MIRFileContentSha256 -Path (Join-Path $RepoRoot 'README.md') -RelativePath 'README.md') -cne $expectedReadme) { throw '[mir4-m41-f2b-readme]' }

$rolePaths = @(
  '.mir/assurance.json','.mir/control/paths.yml','.mir/modules.yml','CHANGELOG.md','docs/architecture/module-boundaries.md',
  'releases/governance/MIR4-Source-Changelog-PlanV1.json','tools/lib/mir4/PreFreezeRelease.ps1','tools/mir.ps1','validation/tests.yml','validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1',
  'changes/unreleased/MIR4-CHG-2026-0006.json','contracts/repository/mir4-m41-f2b-shadow-source-model-authority-evolution-v1.schema.json',
  'spec/schemas/mir4-shadow-source-model-proof-v1.schema.json','tools/commands/mir4/Update-MIR4M41F2BShadowSourceModelAuthority.ps1',
  'tools/mir/application/package/ShadowSourceModel.ps1','tools/mir/cli/Invoke-MIR4PackageSource.ps1','validation/tests/mir4/Test-MIR4ShadowSourceModel.ps1','validation/tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'
)
$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($path in $rolePaths) {
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-m41-f2b-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $currentSha = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previousSha = [string]$state.authority_hashes[$path]
    if ($currentSha -cne $previousSha) {
      $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason='Register the package-excluded semantic source and target-overlay model and its fail-closed proof.';scope='package-excluded-shadow-source-model';package_visible=$false;release_authority=$false})
    }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role='Current package-excluded shadow semantic source-model implementation, contract, or proof.'})
  }
}

$outputPath = Join-Path $RepoRoot $outputRelative
if (-not $Check -and -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
  [IO.File]::WriteAllText($outputPath, "{}`n", [Text.UTF8Encoding]::new($false))
}

$sourceModelReportPath = 'build/reports/package-source/authority/mir4-shadow-source-model-v1.json'
$sourceModel = Write-MIR4ShadowSourceModel -RepoRoot $RepoRoot -OutputPath $sourceModelReportPath
if (-not ((Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $sourceModelReportPath)) | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-shadow-source-model-proof-v1.schema.json'))) { throw '[mir4-m41-f2b-source-model-schema]' }
$characterization = Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization'
[void](Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization' -Check)
$proof = [ordered]@{
  baseline_record_sha256=[string]$sourceModel.baseline_record_sha256
  proof_record_sha256=[string]$sourceModel.record_sha256
  binding_count=@($sourceModel.bindings).Count
  target_count=@($sourceModel.target_overlays).Count
  omission_count=[int]$sourceModel.classification_counts.'target-omission'
  classification_counts=[ordered]@{
    'common-semantic-source'=[int]$sourceModel.classification_counts.'common-semantic-source'
    'common-asset-locale'=[int]$sourceModel.classification_counts.'common-asset-locale'
    'generated-metadata'=[int]$sourceModel.classification_counts.'generated-metadata'
    'generated-lifecycle-entrypoint'=[int]$sourceModel.classification_counts.'generated-lifecycle-entrypoint'
    'target-overlay'=[int]$sourceModel.classification_counts.'target-overlay'
    'target-replacement'=[int]$sourceModel.classification_counts.'target-replacement'
    'target-omission'=[int]$sourceModel.classification_counts.'target-omission'
    'target-compatibility-shim'=[int]$sourceModel.classification_counts.'target-compatibility-shim'
    migration=[int]$sourceModel.classification_counts.migration
    'package-documentation'=[int]$sourceModel.classification_counts.'package-documentation'
  }
  declaration_order_probe_sha256=[string]$sourceModel.declaration_order_probe_sha256
  physical_files=[int]$characterization.summary.physical_files
  unknown_paths=[int]$characterization.invariants.unknown_paths
  package_files=[int]$characterization.summary.package_files
}

if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-m41-f2b-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$receipt = [ordered]@{
  schema=1;kind='MIR4M41F2BShadowSourceModelAuthorityEvolutionV1';recorded_at=$RecordedAt;programme_id='M41-F2B-SHADOW-SOURCE-MODEL';change_id='MIR4-CHG-2026-0006'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256};base=[ordered]@{branch='dev';commit='d71138424f71e1c9ed43fffec210610953972043';tree='f5dde3ae849aea6cb0afc4b854fdd7ccbd95e4d0'}
  evolved_bindings=@($evolved);current_authorities=@($current);source_model_proof=$proof;player_package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme;package_visible_delta=@()
  invariants=[ordered]@{all_paths_classified=$true;no_path_collision=$true;no_unowned_path=$true;declaration_order_independent=$true;no_target_policy_in_common_domain_code=$true;historical_archives_are_comparison_fixtures_only=$true;current_writer_unchanged=$true;no_editable_source_created=$true;runtime_replay_pending=$true;package_source_unchanged=$true;root_readme_byte_stable=$true}
  transition_gate=[ordered]@{merge=$false;source_move=$false;editable_source=$false;package_cutover=$false;readme_rewrite=$false;bridge_retirement=$false;old_writer_retirement=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status='M41-F2B-SHADOW-SOURCE-MODEL-COMPLETE-NO-EDITABLE-SOURCE-NO-CUTOVER'
}
$json = (($receipt | ConvertTo-Json -Depth 80).Replace("`r`n", "`n") + "`n")
if ($Check) { if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-m41-f2b-receipt-stale]' } } else { [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false)) }
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) { throw '[mir4-m41-f2b-receipt-schema]' }
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;source_model_proof=$proof;package_source_sha256=$expectedPackage}
