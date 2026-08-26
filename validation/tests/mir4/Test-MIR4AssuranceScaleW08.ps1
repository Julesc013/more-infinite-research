param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/AssuranceScale.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleaseBudget.ps1')
. (Join-Path $repo 'tools/lib/mir4/OfflineDrill.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
Import-MIR4W08ControlPlane -RepoRoot $repo
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$authority=Get-MIR4W08Authority -RepoRoot $repo
if(@($authority.identity_kinds).Count-ne 4-or@($authority.observation_slices).Count-ne 11-or@($authority.deadline_classes).Count-ne 3-or@($authority.offline_drill_operations).Count-ne 8){throw '[mir4-w08-authority-counts]'}
foreach($flag in @('semantic_authority','evidence_ledger_authority','verification_plan_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','source_freeze_authorized','production_signing_or_sealing_authorized','promotion_or_tag_authorized','network_or_upload_authorized','publication_authorized')){if([bool]$authority.$flag){throw "[mir4-w08-boundary] $flag"}}

$sliceInputs=[ordered]@{}
foreach($id in @($authority.observation_slices)){$sliceInputs[$id]=[pscustomobject][ordered]@{status='available';authority_ref="fixture:$id";rows=@([pscustomobject][ordered]@{authority_ref="fixture:$id";digest=(Get-MIRCPSha256Text -Value $id)});reason='synthetic-test-authority-only'}}
$t12Receipt='sdk/preview/mir4/reference/t12/MIR4_T12_RECEIPT.json'
$sliceInputs['process-ir']=[pscustomobject][ordered]@{status='available';authority_ref=$t12Receipt;rows=@([pscustomobject][ordered]@{authority_ref=$t12Receipt;digest=(Get-MIR4W08FileSha256 (Join-Path $repo $t12Receipt))});reason='exact-target-T12-preview-observation'}
$slices=New-MIR4W08SliceSet -SliceInputs ([pscustomobject]$sliceInputs) -RepoRoot $repo
if(@($slices.slices).Count-ne 11-or$slices.available_count-ne 11-or$slices.unavailable_count-ne 0-or-not$slices.complete-or$null-eq@($slices.slices|Where-Object id -eq process-ir)[0].root_sha256){throw '[mir4-w08-slices]'}
$permuted=[ordered]@{};foreach($id in @($authority.observation_slices|Sort-Object -Descending)){$permuted[$id]=$sliceInputs[$id]}
if([string](New-MIR4W08SliceSet -SliceInputs ([pscustomobject]$permuted) -RepoRoot $repo).aggregate_root_sha256-cne[string]$slices.aggregate_root_sha256){throw '[mir4-w08-slice-order-invariance]'}

$identityInputs=[pscustomobject][ordered]@{
  capture=[pscustomobject][ordered]@{environment_signature=('A'.PadRight(64,'A'));candidate_sha256=('B'.PadRight(64,'B'));target='f210';inputs=[ordered]@{settings='s1';load_order=@('base','mir')}}
  compilation=[pscustomobject][ordered]@{abi=1;target='f210';snapshot_refs=@('snapshot:a');policy_ref='policy:a'}
  realization=[pscustomobject][ordered]@{abi=1;target='f210';accepted_plan_refs=@('plan:a');candidate_sha256=('B'.PadRight(64,'B'));executor_ref='executor:a'}
  evaluation=[pscustomobject][ordered]@{abi=1;expected_status='captured'}
}
$base=New-MIR4W08IdentitySet -Inputs $identityInputs -Slices $slices -RepoRoot $repo
foreach($name in @('CaptureKey','CompilationKey','RealizationKey','EvaluationKey')){if([string]$base.$name-notmatch'^[0-9A-F]{64}$'){throw "[mir4-w08-identity] $name"}}
$compileMutation=$identityInputs|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30;$compileMutation.compilation.policy_ref='policy:b';$compileChanged=New-MIR4W08IdentitySet -Inputs $compileMutation -Slices $slices -RepoRoot $repo
if($compileChanged.CompilationKey-ceq$base.CompilationKey-or$compileChanged.CaptureKey-cne$base.CaptureKey-or$compileChanged.RealizationKey-cne$base.RealizationKey-or$compileChanged.EvaluationKey-cne$base.EvaluationKey){throw '[mir4-w08-compilation-key-locality]'}
$realizationMutation=$identityInputs|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30;$realizationMutation.realization.executor_ref='executor:b';$realizationChanged=New-MIR4W08IdentitySet -Inputs $realizationMutation -Slices $slices -RepoRoot $repo
if($realizationChanged.RealizationKey-ceq$base.RealizationKey-or$realizationChanged.CaptureKey-cne$base.CaptureKey-or$realizationChanged.CompilationKey-cne$base.CompilationKey-or$realizationChanged.EvaluationKey-cne$base.EvaluationKey){throw '[mir4-w08-realization-key-locality]'}
$evaluationMutation=$identityInputs|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30;$evaluationMutation.evaluation.abi=2;$evaluationChanged=New-MIR4W08IdentitySet -Inputs $evaluationMutation -Slices $slices -RepoRoot $repo
if($evaluationChanged.EvaluationKey-ceq$base.EvaluationKey-or$evaluationChanged.CaptureKey-cne$base.CaptureKey-or$evaluationChanged.CompilationKey-cne$base.CompilationKey-or$evaluationChanged.RealizationKey-cne$base.RealizationKey){throw '[mir4-w08-evaluation-key-locality]'}
$captureMutation=$identityInputs|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30;$captureMutation.capture.inputs.settings='s2';$captureChanged=New-MIR4W08IdentitySet -Inputs $captureMutation -Slices $slices -RepoRoot $repo
if($captureChanged.CaptureKey-ceq$base.CaptureKey-or$captureChanged.EvaluationKey-ceq$base.EvaluationKey-or$captureChanged.CompilationKey-cne$base.CompilationKey-or$captureChanged.RealizationKey-cne$base.RealizationKey){throw '[mir4-w08-capture-downstream-locality]'}

$impact=Get-MIR4W08ImpactProjection -ChangedPaths @('settings.lua') -RepoRoot $repo
$unknown=Get-MIR4W08ImpactProjection -ChangedPaths @('unowned/w08-probe.bin') -RepoRoot $repo
if($impact.governance_failure-or-not$impact.selected_task_count-or-not$unknown.governance_failure-or$unknown.unknown_policy-cne'select-all-and-fail-governance'-or$unknown.selected_task_count-lt$impact.selected_task_count){throw '[mir4-w08-semantic-impact]'}
$calibration=Assert-MIRCPMutationCalibration -RepoRoot $repo;if($calibration.false_negative_budget-ne 0-or$calibration.cases-ne 10){throw '[mir4-w08-mutation-calibration]'}

$recoveryFixture=Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/mir4-assurance-scale-v1/recovery.json')|ConvertFrom-Json -Depth 30
$recovery=Resolve-MIR4W08PartialRecovery -Expected @($recoveryFixture.expected) -Completed @($recoveryFixture.completed)
if($recovery.status-cne'recoverable'-or@($recovery.reusable).Count-ne 1-or@($recovery.pending).Count-ne 1-or@($recovery.blocked).Count){throw '[mir4-w08-partial-recovery]'}
$revocation=[pscustomobject][ordered]@{schema=1;authority='test';default_disposition='allow';rules=@([pscustomobject][ordered]@{id='w08';type='object-digest-set';active=$true;reason='fixture';digests=@('D'.PadRight(64,'D'))})}
$evidence=[pscustomobject][ordered]@{producer=[pscustomobject]@{abi=1};payload=[pscustomobject]@{};context_digest='C'.PadRight(64,'C')}
if(-not(Test-MIRCPEvidenceRevocation -Object $evidence -Digest ('D'.PadRight(64,'D')) -Authority $revocation -RepoRoot $repo).revoked){throw '[mir4-w08-revocation]'}

$incident=New-MIR4W08NondeterminismIncident -Results @([pscustomobject]@{identity_key='K';status='passed';result_digest='1'},[pscustomobject]@{identity_key='K';status='failed';result_digest='2'})
if($incident.status-cne'blocked-nondeterministic'-or@($incident.incidents).Count-ne 1){throw '[mir4-w08-nondeterminism]'}
$minimal=Reduce-MIR4W08Counterexample -Counterexample ([pscustomobject][ordered]@{target='f210';witness='collision';evidence_refs=@('a','b');safety_constraints=@('preserve-target');elements=@([pscustomobject]@{id='optional';value=0;required_for_witness=$false},[pscustomobject]@{id='required';value=1;required_for_witness=$true})})
if(-not$minimal.proof_preserved-or$minimal.original_count-ne 2-or$minimal.minimal_count-ne 1-or[string]$minimal.elements[0].id-cne'required'){throw '[mir4-w08-counterexample]'}
$proofFixture=Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/mir4-assurance-scale-v1/proof-cover.json')|ConvertFrom-Json -Depth 30
$cover=New-MIR4W08ProofCover -Obligations @($proofFixture.obligations) -Candidates @($proofFixture.candidates)
if($cover.status-cne'complete-proposal-only'-or@($cover.uncovered).Count-or@($cover.selected).Count-ne 2-or'wrong-trust'-notin@($cover.rejected.id)-or$cover.scheduling_authority){throw '[mir4-w08-proof-cover]'}
$brokenCover=New-MIR4W08ProofCover -Obligations @($proofFixture.obligations) -Candidates @($proofFixture.candidates|Where-Object id -ne runtime-fresh)
if($brokenCover.status-cne'blocked-uncovered-obligation'-or'runtime'-notin@($brokenCover.uncovered)){throw '[mir4-w08-proof-cover-fail-closed]'}

$source=[pscustomobject][ordered]@{commit=(& git -C $repo rev-parse HEAD).Trim();tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim();programme_id='M4C02-09-24H'}
$timing=[pscustomobject][ordered]@{trusted=$true;tasks=@([pscustomobject]@{id='capture';p95_seconds=300;depends_on=@()},[pscustomobject]@{id='evaluate';p95_seconds=600;depends_on=@('capture')},[pscustomobject]@{id='manual';p95_seconds=300;depends_on=@('evaluate')})}
$capacity=[pscustomobject][ordered]@{trusted=$true;workers=4}
$budget=New-MIR4W08ReleaseBudgetPlan -RepoRoot $repo -SourceIdentity $source -AffectedTargets @('f210') -ProofCover $cover -TimingEvidence $timing -CapacityEvidence $capacity
if($budget.status-cne'passed-design-model-only'-or@($budget.deadlines).Count-ne 3-or@($budget.deadlines|Where-Object estimated_p95_seconds -ne 1200).Count){throw '[mir4-w08-release-budget]'}
$blockedBudget=New-MIR4W08ReleaseBudgetPlan -RepoRoot $repo -SourceIdentity $source -AffectedTargets @('f210') -ProofCover $cover
if($blockedBudget.status-cne'partial-with-bounded-blockers'-or@($blockedBudget.deadlines|Where-Object{'BLOCKED-MISSING-TIMING-EVIDENCE'-notin@($_.blockers)}).Count){throw '[mir4-w08-release-budget-missing-evidence]'}

$drillRoot='build/mir4/test-w08-assurance-scale/drill'
$drill=Invoke-MIR4W08OfflineDrill -RepoRoot $repo -SourceIdentity $source -OutputRoot $drillRoot
if($drill.status-cne'passed-non-production-offline-drill'-or$drill.confinement.network_calls-ne 0-or$drill.confinement.real_source_access-or$drill.confinement.real_candidate_access-or-not$drill.package_construction.deterministic_repetition-or-not$drill.publisher.verified_before_transfer-or$drill.publisher.uncertain_transfer_disposition-cne'reconciled-idempotent'-or$drill.publisher.build_authorized-or$drill.publisher.mutation_authorized){throw '[mir4-w08-offline-drill]'}
$conflictRoot=Join-Path $repo 'build/mir4/test-w08-assurance-scale/publisher-conflict';if(Test-Path -LiteralPath $conflictRoot){[IO.Directory]::Delete($conflictRoot,$true)}
$conflictInbox=Join-Path $conflictRoot 'inbox';$conflictOutbox=Join-Path $conflictRoot 'outbox';New-Item -ItemType Directory -Force -Path $conflictInbox,$conflictOutbox|Out-Null
$packagePath=Join-Path $repo "$drillRoot/constructed/dummy-mir4-package.zip";$packageCopy=Join-Path $conflictInbox 'dummy.zip';[IO.File]::Copy($packagePath,$packageCopy,$true);[IO.File]::WriteAllText((Join-Path $conflictOutbox 'conflict.bin'),'different',[Text.UTF8Encoding]::new($false))
$manifest=[pscustomobject][ordered]@{archive_sha256=(Get-MIR4W08FileSha256 $packageCopy)}
try{Invoke-MIR4W08DummyPublisher -DrillRoot $conflictRoot -PackagePath $packageCopy -Manifest $manifest -DestinationId conflict|Out-Null;throw '[mir4-w08-publisher-conflict-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-w08-publisher-conflicting-transfer]')){throw}}

foreach($file in @('tools/lib/mir4/AssuranceScale.ps1','tools/lib/mir4/ReleaseBudget.ps1','tools/lib/mir4/OfflineDrill.ps1')){$text=Get-Content -Raw -LiteralPath (Join-Path $repo $file);if($text-match'(?i)source-freeze-authorized\s*=\s*\$true|production_signing_or_sealing_authorized\s*=\s*\$true|publication_authorized\s*=\s*\$true'){throw "[mir4-w08-forbidden-authority] $file"}}
$offlineText=Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/lib/mir4/OfflineDrill.ps1');if($offlineText-match'(?i)Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|System\.Net\.Http|\bgh\b|ReleaseGovernance|OfflineCandidateCustody|Factorio|git -C'){throw '[mir4-w08-offline-capability-leak]'}

$recordsOut='build/mir4/m4c02-assurance-scale'
& (Join-Path $repo 'tools/commands/mir4/Export-MIR4AssuranceScaleRecords.ps1') -RepoRoot $repo -OutputRoot $recordsOut|Out-Null
& (Join-Path $repo 'tools/commands/mir4/Export-MIR4AssuranceScaleRecords.ps1') -RepoRoot $repo -OutputRoot $recordsOut -Check|Out-Null
foreach($pair in @(@{name='MIR4_ASSURANCE_SCALE_RESULT.json';schema='spec/schemas/mir4-assurance-scale-result-v1.schema.json'},@{name='MIR4_RELEASE_BUDGET_PLAN.json';schema='spec/schemas/mir4-release-budget-plan-v1.schema.json'},@{name='MIR4_OFFLINE_DRILL_RESULT.json';schema='spec/schemas/mir4-offline-drill-result-v1.schema.json'})){$record=Get-Content -Raw -LiteralPath (Join-Path $repo "$recordsOut/$($pair.name)")|ConvertFrom-Json -Depth 100;if(-not(($record|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $repo $pair.schema))-or[string]$record.record_sha256-cne(Get-MIR4W08RecordSha256 $record)-or$record.package_visible-or$record.public_release_proof-or$record.source_freeze_authorized-or$record.production_signing_or_sealing_authorized-or$record.publication_authorized){throw "[mir4-w08-output] $($pair.name)"}}
if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-w08-package-mutation]'}
Write-Host '[ok] MIR 4 W08 assurance identities, slice roots, exact impact/recovery, proof cover, 24/6/1 design budgets, and confined offline publisher drill passed.'
