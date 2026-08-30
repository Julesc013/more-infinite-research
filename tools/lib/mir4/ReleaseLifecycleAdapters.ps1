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

function Invoke-MIR4DefaultPublicationTransferProvider {
  param([string]$RepoRoot,$Request,[string]$Mode,$Context)
  if($Mode-ceq'Transfer'){return [pscustomobject][ordered]@{state='uncertain';transfer_id=[string]$Request.transfer_id;observed_sha256=$null;network_calls=0;production_mutation_performed=$false}}
  return [pscustomobject][ordered]@{state='already-present-exact';transfer_id=[string]$Request.transfer_id;observed_sha256=[string]$Request.package_sha256;network_calls=0;production_mutation_performed=$false}
}

function Assert-MIR4PublicationTransferResponse {
  param($Response,$Request,[string[]]$AllowedStates)
  if([string]$Response.state-notin$AllowedStates-or[string]$Response.transfer_id-cne[string]$Request.transfer_id-or
     [int]$Response.network_calls-ne0-or[bool]$Response.production_mutation_performed){throw "[mir4-publication-transfer-response] $($Request.transfer_id)"}
  return $Response
}

function Get-MIR4PublicationRequests {
  param($Identity,[object[]]$Targets)
  return @(foreach($target in $Targets){foreach($channel in @('github','mod-portal')){
    [pscustomobject][ordered]@{
      transfer_id=Get-MIR4ReleasePhaseSha256 ([ordered]@{domain='mir4-target-publication/1';candidate_id=[string]$Identity.candidate_id;target=[string]$target.target;channel=$channel;package_sha256=[string]$target.package_sha256})
      target=[string]$target.target;channel=$channel;package_sha256=[string]$target.package_sha256;bytes=[long]$target.bytes
    }
  }})
}

function Invoke-MIR4TargetPublicationAdapter {
  param([string]$RepoRoot,$Context,[scriptblock]$TransferProvider)
  $boundary=Assert-MIR4ReleaseAdapterContext -RepoRoot $RepoRoot -Context $Context -Phase 'target-publication'
  $targets=@(Get-MIR4ReleaseLifecycleTargets -RepoRoot $boundary.repo -Context $Context);$identity=Get-MIR4ReleaseLifecycleIdentity $Context $targets
  $requests=@(Get-MIR4PublicationRequests $identity $targets);$executeRoot=Join-Path $boundary.attempt_root 'artifacts/execute';$path=Join-Path $executeRoot 'publication-reconciliation.json'
  switch([string]$Context.operation){
    'DryRun'{
      $detail=[pscustomobject][ordered]@{state='planned-confined-publication-rehearsal';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;transfer_count=$requests.Count;builder_available=$false;source_checkout_required=$false;network_calls=0;publication_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context target-publication MIR4TargetPublicationPhaseResultV1 DryRun $detail @() @('sealed-byte-identities-only','publisher-builder-absent','source-checkout-not-required','idempotency-keys-complete','publish-port-denied')
    }
    'Execute'{
      $receipts=@();$reconciled=0
      foreach($request in $requests){
        $response=Assert-MIR4PublicationTransferResponse (&$TransferProvider $boundary.repo $request Transfer $Context) $request @('transferred-exact','already-present-exact','uncertain')
        $wasUncertain=[string]$response.state-ceq'uncertain'
        if($wasUncertain){$response=Assert-MIR4PublicationTransferResponse (&$TransferProvider $boundary.repo $request Reconcile $Context) $request @('already-present-exact','transferred-exact');$reconciled++}
        if([string]$response.observed_sha256-cne[string]$request.package_sha256){throw "[mir4-publication-transfer-hash] $($request.transfer_id)"}
        $receipts+=[pscustomobject][ordered]@{transfer_id=[string]$request.transfer_id;target=[string]$request.target;channel=[string]$request.channel;package_sha256=[string]$request.package_sha256;disposition=[string]$response.state;uncertain_transfer_reconciled=$wasUncertain;network_calls=0;production_mutation_performed=$false}
      }
      $record=[pscustomobject][ordered]@{schema=1;kind='MIR4PublicationReconciliationV1';identity_sha256=Get-MIR4ReleasePhaseSha256 $identity;identity=$identity;transfers=@($receipts);reconciled_count=$reconciled;builder_available=$false;source_checkout_required=$false;network_calls=0;publication_authorized=$false;production_authorized=$false;release_transition_performed=$false;record_sha256=''}
      $record=Write-MIR4ReleaseLifecycleRecord $record $path
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context target-publication MIR4TargetPublicationPhaseResultV1 Execute $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('transfer-identities-exact','uncertain-transfers-reconciled','idempotency-keys-reused','builder-capability-absent','no-production-publication')
    }
    'Verify'{
      $record=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100;$null=Assert-MIR4ReleaseLifecycleRecord $record MIR4PublicationReconciliationV1 $Context $targets
      if(@($record.transfers).Count-ne$requests.Count-or@($record.transfers|Where-Object{[string]$_.disposition-notin@('already-present-exact','transferred-exact')-or[int]$_.network_calls-ne0-or[bool]$_.production_mutation_performed}).Count-ne0-or[bool]$record.builder_available-or[bool]$record.source_checkout_required-or[bool]$record.publication_authorized){throw '[mir4-publication-reconciliation-verification]'}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context target-publication MIR4TargetPublicationPhaseResultV1 Verify $record @((Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)) @('transfer-receipts-self-hashed','all-transfers-terminal','exact-byte-hashes-reverified','publisher-remains-builder-free','production-boundary-reverified')
    }
    'Compensate'{
      $artifacts=if(Test-Path -LiteralPath $path -PathType Leaf){@(Get-MIR4ReleaseAdapterFileDescriptor -RepoRoot $boundary.repo -Path $path)}else{@()};if(Test-Path -LiteralPath $executeRoot -PathType Container){Remove-Item -LiteralPath $executeRoot -Recurse -Force}
      $detail=[pscustomobject][ordered]@{state='local-reconciliation-record-removed';remote_delete_attempted=$false;network_calls=0;publication_authorized=$false}
      return New-MIR4ReleaseLifecycleResult $boundary.repo $Context target-publication MIR4TargetPublicationPhaseResultV1 Compensate $detail $artifacts @('attempt-local-receipts-removed','remote-delete-not-attempted','production-state-unchanged')
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
  $requests=@(Get-MIR4PublicationRequests $identity $targets);$executeRoot=Join-Path $boundary.attempt_root 'artifacts/execute';$path=Join-Path $executeRoot 'public-readback-rehearsal.json'
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
