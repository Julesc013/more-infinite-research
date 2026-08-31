param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$sourceRepo=(Resolve-Path -LiteralPath $RepoRoot).Path;$repo=$sourceRepo;$mirrorWorktree=$null
$outerEventName=$env:GITHUB_EVENT_NAME;$outerEventPath=$env:GITHUB_EVENT_PATH;$outerRef=$env:GITHUB_REF;$outerSha=$env:GITHUB_SHA
try{
  $baseBranch='main'
  if($env:GITHUB_EVENT_NAME-ceq'pull_request'-and$env:GITHUB_BASE_REF-cin@('main','dev','release/4.0')){$baseBranch=[string]$env:GITHUB_BASE_REF}
  else{
    foreach($candidate in @('main','dev','release/4.0')){
      $candidateCommit=(& git -C $sourceRepo rev-parse --verify "refs/remotes/origin/$candidate" 2>$null).Trim()
      if($candidateCommit-cmatch'^[0-9a-f]{40}$'){
        & git -C $sourceRepo merge-base --is-ancestor $candidateCommit HEAD
        if($LASTEXITCODE-eq0){$baseBranch=$candidate;break}
      }
    }
  }
  $baseRef="refs/remotes/origin/$baseBranch"
  $baseCommit=(& git -C $sourceRepo rev-parse --verify $baseRef 2>$null).Trim()
  if($baseCommit-cmatch'^[0-9a-f]{40}$'){
    & git -C $sourceRepo merge-base --is-ancestor $baseCommit HEAD
    if($LASTEXITCODE-ne0){
      $headTree=(& git -C $sourceRepo rev-parse 'HEAD^{tree}').Trim();$baseTree=(& git -C $sourceRepo rev-parse "$baseCommit^{tree}").Trim()
      if($headTree-cne$baseTree){throw '[mir4-t05-non-base-lineage-tree]'}
      $temporaryRoot=if([string]::IsNullOrWhiteSpace([string]$env:RUNNER_TEMP)){[IO.Path]::GetTempPath()}else{$env:RUNNER_TEMP}
      $mirrorWorktree=Join-Path $temporaryRoot ('mir-t05-base-'+[guid]::NewGuid().ToString('N'))
      & git -C $sourceRepo worktree add --detach $mirrorWorktree $baseCommit 2>$null|Out-Null
      if($LASTEXITCODE-ne0){throw '[mir4-t05-base-worktree]'}
      $repo=(Resolve-Path -LiteralPath $mirrorWorktree).Path
    }
  }
  . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  . (Join-Path $repo 'tools/lib/mir4/ReleasePhaseEngine.ps1')
  . (Join-Path $repo 'tools/lib/mir4/ReleaseAdapters.ps1')
  . (Join-Path $repo 'tools/lib/mir4/ReleaseLifecycleAdapters.ps1')

  # Test fixtures own their event topology. An enclosing GitHub workflow event is
  # not promotion input for the baseline, tamper, or compensation cases below.
  $env:GITHUB_EVENT_NAME=$null;$env:GITHUB_EVENT_PATH=$null;$env:GITHUB_REF=$null;$env:GITHUB_SHA=$null

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$developmentPlanPath='.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json'
$developmentPlan=Get-Content -Raw -LiteralPath (Join-Path $repo $developmentPlanPath)|ConvertFrom-Json -Depth 100
$inputs=[pscustomobject][ordered]@{
  source_release_record='.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  candidate_id='DEV-T05-UNALLOCATED';source_commit=(& git -C $repo rev-parse HEAD).Trim();source_tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  target_distribution_record_set=$developmentPlanPath;release_plan_digest=[string]$developmentPlan.verification_plan.plan_sha256
  proof_root='build/mir4/release-phase-engine/tests/t05-proof';seal_root='not-allocated'
}
$testRoot='build/mir4/release-phase-engine/tests/t05-'+[guid]::NewGuid().ToString('N')
function Invoke-T05([string]$Operation,[string]$Phase,[string]$Root,$Adapter,$UseInputs=$inputs){
  Invoke-MIR4ReleasePhaseEngine -RepoRoot $repo -Operation $Operation -Phase $Phase -Inputs $UseInputs -Adapter $Adapter -OutputRoot $Root
}
function Complete-T05([string]$Phase,[string]$Root,$Adapter,$UseInputs=$inputs){
  $plan=Invoke-T05 Plan $Phase $Root $Adapter $UseInputs
  $dry=Invoke-T05 DryRun $Phase $Root $Adapter $UseInputs
  $execute=Invoke-T05 Execute $Phase $Root $Adapter $UseInputs
  $verify=Invoke-T05 Verify $Phase $Root $Adapter $UseInputs
  $receipt=Invoke-T05 Receipt $Phase $Root $Adapter $UseInputs
  if([string]$dry.state-cne'dry-run-passed'-or[string]$execute.state-cne'executed'-or[string]$verify.state-cne'verified'-or
     [string]$receipt.final_state-cne'verified'-or[bool]$receipt.production_authorized){throw "[mir4-t05-phase-incomplete] $Phase"}
  $state=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$plan.attempt_root)
  return [pscustomobject][ordered]@{plan=$plan;state=$state;execute=@($state.events|Where-Object{[string]$_.operation-ceq'Execute'-and[string]$_.status-ceq'passed'}|Select-Object -Last 1)[0]}
}

$schemas=@(
  'spec/schemas/mir4-release-seal-result-v1.schema.json',
  'spec/schemas/mir4-release-promotion-result-v1.schema.json',
  'spec/schemas/mir4-release-target-publication-result-v1.schema.json',
  'spec/schemas/mir4-release-public-readback-result-v1.schema.json',
  'spec/schemas/mir4-release-restore-drill-result-v1.schema.json'
)
foreach($schema in $schemas){Get-Content -Raw -LiteralPath (Join-Path $repo $schema)|ConvertFrom-Json -Depth 100|Out-Null}
$contractPairs=[ordered]@{
  'spec/distribution/mir4-deployment-contract-v1.json'='spec/schemas/mir4-deployment-contract-v1.schema.json'
  'spec/releases/mir4-patch-policy-v1.json'='spec/schemas/mir4-patch-policy-v1.schema.json'
  'spec/assurance/mir4-proof-applicability-v1.json'='spec/schemas/mir4-proof-applicability-v1.schema.json'
  'spec/programmes/mir4-4x-operating-programme-v1.json'='spec/schemas/mir4-4x-operating-programme-v1.schema.json'
}
foreach($pair in $contractPairs.GetEnumerator()){
  $raw=Get-Content -Raw -LiteralPath (Join-Path $repo $pair.Key)
  if(-not($raw|Test-Json -SchemaFile (Join-Path $repo $pair.Value))){throw "[mir4-t05-post-release-contract] $($pair.Key)"}
}
$assurance=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/assurance.json')|ConvertFrom-Json -Depth 100
$postReleaseProfile=@($assurance.profiles.'mir4-post-release')
$expectedPostReleaseProfile=@('docs.check','tooling.self-test','static.package','static.branch-policy','static.mir4-release-adapters-t05')
if(($postReleaseProfile-join'|')-cne($expectedPostReleaseProfile-join'|')){throw '[mir4-t05-post-release-profile]'}
$validateWorkflow=Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/validate.yml')
if(-not$validateWorkflow.Contains("'mir4-post-release'")-or-not$validateWorkflow.Contains('spec/programmes/mir4-4x-operating-programme-v1.json')){throw '[mir4-t05-post-release-workflow]'}
$applicability=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/assurance/mir4-proof-applicability-v1.json')|ConvertFrom-Json -Depth 100
$prApplicability=@($applicability.propositions|Where-Object{[string]$_.id-ceq'promotion-plan-pr-simulation'})
if($prApplicability.Count-ne1-or[bool]$prApplicability[0].production_authority-or
   'pull_request'-notin@($prApplicability[0].valid_events)-or'untrusted-pull-request'-notin@($prApplicability[0].trust_classes)-or
   'synthetic-merge-ref'-notin@($prApplicability[0].ref_topologies)-or'simulation'-notin@($prApplicability[0].evidence_modes)){
  throw '[mir4-t05-pr-applicability-contract]'
}

$sealAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase release-seal
$seal=Complete-T05 release-seal (Join-Path $testRoot 'seal') $sealAdapter
if([bool]$seal.execute.result.detail.signing_invoked-or[bool]$seal.execute.result.detail.seal_created-or
   @($seal.execute.result.detail.identity.targets).Count-ne2){throw '[mir4-t05-seal-assembly]'}

$tamperInputs=$inputs.PSObject.Copy();$tamperInputs.candidate_id='DEV-T05-TAMPER'
$tamperRoot=Join-Path $testRoot 'seal-tamper';$tamperPlan=Invoke-T05 Plan release-seal $tamperRoot $sealAdapter $tamperInputs
$null=Invoke-T05 DryRun release-seal $tamperRoot $sealAdapter $tamperInputs;$null=Invoke-T05 Execute release-seal $tamperRoot $sealAdapter $tamperInputs
$tamperPath=Join-Path ([string]$tamperPlan.attempt_root) 'artifacts/execute/unsigned-seal-assembly.json'
$tampered=Get-Content -Raw -LiteralPath $tamperPath|ConvertFrom-Json -Depth 100;$tampered.identity.targets[0].package_sha256='F'*64
$tampered.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $tampered -HashProperty record_sha256
[IO.File]::WriteAllText($tamperPath,(ConvertTo-MIR4ReleasePhaseCanonicalJson $tampered)+"`n",[Text.UTF8Encoding]::new($false))
$tamperRejected=$false
try{$null=Invoke-T05 Verify release-seal $tamperRoot $sealAdapter $tamperInputs}catch{if($_.Exception.Message.StartsWith('[mir4-release-lifecycle-record]')-or$_.Exception.Message.StartsWith('[mir4-release-seal-post-assembly-mutation]')){$tamperRejected=$true}else{throw}}
if(-not$tamperRejected){throw '[mir4-t05-post-seal-mutation-accepted]'}

$promotionAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase promotion
$promotion=Complete-T05 promotion (Join-Path $testRoot 'promotion') $promotionAdapter
if(-not[bool]$promotion.execute.result.detail.fast_forward_proven-or[bool]$promotion.execute.result.detail.ref_update_performed-or
   [bool]$promotion.execute.result.detail.tag_created){throw '[mir4-t05-promotion-plan]'}

$savedEventName=$env:GITHUB_EVENT_NAME;$savedEventPath=$env:GITHUB_EVENT_PATH;$savedRef=$env:GITHUB_REF;$savedSha=$env:GITHUB_SHA
$prInputs=$inputs.PSObject.Copy();$prInputs.candidate_id='DEV-T05-PR-CONTEXT'
$prEventPath=Join-Path $testRoot 'pull-request-event.json';New-Item -ItemType Directory -Force -Path (Split-Path $prEventPath -Parent)|Out-Null
$prEvent=[ordered]@{pull_request=[ordered]@{base=[ordered]@{ref='main';sha=[string]$inputs.source_commit};head=[ordered]@{ref='work/t05-event-proof';sha=[string]$inputs.source_commit};merge_commit_sha=[string]$inputs.source_commit}}
[IO.File]::WriteAllText($prEventPath,($prEvent|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
try{
  $env:GITHUB_EVENT_NAME='pull_request';$env:GITHUB_EVENT_PATH=$prEventPath;$env:GITHUB_REF='refs/pull/999/merge';$env:GITHUB_SHA=[string]$inputs.source_commit
  $prPromotion=Complete-T05 promotion (Join-Path $testRoot 'promotion-pr-context') $promotionAdapter $prInputs
  if([string]$prPromotion.execute.result.detail.observed_ref-cne'event.pull_request.base.sha'-or
     [string]$prPromotion.execute.result.detail.proof_context.trust_class-cne'untrusted-pull-request'-or
     [string]$prPromotion.execute.result.detail.proof_context.ref_topology-cne'synthetic-merge-ref'-or
     [string]$prPromotion.execute.result.detail.proof_context.evidence_mode-cne'simulation'){
    throw '[mir4-t05-pr-proof-context]'
  }
}finally{
  $env:GITHUB_EVENT_NAME=$savedEventName;$env:GITHUB_EVENT_PATH=$savedEventPath;$env:GITHUB_REF=$savedRef;$env:GITHUB_SHA=$savedSha
}

$promotionTamperInputs=$inputs.PSObject.Copy();$promotionTamperInputs.candidate_id='DEV-T05-PROMOTION-TAMPER'
$promotionTamperRoot=Join-Path $testRoot 'promotion-tamper';$promotionTamperPlan=Invoke-T05 Plan promotion $promotionTamperRoot $promotionAdapter $promotionTamperInputs
$null=Invoke-T05 DryRun promotion $promotionTamperRoot $promotionAdapter $promotionTamperInputs;$null=Invoke-T05 Execute promotion $promotionTamperRoot $promotionAdapter $promotionTamperInputs
$promotionTamperPath=Join-Path ([string]$promotionTamperPlan.attempt_root) 'artifacts/execute/fast-forward-promotion-plan.json'
$promotionTampered=Get-Content -Raw -LiteralPath $promotionTamperPath|ConvertFrom-Json -Depth 100;$promotionTampered.from_commit='0'*40
$promotionTampered.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $promotionTampered -HashProperty record_sha256
[IO.File]::WriteAllText($promotionTamperPath,(ConvertTo-MIR4ReleasePhaseCanonicalJson $promotionTampered)+"`n",[Text.UTF8Encoding]::new($false))
$promotionTamperRejected=$false
try{$null=Invoke-T05 Verify promotion $promotionTamperRoot $promotionAdapter $promotionTamperInputs}catch{if($_.Exception.Message-ceq'[mir4-promotion-plan-stale]'){$promotionTamperRejected=$true}else{throw}}
if(-not$promotionTamperRejected){throw '[mir4-t05-promotion-tamper-accepted]'}

$transferCalls=[Collections.Generic.List[object]]::new()
$transferProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  $transferCalls.Add([pscustomobject][ordered]@{transfer_id=[string]$Request.transfer_id;mode=$Mode})|Out-Null
  if($Mode-ceq'Transfer'){return [pscustomobject][ordered]@{state='uncertain';transfer_id=[string]$Request.transfer_id;observed_sha256=$null;network_calls=0;production_mutation_performed=$false}}
  return [pscustomobject][ordered]@{state='already-present-exact';transfer_id=[string]$Request.transfer_id;observed_sha256=[string]$Request.package_sha256;network_calls=0;production_mutation_performed=$false}
}.GetNewClosure()
$publicationAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase target-publication -PublicationTransferProvider $transferProvider -PublicationTransferProviderIdentity ('A'*64)
$publication=Complete-T05 target-publication (Join-Path $testRoot 'publication') $publicationAdapter
$transferGroups=@($transferCalls|Group-Object transfer_id)
if($transferGroups.Count-ne4-or@($transferGroups|Where-Object{$_.Count-ne2-or(@($_.Group.mode)-join'|')-cne'Transfer|Reconcile'}).Count-ne0-or
   [int]$publication.execute.result.detail.reconciled_count-ne4-or[bool]$publication.execute.result.detail.builder_available-or
   [bool]$publication.execute.result.detail.source_checkout_required){throw '[mir4-t05-publication-reconciliation]'}

$wrongTransferProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  [pscustomobject][ordered]@{state='transferred-exact';transfer_id=[string]$Request.transfer_id;observed_sha256=('D'*64);network_calls=0;production_mutation_performed=$false}
}
$wrongPublicationAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase target-publication -PublicationTransferProvider $wrongTransferProvider -PublicationTransferProviderIdentity ('C'*64)
$wrongPublicationInputs=$inputs.PSObject.Copy();$wrongPublicationInputs.candidate_id='DEV-T05-WRONG-PUBLICATION';$wrongPublicationRoot=Join-Path $testRoot 'publication-wrong'
$null=Invoke-T05 Plan target-publication $wrongPublicationRoot $wrongPublicationAdapter $wrongPublicationInputs;$null=Invoke-T05 DryRun target-publication $wrongPublicationRoot $wrongPublicationAdapter $wrongPublicationInputs
$wrongPublicationRejected=$false
try{$null=Invoke-T05 Execute target-publication $wrongPublicationRoot $wrongPublicationAdapter $wrongPublicationInputs}catch{if($_.Exception.Message.StartsWith('[mir4-publication-transfer-hash]')){$wrongPublicationRejected=$true}else{throw}}
if(-not$wrongPublicationRejected){throw '[mir4-t05-publication-mismatch-accepted]'}

$readbackAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase public-readback
$readback=Complete-T05 public-readback (Join-Path $testRoot 'readback') $readbackAdapter
if(-not[bool]$readback.execute.result.detail.all_bytes_equal-or[bool]$readback.execute.result.detail.public_observation-or
   @($readback.execute.result.detail.observations).Count-ne4){throw '[mir4-t05-readback]'}
$wrongReadback={
  param([string]$FixtureRepo,$Request,$Context)
  [pscustomobject][ordered]@{target=[string]$Request.target;channel=[string]$Request.channel;observed_sha256=('E'*64);observed_bytes=[long]$Request.bytes;network_calls=0;public_observation=$false}
}
$wrongAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase public-readback -PublicReadbackProvider $wrongReadback -PublicReadbackProviderIdentity ('B'*64)
$wrongInputs=$inputs.PSObject.Copy();$wrongInputs.candidate_id='DEV-T05-WRONG-READBACK';$wrongRoot=Join-Path $testRoot 'readback-wrong'
$null=Invoke-T05 Plan public-readback $wrongRoot $wrongAdapter $wrongInputs;$null=Invoke-T05 DryRun public-readback $wrongRoot $wrongAdapter $wrongInputs
$wrongRejected=$false
try{$null=Invoke-T05 Execute public-readback $wrongRoot $wrongAdapter $wrongInputs}catch{if($_.Exception.Message.StartsWith('[mir4-public-readback-mismatch]')){$wrongRejected=$true}else{throw}}
if(-not$wrongRejected){throw '[mir4-t05-readback-mismatch-accepted]'}

$restoreAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase restore-drill
$restore=Complete-T05 restore-drill (Join-Path $testRoot 'restore') $restoreAdapter
if(-not[bool]$restore.execute.result.detail.clean_destination-or-not[bool]$restore.execute.result.detail.all_bytes_equal-or
   @($restore.execute.result.detail.files).Count-ne2-or[bool]$restore.execute.result.detail.source_repository_access-or
   [bool]$restore.execute.result.detail.credential_access){throw '[mir4-t05-clean-restore]'}

$restoreExtraInputs=$inputs.PSObject.Copy();$restoreExtraInputs.candidate_id='DEV-T05-RESTORE-EXTRA';$restoreExtraRoot=Join-Path $testRoot 'restore-extra'
$restoreExtraPlan=Invoke-T05 Plan restore-drill $restoreExtraRoot $restoreAdapter $restoreExtraInputs
$null=Invoke-T05 DryRun restore-drill $restoreExtraRoot $restoreAdapter $restoreExtraInputs;$null=Invoke-T05 Execute restore-drill $restoreExtraRoot $restoreAdapter $restoreExtraInputs
[IO.File]::WriteAllText((Join-Path ([string]$restoreExtraPlan.attempt_root) 'artifacts/execute/restored/extra.json'),'{}',[Text.UTF8Encoding]::new($false))
$restoreExtraRejected=$false
try{$null=Invoke-T05 Verify restore-drill $restoreExtraRoot $restoreAdapter $restoreExtraInputs}catch{if($_.Exception.Message-ceq'[mir4-restore-drill-verification]'){$restoreExtraRejected=$true}else{throw}}
if(-not$restoreExtraRejected){throw '[mir4-t05-restore-extra-accepted]'}

$compensateInputs=$inputs.PSObject.Copy();$compensateInputs.candidate_id='DEV-T05-COMPENSATE';$compensateRoot=Join-Path $testRoot 'promotion-compensate'
$compensatePlan=Invoke-T05 Plan promotion $compensateRoot $promotionAdapter $compensateInputs;$null=Invoke-T05 DryRun promotion $compensateRoot $promotionAdapter $compensateInputs;$null=Invoke-T05 Execute promotion $compensateRoot $promotionAdapter $compensateInputs
$compensated=Invoke-T05 Compensate promotion $compensateRoot $promotionAdapter $compensateInputs;$receipt=Invoke-T05 Receipt promotion $compensateRoot $promotionAdapter $compensateInputs
if([string]$compensated.state-cne'compensated'-or[string]$receipt.final_state-cne'compensated'-or
   (Test-Path -LiteralPath (Join-Path ([string]$compensatePlan.attempt_root) 'artifacts/execute/fast-forward-promotion-plan.json'))){throw '[mir4-t05-compensation]'}

$publisherWorkflow=Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/mir4-target-publication.yml')
if($publisherWorkflow-match'actions/checkout|Build-MIRPackage|New-MIR4BootstrapLocalCandidate|mir4\s+platform\s+package'-or
   $publisherWorkflow-notmatch'publisher-forbidden-capability'){throw '[mir4-t05-publisher-has-builder]'}
if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-t05-package-mutation]'}
  Write-Host '[ok] MIR 4 T05 unsigned seal assembly, fast-forward promotion plan, builder-free publication reconciliation, exact readback, clean restore, tamper rejection, and compensation passed.'
}finally{
  $env:GITHUB_EVENT_NAME=$outerEventName;$env:GITHUB_EVENT_PATH=$outerEventPath;$env:GITHUB_REF=$outerRef;$env:GITHUB_SHA=$outerSha
  if(-not[string]::IsNullOrWhiteSpace([string]$mirrorWorktree)-and(Test-Path -LiteralPath $mirrorWorktree -PathType Container)){
    & git -C $sourceRepo worktree remove --force $mirrorWorktree 2>$null|Out-Null
  }
}
