# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/ReleasePhaseEngine.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/ReleaseAdapters.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/ReleaseLifecycleAdapters.ps1')

function Expect-A07Failure {
  param([scriptblock]$Action,[string]$Prefix)
  try { & $Action | Out-Null } catch {
    if($_.Exception.Message.StartsWith($Prefix,[StringComparison]::Ordinal)){return}
    throw
  }
  throw "Expected A07 failure: $Prefix"
}

function New-A07PublicationResponse {
  param($Request,[ValidateSet('absent','already-present-exact','transferred-exact')][string]$State)
  $bound=[ordered]@{}
  foreach($name in @('transfer_id','candidate_id','source_commit','source_tree','release_plan_digest','draft_identity','tag_identity','seal_identity','target','channel','asset_id','package_sha256','content_sha256','bytes','entry_count')){$bound[$name]=$Request.$name}
  $match=[ordered]@{}
  foreach($pair in $bound.GetEnumerator()){$match[$pair.Key]=$pair.Value}
  $match.observed_sha256=[string]$Request.package_sha256;$match.observed_bytes=[long]$Request.bytes
  $response=[ordered]@{}
  foreach($pair in $bound.GetEnumerator()){$response[$pair.Key]=$pair.Value}
  $present=$State-cne'absent'
  $response.state=$State;$response.observed_sha256=$(if($present){[string]$Request.package_sha256}else{$null})
  $response.observed_bytes=$(if($present){[long]$Request.bytes}else{0});$response.match_count=$(if($present){1}else{0})
  $response.matches=if($present){[object[]]@([pscustomobject]$match)}else{[object[]]@()}
  $response.network_calls=0;$response.production_mutation_performed=$false
  return [pscustomobject]$response
}
$fixtureResponseFunction=(Get-Item -Path Function:New-A07PublicationResponse).ScriptBlock
Set-Item -Path Function:\global:New-A07PublicationResponse -Value $fixtureResponseFunction

$beforePackage=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$developmentPlanPath='.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json'
$developmentPlan=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $developmentPlanPath)|ConvertFrom-Json -Depth 100
$inputs=[pscustomobject][ordered]@{
  source_release_record='.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  candidate_id='DEV-A07-UNALLOCATED';source_commit=(& git -C $RepoRoot rev-parse HEAD).Trim();source_tree=(& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  target_distribution_record_set=$developmentPlanPath;release_plan_digest=[string]$developmentPlan.verification_plan.plan_sha256
  proof_root='build/mir4/release-phase-engine/tests/a07-proof';seal_root='not-allocated'
}
$testRoot=Join-Path $RepoRoot ('build/mir4/release-phase-engine/tests/a07-'+[guid]::NewGuid().ToString('N'))

function New-A07Attempt {
  param([string]$Name,[scriptblock]$Provider,[string]$Candidate='DEV-A07-UNALLOCATED')
  $attemptInputs=$inputs.PSObject.Copy();$attemptInputs.candidate_id=$Candidate
  $adapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $RepoRoot -Phase target-publication -PublicationTransferProvider $Provider -PublicationTransferProviderIdentity ('A'*64)
  $root=Join-Path $testRoot $Name
  $plan=Invoke-MIR4ReleasePhaseEngine -RepoRoot $RepoRoot -Operation Plan -Phase target-publication -Inputs $attemptInputs -Adapter $adapter -OutputRoot $root
  $dry=Invoke-MIR4ReleasePhaseEngine -RepoRoot $RepoRoot -Operation DryRun -Phase target-publication -Inputs $attemptInputs -Adapter $adapter -OutputRoot $root
  if([string]$dry.state-cne'dry-run-passed'){throw '[mir4-a07-dry-run]'}
  return [pscustomobject][ordered]@{adapter=$adapter;inputs=$attemptInputs;root=$root;plan=$plan}
}

function Invoke-A07Attempt {
  param($Attempt,[ValidateSet('Execute','Resume','Verify')][string]$Operation)
  return Invoke-MIR4ReleasePhaseEngine -RepoRoot $RepoRoot -Operation $Operation -Phase target-publication -Inputs $Attempt.inputs -Adapter $Attempt.adapter -OutputRoot $Attempt.root
}

function New-A07DirectContext {
  param($Attempt)
  $attemptRoot=[string]$Attempt.plan.attempt_root
  return [pscustomobject][ordered]@{
    schema=1;kind='MIR4ReleasePhaseAdapterContextV1';operation='Execute'
    idempotency_key=(Get-MIR4ReleasePhaseSha256 ([ordered]@{attempt_id=[string]$Attempt.plan.plan.attempt_id;operation='Execute'}))
    attempt_root=$attemptRoot;artifact_root=(Join-Path $attemptRoot 'artifacts/execute');plan=$Attempt.plan.plan
    ports=@($Attempt.plan.plan.ports);non_production=$true;production_authorized=$false
  }
}

function Assert-A07CanonicalPublicationRecord {
  param([string]$Path)
  $raw=[IO.File]::ReadAllText($Path)
  $record=$raw|ConvertFrom-Json -Depth 100
  if($raw-cne((ConvertTo-MIR4ReleasePhaseCanonicalJson $record)+"`n")){throw "[mir4-a07-publication-record-not-canonical] $Path"}
  return $raw
}

# Zero exact matches performs one transfer only after an intent has been persisted.
$zeroCalls=[Collections.Generic.List[object]]::new();$zeroRemote=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$zeroProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  $intentPath=Join-Path ([string]$Context.attempt_root) 'artifacts/execute/publication-intent.json'
  if(-not(Test-Path -LiteralPath $intentPath -PathType Leaf)){throw '[mir4-a07-intent-not-before-provider]'}
  $intent=Get-Content -Raw -LiteralPath $intentPath|ConvertFrom-Json -Depth 100
  if([string]$intent.draft.draft_identity-cne'unallocated'-or[string]$intent.draft.tag_identity-cne'unallocated'-or
     [string]$intent.draft.seal_identity-cne[string]$Context.plan.identity.seal_root-or[bool]$intent.publication_authorized-or[bool]$intent.production_authorized){
    throw '[mir4-a07-intent-binding]'
  }
  $zeroCalls.Add([pscustomobject]@{transfer_id=[string]$Request.transfer_id;mode=$Mode})|Out-Null
  if($Mode-ceq'Reconcile'){
    if($zeroRemote.Contains([string]$Request.transfer_id)){return New-A07PublicationResponse -Request $Request -State 'already-present-exact'}
    return New-A07PublicationResponse -Request $Request -State absent
  }
  [void]$zeroRemote.Add([string]$Request.transfer_id)
  return New-A07PublicationResponse -Request $Request -State 'transferred-exact'
}.GetNewClosure()
$zero=New-A07Attempt zero $zeroProvider
$zeroExecute=Invoke-A07Attempt $zero Execute
$zeroVerify=Invoke-A07Attempt $zero Verify
$zeroGroups=@($zeroCalls|Group-Object transfer_id)
if([string]$zeroExecute.state-cne'executed'-or[string]$zeroVerify.state-cne'verified'-or$zeroGroups.Count-ne4-or
   @($zeroGroups|Where-Object{$_.Count-ne2-or(@($_.Group.mode)-join'|')-cne'Reconcile|Transfer'}).Count-ne0){throw '[mir4-a07-zero-reconcile-before-transfer]'}
$zeroExecuteRoot=Join-Path ([string]$zero.plan.attempt_root) 'artifacts/execute'
$zeroIntent=Get-Content -Raw -LiteralPath (Join-Path $zeroExecuteRoot 'publication-intent.json')|ConvertFrom-Json -Depth 100
$zeroCheckpoints=@(Get-ChildItem -LiteralPath (Join-Path $zeroExecuteRoot 'publication-transfer-checkpoints') -Filter '*.json' -File)
if(@($zeroIntent.transfers).Count-ne4-or$zeroCheckpoints.Count-ne4-or[bool]$zeroIntent.release_transition_performed-or
   [bool]$zeroExecute.plan.production_authorized-or-not[bool]$zeroExecute.plan.non_production){throw '[mir4-a07-zero-journal]'}
$zeroContext=New-A07DirectContext $zero
$zeroTargets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $RepoRoot -Context $zeroContext)
$zeroIdentity=Get-MIR4ReleaseLifecycleIdentity $zeroContext $zeroTargets;$zeroDraft=Get-MIR4PublicationDraftBinding $zeroIdentity $zeroTargets
$deterministic=New-A07Attempt deterministic $zeroProvider
$deterministicContext=New-A07DirectContext $deterministic
$deterministicTargets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $RepoRoot -Context $deterministicContext)
$deterministicIdentity=Get-MIR4ReleaseLifecycleIdentity $deterministicContext $deterministicTargets
$deterministicDraft=Get-MIR4PublicationDraftBinding $deterministicIdentity $deterministicTargets
$zeroRequests=@(Get-MIR4PublicationRequests $zeroIdentity $zeroDraft $zeroTargets)
$recomputedRequests=@(Get-MIR4PublicationRequests $deterministicIdentity $deterministicDraft $deterministicTargets)
$expectedOrder='F200/github|F200/mod-portal|F210/github|F210/mod-portal'
if(($zeroRequests.transfer_id-join'|')-cne($recomputedRequests.transfer_id-join'|')-or
   @($zeroRequests.transfer_id|Sort-Object -Unique).Count-ne4-or
   @($zeroRequests|Where-Object{[string]$_.transfer_id-cnotmatch'^[A-F0-9]{64}$'}).Count-ne0-or
   (($zeroRequests|ForEach-Object{"$($_.target)/$($_.channel)"})-join'|')-cne$expectedOrder){throw '[mir4-a07-transfer-id-nondeterministic]'}

# Readback reuses the exact draft-bound request surface and remains read-only.
$readbackCalls=[Collections.Generic.List[object]]::new()
$readbackProvider={
  param([string]$FixtureRepo,$Request,$Context)
  $readbackCalls.Add($Request)|Out-Null
  if([string]$Request.draft_identity-cne'unallocated'-or[string]$Request.tag_identity-cne'unallocated'-or
     [string]$Request.seal_identity-cne[string]$Context.plan.identity.seal_root-or
     [string]$Request.asset_id-cne('target-package/'+([string]$Request.target).ToLowerInvariant())){throw '[mir4-a07-readback-request-binding]'}
  return [pscustomobject][ordered]@{
    target=[string]$Request.target;channel=[string]$Request.channel;observed_sha256=[string]$Request.package_sha256
    observed_bytes=[long]$Request.bytes;network_calls=0;public_observation=$false
  }
}.GetNewClosure()
$readbackInputs=$inputs.PSObject.Copy();$readbackInputs.candidate_id='DEV-A07-READBACK'
$readbackAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $RepoRoot -Phase public-readback -PublicReadbackProvider $readbackProvider -PublicReadbackProviderIdentity ('B'*64)
$readbackRoot=Join-Path $testRoot 'readback'
$readbackPlan=Invoke-MIR4ReleasePhaseEngine -RepoRoot $RepoRoot -Operation Plan -Phase public-readback -Inputs $readbackInputs -Adapter $readbackAdapter -OutputRoot $readbackRoot
$readbackDry=Invoke-MIR4ReleasePhaseEngine -RepoRoot $RepoRoot -Operation DryRun -Phase public-readback -Inputs $readbackInputs -Adapter $readbackAdapter -OutputRoot $readbackRoot
$readbackExecute=Invoke-MIR4ReleasePhaseEngine -RepoRoot $RepoRoot -Operation Execute -Phase public-readback -Inputs $readbackInputs -Adapter $readbackAdapter -OutputRoot $readbackRoot
$readbackVerify=Invoke-MIR4ReleasePhaseEngine -RepoRoot $RepoRoot -Operation Verify -Phase public-readback -Inputs $readbackInputs -Adapter $readbackAdapter -OutputRoot $readbackRoot
if([string]$readbackDry.state-cne'dry-run-passed'-or[string]$readbackExecute.state-cne'executed'-or[string]$readbackVerify.state-cne'verified'-or
   $readbackCalls.Count-ne4-or-not[bool]$readbackExecute.events[-1].result.detail.all_bytes_equal){throw '[mir4-a07-readback-contract]'}

# One exact match is adopted without invoking a transfer.
$oneCalls=[Collections.Generic.List[object]]::new()
$oneProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  $oneCalls.Add([string]$Mode)|Out-Null
  if($Mode-cne'Reconcile'){throw '[mir4-a07-one-transferred]'}
  return New-A07PublicationResponse -Request $Request -State 'already-present-exact'
}.GetNewClosure()
$one=New-A07Attempt one $oneProvider 'DEV-A07-ONE'
$oneExecute=Invoke-A07Attempt $one Execute
if(@($oneCalls|Where-Object{$_-cne'Reconcile'}).Count-ne0-or[int]$oneExecute.events[-1].result.detail.adopted_count-ne4-or
   [int]$oneExecute.events[-1].result.detail.transferred_count-ne0){throw '[mir4-a07-one-adoption]'}

# Many exact matches fail closed rather than selecting an arbitrary provider result.
$manyProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  $response=New-A07PublicationResponse -Request $Request -State 'already-present-exact'
  $response.matches=@($response.matches[0],$response.matches[0]);$response.match_count=2
  return $response
}
$many=New-A07Attempt many $manyProvider 'DEV-A07-MANY'
Expect-A07Failure { Invoke-A07Attempt $many Execute } '[mir4-publication-transfer-match-count]'

# A malformed response and a drifted durable intent are rejected before a provider effect.
$malformedProvider={param([string]$FixtureRepo,$Request,[string]$Mode,$Context)[pscustomobject]@{state='absent'}}
$malformed=New-A07Attempt malformed $malformedProvider 'DEV-A07-MALFORMED'
Expect-A07Failure { Invoke-A07Attempt $malformed Execute } '[mir4-publication-transfer-response]'
$boundDriftProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  $response=New-A07PublicationResponse -Request $Request -State 'already-present-exact'
  $response.tag_identity='drifted-tag'
  return $response
}
$boundDrift=New-A07Attempt bound-drift $boundDriftProvider 'DEV-A07-BOUND-DRIFT'
Expect-A07Failure { Invoke-A07Attempt $boundDrift Execute } '[mir4-publication-transfer-binding]'
$hashDriftProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  $response=New-A07PublicationResponse -Request $Request -State 'already-present-exact'
  $response.observed_sha256=('D'*64);$response.matches[0].observed_sha256=('D'*64)
  return $response
}
$hashDrift=New-A07Attempt hash-drift $hashDriftProvider 'DEV-A07-HASH-DRIFT'
Expect-A07Failure { Invoke-A07Attempt $hashDrift Execute } '[mir4-publication-transfer-hash]'
$driftProvider={param([string]$FixtureRepo,$Request,[string]$Mode,$Context)throw '[mir4-a07-drift-provider-called]'}
$drift=New-A07Attempt drift $driftProvider 'DEV-A07-DRIFT'
$driftContext=New-A07DirectContext $drift;$driftTargets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $RepoRoot -Context $driftContext)
$driftIdentity=Get-MIR4ReleaseLifecycleIdentity $driftContext $driftTargets;$driftDraft=Get-MIR4PublicationDraftBinding $driftIdentity $driftTargets
$driftRecord=New-MIR4PublicationIntentRecord $driftIdentity $driftDraft (Get-MIR4PublicationRequests $driftIdentity $driftDraft $driftTargets)
$driftRecord.identity.candidate_id='DRIFTED';$driftRecord.identity_sha256=Get-MIR4ReleasePhaseSha256 $driftRecord.identity
$driftRecord.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $driftRecord -HashProperty record_sha256
$driftPath=Join-Path ([string]$drift.plan.attempt_root) 'artifacts/execute/publication-intent.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $driftPath)|Out-Null
Write-MIR4ReleasePhaseJsonCreateNew -Value $driftRecord -Path $driftPath
Expect-A07Failure { Invoke-A07Attempt $drift Execute } '[mir4-publication-intent-drift]'
$missingIntent=New-A07Attempt missing-intent $driftProvider 'DEV-A07-MISSING-INTENT'
$missingIntentContext=New-A07DirectContext $missingIntent;$missingIntentContext.operation='Verify'
$missingIntentPath=Join-Path ([string]$missingIntent.plan.attempt_root) 'artifacts/execute/publication-intent.json'
Expect-A07Failure { & $missingIntent.adapter.invoke $missingIntentContext } '[mir4-publication-intent-drift]'
if(Test-Path -LiteralPath $missingIntentPath -PathType Leaf){throw '[mir4-a07-verify-materialized-intent]'}

# A timeout after a provider-side effect leaves no terminal local receipt. Resume
# reconciles that exact remote outcome and does not repeat Transfer.
$timeoutCalls=[Collections.Generic.List[object]]::new();$timeoutRemote=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$timeoutState=[pscustomobject]@{thrown=$false}
$timeoutProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  $timeoutCalls.Add([pscustomobject]@{transfer_id=[string]$Request.transfer_id;mode=$Mode})|Out-Null
  if($Mode-ceq'Reconcile'){
    if($timeoutRemote.Contains([string]$Request.transfer_id)){return New-A07PublicationResponse -Request $Request -State 'already-present-exact'}
    return New-A07PublicationResponse -Request $Request -State absent
  }
  [void]$timeoutRemote.Add([string]$Request.transfer_id)
  if(-not[bool]$timeoutState.thrown){$timeoutState.thrown=$true;throw '[mir4-a07-timeout-lost-response]'}
  return New-A07PublicationResponse -Request $Request -State 'transferred-exact'
}.GetNewClosure()
$timeout=New-A07Attempt timeout $timeoutProvider 'DEV-A07-TIMEOUT'
Expect-A07Failure { Invoke-A07Attempt $timeout Execute } '[mir4-a07-timeout-lost-response]'
$timeoutIntentPath=Join-Path ([string]$timeout.plan.attempt_root) 'artifacts/execute/publication-intent.json'
if(-not(Test-Path -LiteralPath $timeoutIntentPath -PathType Leaf)){throw '[mir4-a07-timeout-no-intent]'}
$timeoutResume=Invoke-A07Attempt $timeout Resume
if([string]$timeoutResume.state-cne'executed'-or@($timeoutCalls|Where-Object{[string]$_.mode-ceq'Transfer'}).Count-ne4){throw '[mir4-a07-timeout-transfer-repeated]'}

# A process killed after the provider effect but before local receipt persistence
# leaves pre-existing exact remote state and no checkpoint. Execute adopts it.
$killCalls=[Collections.Generic.List[object]]::new();$killRemote=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$killProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  $killCalls.Add([pscustomobject]@{transfer_id=[string]$Request.transfer_id;mode=$Mode})|Out-Null
  if($Mode-ceq'Reconcile'){
    if($killRemote.Contains([string]$Request.transfer_id)){return New-A07PublicationResponse -Request $Request -State 'already-present-exact'}
    return New-A07PublicationResponse -Request $Request -State absent
  }
  [void]$killRemote.Add([string]$Request.transfer_id)
  return New-A07PublicationResponse -Request $Request -State 'transferred-exact'
}.GetNewClosure()
$kill=New-A07Attempt kill $killProvider 'DEV-A07-KILL'
$killContext=New-A07DirectContext $kill
$killTargets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $RepoRoot -Context $killContext)
$killIdentity=Get-MIR4ReleaseLifecycleIdentity $killContext $killTargets;$killDraft=Get-MIR4PublicationDraftBinding $killIdentity $killTargets
foreach($request in @(Get-MIR4PublicationRequests $killIdentity $killDraft $killTargets)){[void]$killRemote.Add([string]$request.transfer_id)}
$killCheckpointRoot=Join-Path ([string]$kill.plan.attempt_root) 'artifacts/execute/publication-transfer-checkpoints'
if(Test-Path -LiteralPath $killCheckpointRoot){throw '[mir4-a07-kill-precreated-checkpoint]'}
$killExecute=Invoke-A07Attempt $kill Execute
if([string]$killExecute.state-cne'executed'-or@($killCalls|Where-Object{[string]$_.mode-ceq'Transfer'}).Count-ne0){throw '[mir4-a07-kill-remote-adoption]'}

# A stale owned sibling temp is ignored, while a canonical aggregate written
# before its phase event is atomically adopted by Resume without provider calls.
$aggregate=New-A07Attempt aggregate $killProvider 'DEV-A07-AGGREGATE'
$aggregateContext=New-A07DirectContext $aggregate
$aggregateTargets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $RepoRoot -Context $aggregateContext)
$aggregateIdentity=Get-MIR4ReleaseLifecycleIdentity $aggregateContext $aggregateTargets
$aggregateDraft=Get-MIR4PublicationDraftBinding $aggregateIdentity $aggregateTargets
$aggregateRequests=@(Get-MIR4PublicationRequests $aggregateIdentity $aggregateDraft $aggregateTargets)
$aggregateExecuteRoot=Join-Path ([string]$aggregate.plan.attempt_root) 'artifacts/execute'
$aggregateCheckpointRoot=Join-Path $aggregateExecuteRoot 'publication-transfer-checkpoints'
New-Item -ItemType Directory -Force -Path $aggregateExecuteRoot,$aggregateCheckpointRoot|Out-Null
$ownedIntentTemp=Join-Path $aggregateExecuteRoot ('.publication-intent.json.'+[guid]::NewGuid().ToString('N')+'.tmp')
$ownedCheckpointTemp=Join-Path $aggregateCheckpointRoot ('.'+[string]$aggregateRequests[0].transfer_id+'.json.'+[guid]::NewGuid().ToString('N')+'.tmp')
[IO.File]::WriteAllText($ownedIntentTemp,'stale-owned-intent-temp',[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($ownedCheckpointTemp,'stale-owned-checkpoint-temp',[Text.UTF8Encoding]::new($false))
$null=& $aggregate.adapter.invoke $aggregateContext
$aggregatePath=Join-Path $aggregateExecuteRoot 'publication-reconciliation.json'
$aggregateCanonicalBefore=Assert-A07CanonicalPublicationRecord $aggregatePath
$aggregateCanonicalPaths=@((Join-Path $aggregateExecuteRoot 'publication-intent.json'),$aggregatePath)+@(Get-ChildItem -LiteralPath $aggregateCheckpointRoot -Filter '*.json' -File|ForEach-Object{$_.FullName})
if($aggregateCanonicalPaths.Count-ne6-or-not(Test-Path -LiteralPath $ownedIntentTemp -PathType Leaf)-or-not(Test-Path -LiteralPath $ownedCheckpointTemp -PathType Leaf)){throw '[mir4-a07-owned-temp-cleanup]'}
foreach($canonicalPath in $aggregateCanonicalPaths){$null=Assert-A07CanonicalPublicationRecord $canonicalPath}
$aggregateCallsBefore=$killCalls.Count
$aggregateResume=Invoke-A07Attempt $aggregate Resume
$aggregateCanonicalAfter=Assert-A07CanonicalPublicationRecord $aggregatePath
if([string]$aggregateResume.state-cne'executed'-or$killCalls.Count-ne$aggregateCallsBefore-or
   $aggregateCanonicalBefore-cne$aggregateCanonicalAfter-or-not(Test-Path -LiteralPath $ownedIntentTemp -PathType Leaf)-or
   -not(Test-Path -LiteralPath $ownedCheckpointTemp -PathType Leaf)){throw '[mir4-a07-kill-aggregate-resume]'}
$aggregateOriginal=[IO.File]::ReadAllText($aggregatePath)
$aggregateReceiptTamper=$aggregateOriginal|ConvertFrom-Json -Depth 100
$aggregateReceiptTamper.transfers[0].package_sha256=('D'*64)
$aggregateReceiptTamper.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $aggregateReceiptTamper -HashProperty record_sha256
[IO.File]::WriteAllText($aggregatePath,(ConvertTo-MIR4ReleasePhaseCanonicalJson $aggregateReceiptTamper)+"`n",[Text.UTF8Encoding]::new($false))
Expect-A07Failure { Invoke-A07Attempt $aggregate Verify } '[mir4-publication-reconciliation-verification]'
[IO.File]::WriteAllText($aggregatePath,$aggregateOriginal,[Text.UTF8Encoding]::new($false))
$aggregateCountTamper=$aggregateOriginal|ConvertFrom-Json -Depth 100
$aggregateCountTamper.reconcile_required_count=0;$aggregateCountTamper.transferred_count=0;$aggregateCountTamper.adopted_count=4
$aggregateCountTamper.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $aggregateCountTamper -HashProperty record_sha256
[IO.File]::WriteAllText($aggregatePath,(ConvertTo-MIR4ReleasePhaseCanonicalJson $aggregateCountTamper)+"`n",[Text.UTF8Encoding]::new($false))
Expect-A07Failure { Invoke-A07Attempt $aggregate Verify } '[mir4-publication-reconciliation-verification]'
[IO.File]::WriteAllText($aggregatePath,$aggregateOriginal,[Text.UTF8Encoding]::new($false))
$null=Assert-A07CanonicalPublicationRecord $aggregatePath
$aggregateCheckpointPath=Join-Path $aggregateCheckpointRoot ([string]$aggregateRequests[0].transfer_id+'.json')
$aggregateCheckpointOriginal=[IO.File]::ReadAllText($aggregateCheckpointPath)
$aggregateCheckpointTamper=$aggregateCheckpointOriginal|ConvertFrom-Json -Depth 100
$aggregateCheckpointTamper.disposition='already-present-exact'
$aggregateCheckpointTamper.checkpoint_sha256=Get-MIR4ReleasePhaseSelfHash -Record $aggregateCheckpointTamper -HashProperty checkpoint_sha256
[IO.File]::WriteAllText($aggregateCheckpointPath,(ConvertTo-MIR4ReleasePhaseCanonicalJson $aggregateCheckpointTamper)+"`n",[Text.UTF8Encoding]::new($false))
Expect-A07Failure { Invoke-A07Attempt $aggregate Verify } '[mir4-publication-checkpoint-drift]'
[IO.File]::WriteAllText($aggregateCheckpointPath,$aggregateCheckpointOriginal,[Text.UTF8Encoding]::new($false))

& (Join-Path $RepoRoot 'tests/release/Test-MIR4LocalDelivery.ps1') -RepoRoot $RepoRoot
if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$beforePackage){throw '[mir4-a07-package-source-mutated]'}
Write-Host '[ok] A07 non-production publication intent, exact reconciliation, terminal checkpoint, timeout, kill-equivalent, and local-delivery recovery coverage passed.'
