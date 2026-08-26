$mir4W08ControlRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
foreach($mir4W08ControlModule in @('Core','Records','Views','Planner','Observation','Evidence')){
  . (Join-Path $mir4W08ControlRoot "tools/lib/control/$mir4W08ControlModule.ps1")
}

function Import-MIR4W08ControlPlane {
  param([Parameter(Mandatory)][string]$RepoRoot)
  [void](Resolve-Path -LiteralPath $RepoRoot)
  foreach($sentinel in @('Get-MIRCPSha256Object','Get-MIRCPRecordSet','Get-MIRCPCurrentRelease','New-MIRCPPlan','New-MIRCPObservation','Test-MIRCPEvidenceRevocation')){if($null-eq(Get-Command $sentinel -CommandType Function -ErrorAction SilentlyContinue)){throw "[mir4-w08-control-plane-unavailable] $sentinel"}}
}

function Get-MIR4W08RepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4W08Authority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=Get-MIR4W08RepoRoot $RepoRoot
  $path=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Assurance-Scale-ProgrammeV1.json'
  $authority=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100
  if([int]$authority.schema-ne 1-or[string]$authority.kind-cne'MIR4AssuranceScaleProgrammeV1'-or[string]$authority.wave-cne'W08'){throw '[mir4-w08-authority]'}
  foreach($flag in @('semantic_authority','evidence_ledger_authority','verification_plan_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','source_freeze_authorized','production_signing_or_sealing_authorized','promotion_or_tag_authorized','network_or_upload_authorized','publication_authorized')){if([bool]$authority.$flag){throw "[mir4-w08-authority-boundary] $flag"}}
  if(@($authority.identity_kinds|Sort-Object -Unique).Count-ne 4-or@($authority.observation_slices|Sort-Object -Unique).Count-ne 11){throw '[mir4-w08-authority-count]'}
  if([int]$authority.rules.impact_false_negative_budget-ne 0-or[string]$authority.rules.unknown_impact_policy-cne'select-all-and-fail-governance'){throw '[mir4-w08-impact-policy]'}
  foreach($entry in @($authority.control_plane_authorities.PSObject.Properties)+@($authority.legacy_assurance_authorities.PSObject.Properties)){
    if(-not(Test-Path -LiteralPath (Join-Path $repo ([string]$entry.Value)) -PathType Leaf)){throw "[mir4-w08-authority-input] $($entry.Value)"}
  }
  return $authority
}

function Get-MIR4W08FileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIR4W08RecordSha256 {
  param([Parameter(Mandatory)]$Record)
  $material=[ordered]@{}
  foreach($property in $Record.PSObject.Properties){if($property.Name-cne'record_sha256'){$material[$property.Name]=$property.Value}}
  Import-MIR4W08ControlPlane -RepoRoot (Join-Path $PSScriptRoot '../../..')
  return Get-MIRCPSha256Object -Value $material
}

function Add-MIR4W08RecordSha256 {
  param([Parameter(Mandatory)]$Record)
  $Record.record_sha256=Get-MIR4W08RecordSha256 $Record
  return $Record
}

function Get-MIR4W08MerkleRoot {
  param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Leaves)
  Import-MIR4W08ControlPlane -RepoRoot (Join-Path $PSScriptRoot '../../..')
  if(@($Leaves).Count-eq 0){return $null}
  $level=@($Leaves|ForEach-Object{Get-MIRCPSha256Object -Value $_}|Sort-Object)
  while($level.Count-gt 1){
    $next=@()
    for($index=0;$index-lt$level.Count;$index+=2){
      $right=if($index+1-lt$level.Count){$level[$index+1]}else{$level[$index]}
      $next+=Get-MIRCPSha256Object -Value ([ordered]@{left=[string]$level[$index];right=[string]$right})
    }
    $level=@($next)
  }
  return [string]$level[0]
}

function New-MIR4W08SliceSet {
  param([Parameter(Mandatory)]$SliceInputs,[Parameter(Mandatory)][string]$RepoRoot)
  $authority=Get-MIR4W08Authority -RepoRoot $RepoRoot
  $inputNames=@($SliceInputs.PSObject.Properties.Name|Sort-Object -Unique)
  $expected=@($authority.observation_slices|ForEach-Object{[string]$_}|Sort-Object)
  if(($inputNames-join'|')-cne($expected-join'|')){throw '[mir4-w08-slice-set-exact]'}
  $slices=@()
  foreach($id in @($authority.observation_slices)){
    $input=$SliceInputs.PSObject.Properties[[string]$id].Value
    if([string]$input.status-cne'available'-and[string]$input.status-cne'unavailable'){throw "[mir4-w08-slice-status] $id"}
    if([string]::IsNullOrWhiteSpace([string]$input.authority_ref)){throw "[mir4-w08-slice-authority] $id"}
    $leaves=@()
    if([string]$input.status-ceq'available'){
      foreach($row in @($input.rows|Sort-Object authority_ref,digest)){
        if([string]$row.digest-notmatch'^[0-9A-Fa-f]{64}$'-or[string]::IsNullOrWhiteSpace([string]$row.authority_ref)){throw "[mir4-w08-slice-leaf] $id"}
        $leaves+=[ordered]@{authority_ref=[string]$row.authority_ref;digest=([string]$row.digest).ToUpperInvariant()}
      }
      if($leaves.Count-eq 0){throw "[mir4-w08-slice-empty] $id"}
    }elseif(-not[string]::IsNullOrWhiteSpace([string]$input.digest)){throw "[mir4-w08-slice-unavailable-digest] $id"}
    $slices+=[pscustomobject][ordered]@{
      id=[string]$id;status=[string]$input.status;authority_ref=[string]$input.authority_ref
      leaf_count=$leaves.Count;leaves=$leaves;root_sha256=$(if($leaves.Count){Get-MIR4W08MerkleRoot -Leaves $leaves}else{$null})
      reason=$(if($null-ne$input.PSObject.Properties['reason']){[string]$input.reason}else{''})
      proof_eligible=([string]$input.status-ceq'available')
    }
  }
  $availableRoots=@($slices|Where-Object status -eq available|ForEach-Object{[ordered]@{id=$_.id;root_sha256=$_.root_sha256}})
  return [pscustomobject][ordered]@{
    kind='MIR4ObservationSliceSetV1';schema=1;slices=$slices;available_count=@($slices|Where-Object status -eq available).Count
    unavailable_count=@($slices|Where-Object status -eq unavailable).Count;aggregate_root_sha256=(Get-MIR4W08MerkleRoot -Leaves $availableRoots)
    complete=(@($slices|Where-Object status -eq unavailable).Count-eq 0)
  }
}

function New-MIR4W08IdentitySet {
  param([Parameter(Mandatory)]$Inputs,[Parameter(Mandatory)]$Slices,[Parameter(Mandatory)][string]$RepoRoot)
  Import-MIR4W08ControlPlane -RepoRoot $RepoRoot
  foreach($name in @('capture','compilation','realization','evaluation')){if($null-eq$Inputs.PSObject.Properties[$name]){throw "[mir4-w08-identity-input] $name"}}
  $capture=$Inputs.capture
  foreach($digest in @($capture.environment_signature,$capture.candidate_sha256)){if([string]$digest-notmatch'^[0-9A-Fa-f]{64}$'){throw '[mir4-w08-capture-digest]'}}
  $observation=New-MIRCPObservation -Kind environment-capture -EnvironmentSignature ([string]$capture.environment_signature) -Target ([string]$capture.target) -CandidateSha256 ([string]$capture.candidate_sha256) -Facts ([ordered]@{status='captured';slice_aggregate_root=$Slices.aggregate_root_sha256}) -Source ([ordered]@{capture_inputs=$capture.inputs;slices=@($Slices.slices|ForEach-Object{[ordered]@{id=$_.id;status=$_.status;root_sha256=$_.root_sha256}})})
  $compilationMaterial=[ordered]@{kind='CompilationKey';abi=[int]$Inputs.compilation.abi;target=[string]$Inputs.compilation.target;snapshot_refs=@($Inputs.compilation.snapshot_refs|Sort-Object);policy_ref=[string]$Inputs.compilation.policy_ref}
  $realizationMaterial=[ordered]@{kind='RealizationKey';abi=[int]$Inputs.realization.abi;target=[string]$Inputs.realization.target;accepted_plan_refs=@($Inputs.realization.accepted_plan_refs|Sort-Object);candidate_sha256=([string]$Inputs.realization.candidate_sha256).ToUpperInvariant();executor_ref=[string]$Inputs.realization.executor_ref}
  $assertion=[pscustomobject][ordered]@{schema=1;id='mir4.w08.capture-status';version=1;type='status-equals';reads=@('facts.status');proposition='The projected observation was captured.';expected=[string]$Inputs.evaluation.expected_status}
  $evaluation=Invoke-MIRCPEvaluation -Observation $observation -Assertion $assertion -EvaluationAbi ([int]$Inputs.evaluation.abi)
  return [pscustomobject][ordered]@{
    kind='MIR4AssuranceIdentitySetV1';schema=1
    CaptureKey=[string]$observation.capture_key;CompilationKey=(Get-MIRCPSha256Object -Value $compilationMaterial)
    RealizationKey=(Get-MIRCPSha256Object -Value $realizationMaterial);EvaluationKey=[string]$evaluation.evaluation_key
    bindings=[ordered]@{capture_observation_sha256=(Get-MIRCPSha256Object -Value $observation);slice_aggregate_root=$Slices.aggregate_root_sha256;evaluation_status=[string]$evaluation.status}
  }
}

function Get-MIR4W08ImpactProjection {
  param([Parameter(Mandatory)][string[]]$ChangedPaths,[Parameter(Mandatory)][string]$RepoRoot)
  Import-MIR4W08ControlPlane -RepoRoot $RepoRoot
  $impact=Get-MIRCPSemanticImpact -ChangedPaths $ChangedPaths -RepoRoot $RepoRoot
  $plan=New-MIRCPPlan -Mode changed -ChangedPath $ChangedPaths -SelectionOnly -RepoRoot $RepoRoot
  return [pscustomobject][ordered]@{
    authority='mir-control-plane-v5';adapter_only=$true;changed_paths=@($impact.changed_paths);semantic_reads_writes=[ordered]@{modules=@($impact.modules);direct=@($impact.direct_domains);transitive=@($impact.affected_domains)}
    selected_tasks=@($plan.plan.tasks|ForEach-Object{[string]$_.id}|Sort-Object);selected_task_count=[int]$plan.plan.task_count
    governance_failure=[bool]$impact.governance_failure;unknown_paths=@($impact.unknown_paths);unknown_policy=[string]$impact.unknown_policy
  }
}

function Resolve-MIR4W08PartialRecovery {
  param([Parameter(Mandatory)][object[]]$Expected,[Parameter(Mandatory)][object[]]$Completed)
  $reusable=@();$pending=@();$blocked=@()
  foreach($expect in @($Expected|Sort-Object task_id)){
    $sameTask=@($Completed|Where-Object task_id -eq $expect.task_id)
    $exact=@($sameTask|Where-Object{
      [string]$_.identity_key-ceq[string]$expect.identity_key-and[string]$_.candidate_sha256-ceq[string]$expect.candidate_sha256-and[string]$_.target-ceq[string]$expect.target-and[int]$_.abi-eq[int]$expect.abi-and[string]$_.trust-ceq[string]$expect.trust-and[string]$_.status-ceq'passed'-and-not[bool]$_.revoked
    })
    if($exact.Count-eq 1){$reusable+=[ordered]@{task_id=[string]$expect.task_id;object_digest=[string]$exact[0].object_digest;decision='REUSE-EXACT'}}
    elseif($exact.Count-gt 1){$blocked+=[ordered]@{task_id=[string]$expect.task_id;reason='ambiguous-exact-evidence'}}
    else{$pending+=[ordered]@{task_id=[string]$expect.task_id;decision='RUN';reason=$(if($sameTask.Count){'identity-candidate-target-abi-trust-revocation-or-status-mismatch'}else{'missing'})}}
  }
  return [pscustomobject][ordered]@{policy='exact-identity-target-candidate-abi-trust-unrevoked-only';reusable=$reusable;pending=$pending;blocked=$blocked;status=$(if($blocked.Count){'blocked'}else{'recoverable'})}
}

function New-MIR4W08NondeterminismIncident {
  param([Parameter(Mandatory)][object[]]$Results)
  $groups=@($Results|Group-Object identity_key|Sort-Object Name)
  $incidents=@()
  foreach($group in $groups){
    $outcomes=@($group.Group|ForEach-Object{"$([string]$_.status):$([string]$_.result_digest)"}|Sort-Object -Unique)
    if($outcomes.Count-gt 1){$incidents+=[ordered]@{identity_key=[string]$group.Name;outcomes=$outcomes;result_count=$group.Count;disposition='block-and-quarantine-for-independent-reproduction'}}
  }
  return [pscustomobject][ordered]@{kind='MIR4NondeterminismIncidentSetV1';schema=1;incidents=$incidents;status=$(if($incidents.Count){'blocked-nondeterministic'}else{'deterministic'})}
}

function Reduce-MIR4W08Counterexample {
  param([Parameter(Mandatory)]$Counterexample)
  if([string]::IsNullOrWhiteSpace([string]$Counterexample.target)-or@($Counterexample.evidence_refs).Count-eq 0-or@($Counterexample.safety_constraints).Count-eq 0){throw '[mir4-w08-counterexample-binding]'}
  $minimal=@($Counterexample.elements|Where-Object required_for_witness|Sort-Object id|ForEach-Object{[ordered]@{id=[string]$_.id;value=$_.value;required_for_witness=$true}})
  if($minimal.Count-eq 0){throw '[mir4-w08-counterexample-empty-witness]'}
  return [pscustomobject][ordered]@{kind='MIR4CounterexampleV1';schema=1;target=[string]$Counterexample.target;witness=[string]$Counterexample.witness;evidence_refs=@($Counterexample.evidence_refs|Sort-Object -Unique);safety_constraints=@($Counterexample.safety_constraints|Sort-Object -Unique);original_count=@($Counterexample.elements).Count;minimal_count=$minimal.Count;elements=$minimal;proof_preserved=$true}
}

function New-MIR4W08ProofCover {
  param([Parameter(Mandatory)][object[]]$Obligations,[Parameter(Mandatory)][object[]]$Candidates)
  $obligationMap=@{};foreach($obligation in $Obligations){$id=[string]$obligation.id;if($obligationMap.ContainsKey($id)){throw "[mir4-w08-proof-obligation-duplicate] $id"};$obligationMap[$id]=$obligation}
  $uncovered=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($id in $obligationMap.Keys){[void]$uncovered.Add($id)}
  $selected=@();$rejected=@()
  while($uncovered.Count){
    $ranked=@()
    foreach($candidate in @($Candidates|Sort-Object id)){
      if([string]$candidate.id-in@($selected.id)){continue}
      $eligible=@()
      foreach($id in @($candidate.covers|ForEach-Object{[string]$_}|Sort-Object -Unique)){
        if(-not$obligationMap.ContainsKey($id)-or-not$uncovered.Contains($id)){continue}
        $obligation=$obligationMap[$id]
        if([string]$candidate.target-ceq[string]$obligation.target-and[string]$candidate.environment-ceq[string]$obligation.environment-and[string]$candidate.trust-ceq[string]$obligation.trust){$eligible+=$id}
      }
      if($eligible.Count){$ranked+=[pscustomobject]@{candidate=$candidate;eligible=@($eligible);score=$eligible.Count}}
    }
    $best=@($ranked|Sort-Object @{Expression='score';Descending=$true},@{Expression={$_.candidate.id};Descending=$false}|Select-Object -First 1)
    if($best.Count-eq 0){break}
    $selected+=[ordered]@{id=[string]$best[0].candidate.id;covers=@($best[0].eligible);target=[string]$best[0].candidate.target;environment=[string]$best[0].candidate.environment;trust=[string]$best[0].candidate.trust;action=[string]$best[0].candidate.action;evidence_digest=$best[0].candidate.evidence_digest}
    foreach($id in @($best[0].eligible)){[void]$uncovered.Remove($id)}
  }
  foreach($candidate in @($Candidates|Sort-Object id)){
    if([string]$candidate.id-in@($selected.id)){continue}
    $rejected+=[ordered]@{id=[string]$candidate.id;reason='duplicate-or-incompatible-target-environment-trust-cover'}
  }
  $uncoveredIds=@($uncovered|Sort-Object)
  return [pscustomobject][ordered]@{
    kind='MIR4ProofCoverPlanV1';schema=1;mandatory_obligations=@($obligationMap.Keys|Sort-Object);selected=$selected;rejected=$rejected;uncovered=$uncoveredIds
    fresh_proof=@($selected|Where-Object action -eq RUN|ForEach-Object id);reused_proof=@($selected|Where-Object action -eq REUSE|ForEach-Object id)
    status=$(if($uncoveredIds.Count){'blocked-uncovered-obligation'}else{'complete-proposal-only'});scheduling_authority=$false
  }
}

function New-MIR4W08AssuranceScaleResult {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$SourceIdentity,[Parameter(Mandatory)]$SliceInputs,
    [Parameter(Mandatory)]$IdentityInputs,[Parameter(Mandatory)]$ProofCoverFixture,[Parameter(Mandatory)]$RecoveryFixture
  )
  $repo=Get-MIR4W08RepoRoot $RepoRoot
  Import-MIR4W08ControlPlane -RepoRoot $repo
  $authority=Get-MIR4W08Authority -RepoRoot $repo
  $slices=New-MIR4W08SliceSet -SliceInputs $SliceInputs -RepoRoot $repo
  $identities=New-MIR4W08IdentitySet -Inputs $IdentityInputs -Slices $slices -RepoRoot $repo
  $impact=Get-MIR4W08ImpactProjection -ChangedPaths @('tools/lib/mir4/AssuranceScale.ps1') -RepoRoot $repo
  $calibration=Assert-MIRCPMutationCalibration -RepoRoot $repo
  $recovery=Resolve-MIR4W08PartialRecovery -Expected @($RecoveryFixture.expected) -Completed @($RecoveryFixture.completed)
  $incident=New-MIR4W08NondeterminismIncident -Results @(
    [pscustomobject]@{identity_key=('N'.PadRight(64,'N'));status='passed';result_digest=('1'.PadRight(64,'1'))},
    [pscustomobject]@{identity_key=('N'.PadRight(64,'N'));status='failed';result_digest=('2'.PadRight(64,'2'))}
  )
  $counterexample=Reduce-MIR4W08Counterexample -Counterexample ([pscustomobject][ordered]@{target='f210';witness='same-identity-conflicting-result';evidence_refs=@('fixture:nondeterminism-a','fixture:nondeterminism-b');safety_constraints=@('preserve-target','preserve-evidence');elements=@([pscustomobject]@{id='irrelevant-locale';value='x';required_for_witness=$false},[pscustomobject]@{id='identity';value='N';required_for_witness=$true},[pscustomobject]@{id='outcome-pair';value=@('passed','failed');required_for_witness=$true})})
  $proofCover=New-MIR4W08ProofCover -Obligations @($ProofCoverFixture.obligations) -Candidates @($ProofCoverFixture.candidates)
  $freshness=Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$authority.control_plane_authorities.freshness))|ConvertFrom-Json
  $revocation=Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$authority.control_plane_authorities.revocation))|ConvertFrom-Json
  $record=[pscustomobject][ordered]@{
    kind='MIR4AssuranceScaleResultV1';schema=1;programme_id=[string]$authority.programme_id;wave='W08';maturity='developer-preview';authority='read-only-control-plane-and-assurance-crosswalk';source_identity=$SourceIdentity
    identities=$identities;observation_slices=$slices;impact=$impact
    freshness_revocation=[ordered]@{freshness_authority=[string]$authority.control_plane_authorities.freshness;freshness_sha256=(Get-MIR4W08FileSha256 (Join-Path $repo ([string]$authority.control_plane_authorities.freshness)));freshness_classes=@($freshness.classes.PSObject.Properties.Name|Sort-Object);revocation_authority=[string]$authority.control_plane_authorities.revocation;revocation_sha256=(Get-MIR4W08FileSha256 (Join-Path $repo ([string]$authority.control_plane_authorities.revocation)));active_revocations=@($revocation.rules|Where-Object active).Count;override_authorized=$false}
    mutation_calibration=[ordered]@{authority=[string]$authority.control_plane_authorities.mutation_calibration;cases=[int]$calibration.cases;false_negative_budget=[int]$calibration.false_negative_budget;status='passed'}
    partial_recovery=$recovery;nondeterminism_incident=$incident;counterexample=$counterexample;proof_cover=$proofCover
    blockers=@($slices.slices|Where-Object status -eq unavailable|ForEach-Object{[string]$_.reason}|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}|Sort-Object -Unique)
    status=$(if($slices.complete-and$proofCover.status-eq'complete-proposal-only'-and-not$impact.governance_failure){'passed-projection-only'}else{'partial-with-bounded-blockers'})
    package_visible=$false;public_release_proof=$false;evidence_ledger_authority=$false;verification_plan_authority=$false;source_freeze_authorized=$false;production_signing_or_sealing_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  return Add-MIR4W08RecordSha256 $record
}
