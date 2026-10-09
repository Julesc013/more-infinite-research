Set-StrictMode -Version Latest

function Get-MIR4ReleaseLifecycleTargets {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Context)
  return @(Get-MIR4TargetQualificationExpectations -RepoRoot $RepoRoot -Context $Context | ForEach-Object {
    [pscustomobject][ordered]@{
      target=[string]$_.target;distribution_version=[string]$_.distribution_version
      package_sha256=[string]$_.package.sha256;content_sha256=[string]$_.package.content_sha256
      bytes=[long]$_.package.bytes;entry_count=[int]$_.package.entry_count
    }
  })
}

function Get-MIR4ReleaseLifecycleIdentity {
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][object[]]$Targets)
  return [pscustomobject][ordered]@{
    candidate_id=[string]$Context.plan.identity.candidate_id
    source_commit=[string]$Context.plan.identity.source_commit
    source_tree=[string]$Context.plan.identity.source_tree
    source_release_record=$Context.plan.identity.source_release_record
    target_distribution_record_set=$Context.plan.identity.target_distribution_record_set
    release_plan_digest=[string]$Context.plan.identity.release_plan_digest
    proof_root=[string]$Context.plan.identity.proof_root;seal_root=[string]$Context.plan.identity.seal_root
    targets=@($Targets)
  }
}

function New-MIR4ReleaseLifecycleResult {
  param([string]$RepoRoot,$Context,[string]$Phase,[string]$PhaseResultKind,[string]$Operation,$Detail,[object[]]$Artifacts,[string[]]$Checks)
  $schemas=@{
    'release-seal'='spec/schemas/mir4-release-seal-result-v1.schema.json'
    'promotion'='spec/schemas/mir4-release-promotion-result-v1.schema.json'
    'target-publication'='spec/schemas/mir4-release-target-publication-result-v1.schema.json'
    'public-readback'='spec/schemas/mir4-release-public-readback-result-v1.schema.json'
    'restore-drill'='spec/schemas/mir4-release-restore-drill-result-v1.schema.json'
  }
  $result=[pscustomobject][ordered]@{
    schema=1;kind='MIR4ReleasePhaseAdapterResultV1';phase=$Phase;phase_result_kind=$PhaseResultKind
    operation=$Operation;status='passed';idempotency_key=[string]$Context.idempotency_key
    artifact_root=Get-MIR4ReleaseAdapterRelativePath -RepoRoot $RepoRoot -Path ([string]$Context.artifact_root)
    production_mutation_performed=$false;release_transition_performed=$false
    detail=$Detail;artifacts=@($Artifacts);checks=@($Checks|Sort-Object -CaseSensitive -Unique)
  }
  return Test-MIR4ReleaseAdapterResultSchema -RepoRoot $RepoRoot -Schema $schemas[$Phase] -Result $result
}

function Write-MIR4ReleaseLifecycleRecord {
  param($Record,[string]$Path)
  $Record.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $Record -HashProperty record_sha256
  Write-MIR4ReleaseAdapterRecord -Record $Record -Path $Path
  return $Record
}

function Assert-MIR4ReleaseLifecycleRecord {
  param($Record,[string]$Kind,$Context,[object[]]$Targets)
  $identity=Get-MIR4ReleaseLifecycleIdentity -Context $Context -Targets $Targets
  if([string]$Record.kind-cne$Kind-or[string]$Record.record_sha256-cne(Get-MIR4ReleasePhaseSelfHash -Record $Record -HashProperty record_sha256)-or
     [string]$Record.identity_sha256-cne(Get-MIR4ReleasePhaseSha256 $identity)-or[bool]$Record.production_authorized-or
     [bool]$Record.release_transition_performed){throw "[mir4-release-lifecycle-record] $Kind"}
  return $Record
}

function Invoke-MIR4ReleaseSealAdapter {
  param([string]$RepoRoot,$Context)
  $boundary=Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'release-seal'
  $null=Get-MIR4ReleaseAdapterSourceState -RepoRoot $boundary.repo -Context $Context
  $targets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $boundary.repo -Context $Context)
  $identity=Get-MIR4ReleaseLifecycleIdentity -Context $Context -Targets $targets
  $executeRoot=Join-Path $boundary.attempt_root 'artifacts/execute';$path=Join-Path $executeRoot 'unsigned-seal-assembly.json'
  switch([string]$Context.operation){
    'DryRun'{
      $detail=[pscustomobject][ordered]@{state='planned-unsigned-seal-assembly';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;target_count=$targets.Count;signing_invoked=$false;seal_created=$false;production_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context release-seal MIR4ReleaseSealPhaseResultV1 DryRun $detail @() @('exact-candidate-closure','mandatory-target-cardinality','sign-port-denied','unsigned-assembly-only','production-transition-denied')
    }
    'Execute'{
      $record=[pscustomobject][ordered]@{schema=1;kind='MIR4UnsignedSealAssemblyV1';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;identity=$identity;assembly_sha256=Get-MIR4ReleasePhaseSha256 ([ordered]@{identity=$identity;domain='mir4-release-seal-assembly/1'});signing_invoked=$false;seal_created=$false;production_authorized=$false;release_transition_performed=$false;record_sha256=''}
      $record=Write-MIR4ReleaseLifecycleRecord $record $path
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context release-seal MIR4ReleaseSealPhaseResultV1 Execute $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('unsigned-assembly-created','assembly-self-hashed','exact-target-bytes-bound','signing-not-invoked','seal-not-created')
    }
    'Verify'{
      $record=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100
      $null=Assert-MIR4ReleaseLifecycleRecord $record MIR4UnsignedSealAssemblyV1 $Context $targets
      if([string]$record.assembly_sha256-cne(Get-MIR4ReleasePhaseSha256 ([ordered]@{identity=$identity;domain='mir4-release-seal-assembly/1'}))-or
         (ConvertTo-MIR4ReleasePhaseCanonicalJson @($record.identity.targets))-cne(ConvertTo-MIR4ReleasePhaseCanonicalJson $targets)-or
         [bool]$record.signing_invoked-or[bool]$record.seal_created){throw '[mir4-release-seal-post-assembly-mutation]'}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context release-seal MIR4ReleaseSealPhaseResultV1 Verify $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('assembly-self-hash','identity-recomputed','target-bytes-recomputed','post-assembly-mutation-rejected','production-boundary-reverified')
    }
    'Compensate'{
      $artifacts=if(Test-Path -LiteralPath $path -PathType Leaf){@(Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)}else{@()}
      if(Test-Path -LiteralPath $executeRoot -PathType Container){Remove-Item -LiteralPath $executeRoot -Recurse -Force}
      $detail=[pscustomobject][ordered]@{state='unsigned-assembly-removed';signing_invoked=$false;seal_created=$false;production_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context release-seal MIR4ReleaseSealPhaseResultV1 Compensate $detail $artifacts @('attempt-local-assembly-removed','signing-not-invoked','repository-unchanged')
    }
    default{throw "[mir4-release-seal-adapter-operation] $($Context.operation)"}
  }
}

function Get-MIR4PromotionBase {
  param([string]$RepoRoot)
  $eventName=[string]$env:GITHUB_EVENT_NAME
  if($eventName-ceq'pull_request'){
    $eventPath=[string]$env:GITHUB_EVENT_PATH
    if([string]::IsNullOrWhiteSpace($eventPath)-or-not(Test-Path -LiteralPath $eventPath -PathType Leaf)){throw '[mir4-promotion-pr-event-unavailable]'}
    $event=Get-Content -Raw -LiteralPath $eventPath|ConvertFrom-Json -Depth 100
    $baseRef=[string]$event.pull_request.base.ref;$baseSha=[string]$event.pull_request.base.sha
    $mergeSha=[string]$event.pull_request.merge_commit_sha;$workflowSha=[string]$env:GITHUB_SHA
    if($baseRef-cne'main'-or$baseSha-cnotmatch'^[0-9a-f]{40}$'-or$mergeSha-cnotmatch'^[0-9a-f]{40}$'-or$workflowSha-cnotmatch'^[0-9a-f]{40}$'){throw '[mir4-promotion-pr-event-invalid]'}
    & git -C $RepoRoot cat-file -e "$baseSha^{commit}" 2>$null
    if($LASTEXITCODE-ne0){throw '[mir4-promotion-pr-base-unavailable]'}
    return [pscustomobject][ordered]@{
      ref='event.pull_request.base.sha';commit=$baseSha
      proof_context=[pscustomobject][ordered]@{
        event_name='pull_request';trust_class='untrusted-pull-request';ref_topology='synthetic-merge-ref'
        credential_class='none';environment_class='github-hosted-read-only';evidence_mode='simulation'
        base_ref='main';source_ref=[string]$event.pull_request.head.ref;event_source_commit=$workflowSha
        event_payload_merge_commit=$mergeSha
      }
    }
  }
  foreach($ref in @('refs/remotes/origin/main','refs/heads/main')){
    $value=& git -C $RepoRoot rev-parse --verify $ref 2>$null
    if($LASTEXITCODE-eq0-and[string]$value-cmatch'^[0-9a-f]{40}$'){
      return [pscustomobject][ordered]@{
        ref=$ref;commit=([string]$value).Trim()
        proof_context=[pscustomobject][ordered]@{
          event_name=$(if([string]::IsNullOrWhiteSpace($eventName)){'local'}else{$eventName})
          trust_class='trusted-read-only';ref_topology='branch-tip';credential_class='not-required'
          environment_class=$(if([string]::IsNullOrWhiteSpace($eventName)){'maintainer-workstation'}else{'github-hosted-read-only'})
          evidence_mode='simulation';base_ref='main';source_ref=$(if([string]::IsNullOrWhiteSpace([string]$env:GITHUB_REF)){'HEAD'}else{[string]$env:GITHUB_REF})
          event_source_commit=$null
        }
      }
    }
  }
  throw '[mir4-promotion-base-unavailable]'
}

function Invoke-MIR4PromotionAdapter {
  param([string]$RepoRoot,$Context)
  $boundary=Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase promotion
  $source=Get-MIR4ReleaseAdapterSourceState -RepoRoot $boundary.repo -Context $Context;$base=Get-MIR4PromotionBase $boundary.repo
  if([string]$base.proof_context.event_source_commit-cmatch'^[0-9a-f]{40}$'-and[string]$base.proof_context.event_source_commit-cne[string]$source.commit){throw '[mir4-promotion-pr-source-mismatch]'}
  & git -C $boundary.repo merge-base --is-ancestor ([string]$base.commit) ([string]$source.commit)
  if($LASTEXITCODE-ne0){throw '[mir4-promotion-non-fast-forward]'}
  $targets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $boundary.repo -Context $Context);$identity=Get-MIR4ReleaseLifecycleIdentity $Context $targets
  $executeRoot=Join-Path $boundary.attempt_root 'artifacts/execute';$path=Join-Path $executeRoot 'fast-forward-promotion-plan.json'
  $makePlan={ [pscustomobject][ordered]@{schema=1;kind='MIR4FastForwardPromotionPlanV1';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;branch='main';observed_ref=[string]$base.ref;from_commit=[string]$base.commit;to_commit=[string]$source.commit;to_tree=[string]$source.tree;proof_context=$base.proof_context;fast_forward_required=$true;fast_forward_proven=$true;ref_update_performed=$false;tag_created=$false;production_authorized=$false;release_transition_performed=$false;record_sha256=''} }
  switch([string]$Context.operation){
    'DryRun'{$detail=&$makePlan;return New-MIR4ReleaseLifecycleResult $boundary.repo $Context promotion MIR4PromotionPhaseResultV1 DryRun $detail @() @('main-ref-observed','exact-source-descendant','fast-forward-only','git-port-read-only','promotion-denied')}
    'Execute'{$record=Write-MIR4ReleaseLifecycleRecord (&$makePlan) $path;return New-MIR4ReleaseLifecycleResult $boundary.repo $Context promotion MIR4PromotionPhaseResultV1 Execute $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('fast-forward-plan-created','ancestry-proven','exact-tree-bound','ref-not-updated','tag-not-created')}
    'Verify'{
      $record=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100;$null=Assert-MIR4ReleaseLifecycleRecord $record MIR4FastForwardPromotionPlanV1 $Context $targets;$current=Get-MIR4PromotionBase $boundary.repo
      if([string]$record.from_commit-cne[string]$current.commit-or[string]$record.to_commit-cne[string]$source.commit-or[string]$record.to_tree-cne[string]$source.tree-or
         (ConvertTo-MIR4ReleasePhaseCanonicalJson $record.proof_context)-cne(ConvertTo-MIR4ReleasePhaseCanonicalJson $current.proof_context)-or
         -not[bool]$record.fast_forward_proven-or[bool]$record.ref_update_performed-or[bool]$record.tag_created){throw '[mir4-promotion-plan-stale]'}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context promotion MIR4PromotionPhaseResultV1 Verify $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('event-aware-base-reverified','source-identity-reverified','ancestry-reverified','no-ref-mutation','production-boundary-reverified')
    }
    'Compensate'{
      $artifacts=if(Test-Path -LiteralPath $path -PathType Leaf){@(Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)}else{@()};if(Test-Path -LiteralPath $executeRoot -PathType Container){Remove-Item -LiteralPath $executeRoot -Recurse -Force}
      $detail=[pscustomobject][ordered]@{state='promotion-plan-removed';ref_update_performed=$false;tag_created=$false;production_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context promotion MIR4PromotionPhaseResultV1 Compensate $detail $artifacts @('attempt-local-plan-removed','refs-unchanged','tags-unchanged')
    }
    default{throw "[mir4-promotion-adapter-operation] $($Context.operation)"}
  }
}

function Get-MIR4PublicationDraftBinding {
  param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)][object[]]$Targets)
  $assets=@(foreach($target in @($Targets|Sort-Object target)){
    [pscustomobject][ordered]@{
      asset_id=('target-package/'+([string]$target.target).ToLowerInvariant())
      target=[string]$target.target;distribution_version=[string]$target.distribution_version
      package_sha256=[string]$target.package_sha256;content_sha256=[string]$target.content_sha256
      bytes=[long]$target.bytes;entry_count=[int]$target.entry_count
    }
  })
  return [pscustomobject][ordered]@{
    draft_identity='unallocated';tag_identity='unallocated';seal_identity=[string]$Identity.seal_root
    candidate_id=[string]$Identity.candidate_id;assets=$assets
    production_authorized=$false;publication_authorized=$false
  }
}

function Get-MIR4PublicationRequests {
  param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)]$Draft,[Parameter(Mandatory)][object[]]$Targets)
  return @(foreach($asset in @($Draft.assets|Sort-Object target)){foreach($channel in @('github','mod-portal')){
    $material=[ordered]@{
      domain='mir4-target-publication-transfer/2';identity=$Identity;draft=$Draft
      asset=$asset;channel=$channel
    }
    [pscustomobject][ordered]@{
      transfer_id=Get-MIR4ReleasePhaseSha256 $material
      candidate_id=[string]$Identity.candidate_id;source_commit=[string]$Identity.source_commit;source_tree=[string]$Identity.source_tree
      release_plan_digest=[string]$Identity.release_plan_digest
      draft_identity=[string]$Draft.draft_identity;tag_identity=[string]$Draft.tag_identity;seal_identity=[string]$Draft.seal_identity
      target=[string]$asset.target;channel=$channel;asset_id=[string]$asset.asset_id
      package_sha256=[string]$asset.package_sha256;content_sha256=[string]$asset.content_sha256
      bytes=[long]$asset.bytes;entry_count=[int]$asset.entry_count
    }
  }})
}

function New-MIR4PublicationIntentRecord {
  param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)]$Draft,[Parameter(Mandatory)][object[]]$Requests)
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR4PublicationIntentV1';identity_sha256=Get-MIR4ReleasePhaseSha256 $Identity
    identity=$Identity;draft=$Draft;transfer_count=@($Requests).Count;transfers=@($Requests)
    builder_available=$false;source_checkout_required=$false;network_calls=0
    publication_authorized=$false;production_authorized=$false;release_transition_performed=$false;record_sha256=''
  }
  $record.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty record_sha256
  return $record
}

function Assert-MIR4PublicationIntentRecord {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$Expected)
  if([string]$Record.kind-cne'MIR4PublicationIntentV1'-or
     [string]$Record.record_sha256-cne(Get-MIR4ReleasePhaseSelfHash -Record $Record -HashProperty record_sha256)-or
     (ConvertTo-MIR4ReleasePhaseCanonicalJson $Record)-cne(ConvertTo-MIR4ReleasePhaseCanonicalJson $Expected)){
    throw '[mir4-publication-intent-drift]'
  }
  if([string]$Record.draft.draft_identity-cne'unallocated'-or[string]$Record.draft.tag_identity-cne'unallocated'-or
     [string]::IsNullOrWhiteSpace([string]$Record.draft.seal_identity)-or[bool]$Record.draft.production_authorized-or
     [bool]$Record.draft.publication_authorized-or[bool]$Record.production_authorized-or[bool]$Record.publication_authorized){
    throw '[mir4-publication-intent-authority]'
  }
  return $Record
}

function Get-MIR4PublicationProperty {
  param($Value,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Failure)
  if($null-eq$Value-or$null-eq$Value.PSObject.Properties[$Name]){throw $Failure}
  return $Value.PSObject.Properties[$Name].Value
}

function Assert-MIR4PublicationTransferBinding {
  param($Value,$Request,[Parameter(Mandatory)][string]$Failure)
  foreach($name in @('transfer_id','candidate_id','source_commit','source_tree','release_plan_digest','draft_identity','tag_identity','seal_identity','target','channel','asset_id','package_sha256','content_sha256')){
    if([string](Get-MIR4PublicationProperty $Value $name $Failure)-cne[string]$Request.$name){throw $Failure}
  }
  foreach($name in @('bytes','entry_count')){
    if([long](Get-MIR4PublicationProperty $Value $name $Failure)-ne[long]$Request.$name){throw $Failure}
  }
}

function New-MIR4PublicationProviderResponse {
  param(
    [Parameter(Mandatory)]$Request,
    [Parameter(Mandatory)][ValidateSet('absent','already-present-exact','transferred-exact','uncertain')][string]$State,
    [int]$MatchCount=$(if($State-ceq'absent'-or$State-ceq'uncertain'){0}else{1})
  )
  $bound=[ordered]@{}
  foreach($name in @('transfer_id','candidate_id','source_commit','source_tree','release_plan_digest','draft_identity','tag_identity','seal_identity','target','channel','asset_id','package_sha256','content_sha256','bytes','entry_count')){$bound[$name]=$Request.$name}
  $match=[pscustomobject][ordered]@{}
  foreach($pair in $bound.GetEnumerator()){$match|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
  $match|Add-Member -NotePropertyName observed_sha256 -NotePropertyValue ([string]$Request.package_sha256)
  $match|Add-Member -NotePropertyName observed_bytes -NotePropertyValue ([long]$Request.bytes)
  $response=[pscustomobject][ordered]@{}
  foreach($pair in $bound.GetEnumerator()){$response|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
  $response|Add-Member -NotePropertyName state -NotePropertyValue $State
  $response|Add-Member -NotePropertyName observed_sha256 -NotePropertyValue $(if($MatchCount-eq1){[string]$Request.package_sha256}else{$null})
  $response|Add-Member -NotePropertyName observed_bytes -NotePropertyValue $(if($MatchCount-eq1){[long]$Request.bytes}else{0})
  $response|Add-Member -NotePropertyName match_count -NotePropertyValue $MatchCount
  $matches=if($MatchCount-eq0){[object[]]@()}else{[object[]]@($match)}
  $response|Add-Member -NotePropertyName matches -NotePropertyValue $matches
  $response|Add-Member -NotePropertyName network_calls -NotePropertyValue 0
  $response|Add-Member -NotePropertyName production_mutation_performed -NotePropertyValue $false
  return $response
}

function Assert-MIR4PublicationTransferResponse {
  param($Response,$Request,[Parameter(Mandatory)][ValidateSet('Reconcile','Transfer')][string]$Mode)
  $failure="[mir4-publication-transfer-response] $($Request.transfer_id)"
  $state=[string](Get-MIR4PublicationProperty $Response state $failure)
  $allowed=if($Mode-ceq'Reconcile'){@('absent','already-present-exact','transferred-exact')}else{@('already-present-exact','transferred-exact','uncertain')}
  if($state-notin$allowed-or[int](Get-MIR4PublicationProperty $Response network_calls $failure)-ne0-or
     [bool](Get-MIR4PublicationProperty $Response production_mutation_performed $failure)){throw $failure}
  $bindingFailure="[mir4-publication-transfer-binding] $($Request.transfer_id)"
  Assert-MIR4PublicationTransferBinding $Response $Request $bindingFailure
  $matchProperty=$Response.PSObject.Properties['matches']
  if($null-eq$matchProperty){throw $failure}
  $matches=@()
  if($null-ne$matchProperty.Value){$matches=@($matchProperty.Value)}
  $matchCount=[int](Get-MIR4PublicationProperty $Response match_count $failure)
  if($matchCount-ne$matches.Count){throw $failure}
  if($state-ceq'absent'-or$state-ceq'uncertain'){
    if($matchCount-ne0-or$null-ne(Get-MIR4PublicationProperty $Response observed_sha256 $failure)-or
       [long](Get-MIR4PublicationProperty $Response observed_bytes $failure)-ne0){throw $failure}
    return $Response
  }
  if($matchCount-ne1){throw "[mir4-publication-transfer-match-count] $($Request.transfer_id)"}
  Assert-MIR4PublicationTransferBinding $matches[0] $Request $bindingFailure
  $hashFailure="[mir4-publication-transfer-hash] $($Request.transfer_id)"
  foreach($value in @($Response,$matches[0])){
    if([string](Get-MIR4PublicationProperty $value observed_sha256 $failure)-cne[string]$Request.package_sha256-or
       [long](Get-MIR4PublicationProperty $value observed_bytes $failure)-ne[long]$Request.bytes){throw $hashFailure}
  }
  return $Response
}

function Write-MIR4PublicationCreateNewOrAdopt {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Failure)
  $read={
    try{$existing=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json -Depth 100}catch{throw $Failure}
    if((ConvertTo-MIR4ReleasePhaseCanonicalJson $existing)-cne(ConvertTo-MIR4ReleasePhaseCanonicalJson $Record)){throw $Failure}
    return $existing
  }
  if(Test-Path -LiteralPath $Path -PathType Leaf){return & $read}
  $directory=[IO.Path]::GetDirectoryName($Path)
  if(-not(Test-Path -LiteralPath $directory -PathType Container)){throw $Failure}
  $temp=Join-Path $directory ('.'+[IO.Path]::GetFileName($Path)+'.'+[guid]::NewGuid().ToString('N')+'.tmp')
  try{
    Write-MIR4ReleasePhaseJsonCreateNew -Value $Record -Path $temp
    try{
      [IO.File]::Move($temp,$Path)
      return $Record
    }catch [IO.IOException]{
      if(Test-Path -LiteralPath $Path -PathType Leaf){return & $read}
      throw
    }
  }finally{
    if(Test-Path -LiteralPath $temp -PathType Leaf){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
  }
}

function Get-OrWrite-MIR4PublicationIntent {
  param([Parameter(Mandatory)]$Expected,[Parameter(Mandatory)][string]$Path)
  $record=Write-MIR4PublicationCreateNewOrAdopt $Expected $Path '[mir4-publication-intent-drift]'
  return Assert-MIR4PublicationIntentRecord $record $Expected
}

function New-MIR4PublicationTransferCheckpoint {
  param([Parameter(Mandatory)]$Intent,[Parameter(Mandatory)]$Request,[Parameter(Mandatory)]$Response,[Parameter(Mandatory)][string]$Disposition,[Parameter(Mandatory)][bool]$Adopted)
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR4PublicationTransferCheckpointV1';intent_sha256=[string]$Intent.record_sha256
    transfer_id=[string]$Request.transfer_id;request=$Request;response=$Response;disposition=$Disposition
    adopted_from_reconciliation=$Adopted;network_calls=0;production_mutation_performed=$false
    publication_authorized=$false;production_authorized=$false;release_transition_performed=$false;checkpoint_sha256=''
  }
  $record.checkpoint_sha256=Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty checkpoint_sha256
  return $record
}

function Assert-MIR4PublicationTransferCheckpoint {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$Intent,[Parameter(Mandatory)]$Request)
  $failure="[mir4-publication-checkpoint-drift] $($Request.transfer_id)"
  if([string]$Record.kind-cne'MIR4PublicationTransferCheckpointV1'-or
     [string]$Record.checkpoint_sha256-cne(Get-MIR4ReleasePhaseSelfHash -Record $Record -HashProperty checkpoint_sha256)-or
     [string]$Record.intent_sha256-cne[string]$Intent.record_sha256-or[string]$Record.transfer_id-cne[string]$Request.transfer_id-or
     (ConvertTo-MIR4ReleasePhaseCanonicalJson $Record.request)-cne(ConvertTo-MIR4ReleasePhaseCanonicalJson $Request)-or
     [string]$Record.disposition-notin@('already-present-exact','transferred-exact')-or
     [int]$Record.network_calls-ne0-or[bool]$Record.production_mutation_performed-or[bool]$Record.production_authorized-or
     [bool]$Record.publication_authorized-or[bool]$Record.release_transition_performed){throw $failure}
  $null=Assert-MIR4PublicationTransferResponse $Record.response $Request Reconcile
  if([string]$Record.response.state-cnotin@('already-present-exact','transferred-exact')-or
     [string]$Record.disposition-cne[string]$Record.response.state){throw $failure}
  return $Record
}

function Get-OrWrite-MIR4PublicationTransferCheckpoint {
  param($Expected,[Parameter(Mandatory)]$Intent,[Parameter(Mandatory)]$Request,[Parameter(Mandatory)][string]$Path)
  if($null-ne$Expected){$null=Write-MIR4PublicationCreateNewOrAdopt $Expected $Path "[mir4-publication-checkpoint-drift] $($Request.transfer_id)"}
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "[mir4-publication-checkpoint-missing] $($Request.transfer_id)"}
  try{$record=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json -Depth 100}catch{throw "[mir4-publication-checkpoint-drift] $($Request.transfer_id)"}
  return Assert-MIR4PublicationTransferCheckpoint $record $Intent $Request
}

function ConvertFrom-MIR4PublicationCheckpoint {
  param([Parameter(Mandatory)]$Checkpoint)
  return [pscustomobject][ordered]@{
    transfer_id=[string]$Checkpoint.transfer_id;target=[string]$Checkpoint.request.target;channel=[string]$Checkpoint.request.channel
    package_sha256=[string]$Checkpoint.request.package_sha256;bytes=[long]$Checkpoint.request.bytes
    disposition=[string]$Checkpoint.disposition;adopted_from_reconciliation=[bool]$Checkpoint.adopted_from_reconciliation
    checkpoint_sha256=[string]$Checkpoint.checkpoint_sha256;network_calls=0;production_mutation_performed=$false
  }
}

function Invoke-MIR4DefaultPublicationTransferProvider {
  param([string]$RepoRoot,$Request,[string]$Mode,$Context)
  return New-MIR4PublicationProviderResponse -Request $Request -State 'already-present-exact'
}

function Invoke-MIR4TargetPublicationAdapter {
  param([string]$RepoRoot,$Context,[scriptblock]$TransferProvider)
  $boundary=Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'target-publication'
  $targets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $boundary.repo -Context $Context);$identity=Get-MIR4ReleaseLifecycleIdentity $Context $targets
  $draft=Get-MIR4PublicationDraftBinding $identity $targets;$requests=@(Get-MIR4PublicationRequests $identity $draft $targets)
  $executeRoot=Join-Path $boundary.attempt_root 'artifacts/execute';$intentPath=Join-Path $executeRoot 'publication-intent.json'
  $checkpointRoot=Join-Path $executeRoot 'publication-transfer-checkpoints';$path=Join-Path $executeRoot 'publication-reconciliation.json'
  switch([string]$Context.operation){
    'DryRun'{
      $detail=[pscustomobject][ordered]@{state='planned-confined-publication-rehearsal';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;draft=$draft;transfer_count=$requests.Count;builder_available=$false;source_checkout_required=$false;network_calls=0;publication_authorized=$false;production_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context target-publication MIR4TargetPublicationPhaseResultV1 DryRun $detail @() @('sealed-byte-identities-only','publisher-builder-absent','source-checkout-not-required','idempotency-keys-complete','draft-tag-seal-assets-unallocated','publish-port-denied')
    }
    'Execute'{
      New-Item -ItemType Directory -Force -Path $executeRoot,$checkpointRoot|Out-Null
      $intent=Get-OrWrite-MIR4PublicationIntent (New-MIR4PublicationIntentRecord $identity $draft $requests) $intentPath
      $reconciled=0
      foreach($request in $requests){
        $checkpointPath=Join-Path $checkpointRoot ($request.transfer_id+'.json')
        if(Test-Path -LiteralPath $checkpointPath -PathType Leaf){
          $null=Get-OrWrite-MIR4PublicationTransferCheckpoint $null $intent $request $checkpointPath
          continue
        }
        $response=Assert-MIR4PublicationTransferResponse (&$TransferProvider $boundary.repo $request Reconcile $Context) $request Reconcile;$reconciled++
        $adoptedFromReconciliation=$false
        if([string]$response.state-ceq'absent'){
          $response=Assert-MIR4PublicationTransferResponse (&$TransferProvider $boundary.repo $request Transfer $Context) $request Transfer
          if([string]$response.state-ceq'uncertain'){
            $response=Assert-MIR4PublicationTransferResponse (&$TransferProvider $boundary.repo $request Reconcile $Context) $request Reconcile;$reconciled++
            if([string]$response.state-ceq'absent'){throw "[mir4-publication-uncertain-unresolved] $($request.transfer_id)"}
            $adoptedFromReconciliation=$true
          }
        }else{$adoptedFromReconciliation=$true}
        $checkpoint=New-MIR4PublicationTransferCheckpoint $intent $request $response ([string]$response.state) $adoptedFromReconciliation
        $null=Get-OrWrite-MIR4PublicationTransferCheckpoint $checkpoint $intent $request $checkpointPath
      }
      $receipts=@(foreach($request in $requests){
        $checkpointPath=Join-Path $checkpointRoot ($request.transfer_id+'.json')
        ConvertFrom-MIR4PublicationCheckpoint (Get-OrWrite-MIR4PublicationTransferCheckpoint $null $intent $request $checkpointPath)
      })
      $transferredCount=@($receipts|Where-Object{-not[bool]$_.adopted_from_reconciliation}).Count
      $adoptedCount=@($receipts|Where-Object{[bool]$_.adopted_from_reconciliation}).Count
      $record=[pscustomobject][ordered]@{schema=1;kind='MIR4PublicationReconciliationV1';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;identity=$identity;intent_sha256=[string]$intent.record_sha256;draft=$draft;transfers=@($receipts);reconcile_required_count=$requests.Count;transferred_count=$transferredCount;adopted_count=$adoptedCount;builder_available=$false;source_checkout_required=$false;network_calls=0;publication_authorized=$false;production_authorized=$false;release_transition_performed=$false;record_sha256=''}
      $record.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty record_sha256
      $record=Write-MIR4PublicationCreateNewOrAdopt $record $path '[mir4-publication-reconciliation-drift]'
      $null=Assert-MIR4ReleaseLifecycleRecord $record MIR4PublicationReconciliationV1 $Context $targets
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context target-publication MIR4TargetPublicationPhaseResultV1 Execute $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('publication-intent-persisted-before-provider','transfer-identities-exact','reconcile-before-transfer','terminal-checkpoints-atomic','exact-existing-transfers-adopted','builder-capability-absent','no-production-publication')
    }
    'Verify'{
      if(-not(Test-Path -LiteralPath $intentPath -PathType Leaf)){throw '[mir4-publication-intent-drift]'}
      $intent=Get-OrWrite-MIR4PublicationIntent (New-MIR4PublicationIntentRecord $identity $draft $requests) $intentPath
      $record=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100;$null=Assert-MIR4ReleaseLifecycleRecord $record MIR4PublicationReconciliationV1 $Context $targets
      if([string]$record.intent_sha256-cne[string]$intent.record_sha256-or
         (ConvertTo-MIR4ReleasePhaseCanonicalJson $record.draft)-cne(ConvertTo-MIR4ReleasePhaseCanonicalJson $draft)-or
         @($record.transfers).Count-ne$requests.Count-or@($record.transfers|Where-Object{[string]$_.disposition-notin@('already-present-exact','transferred-exact')-or[int]$_.network_calls-ne0-or[bool]$_.production_mutation_performed}).Count-ne0-or[bool]$record.builder_available-or[bool]$record.source_checkout_required-or[bool]$record.publication_authorized-or[bool]$record.production_authorized){throw '[mir4-publication-reconciliation-verification]'}
      $expectedReceipts=@()
      foreach($request in $requests){
        $checkpointPath=Join-Path $checkpointRoot ($request.transfer_id+'.json')
        if(-not(Test-Path -LiteralPath $checkpointPath -PathType Leaf)){throw "[mir4-publication-checkpoint-missing] $($request.transfer_id)"}
        $checkpoint=Get-OrWrite-MIR4PublicationTransferCheckpoint $null $intent $request $checkpointPath
        $expectedReceipt=ConvertFrom-MIR4PublicationCheckpoint $checkpoint
        $expectedReceipts+=$expectedReceipt
        $receipt=@($record.transfers|Where-Object{[string]$_.transfer_id-ceq[string]$request.transfer_id})
        if($receipt.Count-ne1-or
           (ConvertTo-MIR4ReleasePhaseCanonicalJson $receipt[0])-cne(ConvertTo-MIR4ReleasePhaseCanonicalJson $expectedReceipt)){throw '[mir4-publication-reconciliation-verification]'}
      }
      $expectedTransferred=@($expectedReceipts|Where-Object{-not[bool]$_.adopted_from_reconciliation}).Count
      $expectedAdopted=@($expectedReceipts|Where-Object{[bool]$_.adopted_from_reconciliation}).Count
      if([int]$record.reconcile_required_count-ne$expectedReceipts.Count-or
         [int]$record.transferred_count-ne$expectedTransferred-or[int]$record.adopted_count-ne$expectedAdopted){throw '[mir4-publication-reconciliation-verification]'}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context target-publication MIR4TargetPublicationPhaseResultV1 Verify $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('intent-self-hashed','transfer-checkpoints-self-hashed','all-transfers-terminal','exact-byte-hashes-reverified','publisher-remains-builder-free','production-boundary-reverified')
    }
    'Compensate'{
      $artifacts=if(Test-Path -LiteralPath $path -PathType Leaf){@(Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)}else{@()};if(Test-Path -LiteralPath $executeRoot -PathType Container){Remove-Item -LiteralPath $executeRoot -Recurse -Force}
      $detail=[pscustomobject][ordered]@{state='local-publication-journal-removed';remote_delete_attempted=$false;network_calls=0;publication_authorized=$false;production_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context target-publication MIR4TargetPublicationPhaseResultV1 Compensate $detail $artifacts @('attempt-local-journal-removed','remote-delete-not-attempted','production-state-unchanged')
    }
    default{throw "[mir4-target-publication-adapter-operation] $($Context.operation)"}
  }
}

function Invoke-MIR4DefaultPublicReadbackProvider {
  param([string]$RepoRoot,$Request,$Context)
  return [pscustomobject][ordered]@{target=[string]$Request.target;channel=[string]$Request.channel;observed_sha256=[string]$Request.package_sha256;observed_bytes=[long]$Request.bytes;network_calls=0;public_observation=$false}
}

function Invoke-MIR4PublicReadbackAdapter {
  param([string]$RepoRoot,$Context,[scriptblock]$ReadbackProvider)
  $boundary=Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'public-readback'
  $targets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $boundary.repo -Context $Context);$identity=Get-MIR4ReleaseLifecycleIdentity $Context $targets
  $draft=Get-MIR4PublicationDraftBinding $identity $targets;$requests=@(Get-MIR4PublicationRequests $identity $draft $targets);$executeRoot=Join-Path $boundary.attempt_root 'artifacts/execute';$path=Join-Path $executeRoot 'public-readback-rehearsal.json'
  switch([string]$Context.operation){
    'DryRun'{
      $detail=[pscustomobject][ordered]@{state='planned-readback-rehearsal';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;observation_count=$requests.Count;network_calls=0;public_observation=$false;publication_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context public-readback MIR4PublicReadbackPhaseResultV1 DryRun $detail @() @('exact-sealed-byte-expectations','all-target-channel-pairs','read-only-provider','network-disabled-rehearsal','publication-denied')
    }
    'Execute'{
      $observations=@()
      foreach($request in $requests){
        $observation=&$ReadbackProvider $boundary.repo $request $Context
        if([string]$observation.target-cne[string]$request.target-or[string]$observation.channel-cne[string]$request.channel-or[string]$observation.observed_sha256-cne[string]$request.package_sha256-or[long]$observation.observed_bytes-ne[long]$request.bytes-or[int]$observation.network_calls-ne0-or[bool]$observation.public_observation){throw "[mir4-public-readback-mismatch] $($request.target)/$($request.channel)"}
        $observations+=$observation
      }
      $record=[pscustomobject][ordered]@{schema=1;kind='MIR4PublicReadbackRehearsalV1';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;identity=$identity;observations=@($observations);all_bytes_equal=$true;network_calls=0;public_observation=$false;publication_authorized=$false;production_authorized=$false;release_transition_performed=$false;record_sha256=''}
      $record=Write-MIR4ReleaseLifecycleRecord $record $path
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context public-readback MIR4PublicReadbackPhaseResultV1 Execute $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('all-target-channel-observations-imported','sha256-equality','byte-count-equality','network-disabled-rehearsal','no-public-claim-created')
    }
    'Verify'{
      $record=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100;$null=Assert-MIR4ReleaseLifecycleRecord $record MIR4PublicReadbackRehearsalV1 $Context $targets
      if(@($record.observations).Count-ne$requests.Count-or-not[bool]$record.all_bytes_equal-or[int]$record.network_calls-ne0-or[bool]$record.public_observation-or[bool]$record.publication_authorized){throw '[mir4-public-readback-verification]'}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context public-readback MIR4PublicReadbackPhaseResultV1 Verify $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('readback-record-self-hash','identity-recomputed','observation-cardinality','sealed-byte-equality-reverified','production-boundary-reverified')
    }
    'Compensate'{
      $artifacts=if(Test-Path -LiteralPath $path -PathType Leaf){@(Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)}else{@()};if(Test-Path -LiteralPath $executeRoot -PathType Container){Remove-Item -LiteralPath $executeRoot -Recurse -Force}
      $detail=[pscustomobject][ordered]@{state='local-readback-record-removed';public_state_mutated=$false;network_calls=0;publication_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context public-readback MIR4PublicReadbackPhaseResultV1 Compensate $detail $artifacts @('attempt-local-observations-removed','public-state-unchanged','network-unused')
    }
    default{throw "[mir4-public-readback-adapter-operation] $($Context.operation)"}
  }
}

function Invoke-MIR4RestoreDrillAdapter {
  param([string]$RepoRoot,$Context)
  $boundary=Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'restore-drill'
  $targets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $boundary.repo -Context $Context);$identity=Get-MIR4ReleaseLifecycleIdentity $Context $targets
  $executeRoot=Join-Path $boundary.attempt_root 'artifacts/execute';$capsuleRoot=Join-Path $executeRoot 'capsule';$restoreRoot=Join-Path $executeRoot 'restored';$path=Join-Path $executeRoot 'restore-drill.json'
  switch([string]$Context.operation){
    'DryRun'{
      $detail=[pscustomobject][ordered]@{state='planned-clean-offline-restore';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;target_count=$targets.Count;clean_destination_required=$true;network_calls=0;production_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context restore-drill MIR4RestoreDrillPhaseResultV1 DryRun $detail @() @('exact-capsule-identity','clean-destination-required','portable-target-paths','network-denied','production-transition-denied')
    }
    'Execute'{
      if(Test-Path -LiteralPath $restoreRoot){throw '[mir4-restore-drill-destination-not-clean]'}
      New-Item -ItemType Directory -Path $capsuleRoot,$restoreRoot -Force|Out-Null;$rows=@()
      foreach($target in $targets){
        $name=([string]$target.target).ToLowerInvariant()+'.json';$source=Join-Path $capsuleRoot $name;$restored=Join-Path $restoreRoot $name
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ReleasePhaseCanonicalJson $target)+"`n");[IO.File]::WriteAllBytes($source,$bytes);[IO.File]::Copy($source,$restored,$false)
        $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToUpperInvariant();$restoredHash=(Get-FileHash -LiteralPath $restored -Algorithm SHA256).Hash.ToUpperInvariant()
        if($sourceHash-cne$restoredHash){throw "[mir4-restore-drill-copy-mismatch] $name"}
        $rows+=[pscustomobject][ordered]@{target=[string]$target.target;path=$name;source_sha256=$sourceHash;restored_sha256=$restoredHash;bytes=[long]$bytes.Length}
      }
      $record=[pscustomobject][ordered]@{schema=1;kind='MIR4CleanRestoreDrillV1';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;identity=$identity;files=@($rows);clean_destination=$true;all_bytes_equal=$true;network_calls=0;source_repository_access=$false;credential_access=$false;production_authorized=$false;release_transition_performed=$false;record_sha256=''}
      $record=Write-MIR4ReleaseLifecycleRecord $record $path
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context restore-drill MIR4RestoreDrillPhaseResultV1 Execute $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('clean-root-created','capsule-files-restored','source-and-restored-hashes-equal','network-unused','credentials-unused')
    }
    'Verify'{
      $record=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100;$null=Assert-MIR4ReleaseLifecycleRecord $record MIR4CleanRestoreDrillV1 $Context $targets;$files=@(Get-ChildItem -LiteralPath $restoreRoot -File)
      if($files.Count-ne$targets.Count-or@($record.files).Count-ne$targets.Count-or-not[bool]$record.clean_destination-or-not[bool]$record.all_bytes_equal-or[int]$record.network_calls-ne0-or[bool]$record.source_repository_access-or[bool]$record.credential_access){throw '[mir4-restore-drill-verification]'}
      foreach($row in $record.files){$restored=Join-Path $restoreRoot ([string]$row.path);if((Get-FileHash -LiteralPath $restored -Algorithm SHA256).Hash.ToUpperInvariant()-cne[string]$row.restored_sha256-or[string]$row.source_sha256-cne[string]$row.restored_sha256){throw "[mir4-restore-drill-byte-mismatch] $($row.path)"}}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context restore-drill MIR4RestoreDrillPhaseResultV1 Verify $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('restore-record-self-hash','clean-root-cardinality','restored-byte-hashes-reverified','no-extra-files','production-boundary-reverified')
    }
    'Compensate'{
      $artifacts=if(Test-Path -LiteralPath $path -PathType Leaf){@(Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)}else{@()};if(Test-Path -LiteralPath $executeRoot -PathType Container){Remove-Item -LiteralPath $executeRoot -Recurse -Force}
      $detail=[pscustomobject][ordered]@{state='attempt-local-restore-removed';external_archive_mutated=$false;network_calls=0;production_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context restore-drill MIR4RestoreDrillPhaseResultV1 Compensate $detail $artifacts @('attempt-local-restore-removed','external-archive-unchanged','repository-unchanged')
    }
    default{throw "[mir4-restore-drill-adapter-operation] $($Context.operation)"}
  }
}
