function Get-MIR4ProcessIRRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function ConvertTo-MIR4ProcessIRCanonicalValue {
  param([AllowNull()]$Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) { return $Value }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
      $result[$key] = ConvertTo-MIR4ProcessIRCanonicalValue $Value[$key]
    }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
      $result[$property.Name] = ConvertTo-MIR4ProcessIRCanonicalValue $property.Value
    }
    return $result
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    Write-Output -NoEnumerate @($Value | ForEach-Object { ConvertTo-MIR4ProcessIRCanonicalValue $_ })
    return
  }
  return $Value
}

function ConvertTo-MIR4ProcessIRCanonicalJson {
  param([Parameter(Mandatory)]$Value)
  return ((ConvertTo-MIR4ProcessIRCanonicalValue $Value) | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIR4ProcessIRDigest {
  param([Parameter(Mandatory)]$Value)
  $material = [ordered]@{}
  if ($Value -is [Collections.IDictionary]) {
    foreach ($key in $Value.Keys) { if ([string]$key -cne 'digest') { $material[[string]$key] = $Value[$key] } }
  } else {
    foreach ($property in $Value.PSObject.Properties) { if ($property.Name -cne 'digest') { $material[$property.Name] = $property.Value } }
  }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ProcessIRCanonicalJson $material))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return 'sha256:' + ([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()) }
  finally { $sha.Dispose() }
}

function Add-MIR4ProcessIRDigest {
  param([Parameter(Mandatory)]$Value)
  if ($Value -is [Collections.IDictionary]) { $Value['digest'] = Get-MIR4ProcessIRDigest $Value }
  else { $Value.digest = Get-MIR4ProcessIRDigest $Value }
  return $Value
}

function Copy-MIR4ProcessIRValue {
  param([AllowNull()]$Value)
  if ($null -eq $Value) { return $null }
  return (ConvertTo-MIR4ProcessIRCanonicalJson $Value) | ConvertFrom-Json
}

function Get-MIR4ProcessIRSynthesisAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4ProcessIRRepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json'
  $authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4ProcessIRSynthesisProgrammeV1') { throw '[mir4-processir-authority-schema]' }
  if (@($authority.candidate_constructors).Count -ne 10 -or @($authority.terminal_dispositions).Count -ne 5 -or @($authority.modes).Count -ne 3 -or @($authority.effect_channels).Count -ne 6) { throw '[mir4-processir-authority-counts]' }
  if ($authority.semantic_authority -or $authority.canonical_recipe_fact_authority -or $authority.canonical_risk_fact_authority -or $authority.player_mutation_authorized -or $authority.prototype_write_authorized -or $authority.runtime_state_mutation_authorized -or $authority.migration_execution_authorized -or $authority.planner_or_emitter_admission_authorized -or $authority.safety_kernel_override_authorized -or $authority.public_support_authorized -or $authority.signing_or_sealing_authorized -or $authority.publication_authorized) { throw '[mir4-processir-authority-boundary]' }
  return $authority
}

function Test-MIR4CanonicalRecipeFactInputV1 {
  param([Parameter(Mandatory)]$InputRecord,[Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4ProcessIRRepoRoot $RepoRoot
  $schemaPath = Join-Path $repo 'spec/schemas/mir4-canonical-recipe-fact-input-v1.schema.json'
  try { $valid = (($InputRecord | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath -ErrorAction Stop) }
  catch { throw '[mir4-processir-input-schema] Canonical recipe/risk fact input schema validation failed.' }
  if (-not $valid) { throw '[mir4-processir-input-schema] Canonical recipe/risk fact input schema validation failed.' }
  $ids = @($InputRecord.processes | ForEach-Object { [string]$_.id })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw '[mir4-processir-duplicate-process]' }
  foreach ($process in @($InputRecord.processes)) {
    foreach ($flow in @($process.inputs) + @($process.outputs)) {
      foreach ($quantity in @($flow.amount, $flow.probability)) {
        if ([string]$quantity.kind -eq 'bounded' -and [decimal]$quantity.min -gt [decimal]$quantity.max) { throw "[mir4-processir-invalid-bound] $($process.id)" }
      }
    }
  }
  return $true
}

function Read-MIR4CanonicalRecipeFactInputV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  $repo = Get-MIR4ProcessIRRepoRoot $RepoRoot
  $fullPath = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "[mir4-processir-fixture-missing] $Path" }
  $record = Get-Content -Raw -LiteralPath $fullPath | ConvertFrom-Json
  Test-MIR4CanonicalRecipeFactInputV1 -InputRecord $record -RepoRoot $repo | Out-Null
  return $record
}

function ConvertTo-MIR4ProcessIRQuantity {
  param([Parameter(Mandatory)]$Quantity)
  if ([string]$Quantity.kind -eq 'exact') { return [ordered]@{kind='exact';value=[decimal]$Quantity.value} }
  return [ordered]@{kind='bounded';min=[decimal]$Quantity.min;max=[decimal]$Quantity.max}
}

function ConvertTo-MIR4ProcessIRFlow {
  param([Parameter(Mandatory)]$Flow)
  return [ordered]@{
    type=[string]$Flow.type
    name=[string]$Flow.name
    amount=(ConvertTo-MIR4ProcessIRQuantity $Flow.amount)
    probability=(ConvertTo-MIR4ProcessIRQuantity $Flow.probability)
    productivity_sensitive=[bool]$Flow.productivity_sensitive
    catalyst_amount=$(if($null-ne$Flow.catalyst_amount){[decimal]$Flow.catalyst_amount}else{[decimal]0})
    ignored_by_productivity=$(if($null-ne$Flow.ignored_by_productivity){[decimal]$Flow.ignored_by_productivity}else{[decimal]0})
    temperature=$(if($null-ne$Flow.temperature){Copy-MIR4ProcessIRValue $Flow.temperature}else{[ordered]@{status='unavailable'}})
    quality=$(if($null-ne$Flow.quality){Copy-MIR4ProcessIRValue $Flow.quality}else{[ordered]@{status='unavailable'}})
  }
}

function Get-MIR4ProcessIRFlowKey {
  param([Parameter(Mandatory)]$Flow)
  return ([string]$Flow.type + ':' + [string]$Flow.name)
}

function Get-MIR4MinimalCycleWitness {
  param([Parameter(Mandatory)][hashtable]$Adjacency,[Parameter(Mandatory)][string[]]$Nodes)
  $allowed = @{}; foreach ($node in $Nodes) { $allowed[$node] = $true }
  $candidates = @()
  foreach ($start in @($Nodes | Sort-Object -CaseSensitive)) {
    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([object]@($start))
    $seen = @{$start=$true}
    $found = $null
    :cycleSearch while ($queue.Count -gt 0) {
      $path = @($queue.Dequeue())
      $last = [string]$path[-1]
      foreach ($next in @($Adjacency[$last] | Where-Object { $allowed.ContainsKey([string]$_) } | Sort-Object -CaseSensitive)) {
        $nextValue = [string]$next
        if ($nextValue -ceq $start) {
          $found = @($path + $start)
          break cycleSearch
        } elseif (-not $seen.ContainsKey($nextValue)) {
          $seen[$nextValue] = $true
          $queue.Enqueue([object]@($path + $nextValue))
        }
      }
    }
    if ($null -ne $found) { $candidates += [pscustomobject]@{edge_count=$found.Count-1;key=($found -join '>');nodes=$found} }
  }
  if ($candidates.Count -eq 0) { return @($Nodes | Sort-Object -CaseSensitive) }
  return @(($candidates | Sort-Object edge_count,key | Select-Object -First 1).nodes)
}

function Get-MIR4ProcessIRSccs {
  param([Parameter(Mandatory)][hashtable]$Adjacency,[Parameter(Mandatory)]$ProcessById)
  $nodes = @($Adjacency.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)
  $reach = @{}
  foreach ($start in $nodes) {
    $seen = @{}; $stack = [Collections.Generic.Stack[string]]::new(); $stack.Push($start)
    while ($stack.Count -gt 0) {
      $node = $stack.Pop()
      if ($seen.ContainsKey($node)) { continue }
      $seen[$node] = $true
      foreach ($next in @($Adjacency[$node] | Sort-Object -Descending -CaseSensitive)) { if (-not $seen.ContainsKey([string]$next)) { $stack.Push([string]$next) } }
    }
    $reach[$start] = $seen
  }
  $assigned = @{}; $sccs = @(); $ordinal = 0
  foreach ($start in $nodes) {
    if ($assigned.ContainsKey($start)) { continue }
    $component = @($nodes | Where-Object { $reach[$start].ContainsKey($_) -and $reach[$_].ContainsKey($start) } | Sort-Object -CaseSensitive)
    foreach ($node in $component) { $assigned[$node] = $true }
    $selfLoop = $component.Count -eq 1 -and $component[0] -in @($Adjacency[$component[0]])
    if ($component.Count -le 1 -and -not $selfLoop) { continue }
    $ordinal++
    $members = @($component | ForEach-Object { $ProcessById[[string]$_] })
    $hardUnsafe = @($members | Where-Object { 'unbounded-positive-cycle' -in @($_.risk.hard_flags) -or [string]$_.cycle_bound -eq 'unbounded' }).Count -gt 0
    $allBounded = @($members | Where-Object { [string]$_.cycle_bound -ne 'bounded' }).Count -eq 0
    $classification = if ($hardUnsafe) { 'UNSAFE' } elseif ($allBounded) { 'CERTIFIED_BOUNDED' } else { 'UNKNOWN' }
    $witness = @(Get-MIR4MinimalCycleWitness -Adjacency $Adjacency -Nodes $component)
    $row = [ordered]@{
      id=('scc-{0:d3}' -f $ordinal)
      nodes=$component
      classification=$classification
      minimal_witness=$witness
      witness_edge_count=[Math]::Max(0,$witness.Count-1)
      input_order_invariant=$true
      digest=''
    }
    Add-MIR4ProcessIRDigest $row | Out-Null
    $sccs += [pscustomobject]$row
  }
  return @($sccs)
}

function New-MIR4ProcessIRV1 {
  param([Parameter(Mandatory)]$InputRecord,[Parameter(Mandatory)][string]$RepoRoot)
  Test-MIR4CanonicalRecipeFactInputV1 -InputRecord $InputRecord -RepoRoot $RepoRoot | Out-Null
  $processes = @(); $processById = @{}
  foreach ($sourceProcess in @($InputRecord.processes | Sort-Object id -CaseSensitive)) {
    $inputs = @($sourceProcess.inputs | ForEach-Object { ConvertTo-MIR4ProcessIRFlow $_ } | Sort-Object type,name)
    $outputs = @($sourceProcess.outputs | ForEach-Object { ConvertTo-MIR4ProcessIRFlow $_ } | Sort-Object type,name)
    $inputKeys = @($inputs | ForEach-Object { Get-MIR4ProcessIRFlowKey $_ } | Sort-Object -Unique -CaseSensitive)
    $outputKeys = @($outputs | ForEach-Object { Get-MIR4ProcessIRFlowKey $_ } | Sort-Object -Unique -CaseSensitive)
    $intersection = @($inputKeys | Where-Object { $_ -in $outputKeys } | Sort-Object -Unique -CaseSensitive)
    $hardFlags = @($sourceProcess.risk.hard_flags | ForEach-Object { [string]$_ } | Sort-Object -Unique -CaseSensitive)
    $reviewFlags = @($sourceProcess.risk.review_flags | ForEach-Object { [string]$_ } | Sort-Object -Unique -CaseSensitive)
    $certainty = if ($hardFlags.Count -gt 0 -or [string]$sourceProcess.cycle_bound -eq 'unbounded') { 'UNSAFE' } elseif (-not [bool]$sourceProcess.shape_supported -or [string]$sourceProcess.risk.confidence -ne 'complete' -or [string]$sourceProcess.cycle_bound -eq 'unknown') { 'UNKNOWN' } elseif ($reviewFlags.Count -gt 0) { 'REVIEW_REQUIRED' } else { 'CERTIFIED_SAFE' }
    $identityMaterial = [ordered]@{target=[string]$InputRecord.source.target;profile=[string]$InputRecord.source.profile;recipe=[string]$sourceProcess.recipe;variant=[string]$sourceProcess.variant;fact_id=[string]$sourceProcess.id;recipe_facts_sha256=[string]$InputRecord.source.recipe_facts_sha256}
    $identity = [ordered]@{id=([string]$sourceProcess.id);target=[string]$InputRecord.source.target;profile=[string]$InputRecord.source.profile;recipe=[string]$sourceProcess.recipe;variant=[string]$sourceProcess.variant;source_fingerprint=(Get-MIR4ProcessIRDigest $identityMaterial)}
    $row = [ordered]@{
      identity=$identity
      classification=[string]$sourceProcess.classification
      inputs=$inputs
      outputs=$outputs
      exact_and_bounded_quantities=$true
      productivity_sensitive=(@($inputs + $outputs | Where-Object { $_.productivity_sensitive }).Count -gt 0)
      catalysts=@($sourceProcess.catalysts | ForEach-Object { [string]$_ } | Sort-Object -Unique -CaseSensitive)
      returned_containers=@($sourceProcess.returned_containers | ForEach-Object { [string]$_ } | Sort-Object -Unique -CaseSensitive)
      basic_recycling=([string]$sourceProcess.classification -eq 'recycling')
      basic_recovery=([string]$sourceProcess.classification -eq 'recovery')
      self_intersection=$intersection
      shape_supported=[bool]$sourceProcess.shape_supported
      cycle_bound=[string]$sourceProcess.cycle_bound
      categories=@($sourceProcess.categories|ForEach-Object{[string]$_}|Sort-Object -Unique -CaseSensitive)
      machines=@($sourceProcess.machines|ForEach-Object{[string]$_}|Sort-Object -Unique -CaseSensitive)
      surface_conditions=(Copy-MIR4ProcessIRValue $sourceProcess.surface_conditions)
      unlocks=@($sourceProcess.unlocks|ForEach-Object{[string]$_}|Sort-Object -Unique -CaseSensitive)
      owners=@($sourceProcess.owners|ForEach-Object{[string]$_}|Sort-Object -Unique -CaseSensitive)
      source_mod=(Copy-MIR4ProcessIRValue $sourceProcess.source_mod)
      energy_required=$sourceProcess.energy_required
      risk=[ordered]@{fingerprint=[string]$sourceProcess.risk.fingerprint;terminal_fingerprint=$(if($sourceProcess.risk.terminal_fingerprint){[string]$sourceProcess.risk.terminal_fingerprint}else{$null});confidence=[string]$sourceProcess.risk.confidence;hard_flags=$hardFlags;review_flags=$reviewFlags;evidence=@($sourceProcess.risk.evidence|ForEach-Object{[string]$_}|Sort-Object -Unique -CaseSensitive);copied_not_reclassified=$true}
      certainty=$certainty
      disposition=$(if($certainty -eq 'UNSAFE'){'FailHardSafety'}elseif($certainty -eq 'UNKNOWN'){'RequestReview'}elseif($certainty -eq 'REVIEW_REQUIRED'){'RequestReview'}else{'Preserve'})
      safety_status='pending-graph-evaluation'
      digest=''
    }
    Add-MIR4ProcessIRDigest $row | Out-Null
    $object = [pscustomobject]$row
    $processes += $object; $processById[[string]$sourceProcess.id] = $object
  }

  $inputOwners = @{}
  foreach ($process in $processes) {
    foreach ($flow in @($process.inputs)) {
      $key = Get-MIR4ProcessIRFlowKey $flow
      if (-not $inputOwners.ContainsKey($key)) { $inputOwners[$key] = @() }
      $inputOwners[$key] = @($inputOwners[$key] + [string]$process.identity.id | Sort-Object -Unique -CaseSensitive)
    }
  }
  $adjacency = @{}
  foreach ($process in $processes) {
    $id = [string]$process.identity.id; $neighbors = @()
    foreach ($flow in @($process.outputs)) {
      $key = Get-MIR4ProcessIRFlowKey $flow
      if ($inputOwners.ContainsKey($key)) { $neighbors += @($inputOwners[$key]) }
    }
    $adjacency[$id] = @($neighbors | Sort-Object -Unique -CaseSensitive)
  }
  $sccs = @(Get-MIR4ProcessIRSccs -Adjacency $adjacency -ProcessById $processById)
  foreach ($process in $processes) {
    $membership = @($sccs | Where-Object { [string]$process.identity.id -in @($_.nodes) })
    if (@($membership | Where-Object classification -eq 'UNSAFE').Count -gt 0) { $process.certainty='UNSAFE';$process.disposition='FailHardSafety' }
    elseif (@($membership | Where-Object classification -eq 'UNKNOWN').Count -gt 0 -and [string]$process.certainty -eq 'CERTIFIED_SAFE') { $process.certainty='UNKNOWN';$process.disposition='RequestReview' }
    $positiveCycle = $membership.Count -gt 0
    $provenBounded = $positiveCycle -and @($membership | Where-Object classification -ne 'CERTIFIED_BOUNDED').Count -eq 0
    if ([string]$process.certainty -eq 'UNKNOWN') {
      $process.safety_status = 'not-evaluated-unknown'
    } else {
      $operations = @('data-only-process-certificate')
      if ([string]$process.certainty -eq 'UNSAFE') { $operations += 'unbounded-positive-cycle' }
      $decision = Test-MIR4SafetyContribution -Contribution ([pscustomobject]@{subject=[string]$process.identity.id;operations=$operations;evidence=@('risk:'+[string]$process.risk.fingerprint);positive_cycle=$positiveCycle;proven_bounded=$provenBounded;owner_opaque=([string]$process.classification -eq 'opaque');owner_rewrite=$false;requested_disposition='preserve'})
      $process.safety_status = [string]$decision.status
    }
    $process.digest = Get-MIR4ProcessIRDigest $process
  }
  $rank = @{CERTIFIED_SAFE=0;REVIEW_REQUIRED=1;UNKNOWN=2;UNSAFE=3}
  $overall = @($processes | Sort-Object @{Expression={$rank[[string]$_.certainty]};Descending=$true},@{Expression={[string]$_.identity.id}} | Select-Object -First 1)[0].certainty
  $disposition = if($overall -eq 'UNSAFE'){'FailHardSafety'}elseif($overall -in @('UNKNOWN','REVIEW_REQUIRED')){'RequestReview'}else{'Preserve'}
  $graphMaterial = [ordered]@{processes=$processes;sccs=$sccs}
  $record = [ordered]@{
    schema=1;kind='MIR4ProcessIRV1';fixture_id=[string]$InputRecord.fixture_id
    source=[ordered]@{authority=[string]$InputRecord.source.authority;target=[string]$InputRecord.source.target;profile=[string]$InputRecord.source.profile;exact_target=[bool]$InputRecord.source.exact_target;recipe_facts_sha256=[string]$InputRecord.source.recipe_facts_sha256;risk_facts_sha256=[string]$InputRecord.source.risk_facts_sha256;environment_lock_digest=$(if($InputRecord.source.environment_lock_digest){[string]$InputRecord.source.environment_lock_digest}else{$null})}
    processes=$processes;sccs=$sccs;overall_classification=[string]$overall;terminal_disposition=$disposition
    graph_digest=(Get-MIR4ProcessIRDigest $graphMaterial);mutation_authorized=$false;authoritative=$false;digest=''
  }
  Add-MIR4ProcessIRDigest $record | Out-Null
  return [pscustomobject]$record
}

function Test-MIR4SynthesisCandidateV1 {
  param(
    [Parameter(Mandatory)]$ProcessIR,
    [Parameter(Mandatory)][string]$Constructor,
    [Parameter(Mandatory)][string]$Mode,
    [Parameter(Mandatory)][string]$ProcessId,
    [Parameter(Mandatory)]$Authority,
    [hashtable]$Certificates=@{}
  )
  if ($Constructor -notin @($Authority.candidate_constructors)) { throw "[mir4-synthesis-constructor] $Constructor" }
  if ($Mode -notin @($Authority.modes.id)) { throw "[mir4-synthesis-mode] $Mode" }
  $process = @($ProcessIR.processes | Where-Object { [string]$_.identity.id -ceq $ProcessId })[0]
  if ($null -eq $process) { throw "[mir4-synthesis-process] $ProcessId" }
  $gate = @(foreach ($id in @($Authority.certificate_gate)) { [ordered]@{id=[string]$id;status=$(if($Certificates.ContainsKey([string]$id)-and[bool]$Certificates[[string]$id]){'complete'}else{'missing'})} })
  $gateComplete = @($gate | Where-Object status -ne 'complete').Count -eq 0
  $certainty = [string]$process.certainty
  if ($certainty -eq 'UNSAFE') { $assessment='rejected-hard-safety';$disposition='FailHardSafety' }
  elseif ($certainty -in @('UNKNOWN','REVIEW_REQUIRED')) { $assessment='explicitly-quarantined';$disposition='RequestReview' }
  elseif ($Mode -eq 'Diagnose') { $assessment='admissible-preview-proposal-only';$disposition='Preserve' }
  elseif ($Mode -eq 'Conservative' -and $gateComplete) { $assessment='candidate-complete-preview';$disposition='Preserve' }
  elseif ($Mode -eq 'Experimental') { $assessment='private-opt-in-research-only';$disposition='Preserve' }
  else { $assessment='explicitly-quarantined-incomplete-certificates';$disposition='RequestReview' }
  return [pscustomobject][ordered]@{
    id=([string]$ProcessIR.fixture_id+'.'+$Constructor+'.'+$Mode)
    constructor=$Constructor;mode=$Mode;process_id=$ProcessId;certainty=$certainty;assessment=$assessment;disposition=$disposition
    certificate_gate=$gate;certificate_gate_complete=$gateComplete;operation_object=$false;planner_admission=$false;mutation_authorized=$false
  }
}

function New-MIR4EffectChannelRegistryV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Authority,[AllowNull()]$SourceIdentity)
  $repo = Get-MIR4ProcessIRRepoRoot $RepoRoot
  $channels = @(
    foreach ($source in @($Authority.effect_channels | Sort-Object id -CaseSensitive)) {
      $ownerPath = Join-Path $repo ([string]$source.owner_path)
      if (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf)) { throw "[mir4-effect-channel-owner-missing] $($source.owner_path)" }
      $row = [ordered]@{
        id=[string]$source.id;class=[string]$source.class;subject=[string]$source.subject
        value_domain=$source.value_domain;composition_law=$source.composition_law;neutral_value=$source.neutral_value;repeatability=$source.repeatability;saturation=$source.saturation;bounds=$source.bounds
        target_representation=[string]$source.target_representation;runtime_owner=$source.runtime_owner;migration=[string]$source.migration;presentation=[string]$source.presentation;proof=[string]$source.proof
        owner_ref=[ordered]@{path=[string]$source.owner_path;sha256=(Get-MIR4PlatformInputSha256 $ownerPath)}
        disposition=[string]$source.disposition;maturity='developer-preview';package_visible=$false;semantic_owner_preserved=$true;digest=''
      }
      Add-MIR4ProcessIRDigest $row | Out-Null
      [pscustomobject]$row
    }
  )
  $opaque = @($channels | Where-Object class -eq 'opaque')[0]
  $opaquePreserved = $null -ne $opaque -and $null -eq $opaque.value_domain -and $null -eq $opaque.composition_law -and [string]$opaque.disposition -eq 'Preserve'
  $record = [ordered]@{
    schema=1;kind='MIR4EffectChannelRegistryV1';programme_id='M4C02-09-24H';source_identity=$SourceIdentity
    authority='.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json';maturity='developer-preview';channels=$channels;opaque_preserved=$opaquePreserved
    package_visible=$false;public_release_proof=$false;player_mutation_authorized=$false;digest=''
  }
  Add-MIR4ProcessIRDigest $record | Out-Null
  return [pscustomobject]$record
}

function New-MIR4SynthesisMaturityMatrixV1 {
  param([Parameter(Mandatory)]$SafeIR,[Parameter(Mandatory)]$UnsafeIR,[Parameter(Mandatory)]$UnknownIR,[Parameter(Mandatory)]$Authority,[AllowNull()]$SourceIdentity)
  $safeId = [string]$SafeIR.processes[0].identity.id; $unsafeId = [string]$UnsafeIR.processes[0].identity.id; $unknownId = [string]$UnknownIR.processes[0].identity.id
  $candidates = @(foreach ($constructor in @($Authority.candidate_constructors)) { Test-MIR4SynthesisCandidateV1 -ProcessIR $SafeIR -Constructor ([string]$constructor) -Mode Diagnose -ProcessId $safeId -Authority $Authority })
  $candidates += Test-MIR4SynthesisCandidateV1 -ProcessIR $UnsafeIR -Constructor RepairMirProgression -Mode Conservative -ProcessId $unsafeId -Authority $Authority
  $candidates += Test-MIR4SynthesisCandidateV1 -ProcessIR $UnknownIR -Constructor ReplaceReviewedOwner -Mode Conservative -ProcessId $unknownId -Authority $Authority
  $candidates += Test-MIR4SynthesisCandidateV1 -ProcessIR $SafeIR -Constructor ContinueSeries -Mode Conservative -ProcessId $safeId -Authority $Authority
  $candidates += Test-MIR4SynthesisCandidateV1 -ProcessIR $SafeIR -Constructor CreateDeclaredScriptedFamily -Mode Experimental -ProcessId $safeId -Authority $Authority
  $record = [ordered]@{
    schema=1;kind='MIR4SynthesisMaturityMatrixV1';programme_id='M4C02-09-24H';source_identity=$SourceIdentity
    authority='.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json';maturity='developer-preview'
    constructors=@($Authority.candidate_constructors);terminal_dispositions=@($Authority.terminal_dispositions);terminal_disposition_source_note=[string]$Authority.terminal_disposition_source_note
    modes=@($Authority.modes);candidates=@($candidates | Sort-Object id -CaseSensitive);advanced_ecosystems=@($Authority.advanced_ecosystems)
    automatic_player_mutation=$false;package_visible=$false;public_release_proof=$false;player_mutation_authorized=$false;digest=''
  }
  Add-MIR4ProcessIRDigest $record | Out-Null
  return [pscustomobject]$record
}

function Resolve-MIR4W06MepReferences {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Envelope,[Parameter(Mandatory)]$ProcessIR,[Parameter(Mandatory)]$EffectRegistry)
  Test-MIR4MepV1Envelope -Envelope $Envelope -RepoRoot $RepoRoot | Out-Null
  $rows = @()
  foreach ($fragment in @($Envelope.fragments | Where-Object { $_.kind -in @('ProcessClassificationFragment','ExternalEffectChannelDeclaration') } | Sort-Object kind,id)) {
    if ([string]$fragment.data.status -eq 'unavailable') { $rows += [ordered]@{fragment_id=[string]$fragment.id;kind=[string]$fragment.kind;status='unavailable-preserved';matched=$false}; continue }
    $reference = if ([string]$fragment.kind -eq 'ProcessClassificationFragment') { [string]$fragment.data.certificate_ref } else { [string]$fragment.data.channel_ref }
    if ($reference -notmatch '^(process|channel):([^@]+)@(sha256:[0-9a-f]{64})$') { throw "[mir4-w06-mep-reference-format] $($fragment.id)" }
    $type=$Matches[1];$id=$Matches[2];$digest=$Matches[3]
    if ($type -eq 'process') { $match=@($ProcessIR.processes|Where-Object{[string]$_.identity.id-ceq$id-and[string]$_.digest-ceq$digest}) }
    else { $match=@($EffectRegistry.channels|Where-Object{[string]$_.id-ceq$id-and[string]$_.digest-ceq$digest}) }
    if ($match.Count -ne 1) { throw "[mir4-w06-mep-reference-mismatch] $($fragment.id)" }
    $rows += [ordered]@{fragment_id=[string]$fragment.id;kind=[string]$fragment.kind;status='linked';matched=$true;reference=$reference}
  }
  $record=[ordered]@{schema=1;kind='MIR4W06MepReferenceLinkResultV1';extension_id=[string]$Envelope.extension_id;links=$rows;mutation_authorized=$false;digest=''}
  Add-MIR4ProcessIRDigest $record|Out-Null
  return [pscustomobject]$record
}

function Get-MIR4W06FixturePaths {
  return @(
    'fixtures/mir4-process-ir-v1/positive/ordinary-safe.json',
    'fixtures/mir4-process-ir-v1/positive/catalyst-container-bounded-cycle.json',
    'fixtures/mir4-process-ir-v1/positive/recycling-recovery.json',
    'fixtures/mir4-process-ir-v1/negative/unbounded-positive-cycle.json',
    'fixtures/mir4-process-ir-v1/negative/unsupported-unknown.json',
    'fixtures/mir4-process-ir-v1/permutation/scc-order-a.json',
    'fixtures/mir4-process-ir-v1/permutation/scc-order-b.json'
  )
}

function New-MIR4W06Records {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$SourceIdentity)
  $repo=Get-MIR4ProcessIRRepoRoot $RepoRoot;$authority=Get-MIR4ProcessIRSynthesisAuthority -RepoRoot $repo
  if($null-eq$SourceIdentity){$SourceIdentity=[ordered]@{commit=$null;tree=$null;programme_id='M4C02-09-24H'}}
  $fixtureRows=@();$irs=@{}
  foreach($relative in Get-MIR4W06FixturePaths){
    $input=Read-MIR4CanonicalRecipeFactInputV1 -RepoRoot $repo -Path $relative;$ir=New-MIR4ProcessIRV1 -InputRecord $input -RepoRoot $repo;$irs[[string]$input.fixture_id]=$ir
    $actual=[string]$ir.overall_classification;$actualDisposition=[string]$ir.terminal_disposition
    $fixtureRows += [ordered]@{fixture_id=[string]$input.fixture_id;path=$relative;sha256=(Get-MIR4PlatformInputSha256 (Join-Path $repo $relative));expected_classification=[string]$input.expected.classification;actual_classification=$actual;expected_disposition=[string]$input.expected.disposition;actual_disposition=$actualDisposition;graph_digest=[string]$ir.graph_digest;risk_fingerprints=@($ir.processes.risk.fingerprint);passed=($actual-ceq[string]$input.expected.classification-and$actualDisposition-ceq[string]$input.expected.disposition)}
  }
  $safe=$irs['ordinary-safe'];$unsafe=$irs['unbounded-positive-cycle'];$unknown=$irs['unsupported-unknown']
  $safeAssessment=Test-MIR4SynthesisCandidateV1 -ProcessIR $safe -Constructor ContinueSeries -Mode Diagnose -ProcessId ([string]$safe.processes[0].identity.id) -Authority $authority
  $unsafeAssessment=Test-MIR4SynthesisCandidateV1 -ProcessIR $unsafe -Constructor RepairMirProgression -Mode Conservative -ProcessId ([string]$unsafe.processes[0].identity.id) -Authority $authority
  $riskChecks=@($irs.Values|ForEach-Object{$ir=$_;@($ir.processes|ForEach-Object{[bool]$_.risk.copied_not_reclassified-and[string]$_.risk.fingerprint-match'^sha256:[0-9a-f]{64}$'})})
  $riskParity=$false-notin$riskChecks
  $permutationPassed=[string]$irs['scc-order-a'].graph_digest-ceq[string]$irs['scc-order-b'].graph_digest
  $bilateral=[ordered]@{known_safe_admissible=([string]$safeAssessment.assessment-eq'admissible-preview-proposal-only');known_unsafe_rejected=([string]$unsafeAssessment.assessment-eq'rejected-hard-safety'-and[string]$unsafeAssessment.disposition-eq'FailHardSafety');reject_everything=$false;passed=$false}
  $bilateral.passed=$bilateral.known_safe_admissible-and$bilateral.known_unsafe_rejected-and-not$bilateral.reject_everything
  $exact=[ordered]@{status=[string]$authority.exact_target_snapshot.status;receipt=[string]$authority.exact_target_snapshot.receipt;manifest=[string]$authority.exact_target_snapshot.manifest;capture_count=[int]$authority.exact_target_snapshot.capture_count;required_capture_count=[int]$authority.exact_target_snapshot.required_capture_count;custody_blocker=[string]$authority.exact_target_snapshot.custody_blocker;deterministic=$false;package_source_unchanged=$false;authoritative=$false;public_release_proof=$false}
  $exactRefs=@()
  foreach($property in @('receipt','manifest')){$relative=[string]$exact[$property];$path=Join-Path $repo $relative;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-w06-exact-reference-missing] $relative"};$exactRefs+=[ordered]@{path=$relative;sha256=(Get-MIR4PlatformInputSha256 $path)}}
  $receipt=Get-Content -Raw -LiteralPath (Join-Path $repo $exact.receipt)|ConvertFrom-Json -Depth 100
  if([string]$receipt.exact_target_processir_status-cne$exact.status-or[int]$receipt.capture_count-ne$exact.capture_count-or[int]$receipt.required_capture_count-ne$exact.required_capture_count-or-not$receipt.all_deterministic-or-not$receipt.package_source_unchanged){throw '[mir4-w06-exact-reference-invalid]'}
  $exact.deterministic=$true;$exact.package_source_unchanged=$true
  $passed=@($fixtureRows|Where-Object{-not$_.passed}).Count-eq 0-and$permutationPassed-and$riskParity-and$bilateral.passed-and$exact.deterministic-and$exact.package_source_unchanged
  $evidenceRefs=@($fixtureRows|Sort-Object path|ForEach-Object{[ordered]@{path=$_.path;sha256=$_.sha256}})+$exactRefs
  $parity=[ordered]@{schema=1;kind='MIR4ProcessIRParityResultV1';programme_id='M4C02-09-24H';source_identity=$SourceIdentity;authority='.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json';maturity='developer-preview';scope='bilateral-synthetic-plus-exact-target-preview';exact_target_status=[string]$authority.exact_target_snapshot.status;exact_target_reason=[string]$authority.exact_target_snapshot.reason;exact_target_evidence=$exact;fixture_results=@($fixtureRows|Sort-Object fixture_id -CaseSensitive);bilateral_gate=$bilateral;risk_parity=[ordered]@{copied_not_reclassified=$true;all_fixture_fingerprints_preserved=$riskParity;permutation_graph_invariant=$permutationPassed;passed=($riskParity-and$permutationPassed)};package_visible=$false;public_release_proof=$false;player_mutation_authorized=$false;evidence_refs=$evidenceRefs;passed=$passed;digest=''}
  Add-MIR4ProcessIRDigest $parity|Out-Null
  $effects=New-MIR4EffectChannelRegistryV1 -RepoRoot $repo -Authority $authority -SourceIdentity $SourceIdentity
  $synthesis=New-MIR4SynthesisMaturityMatrixV1 -SafeIR $safe -UnsafeIR $unsafe -UnknownIR $unknown -Authority $authority -SourceIdentity $SourceIdentity
  return [pscustomobject][ordered]@{parity=[pscustomobject]$parity;effects=$effects;synthesis=$synthesis;fixture_irs=$irs}
}

# Compatibility names retained for PlatformPreview callers; both now delegate to the W06 authority.
function New-MIR4ProcessIRInventory {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$PlatformSpec)
  return (New-MIR4W06Records -RepoRoot $RepoRoot -SourceIdentity $null).parity
}

function New-MIR4OpportunityCatalogue {
  param([Parameter(Mandatory)]$PlatformSpec,[Parameter(Mandatory)]$ProcessIR)
  $repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
  return (New-MIR4W06Records -RepoRoot $repo -SourceIdentity $null).synthesis
}
