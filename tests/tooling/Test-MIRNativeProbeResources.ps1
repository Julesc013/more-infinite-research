# Current MIR5 native resource guard controls. No engine is launched.
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/validation/OwnedProcessMemorySampler.ps1')
$root=Join-Path $repo ('build/tmp/mir5-native-probe-controls-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Probe([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir5-native-probe-$Code]"};$script:checks++}
function Refuses-Probe([scriptblock]$Action,[string]$Expected){$actual='';try{&$Action|Out-Null}catch{$actual=$_.Exception.Message};Assert-Probe ($actual.Contains($Expected)) "refusal-$Expected"}
function Assert-ImportBoundary {
  $scriptPath=Join-Path $root 'import-boundary.ps1'
  $native=Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1'
  $body=@'
param([string]$Path)
$ErrorActionPreference='Stop'
. $Path
[ordered]@{
  context=[bool](Get-Command New-MIRNativeProbeResourceContext -ErrorAction SilentlyContinue)
  common=[bool](Get-Command Test-MIR441PathContained -ErrorAction SilentlyContinue)
  legacy_reader=[bool](Get-Command Read-MIRNativeProbeCurrentCandidate -ErrorAction SilentlyContinue)
  bootstrap=[bool](Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)
  package_authority=[bool](Get-Command Resolve-MIR4CanonicalPackageIdentity -ErrorAction SilentlyContinue)
  materializer=[bool](Get-Command Get-MIR4TargetMaterializerState -ErrorAction SilentlyContinue)
}|ConvertTo-Json -Compress
'@
  [IO.File]::WriteAllText($scriptPath,$body,[Text.UTF8Encoding]::new($false))
  $output=@(& (Get-Command pwsh -ErrorAction Stop).Source -NoProfile -File $scriptPath -Path $native 2>&1)
  Assert-Probe ($LASTEXITCODE-eq0) 'import-process'
  $state=($output-join"`n")|ConvertFrom-Json -Depth 8
  Assert-Probe ([bool]$state.context-and[bool]$state.common) 'import-current-commands'
  Assert-Probe ((-not[bool]$state.legacy_reader)-and(-not[bool]$state.bootstrap)-and(-not[bool]$state.package_authority)-and(-not[bool]$state.materializer)) 'import-legacy-commands'
}
function Assert-OwnedChildExitRace {
  $scriptPath=Join-Path $root 'owned-child-exit-race.ps1'
  $governor=Join-Path $repo 'tools/lib/validation/ResourceGovernor.ps1'
  $body=@'
param([Parameter(Mandatory)][string]$Governor)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. $Governor
function Assert-Race([bool]$Condition,[string]$Message){if(-not$Condition){throw "[mir441-owned-child-race] $Message"}}
$root=[Diagnostics.Process]::GetCurrentProcess()
$global:raceExpectedStart=[datetime]::new(2026,10,25,0,0,0,[DateTimeKind]::Utc).AddTicks(2)
$global:raceCimCreation=$global:raceExpectedStart.AddTicks(-2)
$global:raceState=[ordered]@{mode='stable';created=0;disposed=0;kills=0}
$expectedStart=$global:raceExpectedStart
$state=$global:raceState
function New-RaceProcess([int]$Id,[string]$Mode){
  $process=[pscustomobject]@{Id=$Id;WorkingSet64=[int64]11;PrivateMemorySize64=[int64]7;mode=$Mode;exit_checks=0}
  $process|Add-Member -MemberType ScriptProperty -Name HasExited -Value {
    $this.exit_checks++
    if($this.mode -in @('null-race','invalid-race')){return $this.exit_checks -gt 1}
    return $this.mode -in @('null-exited','invalid-exited')
  }
  $process|Add-Member -MemberType ScriptProperty -Name StartTime -Value {
    if($this.mode -in @('invalid-race','invalid-live','invalid-exited')){throw [InvalidOperationException]::new('simulated unavailable StartTime')}
    if($this.mode -in @('null-race','null-live','null-exited')){return $null}
    if($this.mode-ceq'replacement-live'){return $global:raceExpectedStart.AddSeconds(1)}
    return $global:raceExpectedStart
  }
  $process|Add-Member -MemberType ScriptMethod -Name Kill -Value {param([bool]$Tree)$global:raceState.kills++}
  $process|Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {param([int]$Milliseconds)return $true}
  $process|Add-Member -MemberType ScriptMethod -Name Dispose -Value {$global:raceState.disposed++}
  $global:raceState.created++
  return $process
}
function Get-CimInstance {
  [CmdletBinding()]param([string]$ClassName,[string]$Filter)
  if($Filter -ceq ('ParentProcessId='+$root.Id)){return [pscustomobject]@{ProcessId=424242;CreationDate=$global:raceCimCreation}}
}
function Get-Process {
  [CmdletBinding()]param([int]$Id)
  if($Id-eq$root.Id){return New-RaceProcess $Id 'root'}
  if($Id-eq424242){return New-RaceProcess $Id $global:raceState.mode}
  throw [Microsoft.PowerShell.Commands.ProcessCommandException]::new('simulated missing process')
}
$started=$expectedStart.AddMinutes(-1)
foreach($mode in @('null-race','invalid-race')){
  $state.mode=$mode;$beforeDisposed=[int]$state.disposed
  $tree=Get-MIR441OwnedProcessTree -Process $root -StartedUtc $started
  Assert-Race ($tree.children.Count-eq0-and$state.disposed-eq($beforeDisposed+2)) "exited $mode child was not skipped and disposed"
  $beforeDisposed=[int]$state.disposed
  Stop-MIR441OwnedProcess -Process $null -Children @([pscustomobject]@{id=424242;started_utc=$expectedStart})
  Assert-Race ($state.kills-eq0-and$state.disposed-eq($beforeDisposed+1)) "exited $mode child was killed or leaked"
}
foreach($mode in @('null-live','invalid-live')){
  $state.mode=$mode;$state.kills=0;$beforeDisposed=[int]$state.disposed;$raceFailure=''
  try{Get-MIR441OwnedProcessTree -Process $root -StartedUtc $started|Out-Null}catch{$raceFailure=$_.Exception.Message}
  Assert-Race ($raceFailure.Length-gt0-and$state.disposed-eq($beforeDisposed+2)) "live $mode child was accepted or leaked"
  $beforeDisposed=[int]$state.disposed;$raceFailure=''
  try{Stop-MIR441OwnedProcess -Process $null -Children @([pscustomobject]@{id=424242;started_utc=$expectedStart})}catch{$raceFailure=$_.Exception.Message}
  Assert-Race ($raceFailure.Length-gt0-and$state.kills-eq0-and$state.disposed-eq($beforeDisposed+1)) "live $mode child was killed, accepted, or leaked"
}
$state.mode='replacement-live';$state.kills=0;$beforeDisposed=[int]$state.disposed;$raceFailure=''
try{Get-MIR441OwnedProcessTree -Process $root -StartedUtc $started|Out-Null}catch{$raceFailure=$_.Exception.Message}
Assert-Race ($raceFailure.Contains('[mir441-owned-child-identity]')-and$state.kills-eq0-and$state.disposed-eq($beforeDisposed+2)) 'replacement PID child was accepted, killable, or leaked'
$state.mode='stable';$state.kills=0
$tree=Get-MIR441OwnedProcessTree -Process $root -StartedUtc $started
Assert-Race ($tree.children.Count-eq1-and$tree.children[0].id-eq424242-and$tree.children[0].started_utc-eq$expectedStart) 'stable child identity was not retained'
Stop-MIR441OwnedProcess -Process $null -Children $tree.children
Assert-Race ($state.kills-eq1) 'matching child identity was not killed'
$state.kills=0
Stop-MIR441OwnedProcess -Process $null -Children @([pscustomobject]@{id=424242;started_utc=$expectedStart.AddSeconds(1)})
Assert-Race ($state.kills-eq0) 'mismatched child identity was killed'
Assert-Race ($state.disposed-eq$state.created) 'an acquired child process handle was not disposed'
Write-Output 'PASS owned child exit race'
'@
  [IO.File]::WriteAllText($scriptPath,$body,[Text.UTF8Encoding]::new($false))
  $output=@(& (Get-Command pwsh -ErrorAction Stop).Source -NoProfile -File $scriptPath -Governor $governor 2>&1)
  Assert-Probe ($LASTEXITCODE-eq0) 'owned-child-exit-race'
  Assert-Probe (($output-join"`n").Contains('PASS owned child exit race')) 'owned-child-exit-race-output'
}
try {
  [IO.Directory]::CreateDirectory($root)|Out-Null
  Assert-ImportBoundary
  Assert-OwnedChildExitRace
  Refuses-Probe {New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot (Join-Path $root 'zero') -ExpectedPeakMemoryMiB 0} '[mir441-resource-peak-budget-required]'
  $occupied=Join-Path $root 'occupied';[IO.Directory]::CreateDirectory($occupied)|Out-Null;[IO.File]::WriteAllText((Join-Path $occupied 'row'),'x')
  Refuses-Probe {New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $occupied -ExpectedPeakMemoryMiB 64 -UseExactOutputRoot} '[mir-native-probe-exact-output-not-empty]'
  $run=Join-Path $root 'run'
  $context=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $run -ExpectedPeakMemoryMiB 1024 -MaxNewOutputMiB 8 -UseExactOutputRoot
  [IO.Directory]::CreateDirectory($context.root)|Out-Null
  $sourceDir=Join-Path $root 'inputs';[IO.Directory]::CreateDirectory($sourceDir)|Out-Null
  $source=Join-Path $sourceDir 'controlled.zip';[IO.File]::WriteAllText($source,'immutable controlled input',[Text.UTF8Encoding]::new($false))
  $leaseInput=[ordered]@{source_path=$source;file_name='controlled.zip';expected_sha256=Get-MIRImmutableInputSha256 $source;role='controlled';identity=@{name='controlled'};provenance=@{kind='test'};immutable=$true}
  $lease=New-MIRImmutableInputLease -RunRoot $context.root -StageDirectory (Join-Path $context.root 'mods') -Inputs @($leaseInput) -RequireHardLinks
  try {
    Add-MIRNativeProbeImmutableLease -Context $context -Lease $lease
    Assert-Probe ($context.aliases.Count-eq1-and$context.aliases[0].bytes-eq(Get-Item $source).Length) 'lease-alias'
    $before=Get-MIRNativeProbeRemainingOutputBytes -Context $context
    [IO.File]::WriteAllBytes((Join-Path $context.root 'generated.bin'),[byte[]]::new(1024))
    Assert-Probe ((Get-MIRNativeProbeRemainingOutputBytes -Context $context)-eq($before-1024)) 'output-budget'
    $child=(Get-Command pwsh -ErrorAction Stop).Source
    $runRecord=Invoke-MIRNativeProbeProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','[Console]::Out.Write("controlled")') -TimeoutSeconds 20
    Assert-Probe ($runRecord.status-ceq'passed'-and(Test-Path -LiteralPath $runRecord.ledger)-and(Test-Path -LiteralPath $runRecord.stdout)) 'governed-process'
    Assert-Probe ($null-eq$runRecord.result.PSObject.Properties['sample_milliseconds']) 'default-governor-result-shape'
    $benchmarkRoot=Join-Path $context.root 'benchmark-observation';[IO.Directory]::CreateDirectory($benchmarkRoot)|Out-Null
    $benchmarkSampler=New-MIROwnedProcessMemorySampler -Context benchmark -ExpectedSlots @([pscustomobject]@{phase='benchmark';role='factorio'})
    $benchmarkState=[pscustomobject]@{registration=$null;sample_events=0;exit_events=0}
    $registerMemorySampler=${function:Register-MIROwnedProcessMemoryProcess}
    $addMemorySample=${function:Add-MIROwnedProcessMemorySample}
    $completeMemorySampler=${function:Complete-MIROwnedProcessMemoryProcess}
    $benchmarkSample={
      param($event)
      if($event.natural_exit){throw '[mir5-native-probe-unexpected-sample-exit]'}
      if($null-eq$benchmarkState.registration){$benchmarkState.registration=& $registerMemorySampler -Sampler $benchmarkSampler -Phase benchmark -Role factorio -Process $event.process}
      if($null-eq$benchmarkState.registration){throw '[mir5-native-probe-benchmark-registration]'}
      & $addMemorySample -Sampler $benchmarkSampler
      $benchmarkState.sample_events++
    }.GetNewClosure()
    $benchmarkExit={
      param($event)
      if(-not$event.natural_exit){throw '[mir5-native-probe-missing-natural-exit]'}
      & $completeMemorySampler -Sampler $benchmarkSampler -Registration $benchmarkState.registration -NaturalExit
      $benchmarkState.exit_events++
    }.GetNewClosure()
    $benchmarkLedger=Join-Path $benchmarkRoot 'resources.jsonl'
    $benchmarkRun=Invoke-MIR441MonitoredProcess -FilePath $child -Arguments @('-NoProfile','-Command','Start-Sleep -Milliseconds 900') -WorkRoot $benchmarkRoot -LedgerPath $benchmarkLedger -Policy $context.policy -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 1024MB -TimeoutSeconds 20 -SampleMilliseconds 250 -OwnedProcessSampleCallback $benchmarkSample -OwnedProcessExitCallback $benchmarkExit
    $benchmarkReceipt=Get-MIROwnedProcessMemoryObservationReceipt -Sampler $benchmarkSampler
    Assert-Probe ($benchmarkRun.status-ceq'passed'-and$benchmarkState.sample_events-ge2-and$benchmarkState.exit_events-eq1-and$benchmarkReceipt.status-ceq'complete-observation'-and$benchmarkReceipt.context-ceq'benchmark'-and$benchmarkReceipt.observations.Count-ge2) 'benchmark-natural-exit-observation'
    Assert-Probe (@($benchmarkReceipt.observations|Where-Object {$_.phase-cne'benchmark'-or$_.role-cne'factorio'-or$_.pid-le0-or$_.working_set_bytes-lt0-or$_.private_bytes-lt0}).Count-eq0) 'benchmark-observation-identity'
    Refuses-Probe {Invoke-MIR441MonitoredProcess -FilePath $child -Arguments @('-NoProfile','-Command','exit 0') -WorkRoot (Join-Path $benchmarkRoot 'invalid-cadence') -LedgerPath (Join-Path $benchmarkRoot 'invalid-cadence/resources.jsonl') -Policy $context.policy -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 64MB -SampleMilliseconds 250} '[mir441-resource-observation-callback-required]'
    Refuses-Probe {Invoke-MIR441MonitoredProcess -FilePath $child -Arguments @('-NoProfile','-Command','exit 0') -WorkRoot (Join-Path $benchmarkRoot 'invalid-callback') -LedgerPath (Join-Path $benchmarkRoot 'invalid-callback/resources.jsonl') -Policy $context.policy -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 64MB -OwnedProcessSampleCallback {param($event)}} '[mir441-resource-observation-cadence-required]'
    Refuses-Probe {Invoke-MIR441MonitoredProcess -FilePath $child -Arguments @('-NoProfile','-Command','exit 0') -WorkRoot (Join-Path $benchmarkRoot 'invalid-interval') -LedgerPath (Join-Path $benchmarkRoot 'invalid-interval/resources.jsonl') -Policy $context.policy -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 64MB -SampleMilliseconds 500 -OwnedProcessSampleCallback {param($event)}} 'SampleMilliseconds'
    foreach($mode in @('immediate','after-sample')){
      $unsupportedRoot=Join-Path $benchmarkRoot ('completion-'+$mode)
      $unsupportedState=[pscustomobject]@{samples=0;exits=0;predicates=0}
      $predicate={
        $unsupportedState.predicates++
        return $mode -ceq 'immediate' -or $unsupportedState.samples -gt 0
      }.GetNewClosure()
      Refuses-Probe {
        Invoke-MIR441MonitoredProcess -FilePath $child -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 5') -WorkRoot $unsupportedRoot -LedgerPath (Join-Path $unsupportedRoot 'resources.jsonl') -Policy $context.policy -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 1024MB -TimeoutSeconds 20 -SampleMilliseconds 250 -CompletionPredicate $predicate -OwnedProcessSampleCallback {param($event)$unsupportedState.samples++} -OwnedProcessExitCallback {param($event)$unsupportedState.exits++}
      } '[mir441-resource-observation-completion-predicate]'
      Assert-Probe (-not(Test-Path -LiteralPath $unsupportedRoot) -and $unsupportedState.samples -eq 0 -and $unsupportedState.exits -eq 0 -and $unsupportedState.predicates -eq 0) ('benchmark-completion-preflight-'+$mode)
    }
    $callbackFailureRoot=Join-Path $benchmarkRoot 'callback-failure';[IO.Directory]::CreateDirectory($callbackFailureRoot)|Out-Null
    $callbackState=[pscustomobject]@{pid=0}
    $callbackError=''
    try{
      Invoke-MIR441MonitoredProcess -FilePath $child -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 5') -WorkRoot $callbackFailureRoot -LedgerPath (Join-Path $callbackFailureRoot 'resources.jsonl') -Policy $context.policy -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 1024MB -TimeoutSeconds 20 -SampleMilliseconds 250 -OwnedProcessSampleCallback {
        param($event)
        $callbackState.pid=[int]$event.pid
        throw '[mir5-native-probe-callback-failure]'
      }|Out-Null
    }catch{$callbackError=$_.Exception.Message}
    Assert-Probe ($callbackError.Contains('[mir5-native-probe-callback-failure]')-and$callbackState.pid-gt0-and$null-eq(Get-Process -Id $callbackState.pid -ErrorAction SilentlyContinue)) 'benchmark-callback-failure-cleanup'
    $callbackRows=@(Get-Content -LiteralPath (Join-Path $callbackFailureRoot 'resources.jsonl')|ForEach-Object {$_|ConvertFrom-Json -Depth 12})
    Assert-Probe ($callbackRows[-1].phase-ceq'interrupted'-and$callbackRows[-1].error.Contains('[mir5-native-probe-callback-failure]')) 'benchmark-callback-failure-ledger'
    Refuses-Probe {Invoke-MIRNativeProbeProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','exit 7') -TimeoutSeconds 20} '[mir441-process-exit] 7'
    $timeoutError=''
    try {Invoke-MIRNativeProbeProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 3') -TimeoutSeconds 1|Out-Null}catch{$timeoutError=$_.Exception.Message}
    Assert-Probe ($timeoutError.Contains('[mir441-process-timeout]')) 'timeout-refusal'
    $timeoutLedger=Join-Path $context.root ('process-'+$context.process_index+'.resources.jsonl')
    $timeoutRows=@(Get-Content -LiteralPath $timeoutLedger|ForEach-Object {$_|ConvertFrom-Json -Depth 12})
    Assert-Probe ($timeoutRows.Count-gt0-and$timeoutRows[-1].phase-ceq'interrupted'-and[bool]$timeoutRows[-1].timed_out) 'timeout-ledger'
    $factorioRecord=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','[Console]::Out.Write($env:SteamAppId+"/"+$env:SteamGameId)') -TimeoutSeconds 20 -AdmissionWaitSeconds 1 -AdmissionPhase 'native-probe-control'
    $text=Get-Content -Raw -LiteralPath $factorioRecord.stdout
    Assert-Probe ($text-ceq'427520/427520'-and$factorioRecord.result.duration_measurement.scope-ceq'direct-native-executable-start-to-exit'-and$factorioRecord.admission_wait.phase-ceq'native-probe-control'-and$factorioRecord.admission_wait.status-ceq'admitted-without-wait'-and$factorioRecord.admission_wait.attempt_count-ge1) 'factorio-actor-admission-wait'
    Refuses-Probe {Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $child -Arguments @('x'*20000)} '[mir-native-probe-argument-budget]'
    Write-MIRNativeProbeResult -Context $context -Record ([ordered]@{kind='MIR5NativeProbeControlV1';status='passed'})
    Assert-Probe (Test-Path -LiteralPath (Join-Path $context.root 'result.json')) 'result'
    $terminal=Complete-MIRImmutableInputLease -Lease $lease
    Assert-Probe ([bool]$terminal.inputs_sha256_match-and$terminal.outcome-ceq'passed') 'lease-terminal'
  } finally {if($null-ne$lease-and-not$lease.closed){Complete-MIRImmutableInputLease -Lease $lease -Outcome failed|Out-Null}}
  $budgetRun=Join-Path $root 'budget';$budgetContext=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $budgetRun -ExpectedPeakMemoryMiB 1024 -MaxNewOutputMiB 1 -UseExactOutputRoot
  [IO.Directory]::CreateDirectory($budgetContext.root)|Out-Null
  [IO.File]::WriteAllBytes((Join-Path $budgetContext.root 'too-large.bin'),[byte[]]::new(1MB))
  Refuses-Probe {Get-MIRNativeProbeRemainingOutputBytes -Context $budgetContext} '[mir441-resource-output-budget]'
  [pscustomobject]@{status='passed';checks=$checks;native_execution=$false;package_materialization=$false}|ConvertTo-Json -Compress
} finally {
  if(Test-Path -LiteralPath $root){Remove-MIR441ContainedTree -AdmittedRoot (Join-Path $repo 'build/tmp') -Path $root}
}
