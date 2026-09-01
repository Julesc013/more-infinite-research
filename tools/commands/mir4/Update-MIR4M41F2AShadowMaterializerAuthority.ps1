[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/repository/RepositoryCharacterization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/ShadowTargetMaterializer.ps1')

$outputRelative = 'releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json'
$schemaRelative = 'contracts/repository/mir4-m41-f2a-shadow-target-materializer-authority-evolution-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json'
$predecessorSha256 = 'B6365CE4015BCFAF5A0CE4EBCBE2D4DE0062D6BE42EF53FA2BBF231C5D3FD49C'
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
}
$state = Get-MIR4PreFreezeAuthorityState @stateArguments
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) { throw '[mir4-m41-f2a-predecessor]' }
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackage) { throw '[mir4-m41-f2a-package-source]' }
if ((Get-MIRFileContentSha256 -Path (Join-Path $RepoRoot 'README.md') -RelativePath 'README.md') -cne $expectedReadme) { throw '[mir4-m41-f2a-readme]' }

$rolePaths = @(
  '.mir/assurance.json','.mir/control-plane/ownership.json','.mir/control/paths.yml','.mir/modules.yml','CHANGELOG.md','docs/architecture/module-boundaries.md',
  'releases/governance/MIR4-Source-Changelog-PlanV1.json','tools/lib/mir4/PreFreezeRelease.ps1','tools/mir.ps1','validation/tests.yml','validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1',
  'changes/unreleased/MIR4-CHG-2026-0005.json','contracts/repository/mir4-m41-f2a-shadow-target-materializer-authority-evolution-v1.schema.json',
  'spec/schemas/mir4-shadow-target-materializer-proof-v1.schema.json','tools/commands/mir4/Update-MIR4M41F2AShadowMaterializerAuthority.ps1',
  'tools/mir/application/package/ShadowTargetMaterializer.ps1','tools/mir/cli/Invoke-MIR4PackageSource.ps1','validation/tests/mir4/Test-MIR4ShadowTargetMaterializer.ps1','validation/tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'
)
$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($path in $rolePaths) {
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-m41-f2a-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $currentSha = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previousSha = [string]$state.authority_hashes[$path]
    if ($currentSha -cne $previousSha) {
      $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason='Register the package-excluded four-target shadow materializer and exact tree parity proof.';scope='package-excluded-shadow-materializer';package_visible=$false;release_authority=$false})
    }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role='Current package-excluded shadow target materializer implementation, contract, or proof.'})
  }
}

$outputPath = Join-Path $RepoRoot $outputRelative
if (-not $Check -and -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
  [IO.File]::WriteAllText($outputPath, "{}`n", [Text.UTF8Encoding]::new($false))
}

$shadowReportPath = 'build/reports/package-source/authority/mir4-shadow-target-materializer-v1.json'
$shadow = Invoke-MIR4ShadowTargetParity -RepoRoot $RepoRoot -OutputRoot 'build/mir4/package-source/authority/shadow-materializer-v1' -ReportPath $shadowReportPath
if (-not ((Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $shadowReportPath)) | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-shadow-target-materializer-proof-v1.schema.json'))) { throw '[mir4-m41-f2a-shadow-schema]' }
$characterization = Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization'
[void](Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization' -Check)
$contentIdentities = @($shadow.targets | ForEach-Object { [ordered]@{target=[string]$_.target;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count;common_files=[int]$_.layer_counts.common;family_files=[int]$_.layer_counts.family;target_files=[int]$_.layer_counts.target} })
$proof = [ordered]@{
  baseline_record_sha256=[string]$shadow.baseline_record_sha256;proof_record_sha256=[string]$shadow.record_sha256;target_count=@($shadow.targets).Count;materialization_count=(@($shadow.targets).Count*2)
  all_exact_tree_parity=@($shadow.targets | Where-Object { -not [bool]$_.exact_tree_parity }).Count -eq 0
  all_deterministic_archive_bytes=@($shadow.targets | Where-Object { -not [bool]$_.deterministic_archive_bytes }).Count -eq 0
  historical_archive_byte_parity_count=@($shadow.targets | Where-Object { [bool]$_.historical_archive_byte_parity }).Count
  content_identities=$contentIdentities;physical_files=[int]$characterization.summary.physical_files;unknown_paths=[int]$characterization.invariants.unknown_paths;package_files=[int]$characterization.summary.package_files
}

if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-m41-f2a-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$receipt = [ordered]@{
  schema=1;kind='MIR4M41F2AShadowTargetMaterializerAuthorityEvolutionV1';recorded_at=$RecordedAt;programme_id='M41-F2A-SHADOW-TARGET-MATERIALIZER';change_id='MIR4-CHG-2026-0005'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256};base=[ordered]@{branch='dev';commit='6f6321b4c656792e73b9aad1384b148b7dd2b373';tree='f889e36ac51115c1fe5aac29ff982598ea06e1fa'}
  evolved_bindings=@($evolved);current_authorities=@($current);materializer_proof=$proof;player_package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme;package_visible_delta=@()
  invariants=[ordered]@{four_target_tree_parity=$true;two_construction_determinism=$true;historical_archives_are_bootstrap_inputs=$true;historical_container_difference_explained=$true;current_writer_unchanged=$true;runtime_replay_pending=$true;package_source_unchanged=$true;root_readme_byte_stable=$true}
  transition_gate=[ordered]@{merge=$false;source_move=$false;package_cutover=$false;readme_rewrite=$false;bridge_retirement=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status='M41-F2A-SHADOW-TARGET-MATERIALIZER-PARITY-COMPLETE-NO-CUTOVER'
}
$json = (($receipt | ConvertTo-Json -Depth 80).Replace("`r`n", "`n") + "`n")
if ($Check) { if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-m41-f2a-receipt-stale]' } } else { [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false)) }
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) { throw '[mir4-m41-f2a-receipt-schema]' }
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;materializer_proof=$proof;package_source_sha256=$expectedPackage}
