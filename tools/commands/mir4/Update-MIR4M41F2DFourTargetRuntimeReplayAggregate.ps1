[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$EvidenceHome = '',
  [string]$RecordedAt = '',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioVersionPolicy.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/RuntimeReplayAggregateVerifier.ps1')

function Require-MIR4F2DAggregateWriter([bool]$Condition,[string]$Code) { if (-not $Condition) { throw "[$Code]" } }

$outputRelative = 'releases/migrations/MIR4-M41-F2D-Four-Target-Runtime-Replay-AggregateV1.json'
$schemaRelative = 'contracts/repository/mir4-m41-f2d-four-target-runtime-replay-aggregate-v1.schema.json'
$verifierRelative = 'tools/mir/application/package/RuntimeReplayAggregateVerifier.ps1'
$outputPath = Join-Path $RepoRoot $outputRelative
$predecessorRelative = 'releases/migrations/MIR4-M41-F2D-F100-Runtime-Replay-Authority-EvolutionV1.json'
$predecessorPath = Join-Path $RepoRoot $predecessorRelative
Require-MIR4F2DAggregateWriter (Test-Path -LiteralPath $predecessorPath -PathType Leaf) 'mir4-f2d-aggregate-predecessor-missing'
$predecessorSha256 = Get-MIR4F2DAggregateFileSha256V1 $predecessorPath

$stateArguments = @{
  RepoRoot=$RepoRoot;IncludeT17MachinePreparation=$true;IncludeRepositoryMigration=$true;IncludeCanonicalizationMigration=$true;IncludeDiagnosticsMigration=$true
  IncludeTargetKeyMigration=$true;IncludeWholePlatformMigration=$true;IncludeTechnologyAcceptanceMigration=$true;IncludeTargetCompilerMigration=$true
  IncludeSemanticCompilerPolicyMigration=$true;IncludeRuntimeContinuityMigration=$true;IncludeModuleSdkMepMigration=$true;IncludeProcessIRExactMigration=$true
  IncludeInspectorCompatibilityMigration=$true;IncludeAssuranceOfflineCustodyMigration=$true;IncludeHistoricalToolingMigration=$true;IncludeReleaseToolingMigration=$true
  IncludeF210QualificationPolicyEvolution=$true;IncludeFinalMileToolingEvolution=$true;IncludeFinalReleaseClosureEvolution=$true;IncludePostReleasePackageBaselineEvolution=$true
  IncludePostReleaseAutomationCutover=$true;IncludePostReleaseBranchOperatingModel=$true;IncludePostReleasePatchLaneRehearsal=$true;IncludeM4103ChangeReleaseAuthority=$true
  IncludeM4105AM4200ACharacterizationAuthority=$true;IncludeM41F0TruthReconciliationAuthority=$true;IncludeM41F1GoldenBaselineAuthority=$true
  IncludeM41F2AShadowMaterializerAuthority=$true;IncludeM41F2BShadowSourceModelAuthority=$true;IncludeM41F2CEditableSourceMaterializerAuthority=$true
  IncludeM41F2DHarnessAuthority=$true;IncludeM41F2DF210RuntimeReplayAuthority=$true;M41F2DTargetRuntimeReplayTargets=@('f200','f110','f100')
}
$state = Get-MIR4PreFreezeAuthorityState @stateArguments
Require-MIR4F2DAggregateWriter ([string]$state.prior_receipt_path -ceq $predecessorRelative -and [string]$state.prior_receipt_sha256 -ceq $predecessorSha256) 'mir4-f2d-aggregate-predecessor-chain'

$existing = $null
if ($Check) {
  Require-MIR4F2DAggregateWriter (Test-Path -LiteralPath $outputPath -PathType Leaf) 'mir4-f2d-aggregate-receipt-missing'
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
  $authorityBaseCommit = [string]$existing.base.authority_base_commit
  $authorityBaseTree = [string]$existing.base.authority_base_tree
  $aggregationCommit = [string]$existing.base.aggregation_commit
  $aggregationTree = [string]$existing.base.aggregation_tree
  $verification = $existing.verification
  if (-not [string]::IsNullOrWhiteSpace($EvidenceHome)) {
    $verification = New-MIR4M41F2DFourTargetRuntimeReplayVerificationV1 -RepoRoot $RepoRoot -EvidenceHome $EvidenceHome
    $verification | Add-Member -NotePropertyName verifier_path -NotePropertyValue $verifierRelative -Force
    $verification | Add-Member -NotePropertyName verifier_sha256 -NotePropertyValue (Get-MIR4F2DAggregateFileSha256V1 (Join-Path $RepoRoot $verifierRelative)) -Force
  }
} else {
  Require-MIR4F2DAggregateWriter (-not [string]::IsNullOrWhiteSpace($EvidenceHome) -and (Test-Path -LiteralPath $EvidenceHome -PathType Container)) 'mir4-f2d-aggregate-evidence-home-required'
  $verification = New-MIR4M41F2DFourTargetRuntimeReplayVerificationV1 -RepoRoot $RepoRoot -EvidenceHome $EvidenceHome
  $verification | Add-Member -NotePropertyName verifier_path -NotePropertyValue $verifierRelative -Force
  $verification | Add-Member -NotePropertyName verifier_sha256 -NotePropertyValue (Get-MIR4F2DAggregateFileSha256V1 (Join-Path $RepoRoot $verifierRelative)) -Force
  $authorityBaseCommit = (& git -C $RepoRoot merge-base HEAD origin/dev).Trim()
  $authorityBaseTree = (& git -C $RepoRoot rev-parse "$authorityBaseCommit`^{tree}").Trim()
  $aggregationCommit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  $aggregationTree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  if ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }
}

Require-MIR4F2DAggregateWriter (@($verification.targets).Count -eq 4 -and (@($verification.targets.target) -join '|') -ceq 'f210|f200|f110|f100') 'mir4-f2d-aggregate-target-order'
Require-MIR4F2DAggregateWriter ([string]$verification.verifier_path -ceq $verifierRelative -and [string]$verification.verifier_sha256 -ceq (Get-MIR4F2DAggregateFileSha256V1 (Join-Path $RepoRoot $verifierRelative))) 'mir4-f2d-aggregate-verifier-binding'
foreach ($target in @($verification.targets)) {
  $receiptPath = Join-Path $RepoRoot ([string]$target.receipt.path)
  Require-MIR4F2DAggregateWriter ((Get-MIR4F2DAggregateFileSha256V1 $receiptPath) -ceq [string]$target.receipt.sha256) 'mir4-f2d-aggregate-compact-receipt'
  $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100 -DateKind String
  Require-MIR4F2DAggregateWriter ([string]$receipt.status -ceq [string]$target.receipt.status -and [string]$receipt.base.replay_commit -ceq [string]$target.replay.commit -and [string]$receipt.base.replay_tree -ceq [string]$target.replay.tree -and @($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-f2d-aggregate-compact-binding'
}
Require-MIR4F2DAggregateWriter ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -ceq [string]$verification.package_source_sha256 -and (Get-MIRFileContentSha256 -Path (Join-Path $RepoRoot 'README.md') -RelativePath 'README.md') -ceq [string]$verification.root_readme_sha256) 'mir4-f2d-aggregate-compact-package-boundary'

$changeMatches = [Collections.Generic.List[object]]::new()
foreach ($fragmentPath in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'changes/unreleased') -File -Filter '*.json' | Sort-Object Name)) {
  $fragment = Get-Content -Raw -LiteralPath $fragmentPath.FullName | ConvertFrom-Json -Depth 40
  if (@($fragment.references | Where-Object { [string]$_.kind -ceq 'release-record' -and [string]$_.value -ceq $outputRelative }).Count -eq 1) {
    $changeMatches.Add([pscustomobject]@{path=$fragmentPath.FullName;relative="changes/unreleased/$($fragmentPath.Name)";record=$fragment})
  }
}
Require-MIR4F2DAggregateWriter ($changeMatches.Count -eq 1) 'mir4-f2d-aggregate-change-fragment'
$change = $changeMatches[0]
Require-MIR4F2DAggregateWriter ([string]$change.record.change_id -ceq 'MIR4-CHG-2026-0012' -and [string]$change.record.status -ceq 'accepted' -and [string]$change.record.package_visibility -ceq 'repository-only') 'mir4-f2d-aggregate-change-state'

$rolePaths = @(& git -C $RepoRoot diff --name-only $authorityBaseCommit --)
$rolePaths += @(& git -C $RepoRoot ls-files --others --exclude-standard)
$rolePaths += @($change.relative,$schemaRelative,$verifierRelative,'CHANGELOG.md','docs/releases/mir4-post-4.0-roadmap.md','releases/governance/MIR4-Source-Changelog-PlanV1.json','spec/programmes/mir4-4x-operating-programme-v1.json','spec/schemas/mir4-4x-operating-programme-v1.schema.json','todo.md','tools/lib/mir4/PreFreezeRelease.ps1','validation/tests/mir4/Test-MIR4RuntimeReplayF2D.ps1','validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1','tools/commands/mir4/Update-MIR4M41F2DFourTargetRuntimeReplayAggregate.ps1')
$rolePaths = @($rolePaths | ForEach-Object { ([string]$_).Replace('\','/') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -cne $outputRelative } | Sort-Object -Unique -CaseSensitive)
$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($path in $rolePaths) {
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $currentSha = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previousSha = [string]$state.authority_hashes[$path]
    if ($currentSha -cne $previousSha) { $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason='Accept the independent four-target runtime and transition replay aggregate without package cutover.';scope='package-excluded-four-target-runtime-aggregate';package_visible=$false;release_authority=$false}) }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role='Current four-target runtime aggregate contract, implementation, proof, programme, or verification authority.'})
  }
}

$receipt = [ordered]@{
  schema=1;kind='MIR4M41F2DFourTargetRuntimeReplayAggregateV1';recorded_at=$RecordedAt;programme_id='M41-F2D-FOUR-TARGET-RUNTIME-REPLAY-AGGREGATE';change_id='MIR4-CHG-2026-0012'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  base=[ordered]@{branch='dev';authority_base_commit=$authorityBaseCommit;authority_base_tree=$authorityBaseTree;aggregation_commit=$aggregationCommit;aggregation_tree=$aggregationTree}
  evolved_bindings=@($evolved);current_authorities=@($current);verification=$verification
  package_source_sha256=[string]$verification.package_source_sha256;root_readme_sha256=[string]$verification.root_readme_sha256;package_visible_delta=@()
  invariants=[ordered]@{four_receipts_verified=$true;predecessor_chain_verified=$true;four_independent_engines_verified=$true;four_package_trees_verified=$true;four_upgrade_and_reload_results_verified=$true;four_external_custody_roots_verified=$true;package_source_unchanged=$true;root_readme_unchanged=$true;old_writer_remains_authoritative=$true;aggregate_grants_no_cutover_or_release_authority=$true}
  transition_gate=[ordered]@{merge=$false;package_cutover=$false;old_writer_retirement=$false;readme_rewrite=$false;bridge_retirement=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false;remote_write=$false}
  next_fixed_point='M41-F2E-PACKAGE-AUTHORITY-CUTOVER';status='M41-F2D-FOUR-TARGET-RUNTIME-REPLAY-PASSED-NO-CUTOVER'
}
$json = (($receipt | ConvertTo-Json -Depth 100).Replace("`r`n","`n") + "`n")
if ($Check) {
  if ([IO.File]::ReadAllText($outputPath).Replace("`r`n","`n") -cne $json) { throw '[mir4-f2d-aggregate-receipt-stale]' }
} else {
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
  [IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))
}
Require-MIR4F2DAggregateWriter ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative)) 'mir4-f2d-aggregate-receipt-schema'
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;aggregate_status=[string]$receipt.status;targets=@($receipt.verification.targets).Count;external_custody=[string]$receipt.verification.external_custody;package_cutover=[bool]$receipt.transition_gate.package_cutover}
