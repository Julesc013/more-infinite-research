[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')

$outputRelative = 'releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json'
$schemaRelative = 'contracts/repository/mir4-m41-f2d-runtime-replay-harness-authority-evolution-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json'
$predecessorSha256 = 'E1D7F216EEC6226B13769432E10F9765C7B0DAC2B9A1C910913847DDA0F835BD'
$baseCommit = '12c714a358a88c73705c525bce289649fc2fed7b'
$implementationCommit = 'f3416e80c822b9a0cdc945347760d4f2fb1cccef'
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
  IncludeM41F2AShadowMaterializerAuthority=$true;IncludeM41F2BShadowSourceModelAuthority=$true;IncludeM41F2CEditableSourceMaterializerAuthority=$true
}
$state = Get-MIR4PreFreezeAuthorityState @stateArguments
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) { throw '[mir4-m41-f2d-harness-predecessor]' }
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackage) { throw '[mir4-m41-f2d-harness-package-source]' }
if ((Get-MIRFileContentSha256 -Path (Join-Path $RepoRoot 'README.md') -RelativePath 'README.md') -cne $expectedReadme) { throw '[mir4-m41-f2d-harness-readme]' }

$rolePaths = @(& git -C $RepoRoot diff --name-only "$baseCommit..HEAD")
$rolePaths += @(
  'tools/lib/mir4/PreFreezeRelease.ps1',
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1',
  'tools/commands/mir4/Update-MIR4M41F2DHarnessAuthority.ps1',
  $schemaRelative
)
$rolePaths = @($rolePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -cne $outputRelative } | Sort-Object -Unique -CaseSensitive)
$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($path in $rolePaths) {
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-m41-f2d-harness-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $currentSha = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previousSha = [string]$state.authority_hashes[$path]
    if ($currentSha -cne $previousSha) {
      $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason='Adopt the rolling 2.1 policy and resource-bounded F2D runtime replay harness.';scope='package-excluded-f2d-runtime-replay-harness';package_visible=$false;release_authority=$false})
    }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role='Current rolling-engine policy, F2D harness, evidence contract, test, workflow, or documentation authority.'})
  }
}

$outputPath = Join-Path $RepoRoot $outputRelative
if (-not $Check -and -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
  [IO.File]::WriteAllText($outputPath, "{}`n", [Text.UTF8Encoding]::new($false))
}
if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-m41-f2d-harness-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$channel = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/engines/mir4-factorio-2.1-experimental-channel-v1.json') | ConvertFrom-Json -Depth 100 -DateKind String
$receipt = [ordered]@{
  schema=1;kind='MIR4M41F2DRuntimeReplayHarnessAuthorityEvolutionV1';recorded_at=$RecordedAt;programme_id='M41-F2D-RUNTIME-REPLAY-HARNESS';change_id='MIR4-CHG-2026-0008'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256};base=[ordered]@{branch='dev';commit=$baseCommit;tree='c1e0026843124d59365b5158e80c2972e22404bc';implementation_commit=$implementationCommit}
  evolved_bindings=@($evolved);current_authorities=@($current)
  engine_channel=[ordered]@{selector='latest-installed-official-2.1-experimental';patch_pinned=$false;reviewed_version=[string]$channel.current_review.version;binary_sha256=[string]$channel.current_review.binary_sha256;runtime_api_sha256=[string]$channel.current_review.runtime_api.sha256;prototype_api_sha256=[string]$channel.current_review.prototype_api.sha256;change_task_count=@($channel.change_review.required_tasks).Count}
  harness=[ordered]@{candidate_id_supported=$true;external_work_root=$true;external_evidence_root=$true;retention_modes=@('OnFailure','Always','Never');independent_verifier=$true;one_factorio_process=$true;one_materialization=$true}
  first_attempt=[ordered]@{status='classified-integration-failure';phase='pre-runtime-static-authority-check';classification='missing-f2d-successor-authority-receipt';factorio_started=$false;failure_retained_until_classified=$true;expanded_files=306;expanded_bytes=5390830}
  player_package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme;package_visible_delta=@()
  invariants=[ordered]@{latest_experimental_2_1_selector=$true;exact_execution_identity_required=$true;cross_version_evidence_reuse_forbidden=$true;failure_retained_until_classified=$true;runtime_replay_complete=$false;package_source_unchanged=$true;root_readme_byte_stable=$true;old_writer_remains_authoritative=$true}
  transition_gate=[ordered]@{merge=$false;source_move=$false;package_cutover=$false;readme_rewrite=$false;bridge_retirement=$false;old_writer_retirement=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status='M41-F2D-HARNESS-READY-RUNTIME-REPLAY-PENDING-NO-CUTOVER'
}
$json = (($receipt | ConvertTo-Json -Depth 80).Replace("`r`n", "`n") + "`n")
if ($Check) { if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-m41-f2d-harness-receipt-stale]' } } else { [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false)) }
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) { throw '[mir4-m41-f2d-harness-receipt-schema]' }
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;package_source_sha256=$expectedPackage}
