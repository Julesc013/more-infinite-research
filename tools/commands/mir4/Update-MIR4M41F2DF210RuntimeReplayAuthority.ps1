[CmdletBinding()]
param([string]$RepoRoot = '', [string]$EvidenceRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')

$outputRelative = 'releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json'
$schemaRelative = 'contracts/repository/mir4-m41-f2d-f210-runtime-replay-authority-evolution-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json'
$predecessorSha256 = '24E4132E93D0010E86CCDE7E3F45D1E4440EFB1CA0028EE1B40D036BC96D82BC'
$f2cCommit = '12c714a358a88c73705c525bce289649fc2fed7b'
$harnessCommit = '04586270430d5d742e86135b7904e66f023779b0'
$replayCommit = '67b3695a6fbc65931cb1e75b74b16f2fc9ee4973'
$expectedPackage = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$expectedReadme = 'DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'
$expectedEvidence = [ordered]@{
  'target-proof.json'='B0113BD090B3737A88400F0C4E7BEB544F9BB41482C77E9CEE6740A5F255439E'
  'fresh-load-result.json'='EDF42E0825D5C9C4DD46FE8CB8EE97DF45FAE8C4D8953F50670AF657548AD6D2'
  'upgrade-matrix.json'='40FA4AA0C09FEE0EDB33F11F387C18A52D1EC6B95831917B960B42B49B7D2D4D'
  'independent-verification.json'='349E963704525D6B7DA5F356C4E8164E3CE2A8CF0D5D16C0EB28A98DFFB4D622'
  'resource-receipt.json'='FBE24D705E4EB6754BEA4170B3FD02966020824EFDEDB6309B262C00BF20D74F'
  'custody-manifest.json'='A163B27A950AA280D81632953284D5919CC28BDF7D1E3D8D4FF5E2E8DB6547FC'
}

$stateArguments = @{
  RepoRoot=$RepoRoot;IncludeT17MachinePreparation=$true;IncludeRepositoryMigration=$true;IncludeCanonicalizationMigration=$true;IncludeDiagnosticsMigration=$true
  IncludeTargetKeyMigration=$true;IncludeWholePlatformMigration=$true;IncludeTechnologyAcceptanceMigration=$true;IncludeTargetCompilerMigration=$true
  IncludeSemanticCompilerPolicyMigration=$true;IncludeRuntimeContinuityMigration=$true;IncludeModuleSdkMepMigration=$true;IncludeProcessIRExactMigration=$true
  IncludeInspectorCompatibilityMigration=$true;IncludeAssuranceOfflineCustodyMigration=$true;IncludeHistoricalToolingMigration=$true;IncludeReleaseToolingMigration=$true
  IncludeF210QualificationPolicyEvolution=$true;IncludeFinalMileToolingEvolution=$true;IncludeFinalReleaseClosureEvolution=$true;IncludePostReleasePackageBaselineEvolution=$true
  IncludePostReleaseAutomationCutover=$true;IncludePostReleaseBranchOperatingModel=$true;IncludePostReleasePatchLaneRehearsal=$true;IncludeM4103ChangeReleaseAuthority=$true
  IncludeM4105AM4200ACharacterizationAuthority=$true;IncludeM41F0TruthReconciliationAuthority=$true;IncludeM41F1GoldenBaselineAuthority=$true
  IncludeM41F2AShadowMaterializerAuthority=$true;IncludeM41F2BShadowSourceModelAuthority=$true;IncludeM41F2CEditableSourceMaterializerAuthority=$true
  IncludeM41F2DHarnessAuthority=$true
}
$state = Get-MIR4PreFreezeAuthorityState @stateArguments
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) { throw '[mir4-m41-f2d-f210-predecessor]' }
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackage) { throw '[mir4-m41-f2d-f210-package-source]' }
if ((Get-MIRFileContentSha256 -Path (Join-Path $RepoRoot 'README.md') -RelativePath 'README.md') -cne $expectedReadme) { throw '[mir4-m41-f2d-f210-readme]' }

if (-not $Check) {
  if ([string]::IsNullOrWhiteSpace($EvidenceRoot) -or -not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) { throw '[mir4-m41-f2d-f210-evidence-required]' }
  $resolvedEvidence = (Resolve-Path -LiteralPath $EvidenceRoot).Path
  foreach ($entry in $expectedEvidence.GetEnumerator()) {
    $path = Join-Path $resolvedEvidence $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne [string]$entry.Value) { throw "[mir4-m41-f2d-f210-evidence-hash] $($entry.Key)" }
  }
  $proof = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'target-proof.json') | ConvertFrom-Json -Depth 100
  $verification = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'independent-verification.json') | ConvertFrom-Json -Depth 100
  $resource = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'resource-receipt.json') | ConvertFrom-Json -Depth 100
  $custody = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'custody-manifest.json') | ConvertFrom-Json -Depth 100
  if ([string]$proof.status -cne 'M41-F2D-210-PASSED-NO-CUTOVER' -or [string]$proof.source.commit -cne $replayCommit -or [string]$verification.status -cne 'passed' -or [string]$resource.work_root_status -cne 'removed' -or [string]$custody.status -cne 'verified') { throw '[mir4-m41-f2d-f210-evidence-state]' }
  foreach ($row in @($custody.files)) {
    $path = Join-Path $resolvedEvidence ([string]$row.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne [string]$row.sha256 -or (Get-Item -LiteralPath $path).Length -ne [int64]$row.bytes) { throw "[mir4-m41-f2d-f210-custody] $([string]$row.path)" }
  }
}

$rolePaths = @(& git -C $RepoRoot diff --name-only "$harnessCommit..HEAD")
$rolePaths += @(
  'CHANGELOG.md',
  'changes/unreleased/MIR4-CHG-2026-0008.json',
  'releases/governance/MIR4-Source-Changelog-PlanV1.json',
  'tools/lib/mir4/PreFreezeRelease.ps1',
  'tools/mir/application/package/RuntimeReplay.ps1',
  'tools/mir/application/package/RuntimeReplayVerifier.ps1',
  'validation/tests/mir4/Test-MIR4RuntimeReplayF2D.ps1',
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1',
  'tools/commands/mir4/Update-MIR4M41F2DF210RuntimeReplayAuthority.ps1',
  $schemaRelative
)
$rolePaths = @($rolePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -cne $outputRelative } | Sort-Object -Unique -CaseSensitive)
$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($path in $rolePaths) {
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-m41-f2d-f210-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $currentSha = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previousSha = [string]$state.authority_hashes[$path]
    if ($currentSha -cne $previousSha) { $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason='Accept exact F210 runtime and transition replay with compact external custody.';scope='package-excluded-f210-runtime-replay';package_visible=$false;release_authority=$false}) }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role='Current F210 runtime replay result, compact custody reference, change fact, schema, generator, or verification authority.'})
  }
}

$outputPath = Join-Path $RepoRoot $outputRelative
if (-not $Check -and -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null; [IO.File]::WriteAllText($outputPath, "{}`n", [Text.UTF8Encoding]::new($false)) }
if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-m41-f2d-f210-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$receipt = [ordered]@{
  schema=1;kind='MIR4M41F2DF210RuntimeReplayAuthorityEvolutionV1';recorded_at=$RecordedAt;programme_id='M41-F2D-F210-RUNTIME-REPLAY';change_id='MIR4-CHG-2026-0008'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256};base=[ordered]@{branch='dev';f2c_commit=$f2cCommit;harness_authority_commit=$harnessCommit;replay_commit=$replayCommit;replay_tree='243755895d62fd62453adb75d54bcea0e28a6db0'}
  evolved_bindings=@($evolved);current_authorities=@($current)
  attempts=@(
    [ordered]@{source_commit='f3416e80c822b9a0cdc945347760d4f2fb1cccef';status='classified-integration-failure';phase='pre-runtime-static-authority-check';classification='missing-f2d-successor-authority-receipt';factorio_started=$false;retention='OnFailure';expanded_files=306;expanded_bytes=5390830},
    [ordered]@{source_commit=$harnessCommit;status='classified-integration-failure';phase='pre-runtime-static-authority-check';classification='unrelated-external-evidence-required-by-broad-smoke-preamble';factorio_started=$false;retention='OnFailure';expanded_files=306;expanded_bytes=5390830}
  )
  replay_proof=[ordered]@{
    status='M41-F2D-210-PASSED-NO-CUTOVER';target='f210';candidate_id='M41-F2D-67B3695A-F210'
    engine=[ordered]@{selector='latest-installed-official-2.1-experimental';version='2.1.17';file_version='2.1.17.87315';binary_sha256='710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8'}
    package=[ordered]@{distribution_version='4.0.21000';archive_sha256='4DE721FFCD6BECBA34ED110EE1BEE59ADDE3E6BBF13E993C339FC7729862E41A';content_sha256='CA72A8045654FFDC8630D54567F6D04A1B40BA5682ED06E7FACCF2772A2660ED';entry_count=305}
    predecessor=[ordered]@{version='3.2.11';archive_sha256='5B0252C3E1B8A20FF8E31F408F0217DDC77D2DF0D1C15F59653E948472870A5A'}
    fresh_load=[ordered]@{status='passed';scenario_count=14;result_sha256='EDF42E0825D5C9C4DD46FE8CB8EE97DF45FAE8C4D8953F50670AF657548AD6D2'}
    upgrade=[ordered]@{status='passed';archetype_count=5;first_reload=$true;second_reload=$true;result_sha256='40FA4AA0C09FEE0EDB33F11F387C18A52D1EC6B95831917B960B42B49B7D2D4D'}
    evidence=[ordered]@{logical_root='MIR_EVIDENCE_HOME/m41-f2d/67b3695a6fbc65931cb1e75b74b16f2fc9ee4973/f210';target_proof_sha256='B0113BD090B3737A88400F0C4E7BEB544F9BB41482C77E9CEE6740A5F255439E';independent_verification_sha256='349E963704525D6B7DA5F356C4E8164E3CE2A8CF0D5D16C0EB28A98DFFB4D622';custody_manifest_sha256='A163B27A950AA280D81632953284D5919CC28BDF7D1E3D8D4FF5E2E8DB6547FC';custody_file_count=38;evidence_file_count=39;evidence_bytes=40021171}
    resource=[ordered]@{retention='OnFailure';work_root_status='removed';expanded_files=440;expanded_bytes=70485018;duration_seconds=252.038;receipt_sha256='FBE24D705E4EB6754BEA4170B3FD02966020824EFDEDB6309B262C00BF20D74F'}
  }
  player_package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme;package_visible_delta=@()
  invariants=[ordered]@{latest_experimental_2_1_selector=$true;exact_execution_identity_required=$true;cross_version_evidence_reuse_forbidden=$true;f210_runtime_replay_complete=$true;f2d_four_target_complete=$false;f200_runtime_replay_pending=$true;f110_runtime_replay_pending=$true;f100_runtime_replay_pending=$true;expanded_work_released_after_verified_custody=$true;package_source_unchanged=$true;root_readme_byte_stable=$true;old_writer_remains_authoritative=$true}
  transition_gate=[ordered]@{merge=$false;source_move=$false;package_cutover=$false;readme_rewrite=$false;bridge_retirement=$false;old_writer_retirement=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status='M41-F2D-210-PASSED-NO-CUTOVER'
}
$json = (($receipt | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n")
if ($Check) { if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-m41-f2d-f210-receipt-stale]' } } else { [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false)) }
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) { throw '[mir4-m41-f2d-f210-receipt-schema]' }
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;proof_status='M41-F2D-210-PASSED-NO-CUTOVER';custody_manifest_sha256=$expectedEvidence['custody-manifest.json']}
