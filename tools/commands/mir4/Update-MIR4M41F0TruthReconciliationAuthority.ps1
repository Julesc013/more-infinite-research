[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/repository/RepositoryCharacterization.ps1')

$outputRelative = 'releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json'
$schemaRelative = 'contracts/repository/mir4-m41-f0-truth-reconciliation-authority-evolution-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json'
$predecessorSha256 = '1D5F3F67701DB9F1281B6FA376D031AD7513118259FACF25DEAC82DD66CD8FBF'
$expectedPackage = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$expectedReadme = 'DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'

$stateArguments = @{
  RepoRoot=$RepoRoot;IncludeT17MachinePreparation=$true;IncludeRepositoryMigration=$true;IncludeCanonicalizationMigration=$true;IncludeDiagnosticsMigration=$true
  IncludeTargetKeyMigration=$true;IncludeWholePlatformMigration=$true;IncludeTechnologyAcceptanceMigration=$true;IncludeTargetCompilerMigration=$true
  IncludeSemanticCompilerPolicyMigration=$true;IncludeRuntimeContinuityMigration=$true;IncludeModuleSdkMepMigration=$true;IncludeProcessIRExactMigration=$true
  IncludeInspectorCompatibilityMigration=$true;IncludeAssuranceOfflineCustodyMigration=$true;IncludeHistoricalToolingMigration=$true;IncludeReleaseToolingMigration=$true
  IncludeF210QualificationPolicyEvolution=$true;IncludeFinalMileToolingEvolution=$true;IncludeFinalReleaseClosureEvolution=$true;IncludePostReleasePackageBaselineEvolution=$true
  IncludePostReleaseAutomationCutover=$true;IncludePostReleaseBranchOperatingModel=$true;IncludePostReleasePatchLaneRehearsal=$true;IncludeM4103ChangeReleaseAuthority=$true
  IncludeM4105AM4200ACharacterizationAuthority=$true
}
$state = Get-MIR4PreFreezeAuthorityState @stateArguments
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) { throw '[mir4-m41-f0-predecessor]' }
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackage) { throw '[mir4-m41-f0-package-source]' }
if ((Get-MIRFileContentSha256 -Path (Join-Path $RepoRoot 'README.md') -RelativePath 'README.md') -cne $expectedReadme) { throw '[mir4-m41-f0-readme]' }

$mirToml = [IO.File]::ReadAllText((Join-Path $RepoRoot 'mir.toml'))
if ($mirToml -match '(?m)^(?:programme_id|programme_execution_id|candidate_state|next_candidate|whole_platform_programme)\s*=') { throw '[mir4-m41-f0-mutable-candidate-state]' }
$todoText = [IO.File]::ReadAllText((Join-Path $RepoRoot 'todo.md'))
if ($todoText.IndexOf('## Active MIR 4.x operating programme', [StringComparison]::Ordinal) -lt 0 -or
    $todoText.IndexOf('## Historical MIR 4.0 pre-freeze execution record', [StringComparison]::Ordinal) -lt $todoText.IndexOf('## Active MIR 4.x operating programme', [StringComparison]::Ordinal)) { throw '[mir4-m41-f0-todo-routing]' }
$changelogText = [IO.File]::ReadAllText((Join-Path $RepoRoot 'CHANGELOG.md'))
if ($changelogText -notmatch '(?m)^## Unreleased$' -or $changelogText -notmatch '(?m)^## \[4\.0\.0\] - 2026-08-30$') { throw '[mir4-m41-f0-source-changelog]' }

$rolePaths = @(
  '.gitattributes','.mir/README.md','.mir/assurance.json','.mir/control-plane/ownership.json','.mir/control/paths.yml','.mir/docs.yml','.mir/modules.yml',
  '.mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-Visibility-Canonicalization-ReconciliationV1.json','CHANGELOG.md',
  'changes/unreleased/MIR4-CHG-2026-0003.json','contracts/repository/mir4-m41-f0-truth-reconciliation-authority-evolution-v1.schema.json',
  'docs/architecture/decisions/0007-mir4-4.1-foundation-completion-boundary.md','docs/architecture/decisions/README.md','docs/architecture/mir4-change-and-release-authority.md','docs/architecture/module-boundaries.md',
  'docs/reference/generated/documentation-index.md','docs/reference/generated/documentation-navigation.md','docs/reference/generated/documentation-owner-dashboard.md','docs/reference/generated/documentation-reference-matrix.md','docs/reference/generated/documentation-review-age.md',
  'docs/releases/mir4-post-4.0-roadmap.md','mir.lock','mir.toml','releases/governance/MIR4-Source-Changelog-PlanV1.json',
  'sdk/preview/mir4/reference/compilation-runs.json','sdk/preview/mir4/reference/inspection-bundle-v1.json','sdk/preview/mir4/reference/inspector-workbench-result-v1.json','sdk/preview/mir4/reference/query-snapshot-f210.json',
  'spec/programmes/mir4-4x-operating-programme-v1.json','spec/schemas/mir3-dot9-mod-portal-visibility-canonicalization-reconciliation-v1.schema.json','spec/schemas/mir4-4x-operating-programme-v1.schema.json','todo.md',
  'tools/commands/mir4/Update-MIR4M41F0TruthReconciliationAuthority.ps1','tools/commands/release/Test-MIR4R0Bootstrap.ps1','tools/lib/control/Views.ps1','tools/lib/mir4/BootstrapMaterialization.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/workspace/RepoPaths.ps1',
  'tools/mir.ps1','tools/mir/application/release/ReleaseNarratives.ps1','tools/mir/cli/Invoke-MIR4ReleaseNarratives.ps1','tools/mir/domain/repository/RepositoryFixedPoint.ps1',
  'validation/tests.yml','validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1','validation/tests/mir4/Test-MIR4ReleaseNarrativesM4103.ps1','validation/tests/mir4/Test-MIR4RepositoryCharacterizationM4200A.ps1','validation/tests/release/Test-MIR3Dot9ModPortalVisibilityRecheck.ps1','validation/tests/tooling/Test-MIRControlPlane.ps1'
)
$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($path in $rolePaths) {
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-m41-f0-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $currentSha = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previousSha = [string]$state.authority_hashes[$path]
    if ($currentSha -cne $previousSha) {
      $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason='Reconcile the MIR 4.1 physical-foundation programme and its exact generated or executable projection.';scope='package-excluded-truth-reconciliation';package_visible=$false;release_authority=$false})
    }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role='Current package-excluded MIR 4.1 truth-reconciliation authority or projection.'})
  }
}

$outputPath = Join-Path $RepoRoot $outputRelative
if (-not $Check -and -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
  [IO.File]::WriteAllText($outputPath, "{}`n", [Text.UTF8Encoding]::new($false))
}

$characterization = Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization'
[void](Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization' -Check)
$proof = [ordered]@{
  programme_sha256=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $RepoRoot 'spec/programmes/mir4-4x-operating-programme-v1.json') -Mode 'canonical-text-v1'
  source_changelog_sha256=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $RepoRoot 'CHANGELOG.md') -Mode 'canonical-text-v1'
  todo_sha256=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $RepoRoot 'todo.md') -Mode 'canonical-text-v1'
  portal_reconciliation_sha256=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $RepoRoot '.mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-Visibility-Canonicalization-ReconciliationV1.json') -Mode 'canonical-text-v1'
  platform_lock_sha256=Get-MIR4PreFreezeFileSha256 -Path (Join-Path $RepoRoot 'mir.lock') -Mode 'canonical-text-v1'
  physical_files=[int]$characterization.summary.physical_files;unknown_paths=[int]$characterization.invariants.unknown_paths;package_files=[int]$characterization.summary.package_files
}

if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-m41-f0-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$receipt = [ordered]@{
  schema=1;kind='MIR4M41F0TruthReconciliationAuthorityEvolutionV1';recorded_at=$RecordedAt;programme_id='M41-F0-TRUTH-RECONCILIATION';change_id='MIR4-CHG-2026-0003'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256};base=[ordered]@{branch='dev';commit='e727203fca888994aa3fff2a2463be77d3620b45';tree='8a06a73d624705beb8963e7b007a85093587c3c5'}
  evolved_bindings=@($evolved);current_authorities=@($current);truth_proof=$proof;player_package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme;package_visible_delta=@()
  invariants=[ordered]@{live_programme_is_current=$true;mutable_candidate_state_removed=$true;historical_prefreeze_scoped=$true;source_changelog_generated=$true;todo_routes_live_programme_first=$true;portal_hash_contradiction_reconciled=$true;package_source_unchanged=$true;root_readme_byte_stable=$true}
  transition_gate=[ordered]@{merge=$false;source_move=$false;package_cutover=$false;readme_rewrite=$false;bridge_retirement=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status='M41-F0-TRUTH-RECONCILED-NO-PACKAGE-CUTOVER'
}
$json = (($receipt | ConvertTo-Json -Depth 80).Replace("`r`n", "`n") + "`n")
if ($Check) { if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-m41-f0-receipt-stale]' } } else { [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false)) }
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) { throw '[mir4-m41-f0-receipt-schema]' }
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;truth_proof=$proof;package_source_sha256=$expectedPackage}
