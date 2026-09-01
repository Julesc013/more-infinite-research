[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [Parameter(Mandatory)][ValidateSet('f200','f110','f100')][string]$Target,
  [string]$EvidenceRoot = '',
  [string]$RecordedAt = '',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioVersionPolicy.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')

function Require-MIR4F2DTarget([bool]$Condition,[string]$Code) { if (-not $Condition) { throw "[$Code]" } }
function Get-MIR4F2DTargetFileSha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

$code = $Target.Substring(1).ToUpperInvariant()
$outputRelative = "releases/migrations/MIR4-M41-F2D-F$code-Runtime-Replay-Authority-EvolutionV1.json"
$schemaRelative = 'contracts/repository/mir4-m41-f2d-target-runtime-replay-authority-evolution-v1.schema.json'
$outputPath = Join-Path $RepoRoot $outputRelative
$expectedPackage = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$expectedReadme = 'DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'
$acceptedF210Receipt = 'releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json'
$acceptedF210Sha256 = 'A690D41B0B37D4BAF78B615BB3042F51D97E3A9E552723DBCA3EE717943FBA8C'
$orderedTargets = @('f200','f110','f100')
$targetIndex = [array]::IndexOf($orderedTargets,$Target)
$predecessorRelative = if ($Target -eq 'f200') { $acceptedF210Receipt } else {
  $predecessorCode = $orderedTargets[$targetIndex-1].Substring(1).ToUpperInvariant()
  "releases/migrations/MIR4-M41-F2D-F$predecessorCode-Runtime-Replay-Authority-EvolutionV1.json"
}
$predecessorPath = Join-Path $RepoRoot $predecessorRelative
Require-MIR4F2DTarget (Test-Path -LiteralPath $predecessorPath -PathType Leaf) 'mir4-m41-f2d-target-predecessor-missing'
$predecessorSha256 = Get-MIR4F2DTargetFileSha256 $predecessorPath
if ($Target -eq 'f200') { Require-MIR4F2DTarget ($predecessorSha256 -ceq $acceptedF210Sha256) 'mir4-m41-f2d-target-f210-receipt-mutated' }

$stateArguments = @{
  RepoRoot=$RepoRoot;IncludeT17MachinePreparation=$true;IncludeRepositoryMigration=$true;IncludeCanonicalizationMigration=$true;IncludeDiagnosticsMigration=$true
  IncludeTargetKeyMigration=$true;IncludeWholePlatformMigration=$true;IncludeTechnologyAcceptanceMigration=$true;IncludeTargetCompilerMigration=$true
  IncludeSemanticCompilerPolicyMigration=$true;IncludeRuntimeContinuityMigration=$true;IncludeModuleSdkMepMigration=$true;IncludeProcessIRExactMigration=$true
  IncludeInspectorCompatibilityMigration=$true;IncludeAssuranceOfflineCustodyMigration=$true;IncludeHistoricalToolingMigration=$true;IncludeReleaseToolingMigration=$true
  IncludeF210QualificationPolicyEvolution=$true;IncludeFinalMileToolingEvolution=$true;IncludeFinalReleaseClosureEvolution=$true;IncludePostReleasePackageBaselineEvolution=$true
  IncludePostReleaseAutomationCutover=$true;IncludePostReleaseBranchOperatingModel=$true;IncludePostReleasePatchLaneRehearsal=$true;IncludeM4103ChangeReleaseAuthority=$true
  IncludeM4105AM4200ACharacterizationAuthority=$true;IncludeM41F0TruthReconciliationAuthority=$true;IncludeM41F1GoldenBaselineAuthority=$true
  IncludeM41F2AShadowMaterializerAuthority=$true;IncludeM41F2BShadowSourceModelAuthority=$true;IncludeM41F2CEditableSourceMaterializerAuthority=$true
  IncludeM41F2DHarnessAuthority=$true;IncludeM41F2DF210RuntimeReplayAuthority=$true
}
$priorLowerTargets = @($orderedTargets[0..([Math]::Max(-1,$targetIndex-1))])
if ($targetIndex -eq 0) { $priorLowerTargets = @() }
if ($priorLowerTargets.Count -gt 0) { $stateArguments.M41F2DTargetRuntimeReplayTargets = $priorLowerTargets }
$state = Get-MIR4PreFreezeAuthorityState @stateArguments
Require-MIR4F2DTarget ([string]$state.prior_receipt_path -ceq $predecessorRelative -and [string]$state.prior_receipt_sha256 -ceq $predecessorSha256) 'mir4-m41-f2d-target-predecessor-chain'
Require-MIR4F2DTarget ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -ceq $expectedPackage) 'mir4-m41-f2d-target-package-source'
Require-MIR4F2DTarget ((Get-MIRFileContentSha256 -Path (Join-Path $RepoRoot 'README.md') -RelativePath 'README.md') -ceq $expectedReadme) 'mir4-m41-f2d-target-readme'

$changeMatches = [Collections.Generic.List[object]]::new()
foreach ($fragmentPath in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'changes/unreleased') -File -Filter '*.json' | Sort-Object Name)) {
  $fragment = Get-Content -Raw -LiteralPath $fragmentPath.FullName | ConvertFrom-Json -Depth 40
  if (@($fragment.references | Where-Object { [string]$_.kind -ceq 'release-record' -and [string]$_.value -ceq $outputRelative }).Count -eq 1) {
    $changeMatches.Add([pscustomobject]@{path=$fragmentPath.FullName;relative="changes/unreleased/$($fragmentPath.Name)";record=$fragment})
  }
}
Require-MIR4F2DTarget ($changeMatches.Count -eq 1) 'mir4-m41-f2d-target-change-fragment'
$change = $changeMatches[0]
Require-MIR4F2DTarget ([string]$change.record.status -ceq 'accepted' -and [string]$change.record.package_visibility -ceq 'repository-only') 'mir4-m41-f2d-target-change-state'
$changeId = [string]$change.record.change_id

$golden = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/distribution/mir4-golden-four-target-baseline-v1.json') | ConvertFrom-Json -Depth 100
$baseline = @($golden.targets | Where-Object target -eq $Target)
Require-MIR4F2DTarget ($baseline.Count -eq 1) 'mir4-m41-f2d-target-baseline'
$baseline = $baseline[0]
$engineLock = Get-MIR4FixedFactorioEngineLock -Target $Target -RepoRoot $RepoRoot

$existing = $null
if ($Check) {
  Require-MIR4F2DTarget (Test-Path -LiteralPath $outputPath -PathType Leaf) 'mir4-m41-f2d-target-receipt-missing'
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
  $authorityBaseCommit = [string]$existing.base.authority_base_commit
  $authorityBaseTree = [string]$existing.base.authority_base_tree
  $replayProof = $existing.replay_proof
  $attempts = @($existing.attempts)
} else {
  Require-MIR4F2DTarget (-not [string]::IsNullOrWhiteSpace($EvidenceRoot) -and (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) 'mir4-m41-f2d-target-evidence-required'
  $resolvedEvidence = (Resolve-Path -LiteralPath $EvidenceRoot).Path
  $requiredEvidence = @('target-proof.json','fresh-load-result.json','upgrade-matrix.json','custody-precleanup.json','independent-verification.json','resource-receipt.json','custody-manifest.json')
  foreach ($name in $requiredEvidence) { Require-MIR4F2DTarget (Test-Path -LiteralPath (Join-Path $resolvedEvidence $name) -PathType Leaf) "mir4-m41-f2d-target-evidence-$name" }
  $proof = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'target-proof.json') | ConvertFrom-Json -Depth 100
  $fresh = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'fresh-load-result.json') | ConvertFrom-Json -Depth 100
  $upgrade = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'upgrade-matrix.json') | ConvertFrom-Json -Depth 100
  $verification = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'independent-verification.json') | ConvertFrom-Json -Depth 100
  $resource = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'resource-receipt.json') | ConvertFrom-Json -Depth 100
  $custody = Get-Content -Raw -LiteralPath (Join-Path $resolvedEvidence 'custody-manifest.json') | ConvertFrom-Json -Depth 100
  $expectedStatus = "M41-F2D-$code-PASSED-NO-CUTOVER"
  Require-MIR4F2DTarget ([string]$proof.target -ceq $Target -and [string]$fresh.target -ceq $Target -and [string]$verification.target -ceq $Target -and [string]$resource.target -ceq $Target -and [string]$custody.target -ceq $Target) 'mir4-m41-f2d-target-wrong-target-evidence'
  Require-MIR4F2DTarget ([string]$proof.status -ceq $expectedStatus -and [string]$fresh.status -ceq 'passed' -and [string]$upgrade.status -ceq 'passed' -and [string]$verification.status -ceq 'passed' -and [string]$resource.work_root_status -ceq 'removed' -and [string]$custody.status -ceq 'verified') 'mir4-m41-f2d-target-evidence-state'
  Require-MIR4F2DTarget (Test-MIR4FixedFactorioEngineIdentity -Target $Target -ObservedIdentity $proof.engine -RepoRoot $RepoRoot) 'mir4-m41-f2d-target-wrong-fixed-engine'
  Require-MIR4F2DTarget ([string]$proof.package.distribution_version -ceq [string]$baseline.distribution_version -and [string]$proof.package.content_sha256 -ceq [string]$baseline.archive.content_sha256 -and [int]$proof.package.entry_count -eq [int]$baseline.archive.entry_count) 'mir4-m41-f2d-target-package-identity'
  Require-MIR4F2DTarget ([string]$proof.predecessor.version -ceq [string]$baseline.predecessor -and [string]$proof.predecessor.archive_sha256 -ceq (Get-MIR4F2DTargetFileSha256 (Join-Path $RepoRoot "dist/more-infinite-research_$([string]$baseline.predecessor).zip"))) 'mir4-m41-f2d-target-predecessor-identity'
  Require-MIR4F2DTarget ([string]$fresh.factorio_version -ceq [string]$proof.engine.version -and [string]$fresh.factorio_binary_sha256 -ceq [string]$proof.engine.binary_sha256 -and [string]$fresh.validation_package_sha256 -ceq [string]$proof.package.archive_sha256 -and [string]$fresh.validation_package_content_sha256 -ceq [string]$proof.package.content_sha256 -and @($fresh.rows).Count -gt 0 -and @($fresh.rows | Where-Object status -ne 'passed').Count -eq 0) 'mir4-m41-f2d-target-fresh-load'
  Require-MIR4F2DTarget ([string]$upgrade.source_commit -ceq [string]$proof.source.commit -and [string]$upgrade.factorio.version -ceq [string]$proof.engine.file_version -and [string]$upgrade.factorio.binary_sha256 -ceq [string]$proof.engine.binary_sha256 -and [string]$upgrade.baseline.version -ceq [string]$proof.predecessor.version -and [string]$upgrade.baseline.archive_sha256 -ceq [string]$proof.predecessor.archive_sha256 -and [string]$upgrade.candidate.version -ceq [string]$proof.package.distribution_version -and [string]$upgrade.candidate.archive_sha256 -ceq [string]$proof.package.archive_sha256) 'mir4-m41-f2d-target-upgrade-binding'
  Require-MIR4F2DTarget (@($upgrade.required_archetypes).Count -eq 1 -and [string]$upgrade.required_archetypes[0] -ceq 'base-default' -and @($upgrade.rows).Count -eq 1 -and [string]$upgrade.rows[0].status -ceq 'passed') 'mir4-m41-f2d-target-upgrade-archetype'
  Require-MIR4F2DTarget ('upgraded-save-reload-passed' -in @($upgrade.rows[0].assertions) -and 'upgraded-save-second-reload-passed' -in @($upgrade.rows[0].assertions)) 'mir4-m41-f2d-target-missing-reload'
  foreach ($row in @($custody.files)) {
    $path = Join-Path $resolvedEvidence ([string]$row.path)
    Require-MIR4F2DTarget ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-MIR4F2DTargetFileSha256 $path) -ceq [string]$row.sha256 -and (Get-Item -LiteralPath $path).Length -eq [int64]$row.bytes) 'mir4-m41-f2d-target-custody'
  }
  $replayCommit = [string]$proof.source.commit
  Require-MIR4F2DTarget ($replayCommit -match '^[0-9a-f]{40}$') 'mir4-m41-f2d-target-replay-commit'
  & git -C $RepoRoot cat-file -e "$replayCommit`^{commit}"
  Require-MIR4F2DTarget ($LASTEXITCODE -eq 0) 'mir4-m41-f2d-target-stale-replay-commit'
  & git -C $RepoRoot merge-base --is-ancestor $replayCommit HEAD
  Require-MIR4F2DTarget ($LASTEXITCODE -eq 0) 'mir4-m41-f2d-target-stale-replay-commit'
  $replayTree = (& git -C $RepoRoot rev-parse "$replayCommit`^{tree}").Trim()
  Require-MIR4F2DTarget ([string]$proof.source.tree -ceq $replayTree) 'mir4-m41-f2d-target-replay-tree'
  $authorityBaseCommit = (& git -C $RepoRoot merge-base HEAD origin/dev).Trim()
  $authorityBaseTree = (& git -C $RepoRoot rev-parse "$authorityBaseCommit`^{tree}").Trim()
  $evidenceFiles = @(Get-ChildItem -LiteralPath $resolvedEvidence -File | Sort-Object Name)
  $evidenceBytes = [int64](($evidenceFiles | Measure-Object -Property Length -Sum).Sum)
  $scenarioNames = @($fresh.rows | Sort-Object name | ForEach-Object { [string]$_.name })
  $replayProof = [ordered]@{
    status=$expectedStatus;target=$Target;candidate_id=[string]$proof.candidate_id
    engine=[ordered]@{selector='exact-profile';version=[string]$proof.engine.version;file_version=[string]$proof.engine.file_version;binary_sha256=[string]$proof.engine.binary_sha256;authority_paths=@($engineLock.authority_paths)}
    package=[ordered]@{distribution_version=[string]$proof.package.distribution_version;archive_sha256=[string]$proof.package.archive_sha256;content_sha256=[string]$proof.package.content_sha256;entry_count=[int]$proof.package.entry_count}
    predecessor=[ordered]@{version=[string]$proof.predecessor.version;archive_sha256=[string]$proof.predecessor.archive_sha256}
    fresh_load=[ordered]@{status='passed';scenario_count=$scenarioNames.Count;scenarios=$scenarioNames;result_sha256=(Get-MIR4F2DTargetFileSha256 (Join-Path $resolvedEvidence 'fresh-load-result.json'))}
    upgrade=[ordered]@{status='passed';archetypes=@('base-default');first_reload=$true;second_reload=$true;result_sha256=(Get-MIR4F2DTargetFileSha256 (Join-Path $resolvedEvidence 'upgrade-matrix.json'))}
    evidence=[ordered]@{logical_root="MIR_EVIDENCE_HOME/m41-f2d/$replayCommit/$Target";target_proof_sha256=(Get-MIR4F2DTargetFileSha256 (Join-Path $resolvedEvidence 'target-proof.json'));independent_verification_sha256=(Get-MIR4F2DTargetFileSha256 (Join-Path $resolvedEvidence 'independent-verification.json'));custody_manifest_sha256=(Get-MIR4F2DTargetFileSha256 (Join-Path $resolvedEvidence 'custody-manifest.json'));custody_file_count=@($custody.files).Count;evidence_file_count=$evidenceFiles.Count;evidence_bytes=$evidenceBytes}
    resource=[ordered]@{retention=[string]$resource.retention;work_root_status=[string]$resource.work_root_status;expanded_files=[int]$resource.expanded_files;expanded_bytes=[int64]$resource.expanded_bytes;duration_seconds=[double]$resource.duration_seconds;receipt_sha256=(Get-MIR4F2DTargetFileSha256 (Join-Path $resolvedEvidence 'resource-receipt.json'))}
  }
  $attempts = @()
  if ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }
}

Require-MIR4F2DTarget ([string]$replayProof.target -ceq $Target -and [string]$replayProof.status -ceq "M41-F2D-$code-PASSED-NO-CUTOVER") 'mir4-m41-f2d-target-replay-proof'
Require-MIR4F2DTarget (Test-MIR4FixedFactorioEngineIdentity -Target $Target -ObservedIdentity $replayProof.engine -RepoRoot $RepoRoot) 'mir4-m41-f2d-target-receipt-engine'

$rolePaths = @(& git -C $RepoRoot diff --name-only $authorityBaseCommit --)
$rolePaths += @(& git -C $RepoRoot ls-files --others --exclude-standard)
$rolePaths += @($change.relative,$schemaRelative,'CHANGELOG.md','releases/governance/MIR4-Source-Changelog-PlanV1.json','todo.md','tools/lib/validation/FactorioVersionPolicy.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/mir/application/package/RuntimeReplay.ps1','tools/mir/application/package/RuntimeReplayVerifier.ps1','validation/tests/mir4/Test-MIR4RuntimeReplayF2D.ps1','validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1','tools/commands/mir4/Update-MIR4M41F2DTargetRuntimeReplayAuthority.ps1')
$rolePaths = @($rolePaths | ForEach-Object { ([string]$_).Replace('\\','/') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -cne $outputRelative } | Sort-Object -Unique -CaseSensitive)
$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($path in $rolePaths) {
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $currentSha = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previousSha = [string]$state.authority_hashes[$path]
    if ($currentSha -cne $previousSha) { $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason="Accept exact $Target runtime and transition replay with compact external custody.";scope='package-excluded-target-runtime-replay';package_visible=$false;release_authority=$false}) }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role='Current fixed-target runtime replay result, compact custody reference, schema, generator, or verification authority.'})
  }
}

$completed = @('f210') + @($orderedTargets[0..$targetIndex])
$targetResults = [ordered]@{}
foreach ($key in @('f210','f200','f110','f100')) { $targetResults[$key] = if ($key -in $completed) { 'complete' } else { 'pending' } }
$receipt = [ordered]@{
  schema=1;kind='MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1';recorded_at=$RecordedAt;programme_id="M41-F2D-F$code-RUNTIME-REPLAY";change_id=$changeId;target=$Target
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  base=[ordered]@{branch='dev';authority_base_commit=$authorityBaseCommit;authority_base_tree=$authorityBaseTree;replay_commit=[string]($replayProof.evidence.logical_root -split '/')[2];replay_tree=(& git -C $RepoRoot rev-parse "$([string]($replayProof.evidence.logical_root -split '/')[2])`^{tree}").Trim()}
  evolved_bindings=@($evolved);current_authorities=@($current);attempts=@($attempts);replay_proof=$replayProof
  player_package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme;package_visible_delta=@();target_results=$targetResults;f2d_aggregate='pending';f2e='blocked'
  invariants=[ordered]@{exact_fixed_engine_lock=$true;cross_target_evidence_substitution_forbidden=$true;f210_receipt_byte_stable=$true;expanded_work_released_after_verified_custody=$true;package_source_unchanged=$true;root_readme_byte_stable=$true;old_writer_remains_authoritative=$true}
  transition_gate=[ordered]@{merge=$false;source_move=$false;package_cutover=$false;readme_rewrite=$false;bridge_retirement=$false;old_writer_retirement=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status="M41-F2D-$code-PASSED-NO-CUTOVER"
}
$json = (($receipt | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n")
if ($Check) {
  if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-m41-f2d-target-receipt-stale]' }
} else {
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
  [IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))
}
Require-MIR4F2DTarget ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative)) 'mir4-m41-f2d-target-receipt-schema'
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;target=$Target;proof_status=[string]$replayProof.status;fresh_scenarios=[int]$replayProof.fresh_load.scenario_count;custody_manifest_sha256=[string]$replayProof.evidence.custody_manifest_sha256}
