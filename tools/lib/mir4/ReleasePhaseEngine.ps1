Set-StrictMode -Version Latest

$script:MIR4ReleasePhaseEngineVersion = 1
$script:MIR4ReleasePhaseOperations = @('Plan','DryRun','Execute','Resume','Verify','Compensate','Receipt')

function ConvertTo-MIR4ReleasePhaseCanonicalNode {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
      $result[$key] = ConvertTo-MIR4ReleasePhaseCanonicalNode $Value[$key]
    }
    return $result
  }
  if ($Value -isnot [string] -and $Value -is [Collections.IEnumerable]) {
    return @($Value | ForEach-Object { ConvertTo-MIR4ReleasePhaseCanonicalNode $_ })
  }
  $properties = @($Value.PSObject.Properties | Where-Object MemberType -in @('NoteProperty','Property'))
  if ($properties.Count -gt 0 -and $Value -isnot [ValueType] -and $Value -isnot [string]) {
    $result = [ordered]@{}
    foreach ($property in @($properties | Sort-Object Name -CaseSensitive)) {
      $result[[string]$property.Name] = ConvertTo-MIR4ReleasePhaseCanonicalNode $property.Value
    }
    return $result
  }
  if ($Value -is [DateTime] -or $Value -is [DateTimeOffset]) { return $Value.ToUniversalTime().ToString('o') }
  return $Value
}

function ConvertTo-MIR4ReleasePhaseCanonicalJson {
  param([Parameter(Mandatory)]$Value)
  return (ConvertTo-MIR4ReleasePhaseCanonicalNode $Value | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIR4ReleasePhaseSha256 {
  param([Parameter(Mandatory)]$Value)
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ReleasePhaseCanonicalJson $Value))
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-MIR4ReleasePhaseSelfHash {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$HashProperty)
  $material = [ordered]@{}
  foreach ($property in @($Record.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
    if ([string]$property.Name -cne $HashProperty) { $material[[string]$property.Name] = $property.Value }
  }
  return Get-MIR4ReleasePhaseSha256 $material
}

function Write-MIR4ReleasePhaseJsonCreateNew {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ReleasePhaseCanonicalJson $Value) + "`n")
  $stream = [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}

function Get-MIR4ReleasePhaseRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4ReleasePhaseOutputRoot {
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$OutputRoot='')
  $repo = Get-MIR4ReleasePhaseRepoRoot $RepoRoot
  $allowed = [IO.Path]::GetFullPath((Join-Path $repo 'build/mir4/release-phase-engine')).TrimEnd('\','/')
  $candidate = if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $allowed } elseif ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if (-not $candidate.Equals($allowed,$comparison) -and -not $candidate.StartsWith($allowed + [IO.Path]::DirectorySeparatorChar,$comparison)) {
    throw "[mir4-phase-engine-output-boundary] $candidate"
  }
  return $candidate
}

function Get-MIR4ReleasePhaseFileDescriptor {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  $repo = Get-MIR4ReleasePhaseRepoRoot $RepoRoot
  $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repo $Path)) }
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  $prefix = $repo.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($prefix,$comparison) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
    throw "[mir4-phase-engine-input-file] $Path"
  }
  $json = Get-Content -Raw -LiteralPath $full
  $json | ConvertFrom-Json -Depth 100 | Out-Null
  $item = Get-Item -LiteralPath $full
  return [pscustomobject][ordered]@{
    path=([IO.Path]::GetRelativePath($repo,$full)).Replace('\','/')
    sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
    bytes=[long]$item.Length
  }
}

function Get-MIR4ReleasePhaseContract {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4ReleasePhaseRepoRoot $RepoRoot
  $relative = '.mir/releases/waves/mir4-r0/MIR4-Release-Phase-Engine-ContractV1.json'
  $path = Join-Path $repo $relative
  $schema = Join-Path $repo 'spec/schemas/mir4-release-phase-engine-contract-v1.schema.json'
  $json = Get-Content -Raw -LiteralPath $path
  if (-not ($json | Test-Json -SchemaFile $schema)) { throw '[mir4-phase-engine-contract-schema]' }
  $contract = $json | ConvertFrom-Json -Depth 100
  return [pscustomobject][ordered]@{record=$contract;path=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()}
}

function Assert-MIR4ReleasePhaseAdapter {
  param([Parameter(Mandatory)]$Adapter,[Parameter(Mandatory)]$Contract)
  if ($null -eq $Adapter.PSObject.Properties['descriptor'] -or $Adapter.invoke -isnot [scriptblock]) { throw '[mir4-phase-engine-adapter-shape]' }
  $descriptor = $Adapter.descriptor
  if ([string]$descriptor.id -notmatch '^[a-z][a-z0-9.-]{2,79}$' -or [int]$descriptor.version -lt 1 -or
      [string]$descriptor.implementation_sha256 -cnotmatch '^[A-F0-9]{64}$' -or [bool]$descriptor.production_capable) {
    throw '[mir4-phase-engine-adapter-boundary]'
  }
  $allowedOperations = @('DryRun','Execute','Verify','Compensate')
  if (@($descriptor.supported_operations | Where-Object { [string]$_ -notin $allowedOperations }).Count -ne 0) { throw '[mir4-phase-engine-adapter-operation]' }
  $ports = @($Contract.record.ports)
  foreach ($required in @($descriptor.required_ports)) {
    $matches = @($ports | Where-Object { [string]$_.id -ceq [string]$required })
    if ($matches.Count -ne 1 -or [string]$matches[0].mode -ceq 'denied') { throw "[mir4-phase-engine-adapter-port] $required" }
  }
  return $descriptor
}

function New-MIR4ReleasePhasePlan {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Phase,
    [Parameter(Mandatory)]$Inputs,
    [Parameter(Mandatory)]$Adapter
  )
  $repo = Get-MIR4ReleasePhaseRepoRoot $RepoRoot
  $contract = Get-MIR4ReleasePhaseContract -RepoRoot $repo
  if ($Phase -cnotin @($contract.record.phases)) { throw "[mir4-phase-engine-phase] $Phase" }
  $descriptor = Assert-MIR4ReleasePhaseAdapter -Adapter $Adapter -Contract $contract
  foreach ($field in @('source_release_record','candidate_id','source_commit','source_tree','target_distribution_record_set','release_plan_digest','proof_root','seal_root')) {
    if ($null -eq $Inputs.PSObject.Properties[$field] -and $Inputs -isnot [Collections.IDictionary]) { throw "[mir4-phase-engine-input] $field" }
    if ($Inputs -is [Collections.IDictionary] -and -not $Inputs.Contains($field)) { throw "[mir4-phase-engine-input] $field" }
  }
  $candidateId = [string]$Inputs.candidate_id
  if ($candidateId -notmatch '^[A-Z0-9][A-Z0-9._-]{2,63}$' -or [string]$Inputs.source_commit -cnotmatch '^[0-9a-f]{40}$' -or
      [string]$Inputs.source_tree -cnotmatch '^[0-9a-f]{40}$' -or [string]$Inputs.release_plan_digest -cnotmatch '^[A-F0-9]{64}$' -or
      [string]::IsNullOrWhiteSpace([string]$Inputs.proof_root) -or [string]::IsNullOrWhiteSpace([string]$Inputs.seal_root)) {
    throw '[mir4-phase-engine-input-identity]'
  }
  $identity = [pscustomobject][ordered]@{
    source_release_record=Get-MIR4ReleasePhaseFileDescriptor -RepoRoot $repo -Path ([string]$Inputs.source_release_record)
    candidate_id=$candidateId
    source_commit=[string]$Inputs.source_commit
    source_tree=[string]$Inputs.source_tree
    target_distribution_record_set=Get-MIR4ReleasePhaseFileDescriptor -RepoRoot $repo -Path ([string]$Inputs.target_distribution_record_set)
    release_plan_digest=[string]$Inputs.release_plan_digest
    proof_root=[string]$Inputs.proof_root
    seal_root=[string]$Inputs.seal_root
  }
  $material = [pscustomobject][ordered]@{
    engine_version=$script:MIR4ReleasePhaseEngineVersion;phase=$Phase;identity=$identity
    adapter=$descriptor;contract_sha256=[string]$contract.sha256;ports=@($contract.record.ports)
  }
  $fingerprint = Get-MIR4ReleasePhaseSha256 $material
  $fields = [ordered]@{
    schema=1;kind='MIR4ReleasePhasePlanV1';engine_version=$script:MIR4ReleasePhaseEngineVersion
    attempt_id=('A-' + $fingerprint.Substring(0,32));phase=$Phase;phase_fingerprint=$fingerprint
    non_production=$true;production_authorized=$false;identity=$identity;adapter=$descriptor
    contract=[pscustomobject][ordered]@{path=[string]$contract.path;sha256=[string]$contract.sha256}
    ports=@($contract.record.ports);operation_order=@($script:MIR4ReleasePhaseOperations);plan_sha256=''
  }
  $plan = [pscustomobject]$fields
  $plan.plan_sha256 = Get-MIR4ReleasePhaseSelfHash -Record $plan -HashProperty 'plan_sha256'
  return $plan
}

function Read-MIR4ReleasePhaseEvents {
  param([Parameter(Mandatory)][string]$AttemptRoot,[Parameter(Mandatory)]$Plan)
  $eventRoot = Join-Path $AttemptRoot 'events'
  if (-not (Test-Path -LiteralPath $eventRoot -PathType Container)) { return @() }
  $events = @()
  $prior = 'GENESIS'
  $sequence = 0
  foreach ($path in @(Get-ChildItem -LiteralPath $eventRoot -Filter '*.json' -File | Sort-Object Name)) {
    $event = Get-Content -Raw -LiteralPath $path.FullName | ConvertFrom-Json -Depth 100
    $sequence++
    if ([int]$event.sequence -ne $sequence -or [string]$event.attempt_id -cne [string]$Plan.attempt_id -or
        [string]$event.phase_fingerprint -cne [string]$Plan.phase_fingerprint -or [string]$event.previous_event_sha256 -cne $prior -or
        [string]$event.record_sha256 -cne (Get-MIR4ReleasePhaseSelfHash -Record $event -HashProperty 'record_sha256')) {
      throw "[mir4-phase-engine-event-chain] $($path.Name)"
    }
    $prior = [string]$event.record_sha256
    $events += $event
  }
  return @($events)
}

function Get-MIR4ReleasePhaseAttemptState {
  param([Parameter(Mandatory)][string]$AttemptRoot)
  $planPath = Join-Path $AttemptRoot 'plan.json'
  $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json -Depth 100
  if ([string]$plan.plan_sha256 -cne (Get-MIR4ReleasePhaseSelfHash -Record $plan -HashProperty 'plan_sha256')) { throw '[mir4-phase-engine-plan-hash]' }
  $events = @(Read-MIR4ReleasePhaseEvents -AttemptRoot $AttemptRoot -Plan $plan)
  $state = 'new'; $lastFailed = ''
  foreach ($event in $events) {
    if ([string]$event.status -ceq 'failed') { $lastFailed=[string]$event.operation; continue }
    $lastFailed=''
    switch ([string]$event.operation) {
      'Plan' { if($state-cne'new'){throw '[mir4-phase-engine-transition]'}; $state='planned' }
      'DryRun' { if($state-cne'planned'){throw '[mir4-phase-engine-transition]'}; $state='dry-run-passed' }
      'Execute' { if($state-cne'dry-run-passed'){throw '[mir4-phase-engine-transition]'}; $state='executed' }
      'Verify' { if($state-cne'executed'){throw '[mir4-phase-engine-transition]'}; $state='verified' }
      'Compensate' { if($state-cne'executed'){throw '[mir4-phase-engine-transition]'}; $state='compensated' }
      'Receipt' { if($state-cnotin@('verified','compensated')){throw '[mir4-phase-engine-transition]'}; $state='complete' }
      default { throw '[mir4-phase-engine-event-operation]' }
    }
  }
  return [pscustomobject][ordered]@{plan=$plan;events=$events;state=$state;last_failed_operation=$lastFailed;last_event_sha256=$(if($events.Count){[string]$events[-1].record_sha256}else{'GENESIS'})}
}

function Add-MIR4ReleasePhaseEvent {
  param([Parameter(Mandatory)][string]$AttemptRoot,[Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$Operation,[Parameter(Mandatory)][string]$Status,[Parameter(Mandatory)]$Result)
  $sequence = @($State.events).Count + 1
  $idempotencyKey = Get-MIR4ReleasePhaseSha256 ([ordered]@{attempt_id=[string]$State.plan.attempt_id;operation=$Operation})
  $fields = [ordered]@{
    schema=1;kind='MIR4ReleasePhaseEventV1';attempt_id=[string]$State.plan.attempt_id
    phase_fingerprint=[string]$State.plan.phase_fingerprint;sequence=$sequence;operation=$Operation;status=$Status
    idempotency_key=$idempotencyKey;previous_event_sha256=[string]$State.last_event_sha256
    result_sha256=(Get-MIR4ReleasePhaseSha256 $Result);result=$Result;recorded_at=[DateTime]::UtcNow.ToString('o');record_sha256=''
  }
  $event=[pscustomobject]$fields
  $event.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $event -HashProperty 'record_sha256'
  $path=Join-Path $AttemptRoot ('events/{0:D6}-{1}.json' -f $sequence,$Operation.ToLowerInvariant())
  Write-MIR4ReleasePhaseJsonCreateNew -Value $event -Path $path
  return $event
}

function Invoke-MIR4ReleasePhaseLocked {
  param([Parameter(Mandatory)][string]$AttemptRoot,[Parameter(Mandatory)][scriptblock]$Action)
  $lockPath=Join-Path $AttemptRoot 'attempt.lock'
  try { $stream=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
  catch { throw '[mir4-phase-engine-attempt-busy]' }
  try { return & $Action } finally { $stream.Dispose() }
}

function Invoke-MIR4ReleasePhaseEngine {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('Plan','DryRun','Execute','Resume','Verify','Compensate','Receipt')][string]$Operation,
    [Parameter(Mandatory)][string]$Phase,
    [Parameter(Mandatory)]$Inputs,
    [Parameter(Mandatory)]$Adapter,
    [string]$OutputRoot=''
  )
  $repo=Get-MIR4ReleasePhaseRepoRoot $RepoRoot
  $root=Get-MIR4ReleasePhaseOutputRoot -RepoRoot $repo -OutputRoot $OutputRoot
  $expectedPlan=New-MIR4ReleasePhasePlan -RepoRoot $repo -Phase $Phase -Inputs $Inputs -Adapter $Adapter
  $attemptRoot=Join-Path $root ([string]$expectedPlan.attempt_id)
  New-Item -ItemType Directory -Path $attemptRoot -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $attemptRoot 'events') -Force | Out-Null
  return Invoke-MIR4ReleasePhaseLocked -AttemptRoot $attemptRoot -Action {
    $planPath=Join-Path $attemptRoot 'plan.json'
    if (Test-Path -LiteralPath $planPath -PathType Leaf) {
      $existing=Get-Content -Raw -LiteralPath $planPath|ConvertFrom-Json -Depth 100
      if ((ConvertTo-MIR4ReleasePhaseCanonicalJson $existing)-cne(ConvertTo-MIR4ReleasePhaseCanonicalJson $expectedPlan)) { throw '[mir4-phase-engine-fingerprint-divergence]' }
    } else { Write-MIR4ReleasePhaseJsonCreateNew -Value $expectedPlan -Path $planPath }
    $state=Get-MIR4ReleasePhaseAttemptState -AttemptRoot $attemptRoot
    if ($state.state-ceq'new') {
      Add-MIR4ReleasePhaseEvent -AttemptRoot $attemptRoot -State $state -Operation Plan -Status passed -Result ([ordered]@{plan_sha256=[string]$expectedPlan.plan_sha256;mutation_performed=$false})|Out-Null
      $state=Get-MIR4ReleasePhaseAttemptState -AttemptRoot $attemptRoot
    }
    if ($Operation-ceq'Plan') { return [pscustomobject][ordered]@{attempt_root=$attemptRoot;plan=$state.plan;state=$state.state;events=@($state.events)} }
    if ($Operation-ceq'Resume') {
      $Operation=if(-not[string]::IsNullOrWhiteSpace([string]$state.last_failed_operation)){[string]$state.last_failed_operation}else{switch($state.state){'planned'{'DryRun'}'dry-run-passed'{'Execute'}'executed'{'Verify'}'verified'{'Receipt'}'compensated'{'Receipt'}'complete'{'Receipt'}default{throw '[mir4-phase-engine-resume-state]'}}}
    }
    if ($Operation-ceq'Receipt' -and $state.state-ceq'complete') {
      return Get-Content -Raw -LiteralPath (Join-Path $attemptRoot 'receipt.json')|ConvertFrom-Json -Depth 100
    }
    $requiredState=@{DryRun='planned';Execute='dry-run-passed';Verify='executed';Compensate='executed';Receipt=@('verified','compensated')}[$Operation]
    if ($Operation-cne'Receipt' -and @($state.events|Where-Object{[string]$_.operation-ceq$Operation-and[string]$_.status-ceq'passed'}).Count-ne0) {
      return [pscustomobject][ordered]@{attempt_root=$attemptRoot;plan=$state.plan;state=$state.state;events=@($state.events);idempotent_reuse=$true}
    }
    if ($state.state -cnotin @($requiredState)) { throw "[mir4-phase-engine-operation-state] $Operation/$($state.state)" }
    if ($Operation-ceq'Receipt') {
      $receiptFields=[ordered]@{schema=1;kind='MIR4ReleasePhaseReceiptV1';attempt_id=[string]$state.plan.attempt_id;phase=[string]$state.plan.phase;phase_fingerprint=[string]$state.plan.phase_fingerprint;final_state=[string]$state.state;event_count=@($state.events).Count;event_chain_sha256=(Get-MIR4ReleasePhaseSha256 @($state.events.record_sha256));non_production=$true;production_authorized=$false;receipt_sha256=''}
      $receipt=[pscustomobject]$receiptFields;$receipt.receipt_sha256=Get-MIR4ReleasePhaseSelfHash -Record $receipt -HashProperty receipt_sha256
      $receiptPath=Join-Path $attemptRoot 'receipt.json'
      if(-not(Test-Path -LiteralPath $receiptPath)){Write-MIR4ReleasePhaseJsonCreateNew -Value $receipt -Path $receiptPath}
      Add-MIR4ReleasePhaseEvent -AttemptRoot $attemptRoot -State $state -Operation Receipt -Status passed -Result ([ordered]@{receipt_sha256=[string]$receipt.receipt_sha256;mutation_performed=$false})|Out-Null
      return $receipt
    }
    if ($Operation-cnotin @($state.plan.adapter.supported_operations)) { throw "[mir4-phase-engine-adapter-unsupported] $Operation" }
    $idempotencyKey=Get-MIR4ReleasePhaseSha256 ([ordered]@{attempt_id=[string]$state.plan.attempt_id;operation=$Operation})
    $artifactRoot=Join-Path $attemptRoot ('artifacts/'+$Operation.ToLowerInvariant())
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    $context=[pscustomobject][ordered]@{schema=1;kind='MIR4ReleasePhaseAdapterContextV1';operation=$Operation;idempotency_key=$idempotencyKey;attempt_root=$attemptRoot;artifact_root=$artifactRoot;plan=$state.plan;ports=@($state.plan.ports);non_production=$true;production_authorized=$false}
    try {
      $result=& $Adapter.invoke $context
      if($null-eq$result-or[string]$result.kind-cne'MIR4ReleasePhaseAdapterResultV1'-or[string]$result.operation-cne$Operation-or[string]$result.status-cne'passed'-or[string]$result.idempotency_key-cne$idempotencyKey-or[bool]$result.production_mutation_performed){throw '[mir4-phase-engine-adapter-result]'}
      Add-MIR4ReleasePhaseEvent -AttemptRoot $attemptRoot -State $state -Operation $Operation -Status passed -Result $result|Out-Null
    } catch {
      $failure=[ordered]@{kind='MIR4ReleasePhaseAdapterFailureV1';operation=$Operation;idempotency_key=$idempotencyKey;message=$_.Exception.Message;production_mutation_performed=$false}
      Add-MIR4ReleasePhaseEvent -AttemptRoot $attemptRoot -State $state -Operation $Operation -Status failed -Result $failure|Out-Null
      throw
    }
    $complete=Get-MIR4ReleasePhaseAttemptState -AttemptRoot $attemptRoot
    return [pscustomobject][ordered]@{attempt_root=$attemptRoot;plan=$complete.plan;state=$complete.state;events=@($complete.events);idempotent_reuse=$false}
  }
}
