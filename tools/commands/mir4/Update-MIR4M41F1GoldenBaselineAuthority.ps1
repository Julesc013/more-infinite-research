[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/repository/RepositoryCharacterization.ps1')

$outputRelative = 'releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json'
$schemaRelative = 'contracts/repository/mir4-m41-f1-golden-four-target-baseline-authority-evolution-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json'
$predecessorSha256 = '0CED3F46BFEEBD48F96E169B4591DC6E3894EC8226C19CEE71D3269809A8568C'
$expectedPackage = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$expectedReadme = 'DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'

$stateArguments = @{
  RepoRoot=$RepoRoot;IncludeT17MachinePreparation=$true;IncludeRepositoryMigration=$true;IncludeCanonicalizationMigration=$true;IncludeDiagnosticsMigration=$true
  IncludeTargetKeyMigration=$true;IncludeWholePlatformMigration=$true;IncludeTechnologyAcceptanceMigration=$true;IncludeTargetCompilerMigration=$true
  IncludeSemanticCompilerPolicyMigration=$true;IncludeRuntimeContinuityMigration=$true;IncludeModuleSdkMepMigration=$true;IncludeProcessIRExactMigration=$true
  IncludeInspectorCompatibilityMigration=$true;IncludeAssuranceOfflineCustodyMigration=$true;IncludeHistoricalToolingMigration=$true;IncludeReleaseToolingMigration=$true
  IncludeF210QualificationPolicyEvolution=$true;IncludeFinalMileToolingEvolution=$true;IncludeFinalReleaseClosureEvolution=$true;IncludePostReleasePackageBaselineEvolution=$true
  IncludePostReleaseAutomationCutover=$true;IncludePostReleaseBranchOperatingModel=$true;IncludePostReleasePatchLaneRehearsal=$true;IncludeM4103ChangeReleaseAuthority=$true
  IncludeM4105AM4200ACharacterizationAuthority=$true;IncludeM41F0TruthReconciliationAuthority=$true
}
$state = Get-MIR4PreFreezeAuthorityState @stateArguments
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) { throw '[mir4-m41-f1-predecessor]' }
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackage) { throw '[mir4-m41-f1-package-source]' }
if ((Get-MIRFileContentSha256 -Path (Join-Path $RepoRoot 'README.md') -RelativePath 'README.md') -cne $expectedReadme) { throw '[mir4-m41-f1-readme]' }

$baselinePath = Join-Path $RepoRoot 'spec/distribution/mir4-golden-four-target-baseline-v1.json'
$baseline = Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json -Depth 100 -DateKind String
if ([string]$baseline.kind -cne 'MIR4GoldenFourTargetBaselineV1' -or [string]$baseline.record_sha256 -cne 'A9CFA8C4F8E799BD1B543EB8F2EC7DACF136730A098CC71D8206A9F83AB6AB8A') { throw '[mir4-m41-f1-baseline]' }

$rolePaths = @(
  '.mir/assurance.json','.mir/control-plane/ownership.json','.mir/control/paths.yml','.mir/modules.yml','CHANGELOG.md',
  'releases/governance/MIR4-Source-Changelog-PlanV1.json','tools/lib/mir4/PreFreezeRelease.ps1','tools/mir.ps1','validation/tests.yml','validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1',
  'changes/unreleased/MIR4-CHG-2026-0004.json','contracts/repository/mir4-m41-f1-golden-four-target-baseline-authority-evolution-v1.schema.json',
  'spec/distribution/mir4-golden-four-target-baseline-v1.json','spec/schemas/mir4-golden-four-target-baseline-v1.schema.json',
  'tools/commands/mir4/Update-MIR4M41F1GoldenBaselineAuthority.ps1','tools/mir/application/package/GoldenTargetBaselines.ps1','tools/mir/cli/Invoke-MIR4PackageSource.ps1',
  'validation/tests/mir4/Test-MIR4GoldenFourTargetBaseline.ps1','validation/tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'
)
$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($path in $rolePaths) {
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-m41-f1-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $currentSha = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previousSha = [string]$state.authority_hashes[$path]
    if ($currentSha -cne $previousSha) {
      $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason='Register the package-excluded golden four-target archive baseline and byte-exact reconstruction proof.';scope='package-excluded-golden-baseline';package_visible=$false;release_authority=$false})
    }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role='Current package-excluded golden four-target archive baseline authority, implementation, or proof.'})
  }
}

$outputPath = Join-Path $RepoRoot $outputRelative
if (-not $Check -and -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
  [IO.File]::WriteAllText($outputPath, "{}`n", [Text.UTF8Encoding]::new($false))
}

$characterization = Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization'
[void](Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization' -Check)
$archives = @($baseline.targets | ForEach-Object { [ordered]@{target=[string]$_.target;version=[string]$_.distribution_version;archive_sha256=[string]$_.archive.sha256;content_sha256=[string]$_.archive.content_sha256;entry_count=[int]$_.archive.entry_count;bytes=[int]$_.archive.bytes} })
$proof = [ordered]@{
  baseline_record_sha256=[string]$baseline.record_sha256
  baseline_authority_sha256=Get-MIR4PreFreezeFileSha256 -Path $baselinePath -Mode 'canonical-text-v1'
  source_changelog_sha256=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $RepoRoot 'CHANGELOG.md') -Mode 'canonical-text-v1'
  target_count=@($baseline.targets).Count
  common_files=@($baseline.classification.common).Count;modern_family_files=@($baseline.classification.families.modern).Count;legacy_family_files=@($baseline.classification.families.legacy).Count
  target_overlays=[ordered]@{f210=@($baseline.classification.targets.f210).Count;f200=@($baseline.classification.targets.f200).Count;f110=@($baseline.classification.targets.f110).Count;f100=@($baseline.classification.targets.f100).Count}
  archives=$archives
  physical_files=[int]$characterization.summary.physical_files;unknown_paths=[int]$characterization.invariants.unknown_paths;package_files=[int]$characterization.summary.package_files
}

if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-m41-f1-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$receipt = [ordered]@{
  schema=1;kind='MIR4M41F1GoldenFourTargetBaselineAuthorityEvolutionV1';recorded_at=$RecordedAt;programme_id='M41-F1-GOLDEN-FOUR-TARGET-BASELINE';change_id='MIR4-CHG-2026-0004'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256};base=[ordered]@{branch='dev';commit='b911f8e3c29ff9bbefdb297a4ffb4913f12d07b2';tree='885ca746ff244d539ad5fa880041bb2e3835ad9a'}
  evolved_bindings=@($evolved);current_authorities=@($current);baseline_proof=$proof;player_package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme;package_visible_delta=@()
  invariants=[ordered]@{four_archives_exact=$true;classification_complete=$true;reconstruction_byte_exact=$true;stable_identity_surface_captured=$true;runtime_replay_pending=$true;package_source_unchanged=$true;root_readme_byte_stable=$true}
  transition_gate=[ordered]@{merge=$false;source_move=$false;package_cutover=$false;readme_rewrite=$false;bridge_retirement=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status='M41-F1-GOLDEN-FOUR-TARGET-ARCHIVE-BASELINE-COMPLETE-RUNTIME-REPLAY-PENDING'
}
$json = (($receipt | ConvertTo-Json -Depth 80).Replace("`r`n", "`n") + "`n")
if ($Check) { if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-m41-f1-receipt-stale]' } } else { [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false)) }
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) { throw '[mir4-m41-f1-receipt-schema]' }
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;baseline_proof=$proof;package_source_sha256=$expectedPackage}
