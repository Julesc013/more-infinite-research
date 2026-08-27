if (-not (Get-Command New-MIR4ProcessIRV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../mir/domain/safety/SafetyKernel.ps1')
  . (Join-Path $PSScriptRoot 'ProcessIR.ps1')
}
if (-not (Get-Command New-MIR4EnvironmentLockV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'EnvironmentEvidence.ps1')
}

function Get-MIR4T12RepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4T12Authority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=Get-MIR4T12RepoRoot $RepoRoot
  $path=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Exact-ProcessIR-T12V1.json'
  $value=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100
  if([int]$value.schema-ne 1-or[string]$value.kind-cne'MIR4ExactProcessIRT12V1'-or[string]$value.work_package-cne'T12'-or@($value.captures).Count-lt 9){throw '[mir4-t12-authority]'}
  foreach($flag in @('semantic_authority','player_mutation_authorized','prototype_write_authorized','planner_or_emitter_admission_authorized','automatic_synthesis_authorized','public_support_authorized','release_admission_authorized','signing_or_sealing_authorized','publication_authorized')){if([bool]$value.$flag){throw "[mir4-t12-authority-boundary] $flag"}}
  $value
}

function Get-MIR4T12FileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-MIR4T12RecordDigest {
  param([Parameter(Mandatory)]$Value,[string]$Domain='mir4:exact-processir:1')
  if($Domain-cnotmatch'^mir4:[a-z0-9][a-z0-9.:-]{0,95}$'){throw "[mir4-t12-digest-domain] $Domain"}
  $material=[ordered]@{}
  if($Value-is[Collections.IDictionary]){foreach($key in $Value.Keys){if([string]$key-cne'digest'){$material[[string]$key]=$Value[$key]}}}
  else{foreach($property in $Value.PSObject.Properties){if($property.Name-cne'digest'){$material[$property.Name]=$property.Value}}}
  $json=ConvertTo-MIR4ProcessIRCanonicalJson $material
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Domain+"`0"+$json)
  $sha=[Security.Cryptography.SHA256]::Create();try{'sha256:'+([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}
}

function Add-MIR4T12RecordDigest {
  param([Parameter(Mandatory)]$Value,[string]$Domain='mir4:exact-processir:1')
  $Value.digest=Get-MIR4T12RecordDigest -Value $Value -Domain $Domain
  $Value
}

function Resolve-MIR4T12InputPath {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  $full=if([IO.Path]::IsPathRooted($Path)){$Path}else{Join-Path $RepoRoot $Path}
  if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "[mir4-t12-input-missing] $Path"}
  (Resolve-Path -LiteralPath $full).Path
}

function Get-MIR4T12ScenarioEvidence {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Capture)
  $evidencePath=Resolve-MIR4T12InputPath -RepoRoot $RepoRoot -Path ([string]$Capture.evidence)
  $lockPath=Resolve-MIR4T12InputPath -RepoRoot $RepoRoot -Path ([string]$Capture.lock)
  $evidence=Get-Content -Raw -LiteralPath $evidencePath|ConvertFrom-Json -Depth 100
  $lock=Get-Content -Raw -LiteralPath $lockPath|ConvertFrom-Json -Depth 100
  $scenario=@($evidence.scenarios|Where-Object{[string]$_.scenario_id-ceq[string]$Capture.scenario_id})
  if($scenario.Count-ne 1){throw "[mir4-t12-scenario-evidence] $($Capture.id)"}
  [pscustomobject][ordered]@{
    scenario=$scenario[0];lock=$lock
    evidence_ref=[ordered]@{path=[string]$Capture.evidence;sha256='sha256:'+(Get-MIR4T12FileSha256 $evidencePath)}
    lock_ref=[ordered]@{path=[string]$Capture.lock;sha256='sha256:'+(Get-MIR4T12FileSha256 $lockPath)}
  }
}

function Resolve-MIR4T12Archive {
  param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][string[]]$SearchRoots)
  $expected=([string]$Entry.sha256).ToLowerInvariant()
  $candidates=@()
  if($Entry.PSObject.Properties['source_path']-and-not[string]::IsNullOrWhiteSpace([string]$Entry.source_path)){$candidates+=[string]$Entry.source_path}
  $fileName=if($Entry.PSObject.Properties['file_name']-and$Entry.file_name){[string]$Entry.file_name}else{"$($Entry.name)_$($Entry.version).zip"}
  foreach($root in $SearchRoots){
    if(-not(Test-Path -LiteralPath $root)){continue}
    $direct=Join-Path $root $fileName;if(Test-Path -LiteralPath $direct -PathType Leaf){$candidates+=$direct}
    $candidates+=@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter $fileName -ErrorAction SilentlyContinue|ForEach-Object FullName)
  }
  foreach($candidate in @($candidates|Select-Object -Unique)){
    if((Test-Path -LiteralPath $candidate -PathType Leaf)-and(Get-MIR4T12FileSha256 $candidate)-ceq$expected){return (Resolve-Path -LiteralPath $candidate).Path}
  }
  throw "[mir4-t12-exact-archive-missing] $($Entry.name)@$($Entry.version) sha256:$expected"
}

function Get-MIR4T12ClosureRows {
  param([Parameter(Mandatory)]$Scenario,[Parameter(Mandatory)]$Lock)
  $rows=@($Scenario.dependency_closure)
  if($rows.Count){
    $joined=@()
    foreach($row in $rows){
      $entry=@($Lock.mods|Where-Object{[string]$_.name-ceq[string]$row.name})
      if($entry.Count-ne 1){throw "[mir4-t12-lock-entry] $($row.name)"}
      if([string]$entry[0].version-cne[string]$row.version-or
         ([string]$entry[0].sha256).ToLowerInvariant()-cne([string]$row.sha256).ToLowerInvariant()){
        throw "[mir4-t12-lock-closure-mismatch] $($row.name)"
      }
      $copy=[ordered]@{}
      foreach($property in $row.PSObject.Properties){$copy[$property.Name]=$property.Value}
      foreach($propertyName in @('file_name','source_path')){
        $property=$entry[0].PSObject.Properties[$propertyName]
        if($null-ne$property-and-not[string]::IsNullOrWhiteSpace([string]$property.Value)){$copy[$propertyName]=$property.Value}
      }
      $joined+=[pscustomobject]$copy
    }
    $rows=$joined
  }
  if($rows.Count-eq 0-and@($Scenario.resolved_mods).Count){
    foreach($name in @($Scenario.resolved_mods|Where-Object{$_-ne'more-infinite-research'-and$_-notlike'mir-fixture-*'})){
      $entry=@($Lock.mods|Where-Object{[string]$_.name-ceq[string]$name})
      if($entry.Count-ne 1){throw "[mir4-t12-lock-entry] $name"}
      $rows+=$entry[0]
    }
  }
  @($rows|Where-Object{[string]$_.name-cne'more-infinite-research'-and[string]$_.name-cnotlike'mir-fixture-*'}|Sort-Object name -CaseSensitive)
}

function Write-MIR4T12ObserverSource {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Capture,[Parameter(Mandatory)]$Target,[Parameter(Mandatory)][int]$MaximumProcesses)
  New-Item -ItemType Directory -Path $Path -Force|Out-Null
  Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-processir-exact-observer/data-final-fixes.lua') -Destination (Join-Path $Path 'data-final-fixes.lua') -Force
  $info=[ordered]@{name='mir4-processir-exact-observer';version='0.1.0';title='MIR 4 Exact ProcessIR Observer';author='MIR';factorio_version=[string]$Target.factorio_line;dependencies=@("base >= $($Target.factorio_line).0","more-infinite-research >= 4.0.0")}
  [IO.File]::WriteAllText((Join-Path $Path 'info.json'),(($info|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
  $quote={param([string]$Value)return ('"'+$Value.Replace('\','\\').Replace('"','\"')+'"')}
  $selectorValues=@();foreach($selector in @($Capture.selectors)){$selectorValues+=(& $quote ([string]$selector))}
  $selectors=$selectorValues-join','
  $captureValue=& $quote ([string]$Capture.id);$targetValue=& $quote ([string]$Capture.target);$scenarioValue=& $quote ([string]$Capture.scenario_id)
  $config="return {capture_id=$captureValue,target=$targetValue,scenario_id=$scenarioValue,maximum_processes=$MaximumProcesses,selectors={$selectors}}`n"
  [IO.File]::WriteAllText((Join-Path $Path 'capture_config.lua'),$config,[Text.UTF8Encoding]::new($false))
}

function Read-MIR4T12ObserverLog {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$CaptureId)
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "[mir4-t12-log-missing] $CaptureId"}
  $headers=@();$rows=@();$footers=@()
  foreach($line in [IO.File]::ReadLines($Path)){
    if($line-match'\[MIR4_PROCESSIR_HEADER\]\s+(\{.*\})\s*$'){$headers+=($Matches[1]|ConvertFrom-Json -Depth 100)}
    elseif($line-match'\[MIR4_PROCESSIR_ROW\]\s+(\{.*\})\s*$'){$rows+=($Matches[1]|ConvertFrom-Json -Depth 100)}
    elseif($line-match'\[MIR4_PROCESSIR_FOOTER\]\s+(\{.*\})\s*$'){$footers+=($Matches[1]|ConvertFrom-Json -Depth 100)}
  }
  if($headers.Count-ne 1-or$footers.Count-ne 1-or$rows.Count-ne[int]$headers[0].selected_processes-or$rows.Count-ne[int]$footers[0].emitted_rows-or-not$footers[0].complete){throw "[mir4-t12-observer-protocol] $CaptureId headers=$($headers.Count) rows=$($rows.Count) footers=$($footers.Count)"}
  $material=[ordered]@{header=$headers[0];rows=@($rows|Sort-Object recipe -CaseSensitive);footer=$footers[0]}
  [pscustomobject][ordered]@{header=$material.header;rows=$material.rows;footer=$material.footer;digest=(Get-MIR4T12RecordDigest -Value $material -Domain 'mir4:exact-processir-observer:1')}
}

function ConvertTo-MIR4T12Quantity {
  param([Parameter(Mandatory)]$Entry)
  if($null-ne$Entry.amount_min-or$null-ne$Entry.amount_max){
    $min=if($null-ne$Entry.amount_min){[decimal]$Entry.amount_min}elseif($null-ne$Entry.amount){[decimal]$Entry.amount}else{0}
    $max=if($null-ne$Entry.amount_max){[decimal]$Entry.amount_max}elseif($null-ne$Entry.amount){[decimal]$Entry.amount}else{$min}
    return [ordered]@{kind='bounded';min=$min;max=$max}
  }
  [ordered]@{kind='exact';value=$(if($null-ne$Entry.amount){[decimal]$Entry.amount}else{[decimal]1})}
}

function ConvertTo-MIR4T12Probability {
  param([Parameter(Mandatory)]$Entry)
  [ordered]@{kind='exact';value=$(if($null-ne$Entry.independent_probability){[decimal]$Entry.independent_probability}elseif($null-ne$Entry.probability){[decimal]$Entry.probability}else{[decimal]1})}
}

function ConvertTo-MIR4T12Array {
  param($Value,[switch]$Strings)
  foreach($item in @($Value)){
    if($null-eq$item){continue}
    if($item-is[pscustomobject]-and$item.PSObject.Properties.Count-eq 0){continue}
    if($item-is[Collections.IDictionary]-and$item.Count-eq 0){continue}
    if($Strings){
      $text=[string]$item
      if(-not[string]::IsNullOrWhiteSpace($text)){$text}
    }else{$item}
  }
}

function ConvertTo-MIR4T12Flow {
  param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][bool]$ProductivitySensitive)
  $type=$Entry.PSObject.Properties['type']
  $catalystAmount=$Entry.PSObject.Properties['catalyst_amount']
  $ignoredByProductivity=$Entry.PSObject.Properties['ignored_by_productivity']
  $temperature=$Entry.PSObject.Properties['temperature']
  $minimumTemperature=$Entry.PSObject.Properties['minimum_temperature']
  $maximumTemperature=$Entry.PSObject.Properties['maximum_temperature']
  $qualityMinimum=$Entry.PSObject.Properties['quality_min']
  $qualityMaximum=$Entry.PSObject.Properties['quality_max']
  $qualityChange=$Entry.PSObject.Properties['quality_change']
  $affectedByQuality=$Entry.PSObject.Properties['affected_by_quality']
  [ordered]@{
    type=$(if($null-eq$type-or[string]::IsNullOrWhiteSpace([string]$type.Value)){'item'}else{[string]$type.Value});name=[string]$Entry.name
    amount=ConvertTo-MIR4T12Quantity $Entry;probability=ConvertTo-MIR4T12Probability $Entry;productivity_sensitive=$ProductivitySensitive
    catalyst_amount=$(if($null-ne$catalystAmount-and$null-ne$catalystAmount.Value){[decimal]$catalystAmount.Value}else{[decimal]0})
    ignored_by_productivity=$(if($null-ne$ignoredByProductivity-and$null-ne$ignoredByProductivity.Value){[decimal]$ignoredByProductivity.Value}else{[decimal]0})
    temperature=[ordered]@{value=$(if($null-ne$temperature){$temperature.Value}else{$null});minimum=$(if($null-ne$minimumTemperature){$minimumTemperature.Value}else{$null});maximum=$(if($null-ne$maximumTemperature){$maximumTemperature.Value}else{$null});status=$(if($null-ne$temperature-or$null-ne$minimumTemperature-or$null-ne$maximumTemperature){'available'}else{'unavailable'})}
    quality=[ordered]@{minimum=$(if($null-ne$qualityMinimum){$qualityMinimum.Value}else{$null});maximum=$(if($null-ne$qualityMaximum){$qualityMaximum.Value}else{$null});change=$(if($null-ne$qualityChange){$qualityChange.Value}else{$null});affected=$(if($null-ne$affectedByQuality){[bool]$affectedByQuality.Value}else{$null});status=$(if($null-ne$qualityMinimum-or$null-ne$qualityMaximum-or$null-ne$qualityChange-or$null-ne$affectedByQuality){'available'}else{'unavailable'})}
  }
}

function ConvertTo-MIR4T12CanonicalInput {
  param([Parameter(Mandatory)]$Observed,[Parameter(Mandatory)]$EnvironmentLock,[Parameter(Mandatory)]$Capture)
  $processes=@();$observationRows=@();$transportOmissions=@()
  foreach($row in @($Observed.rows|Sort-Object recipe -CaseSensitive)){
    $variantOrdinal=0
    foreach($variant in @($row.fact.variants|Sort-Object name -CaseSensitive)){
      $variantOrdinal++
      $rawInputs=@(ConvertTo-MIR4T12Array $variant.ingredients)
      $rawOutputs=@(ConvertTo-MIR4T12Array $variant.results)
      $invalidFlows=@(@($rawInputs)+@($rawOutputs)|Where-Object{[string]::IsNullOrWhiteSpace([string]$_.name)-or([string]$_.type-notin@('item','fluid'))})
      if($rawOutputs.Count-eq 0-or$invalidFlows.Count-ne 0){
        $transportOmissions+=[ordered]@{recipe=[string]$row.recipe;variant=[string]$variant.name;status='unavailable';reason=$(if([bool]$row.fact.parameter){'parameterized recipe flow identities are not concrete in the finalized prototype surface'}else{'one or more finalized recipe flows do not expose a concrete supported type and name'})}
        continue
      }
      $inputs=@($rawInputs|ForEach-Object{ConvertTo-MIR4T12Flow -Entry $_ -ProductivitySensitive $false})
      $outputs=@($rawOutputs|ForEach-Object{
        $amount=if($null-ne$_.amount_max){[decimal]$_.amount_max}elseif($null-ne$_.amount){[decimal]$_.amount}else{[decimal]1}
        $ignored=if($null-ne$_.ignored_by_productivity){[decimal]$_.ignored_by_productivity}else{[decimal]0}
        ConvertTo-MIR4T12Flow -Entry $_ -ProductivitySensitive ([bool]$variant.effective_allow_productivity-and$amount-gt$ignored)
      })
      if($outputs.Count-eq 0){continue}
      $inputNames=@($inputs.name);$outputNames=@($outputs.name);$intersection=@($inputNames|Where-Object{$_-in$outputNames}|Sort-Object -Unique -CaseSensitive)
      $catalysts=@($outputs|Where-Object{[decimal]$_.catalyst_amount-gt 0}|ForEach-Object name|Sort-Object -Unique -CaseSensitive)
      $returned=@($intersection|Where-Object{$_-match'(?i)barrel|canister|container|capsule|empty'}|Sort-Object -Unique -CaseSensitive)
      $unsupported=@($variant.results|Where-Object{$null-ne$_.shared_probability-or($null-ne$_.extra_count_fraction-and[decimal]$_.extra_count_fraction-ne 0)})
      $riskMaterial=[ordered]@{recipe=[string]$row.recipe;terminal_fingerprint=[string]$row.risk.risk_fingerprint;hard_flags=@(ConvertTo-MIR4T12Array $row.risk.hard_flags -Strings);review_flags=@(ConvertTo-MIR4T12Array $row.risk.review_flags -Strings);evidence=@(ConvertTo-MIR4T12Array $row.risk.evidence -Strings);shared_input_output=@(ConvertTo-MIR4T12Array $row.risk.shared_input_output)}
      $idMaterial=[ordered]@{capture=[string]$Capture.id;recipe=[string]$row.recipe;variant=[string]$variant.name;ordinal=$variantOrdinal}
      $idDigest=(Get-MIR4T12RecordDigest -Value $idMaterial -Domain 'mir4:process-id:1').Substring(7,24)
      $classification=if([string]$row.fact.source_class-eq'recycling'){'recycling'}elseif([string]$row.recipe-match'(?i)recover|recovery'){'recovery'}elseif($unsupported.Count){'opaque'}else{'ordinary'}
      $processes+=[ordered]@{
        id="process-$idDigest";recipe=[string]$row.recipe;variant=[string]$variant.name;classification=$classification;shape_supported=($unsupported.Count-eq 0)
        inputs=$inputs;outputs=$outputs;catalysts=$catalysts;returned_containers=$returned;cycle_bound=$(if(@($row.risk.hard_flags).Count){'unknown'}else{'not-applicable'})
        categories=@(ConvertTo-MIR4T12Array $variant.categories -Strings);machines=@(ConvertTo-MIR4T12Array $row.machines -Strings);surface_conditions=@(ConvertTo-MIR4T12Array $variant.surface_conditions);unlocks=@(ConvertTo-MIR4T12Array $row.unlocks -Strings);owners=@(ConvertTo-MIR4T12Array $row.productivity_owners -Strings);source_mod=$row.source_mod
        energy_required=$(if($null-ne$variant.energy_required){$variant.energy_required}else{$null})
        risk=[ordered]@{fingerprint=(Get-MIR4T12RecordDigest -Value $riskMaterial -Domain 'mir4:terminal-risk-fact:1');terminal_fingerprint=[string]$row.risk.risk_fingerprint;confidence=$(if($unsupported.Count){'partial'}else{'complete'});hard_flags=@(ConvertTo-MIR4T12Array $row.risk.hard_flags -Strings|Sort-Object -Unique -CaseSensitive);review_flags=@(ConvertTo-MIR4T12Array $row.risk.review_flags -Strings|Sort-Object -Unique -CaseSensitive);evidence=@(ConvertTo-MIR4T12Array $row.risk.evidence -Strings|Sort-Object -Unique -CaseSensitive)}
      }
    }
    $observationRows+=[ordered]@{recipe=[string]$row.recipe;fact=$row.fact;risk=$row.risk;unlocks=@(ConvertTo-MIR4T12Array $row.unlocks -Strings);productivity_owners=@(ConvertTo-MIR4T12Array $row.productivity_owners -Strings);machines=@(ConvertTo-MIR4T12Array $row.machines -Strings);source_mod=$row.source_mod}
  }
  $factMaterial=@($observationRows|ForEach-Object{[ordered]@{recipe=$_.recipe;fact=$_.fact}})
  $riskMaterial=@($observationRows|ForEach-Object{[ordered]@{recipe=$_.recipe;risk=$_.risk}})
  $input=[pscustomobject][ordered]@{
    schema=1;kind='MIR4CanonicalRecipeFactInputV1';fixture_id=[string]$Capture.id
    source=[ordered]@{authority='terminal-exact-target';target=[string]$Capture.target;profile=[string]$Capture.scenario_id;exact_target=$true;recipe_facts_sha256=(Get-MIR4T12RecordDigest -Value $factMaterial -Domain 'mir4:recipe-facts:1');risk_facts_sha256=(Get-MIR4T12RecordDigest -Value $riskMaterial -Domain 'mir4:risk-facts:1');environment_lock_digest=[string]$EnvironmentLock.digest}
    processes=@($processes|Sort-Object id -CaseSensitive)
  }
  [pscustomobject][ordered]@{input=$input;observations=$observationRows;transport_omissions=@($transportOmissions|Sort-Object recipe,variant -CaseSensitive)}
}

function New-MIR4T12ExactSnapshot {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Capture,[Parameter(Mandatory)]$EnvironmentLock,[Parameter(Mandatory)]$Observed,[Parameter(Mandatory)]$SourceIdentity,[Parameter(Mandatory)]$Evidence,[int]$Repetitions=2,[bool]$Deterministic=$true)
  $transportSet=ConvertTo-MIR4T12CanonicalInput -Observed $Observed -EnvironmentLock $EnvironmentLock -Capture $Capture
  $ir=New-MIR4ProcessIRV1 -InputRecord $transportSet.input -RepoRoot $RepoRoot
  $classes=@('CERTIFIED_SAFE','REVIEW_REQUIRED','UNKNOWN','UNSAFE')
  $counts=[ordered]@{};foreach($class in $classes){$counts[$class]=@($ir.processes|Where-Object{[string]$_.certainty-ceq$class}).Count}
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR4ExactProcessIRSnapshotV1';work_package='T12';capture_id=[string]$Capture.id;target=[string]$Capture.target;scenario_id=[string]$Capture.scenario_id
    source_identity=$SourceIdentity;environment_lock=$EnvironmentLock;environment_lock_digest=[string]$EnvironmentLock.digest
    evidence_refs=@($Evidence.evidence_ref,$Evidence.lock_ref);observer=[ordered]@{digest=[string]$Observed.digest;header=$Observed.header;footer=$Observed.footer;repetitions=$Repetitions;deterministic=$Deterministic;bounded=$true;truncated=([int]$Observed.header.total_recipes-gt[int]$Observed.header.selected_processes)}
    transport=$transportSet.input;transport_omissions=@($transportSet.transport_omissions);process_ir=$ir;observations=@($transportSet.observations);classification_counts=$counts
    explicit_unavailable_not_zero=$true;terminal_fact_authority_preserved=$true;authoritative=$false;maturity='developer-preview';package_visible=$false;public_release_proof=$false;player_mutation_authorized=$false;prototype_write_authorized=$false;planner_or_emitter_admission_authorized=$false;public_support_authorized=$false;digest=''
  }
  Add-MIR4T12RecordDigest $record|Out-Null
  $record
}

function New-MIR4T12ComparisonV1 {
  param([Parameter(Mandatory)]$A,[Parameter(Mandatory)]$B)
  $byA=@{};foreach($p in @($A.process_ir.processes)){$byA[[string]$p.identity.recipe+'|'+[string]$p.identity.variant]=$p}
  $byB=@{};foreach($p in @($B.process_ir.processes)){$byB[[string]$p.identity.recipe+'|'+[string]$p.identity.variant]=$p}
  $keys=@(@($byA.Keys)+@($byB.Keys)|Sort-Object -Unique -CaseSensitive);$changes=@()
  foreach($key in $keys){
    $left=$byA[$key];$right=$byB[$key]
    $status=if($null-eq$left){'added'}elseif($null-eq$right){'removed'}elseif([string]$left.digest-cne[string]$right.digest){'changed'}else{'unchanged'}
    if($status-ne'unchanged'){$changes+=[ordered]@{process=$key;status=$status;before=$(if($left){[ordered]@{certainty=$left.certainty;disposition=$left.disposition;digest=$left.digest;owners=@($left.owners)}}else{$null});after=$(if($right){[ordered]@{certainty=$right.certainty;disposition=$right.disposition;digest=$right.digest;owners=@($right.owners)}}else{$null})}}
  }
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR4ProcessIRComparisonV1';work_package='T12';a=[ordered]@{capture_id=$A.capture_id;target=$A.target;scenario_id=$A.scenario_id;environment_lock_digest=$A.environment_lock_digest;snapshot_digest=$A.digest};b=[ordered]@{capture_id=$B.capture_id;target=$B.target;scenario_id=$B.scenario_id;environment_lock_digest=$B.environment_lock_digest;snapshot_digest=$B.digest}
    process_changes=@($changes|Select-Object -First 100);process_change_count=$changes.Count;truncated=($changes.Count-gt 100);classification_before=$A.classification_counts;classification_after=$B.classification_counts
    safe_unsafe_unknown_explicit=$true;offline=$true;network_or_upload_authorized=$false;mutation_authorized=$false;public_support_claim=$false;package_visible=$false;digest=''
  }
  Add-MIR4T12RecordDigest -Value $record -Domain 'mir4:processir-comparison:1'|Out-Null
  $record
}

function New-MIR4T12EnvironmentLock {
  param([Parameter(Mandatory)]$Authority,[Parameter(Mandatory)]$Target,[Parameter(Mandatory)]$Scenario,[Parameter(Mandatory)]$ClosureRows)
  $settings=@(foreach($property in @($Scenario.settings.PSObject.Properties|Sort-Object Name -CaseSensitive)){[pscustomobject][ordered]@{name=[string]$property.Name;value=$property.Value}})
  $mods=@(foreach($row in @($ClosureRows|Sort-Object name -CaseSensitive)){[pscustomobject][ordered]@{name=[string]$row.name;version=[string]$row.version;sha256='sha256:'+([string]$row.sha256).ToLowerInvariant()}})
  $manifest=[pscustomobject][ordered]@{
    target=[string]$Target.target_key
    engine=[ordered]@{version=[string]$Target.engine_version;executable_sha256=[string]$Target.engine_sha256}
    mir=[ordered]@{version=[string]$Target.candidate_version;package_sha256=[string]$Target.candidate_sha256;source_commit=[string]$Authority.candidate_source.commit;source_tree=[string]$Authority.candidate_source.tree}
    mods=$mods;startup_settings=$settings;extensions=@();contracts=@('mir4-environment-lock/1','mir4-exact-processir/1')
  }
  New-MIR4EnvironmentLockV1 -Manifest $manifest -Capture 'engine-post-finalizer-exact'
}

function Reset-MIR4T12RunDirectory {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path)
  $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\';$pathFull=[IO.Path]::GetFullPath($Path)
  if(-not($pathFull+'\').StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-t12-run-boundary] $pathFull"}
  if(Test-Path -LiteralPath $pathFull){Remove-Item -LiteralPath $pathFull -Recurse -Force}
  New-Item -ItemType Directory -Path $pathFull -Force|Out-Null
  $pathFull
}

function Invoke-MIR4T12ExactCapture {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Authority,[Parameter(Mandatory)]$Capture,
    [Parameter(Mandatory)][string]$EnginePath,[Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string[]]$ArchiveSearchRoots,[Parameter(Mandatory)]$SourceIdentity,
    [int]$Repetitions=2
  )
  $repo=Get-MIR4T12RepoRoot $RepoRoot
  $targetSource=$Authority.targets.PSObject.Properties[[string]$Capture.target].Value
  $target=[pscustomobject][ordered]@{target_key=[string]$Capture.target;factorio_line=[string]$targetSource.factorio_line;engine_version=[string]$targetSource.engine_version;engine_sha256=[string]$targetSource.engine_sha256;candidate=[string]$targetSource.candidate;candidate_version=[string]$targetSource.candidate_version;candidate_sha256=[string]$targetSource.candidate_sha256;available_official_mods=@($targetSource.available_official_mods)}
  $engine=(Resolve-Path -LiteralPath $EnginePath).Path
  if((Get-MIR4T12FileSha256 $engine)-cne([string]$target.engine_sha256).ToLowerInvariant()){throw "[mir4-t12-engine-identity] $($Capture.id)"}
  $candidate=Resolve-MIR4T12InputPath -RepoRoot $repo -Path ([string]$target.candidate)
  if((Get-MIR4T12FileSha256 $candidate)-cne([string]$target.candidate_sha256).ToLowerInvariant()){throw "[mir4-t12-candidate-identity] $($Capture.id)"}
  $evidence=Get-MIR4T12ScenarioEvidence -RepoRoot $repo -Capture $Capture
  $closure=@(Get-MIR4T12ClosureRows -Scenario $evidence.scenario -Lock $evidence.lock)
  $resolved=@()
  foreach($row in $closure){
    $archive=Resolve-MIR4T12Archive -Entry $row -SearchRoots $ArchiveSearchRoots
    $resolved+=[pscustomobject][ordered]@{name=[string]$row.name;version=[string]$row.version;sha256=[string]$row.sha256;archive=$archive;file_name=[IO.Path]::GetFileName($archive)}
  }
  $environmentLock=New-MIR4T12EnvironmentLock -Authority $Authority -Target $target -Scenario $evidence.scenario -ClosureRows $closure
  $observations=@()
  for($repetition=1;$repetition-le$Repetitions;$repetition++){
    $run=Reset-MIR4T12RunDirectory -Root $OutputRoot -Path (Join-Path $OutputRoot "runtime/$($Capture.id)/run-$repetition")
    $mods=Join-Path $run 'mods';New-Item -ItemType Directory -Path $mods|Out-Null
    Copy-Item -LiteralPath $candidate -Destination (Join-Path $mods ([IO.Path]::GetFileName($candidate))) -Force
    foreach($row in $resolved){Copy-Item -LiteralPath $row.archive -Destination (Join-Path $mods $row.file_name) -Force}
    $observerSource=Join-Path $run 'observer-source'
    Write-MIR4T12ObserverSource -RepoRoot $repo -Path $observerSource -Capture $Capture -Target $target -MaximumProcesses ([int]$Authority.maximum_processes_per_capture)
    Publish-MIRModDirectoryArchive -Source $observerSource -Name 'mir4-processir-exact-observer' -Version '0.1.0' -ModsDir $mods|Out-Null
    $enabled=@('more-infinite-research','mir4-processir-exact-observer')+@($resolved|ForEach-Object{[string]$_.name})+@($evidence.scenario.official_mods|ForEach-Object{[string]$_})
    $enabled=@($enabled|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_)})
    Write-MIRModList -ModsDir $mods -EnabledMods $enabled -OfficialBuiltinMods @($target.available_official_mods)
    $result=Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $run -ScenarioName ([string]$Capture.id) -ScenarioTimeoutSeconds 900
    if(-not$result.passed){$stderr=if(Test-Path -LiteralPath $result.stderr){Get-Content -Raw -LiteralPath $result.stderr}else{''};throw "[mir4-t12-factorio] $($Capture.id) repetition=$repetition exit=$($result.exit_code) $stderr"}
    $observations+=Read-MIR4T12ObserverLog -Path $result.stdout -CaptureId ([string]$Capture.id)
  }
  $digests=@($observations.digest|Sort-Object -Unique -CaseSensitive);$deterministic=$digests.Count-eq 1
  if($Repetitions-ge[int]$Authority.required_repetitions-and-not$deterministic){throw "[mir4-t12-nondeterministic] $($Capture.id) $($digests -join ',')"}
  $snapshot=New-MIR4T12ExactSnapshot -RepoRoot $repo -Capture $Capture -EnvironmentLock $environmentLock -Observed $observations[0] -SourceIdentity $SourceIdentity -Evidence $evidence -Repetitions $Repetitions -Deterministic $deterministic
  [pscustomobject][ordered]@{snapshot=$snapshot;environment_lock=$environmentLock;observer_digests=@($observations.digest);deterministic=$deterministic;resolved_mods=@($resolved|ForEach-Object{[ordered]@{name=$_.name;version=$_.version;sha256='sha256:'+([string]$_.sha256).ToLowerInvariant()}})}
}
