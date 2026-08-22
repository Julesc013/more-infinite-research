function Get-MIR4W08ReleaseBudgetAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  if($null-eq(Get-Command Get-MIR4W08Authority -CommandType Function -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'AssuranceScale.ps1')}
  return Get-MIR4W08Authority -RepoRoot $RepoRoot
}

function Get-MIR4W08CriticalPath {
  param([Parameter(Mandatory)][object[]]$Tasks)
  $map=@{};foreach($task in $Tasks){$id=[string]$task.id;if($map.ContainsKey($id)){throw "[mir4-w08-budget-duplicate-task] $id"};if([int]$task.p95_seconds-lt 0){throw "[mir4-w08-budget-duration] $id"};$map[$id]=$task}
  foreach($task in $Tasks){foreach($dependency in @($task.depends_on)){if(-not$map.ContainsKey([string]$dependency)){throw "[mir4-w08-budget-dependency] $($task.id):$dependency"}}}
  $remaining=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($id in $map.Keys){[void]$remaining.Add($id)}
  $finish=@{};$predecessor=@{};$order=@()
  while($remaining.Count){
    $ready=@($remaining|Where-Object{$id=$_;@($map[$id].depends_on|Where-Object{$remaining.Contains([string]$_)}).Count-eq 0}|Sort-Object)
    if(-not$ready.Count){throw '[mir4-w08-budget-cycle]'}
    foreach($id in $ready){
      $deps=@($map[$id].depends_on|ForEach-Object{[string]$_})
      $longest=@($deps|Sort-Object @{Expression={[int]$finish[$_]};Descending=$true},@{Expression={$_}}|Select-Object -First 1)
      $base=if($longest.Count){[int]$finish[$longest[0]]}else{0}
      $finish[$id]=$base+[int]$map[$id].p95_seconds;$predecessor[$id]=if($longest.Count){[string]$longest[0]}else{''}
      $order+=$id;[void]$remaining.Remove($id)
    }
  }
  if(-not$order.Count){return [pscustomobject][ordered]@{task_ids=@();seconds=0}}
  $last=@($order|Sort-Object @{Expression={[int]$finish[$_]};Descending=$true},@{Expression={$_}}|Select-Object -First 1)[0]
  $path=@();$cursor=[string]$last;while($cursor){$path=@($cursor)+$path;$cursor=[string]$predecessor[$cursor]}
  return [pscustomobject][ordered]@{task_ids=$path;seconds=[int]$finish[$last]}
}

function New-MIR4W08ReleaseBudgetPlan {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$SourceIdentity,[Parameter(Mandatory)][string[]]$AffectedTargets,
    [Parameter(Mandatory)]$ProofCover,$TimingEvidence=$null,$CapacityEvidence=$null
  )
  $authority=Get-MIR4W08ReleaseBudgetAuthority -RepoRoot $RepoRoot
  $timingTrusted=$null-ne$TimingEvidence-and[bool]$TimingEvidence.trusted-and@($TimingEvidence.tasks).Count-gt 0
  $capacityTrusted=$null-ne$CapacityEvidence-and[bool]$CapacityEvidence.trusted-and[int]$CapacityEvidence.workers-gt 0
  $critical=if($timingTrusted){Get-MIR4W08CriticalPath -Tasks @($TimingEvidence.tasks)}else{[pscustomobject][ordered]@{task_ids=@();seconds=$null}}
  $deadlines=@()
  foreach($deadline in @($authority.deadline_classes)){
    $estimate=if($timingTrusted){[int]$critical.seconds}else{$null}
    $headroom=if($null-ne$estimate){[int]$deadline.hard_seconds-$estimate}else{$null}
    $rowBlockers=@()
    if(-not$timingTrusted){$rowBlockers+='BLOCKED-MISSING-TIMING-EVIDENCE'}
    if(-not$capacityTrusted){$rowBlockers+='BLOCKED-MISSING-WORKER-CAPACITY-EVIDENCE'}
    if(@($ProofCover.uncovered).Count){$rowBlockers+='BLOCKED-UNCOVERED-PROOF-OBLIGATION'}
    if($null-ne$headroom-and$headroom-lt 0){$rowBlockers+='BLOCKED-DEADLINE-EXCEEDED'}
    $deadlines+=[ordered]@{
      change_class=[string]$deadline.id;hard_seconds=[int]$deadline.hard_seconds;design_p95_seconds=[int]$deadline.design_p95_seconds;design_headroom_seconds=[int]$deadline.design_headroom_seconds
      estimated_p95_seconds=$estimate;estimated_headroom_seconds=$headroom;critical_path=[ordered]@{task_ids=@($critical.task_ids);seconds=$critical.seconds}
      status=$(if($rowBlockers.Count){$rowBlockers[0]}else{'design-model-feasible-nonrelease'});blockers=$rowBlockers
    }
  }
  $record=[pscustomobject][ordered]@{
    kind='MIR4ReleaseBudgetPlanV1';schema=1;programme_id=[string]$authority.programme_id;wave='W08';maturity='shadow-design-model';source_identity=$SourceIdentity
    affected_targets=@($AffectedTargets|Sort-Object -Unique);fresh_proof=@($ProofCover.fresh_proof|Sort-Object);reused_proof=@($ProofCover.reused_proof|Sort-Object)
    deadlines=$deadlines;manual_requirements=@($authority.manual_requirements)
    worker_capacity=[ordered]@{workers=$(if($capacityTrusted){[int]$CapacityEvidence.workers}else{$null});trusted=$capacityTrusted;status=$(if($capacityTrusted){'available-for-design-model'}else{'BLOCKED-MISSING-WORKER-CAPACITY-EVIDENCE'})}
    timing_evidence=[ordered]@{trusted=$timingTrusted;task_count=$(if($timingTrusted){@($TimingEvidence.tasks).Count}else{0});status=$(if($timingTrusted){'available-for-design-model'}else{'BLOCKED-MISSING-TIMING-EVIDENCE'})}
    status=$(if(@($deadlines|Where-Object blockers|ForEach-Object{@($_.blockers)}).Count){'partial-with-bounded-blockers'}else{'passed-design-model-only'})
    package_visible=$false;public_release_proof=$false;deadline_certification=$false;source_freeze_authorized=$false;production_signing_or_sealing_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  return Add-MIR4W08RecordSha256 $record
}
