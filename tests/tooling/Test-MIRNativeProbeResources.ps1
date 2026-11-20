# Current MIR5 native resource guard controls. No engine is launched.
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,[switch]$LinuxMountAdmissionOnly,[switch]$ConsoleStartupDeliveryFaultOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/validation/OwnedProcessMemorySampler.ps1')
$root=Join-Path $repo ('build/tmp/mir5-native-probe-controls-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Probe([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir5-native-probe-$Code]"};$script:checks++}
function Refuses-Probe([scriptblock]$Action,[string]$Expected){$actual='';try{&$Action|Out-Null}catch{$actual=$_.Exception.Message};Assert-Probe ($actual.Contains($Expected)) "refusal-$Expected"}
function Refuses-AnyProbe([scriptblock]$Action,[string]$Code){$refused=$false;try{&$Action|Out-Null}catch{$refused=$true};Assert-Probe $refused $Code}
function New-FactorioConsoleFastReplyWriter {
  param([Parameter(Mandatory)][IO.Stream]$Destination,[Parameter(Mandatory)][string]$ReplyPath,[Parameter(Mandatory)][string]$Reply)
  if($null-eq('MIR441FastReplyStreamWriter'-as[type])){
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public sealed class MIR441FastReplyStreamWriter : StreamWriter {
  private readonly string replyPath;
  private readonly string reply;
  private bool injected;
  public MIR441FastReplyStreamWriter(Stream destination,string replyPath,string reply) : base(destination,new UTF8Encoding(false),1024,true) {
    this.replyPath=replyPath;
    this.reply=reply;
    this.injected=false;
  }
  public override void Flush() {
    base.Flush();
    if(!this.injected) {
      File.AppendAllText(this.replyPath,this.reply,new UTF8Encoding(false));
      this.injected=true;
    }
  }
}
'@
  }
  return [MIR441FastReplyStreamWriter]::new($Destination,$ReplyPath,$Reply)
}
function New-FactorioConsoleFaultingWriter {
  param([Parameter(Mandatory)][IO.Stream]$Destination,[Parameter(Mandatory)][ValidateSet('write','flush')][string]$FaultPhase)
  if($null-eq('MIR441FaultingStreamWriter'-as[type])){
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public sealed class MIR441FaultingStreamWriter : StreamWriter {
  private readonly string faultPhase;
  private bool faulted;
  public MIR441FaultingStreamWriter(Stream destination,string faultPhase) : base(destination,new UTF8Encoding(false),1024,true) {
    this.faultPhase=faultPhase;
    this.faulted=false;
  }
  public override void WriteLine(string value) {
    if(this.faultPhase=="write" && !this.faulted) {
      this.faulted=true;
      throw new IOException("MIR441 controlled console write failure",new InvalidOperationException("MIR441 controlled console write inner"));
    }
    base.WriteLine(value);
  }
  public override void Flush() {
    if(this.faultPhase=="flush" && !this.faulted) {
      this.faulted=true;
      throw new InvalidOperationException("MIR441 controlled console flush failure",new IOException("MIR441 controlled console flush inner"));
    }
    base.Flush();
  }
}
'@
  }
  return [MIR441FaultingStreamWriter]::new($Destination,$FaultPhase)
}
function Send-OldMIR441FactorioConsoleStartupLine {
  # Exact pre-repair behavior retained only as an in-memory counterfactual for
  # the synchronous response boundary. It receives the same state and writer
  # as the repaired primitive rather than standing in for it with a proxy.
  param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][IO.StreamWriter]$Writer,[Parameter(Mandatory)][Diagnostics.Stopwatch]$Timer,[Parameter(Mandatory)][ValidateSet('command','confirmation-replay')][string]$Kind)
  if(($Kind-ceq'command'-and$State.receipt.send_count-ne0)-or($Kind-ceq'confirmation-replay'-and$State.receipt.send_count-ne1)){throw '[mir441-factorio-console-send-order]'}
  try {$Writer.WriteLine($State.command);$Writer.Flush()}catch{throw '[mir441-factorio-console-write]'}
  $State.receipt.send_count++
  $send=[ordered]@{
    order=$State.receipt.send_count;kind=$Kind;command_sha256=Get-MIR441TextSha256 $State.command
    elapsed_monotonic_milliseconds=[Math]::Round([double]$Timer.Elapsed.TotalMilliseconds,3)
    output_boundaries=[Collections.Generic.List[object]]::new();output_boundaries_complete=$false
  }
  $State.receipt.sends.Add($send)
  $priorSend=if($Kind-ceq'confirmation-replay'){$State.receipt.sends[$State.receipt.sends.Count-2]}else{$null}
  foreach($stream in $State.streams){
    try {
      $bytes=if(Test-Path -LiteralPath $stream.path -PathType Leaf){[int64](Get-Item -LiteralPath $stream.path).Length}else{0L}
      $send.output_boundaries.Add([ordered]@{kind=$stream.kind;path=$stream.path;bytes=$bytes})
      if($Kind-ceq'confirmation-replay'){
        $priorBoundary=@($priorSend.output_boundaries|Where-Object {$_.kind-ceq$stream.kind-and$_.path-ceq$stream.path})
        if(-not[bool]$priorSend.output_boundaries_complete-or$priorBoundary.Count-ne1-or$bytes-lt[int64]$priorBoundary[0].bytes){throw '[mir441-factorio-console-baseline]'}
      }
      if($Kind-ceq'command'){$stream.confirmation_start_offset=$bytes;$stream.confirmation_tail=''}
    } catch {throw '[mir441-factorio-console-baseline]'}
  }
  $send.output_boundaries_complete=$true
}
function Assert-LinuxDistinctSystemDiskAccounting {
  param([Parameter(Mandatory)][string]$AdmissionRoot)
  if(-not$IsLinux){return}
  $events=[pscustomobject]@{low=0;high=0;max=0;oom=0;oom_kill=0}
  $pressure=[pscustomobject]@{some=[pscustomobject]@{avg10=0.0;avg60=0.0;avg300=0.0;total=0};full=[pscustomobject]@{avg10=0.0;avg60=0.0;avg300=0.0;total=0}}
  $snapshot=[pscustomobject]@{
    memory=[pscustomobject]@{total_bytes=[int64]64GB;free_bytes=[int64]64GB;cgroup_v2=[pscustomobject]@{effective_headroom_bytes=$null;ancestors=@([pscustomobject]@{relative_path='/host-only';control_applicability='applicable';events=$events;events_local=$events;pressure=$pressure})}}
    work_volume=[ordered]@{name='/work';mount_id=[int64]36;device='8:1';free_bytes=[int64]64GB;total_bytes=[int64]128GB;filesystem_type='ext4'}
    system_volume=[ordered]@{name='/';mount_id=[int64]35;device='8:2';free_bytes=[int64]64GB;total_bytes=[int64]128GB;filesystem_type='overlay'}
  }
  $actualSnapshot=Get-MIR441ResourceSnapshot -WorkRoot $AdmissionRoot
  $actualSystemDevice=Get-MIR441LinuxVolumeDevice -Volume $actualSnapshot.system_volume
  $actualWorkDevice=Get-MIR441LinuxVolumeDevice -Volume $actualSnapshot.work_volume
  Assert-Probe ($actualSnapshot.system_volume-is[Collections.IDictionary]-and$actualSnapshot.work_volume-is[Collections.IDictionary]-and$actualSystemDevice-match'^[0-9]+:[0-9]+$'-and$actualWorkDevice-match'^[0-9]+:[0-9]+$') 'linux-snapshot-ordered-volume-device-readback'
  Assert-Probe ((Get-MIR441LinuxVolumeDevice -Volume ([pscustomobject]@{device='8:1';mount_id=[int64]35}))-ceq'8:1') 'linux-volume-device-pscustomobject-fallback'
  Refuses-Probe {Get-MIR441LinuxVolumeDevice -Volume ([ordered]@{mount_id=[int64]35})} '[mir441-resource-linux-mount-device]'
  Refuses-Probe {Get-MIR441LinuxVolumeDevice -Volume ([ordered]@{device='8:1'})} '[mir441-resource-linux-mount-device]'
  $policy=[pscustomobject]@{minimum_free_ram_gib=4;system_drive_hard_stop_free_gib=24;system_drive_target_free_gib=24;work_volume_reserve_gib=24}
  $limits=Get-MIR441ResourceLimits -Policy $policy -Snapshot $snapshot;$output=[int64]16MB
  $snapshot.system_volume['free_bytes']=[int64]$limits.system_bytes
  $snapshot.work_volume['free_bytes']=[int64]$limits.work_bytes+2*$output
  $priorSnapshot=${function:Get-MIR441ResourceSnapshot}
  try {
    Set-Item -Path Function:Get-MIR441ResourceSnapshot -Value {param([string]$WorkRoot) return $snapshot}.GetNewClosure()
    $null=Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $AdmissionRoot -EstimatedPeakBytes $output -ExpectedPeakMemoryBytes 1GB
    Assert-Probe $true 'linux-distinct-system-reserve-without-work-output-charge'
    $snapshot.system_volume['device']='8:1';$snapshot.system_volume['free_bytes']=[int64]$limits.system_bytes+2*$output-1
    Refuses-Probe {Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $AdmissionRoot -EstimatedPeakBytes $output -ExpectedPeakMemoryBytes 1GB} '[mir441-resource-admission-system-disk]'
    $snapshot.system_volume['free_bytes']=[int64]$limits.system_bytes+2*$output
    $null=Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $AdmissionRoot -EstimatedPeakBytes $output -ExpectedPeakMemoryBytes 1GB
    Assert-Probe $true 'linux-same-device-different-mount-id-retains-output-charge'
    $snapshot.system_volume['device']='8:2';$snapshot.system_volume['free_bytes']=[int64]$limits.system_bytes-1
    Refuses-Probe {Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $AdmissionRoot -EstimatedPeakBytes $output -ExpectedPeakMemoryBytes 1GB} '[mir441-resource-admission-system-disk]'
    $snapshot.system_volume['free_bytes']=[int64]$limits.system_bytes;$snapshot.work_volume['free_bytes']=[int64]$limits.work_bytes+2*$output-1
    Refuses-Probe {Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $AdmissionRoot -EstimatedPeakBytes $output -ExpectedPeakMemoryBytes 1GB} '[mir441-resource-admission-work-disk]'
    $snapshot.work_volume['free_bytes']=[int64]$limits.work_bytes+2*$output;$snapshot.system_volume['device']=''
    Refuses-Probe {Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $AdmissionRoot -EstimatedPeakBytes $output -ExpectedPeakMemoryBytes 1GB} '[mir441-resource-linux-mount-device]'
    $snapshot.system_volume['device']='8:2';$snapshot.system_volume['mount_id']=[int64]0
    Refuses-Probe {Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $AdmissionRoot -EstimatedPeakBytes $output -ExpectedPeakMemoryBytes 1GB} '[mir441-resource-linux-mount-device]'
    $snapshot.system_volume['mount_id']=[int64]35;$snapshot.work_volume['device']='malformed'
    Refuses-Probe {Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $AdmissionRoot -EstimatedPeakBytes $output -ExpectedPeakMemoryBytes 1GB} '[mir441-resource-linux-mount-device]'
  } finally {Set-Item -Path Function:Get-MIR441ResourceSnapshot -Value $priorSnapshot}
}
if($LinuxMountAdmissionOnly){
  if(-not$IsLinux){throw '[mir5-native-probe-linux-required]'}
  [IO.Directory]::CreateDirectory($root)|Out-Null
  try {
    Assert-LinuxDistinctSystemDiskAccounting -AdmissionRoot $root
    Write-Output "MIR5 Linux mount admission controls passed: $checks"
  } finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
  }
  return
}
function New-BenchmarkMemoryCallbacks {
  param([Parameter(Mandatory)]$Sampler,[string]$ReleasePath='')
  $state=[pscustomobject]@{registration=$null;sample_events=0;exit_events=0}
  $registerMemorySampler=${function:Register-MIROwnedProcessMemoryProcess}
  $addMemorySample=${function:Add-MIROwnedProcessMemorySample}
  $completeMemorySampler=${function:Complete-MIROwnedProcessMemoryProcess}
  $sample={
    param($event)
    if($event.natural_exit){throw '[mir5-native-probe-unexpected-sample-exit]'}
    if($null-eq$state.registration){$state.registration=& $registerMemorySampler -Sampler $Sampler -Phase benchmark -Role factorio -Process $event.process}
    if($null-eq$state.registration){throw '[mir5-native-probe-benchmark-registration]'}
    & $addMemorySample -Sampler $Sampler
    $state.sample_events++
    if($ReleasePath.Length-gt0-and$state.sample_events-eq2){[IO.File]::WriteAllText($ReleasePath,'observed',[Text.UTF8Encoding]::new($false))}
  }.GetNewClosure()
  $exit={
    param($event)
    if(-not$event.natural_exit){throw '[mir5-native-probe-missing-natural-exit]'}
    & $completeMemorySampler -Sampler $Sampler -Registration $state.registration -NaturalExit
    $state.exit_events++
  }.GetNewClosure()
  return [pscustomobject]@{state=$state;sample=$sample;exit=$exit}
}
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
function Assert-FactorioConsoleConfirmationBoundary {
  $consoleRoot=Join-Path $root 'factorio-console-boundary';[IO.Directory]::CreateDirectory($consoleRoot)|Out-Null
  $startup=[ordered]@{command='/c game.print("mir-native-console-boundary")';ready_marker='MIR_CONSOLE_READY';confirmation_marker='MIR_CONSOLE_CONFIRMATION'}
  $stdout=Join-Path $consoleRoot 'stdout.txt';$stderr=Join-Path $consoleRoot 'stderr.txt'
  $ready=$startup.ready_marker;$confirmation=$startup.confirmation_marker
  # Both files already contain their complete pre-command output.  Read only
  # the first block before sending so the remaining stdout confirmation would
  # have replayed the command before the byte-boundary correction.
  [IO.File]::WriteAllText($stdout,($ready+('x'*(65536-$ready.Length))+$confirmation),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($stderr,$confirmation,[Text.UTF8Encoding]::new($false))
  $state=New-MIR441FactorioConsoleStartup -Definition $startup
  Add-MIR441FactorioConsoleStartupOutput -State $state -Kind stdout -Path $stdout
  Add-MIR441FactorioConsoleStartupOutput -State $state -Kind stderr -Path $stderr
  Assert-Probe ((Update-MIR441FactorioConsoleStartupOutput -State $state)-and$state.ready_marker_seen-and-not$state.confirmation_marker_seen) 'console-pre-send-markers-not-confirmed'
  $memory=[IO.MemoryStream]::new();$writer=[IO.StreamWriter]::new($memory,[Text.UTF8Encoding]::new($false));$timer=[Diagnostics.Stopwatch]::StartNew()
  try {Send-MIR441FactorioConsoleStartupLine -State $state -Writer $writer -Timer $timer -Kind command} finally {$writer.Dispose();$memory.Dispose()}
  $commandBoundaries=@($state.receipt.sends[0].output_boundaries)
  Assert-Probe ($state.receipt.send_count-eq1-and$state.streams[0].confirmation_start_offset-eq(Get-Item -LiteralPath $stdout).Length-and$state.streams[1].confirmation_start_offset-eq(Get-Item -LiteralPath $stderr).Length) 'console-command-baselines-both-streams'
  Assert-Probe ($state.receipt.sends[0].output_boundaries_complete-and$commandBoundaries.Count-eq2-and$commandBoundaries[0].kind-ceq'stdout'-and$commandBoundaries[0].path-ceq$stdout-and$commandBoundaries[0].bytes-eq(Get-Item -LiteralPath $stdout).Length-and$commandBoundaries[1].kind-ceq'stderr'-and$commandBoundaries[1].path-ceq$stderr-and$commandBoundaries[1].bytes-eq(Get-Item -LiteralPath $stderr).Length) 'console-command-postflush-boundaries-both-streams'
  Assert-Probe ((Update-MIR441FactorioConsoleStartupOutput -State $state)-and-not$state.confirmation_marker_seen) 'console-pre-send-backlog-cannot-replay'
  [IO.File]::AppendAllText($stderr,$confirmation,[Text.UTF8Encoding]::new($false))
  Assert-Probe ((Update-MIR441FactorioConsoleStartupOutput -State $state)-and$state.confirmation_marker_seen) 'console-post-send-confirmation-observed'
  $firstOffsets=@($state.streams|ForEach-Object {[int64]$_.confirmation_start_offset})
  $replayMemory=[IO.MemoryStream]::new();$replayWriter=[IO.StreamWriter]::new($replayMemory,[Text.UTF8Encoding]::new($false));$replayTimer=[Diagnostics.Stopwatch]::StartNew()
  try {Send-MIR441FactorioConsoleStartupLine -State $state -Writer $replayWriter -Timer $replayTimer -Kind confirmation-replay} finally {$replayWriter.Dispose();$replayMemory.Dispose()}
  $replayBoundaries=@($state.receipt.sends[1].output_boundaries)
  Assert-Probe ($state.receipt.send_count-eq2-and$state.receipt.sends[1].output_boundaries_complete-and$replayBoundaries.Count-eq2-and$replayBoundaries[0].kind-ceq'stdout'-and$replayBoundaries[0].path-ceq$stdout-and$replayBoundaries[1].kind-ceq'stderr'-and$replayBoundaries[1].path-ceq$stderr-and$replayBoundaries[0].bytes-ge$commandBoundaries[0].bytes-and$replayBoundaries[1].bytes-ge$commandBoundaries[1].bytes-and$state.streams[0].confirmation_start_offset-eq$firstOffsets[0]-and$state.streams[1].confirmation_start_offset-eq$firstOffsets[1]) 'console-replay-fresh-monotone-boundaries'
  $regressedStdout=Join-Path $consoleRoot 'regressed-stdout.txt';$regressedStderr=Join-Path $consoleRoot 'regressed-stderr.txt'
  [IO.File]::WriteAllText($regressedStdout,($ready+('x'*(65536-$ready.Length))+'after-command-floor'),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($regressedStderr,'',[Text.UTF8Encoding]::new($false))
  $regressedState=New-MIR441FactorioConsoleStartup -Definition $startup
  Add-MIR441FactorioConsoleStartupOutput -State $regressedState -Kind stdout -Path $regressedStdout
  Add-MIR441FactorioConsoleStartupOutput -State $regressedState -Kind stderr -Path $regressedStderr
  Assert-Probe ((Update-MIR441FactorioConsoleStartupOutput -State $regressedState)-and$regressedState.ready_marker_seen-and-not$regressedState.confirmation_marker_seen) 'console-regression-pre-send-ready'
  $regressedCommandMemory=[IO.MemoryStream]::new();$regressedCommandWriter=[IO.StreamWriter]::new($regressedCommandMemory,[Text.UTF8Encoding]::new($false));$regressedTimer=[Diagnostics.Stopwatch]::StartNew()
  try {Send-MIR441FactorioConsoleStartupLine -State $regressedState -Writer $regressedCommandWriter -Timer $regressedTimer -Kind command} finally {$regressedCommandWriter.Dispose();$regressedCommandMemory.Dispose()}
  $firstRegressionBoundary=[int64]$regressedState.receipt.sends[0].output_boundaries[0].bytes
  $regressedHandle=[IO.File]::Open($regressedStdout,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
  try {$regressedHandle.SetLength([int64]$regressedState.streams[0].offset)} finally {$regressedHandle.Dispose()}
  [IO.File]::AppendAllText($regressedStdout,'x',[Text.UTF8Encoding]::new($false))
  [IO.File]::AppendAllText($regressedStderr,$confirmation,[Text.UTF8Encoding]::new($false))
  Assert-Probe ((Update-MIR441FactorioConsoleStartupOutput -State $regressedState)-and$regressedState.confirmation_marker_seen) 'console-regression-truncate-regrow-passes-reader-offset'
  $regressedReplayMemory=[IO.MemoryStream]::new();$regressedReplayWriter=[IO.StreamWriter]::new($regressedReplayMemory,[Text.UTF8Encoding]::new($false));$regressedError=''
  try {Send-MIR441FactorioConsoleStartupLine -State $regressedState -Writer $regressedReplayWriter -Timer $regressedTimer -Kind confirmation-replay}catch{$regressedError=$_.Exception.Message}finally{$regressedReplayWriter.Dispose();$regressedReplayMemory.Dispose();$regressedTimer.Stop()}
  Assert-Probe ($regressedError.Contains('[mir441-factorio-console-baseline]')-and$regressedState.receipt.send_count-eq1-and$regressedState.receipt.sends.Count-eq1-and$regressedState.receipt.sends[0].output_boundaries_complete-and$firstRegressionBoundary-gt(Get-Item -LiteralPath $regressedStdout).Length) 'console-replay-regressed-prewrite-floor-refused'
}
function Assert-FactorioConsoleSynchronousConfirmationBoundary {
  $consoleRoot=Join-Path $root 'factorio-console-synchronous-confirmation';[IO.Directory]::CreateDirectory($consoleRoot)|Out-Null
  $startup=[ordered]@{command='/c game.print("mir-native-console-fast-reply")';ready_marker='MIR_CONSOLE_READY';confirmation_marker='MIR_CONSOLE_CONFIRMATION'}
  $stdout=Join-Path $consoleRoot 'stdout.txt';$stderr=Join-Path $consoleRoot 'stderr.txt';$confirmation=$startup.confirmation_marker
  [IO.File]::WriteAllText($stdout,'',[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText($stderr,'',[Text.UTF8Encoding]::new($false))
  $oldState=New-MIR441FactorioConsoleStartup -Definition $startup
  Add-MIR441FactorioConsoleStartupOutput -State $oldState -Kind stdout -Path $stdout
  Add-MIR441FactorioConsoleStartupOutput -State $oldState -Kind stderr -Path $stderr
  $oldMemory=[IO.MemoryStream]::new();$oldWriter=New-FactorioConsoleFastReplyWriter -Destination $oldMemory -ReplyPath $stdout -Reply $confirmation;$timer=[Diagnostics.Stopwatch]::StartNew()
  try {Send-OldMIR441FactorioConsoleStartupLine -State $oldState -Writer $oldWriter -Timer $timer -Kind command} finally {$oldWriter.Dispose()}
  $oldPayload=[Text.UTF8Encoding]::new($false).GetString($oldMemory.ToArray());$oldMemory.Dispose()
  Assert-Probe ((Update-MIR441FactorioConsoleStartupOutput -State $oldState)-and$oldState.receipt.send_count-eq1-and$oldState.streams[0].confirmation_start_offset-eq(Get-Item -LiteralPath $stdout).Length-and-not$oldState.confirmation_marker_seen-and$oldPayload.Contains($startup.command)) 'console-fast-reply-old-postflush-floor-refuses-observed-marker'
  [IO.File]::WriteAllText($stdout,'',[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText($stderr,'',[Text.UTF8Encoding]::new($false))
  $newState=New-MIR441FactorioConsoleStartup -Definition $startup
  Add-MIR441FactorioConsoleStartupOutput -State $newState -Kind stdout -Path $stdout
  Add-MIR441FactorioConsoleStartupOutput -State $newState -Kind stderr -Path $stderr
  $newMemory=[IO.MemoryStream]::new();$newWriter=New-FactorioConsoleFastReplyWriter -Destination $newMemory -ReplyPath $stdout -Reply $confirmation
  try {Send-MIR441FactorioConsoleStartupLine -State $newState -Writer $newWriter -Timer $timer -Kind command} finally {$newWriter.Dispose();$timer.Stop()}
  $newPayload=[Text.UTF8Encoding]::new($false).GetString($newMemory.ToArray());$newMemory.Dispose()
  $newPreWriteBoundary=@($newState.receipt.sends[0].pre_write_output_boundaries);$newBoundary=@($newState.receipt.sends[0].output_boundaries);$markerStart=0L;$markerEnd=[int64][Text.UTF8Encoding]::new($false).GetByteCount($confirmation)
  Assert-Probe ((Update-MIR441FactorioConsoleStartupOutput -State $newState)-and$newState.receipt.send_count-eq1-and$newState.streams[0].confirmation_start_offset-eq0-and$newState.confirmation_marker_seen-and$newPreWriteBoundary.Count-eq2-and$newPreWriteBoundary[0].kind-ceq'stdout'-and$newPreWriteBoundary[0].bytes-le$markerStart-and$newPreWriteBoundary[1].kind-ceq'stderr'-and$newPreWriteBoundary[1].bytes-eq0-and$newBoundary.Count-eq2-and$newBoundary[0].bytes-ge$markerEnd-and$newBoundary[0].bytes-eq(Get-Item -LiteralPath $stdout).Length-and$newBoundary[1].bytes-eq0-and$newPayload.Contains($startup.command)) 'console-fast-reply-prewrite-floor-accepts-observed-marker'
}
function Assert-FactorioConsolePreWriteBoundaryFailure {
  $consoleRoot=Join-Path $root 'factorio-console-prewrite-boundary-failure';[IO.Directory]::CreateDirectory($consoleRoot)|Out-Null
  $startup=[ordered]@{command='/c game.print("mir-native-console-prewrite-failure")';ready_marker='MIR_CONSOLE_READY'}
  $stdout=Join-Path $consoleRoot 'stdout.txt';$stderr=Join-Path $consoleRoot 'stderr.txt'
  [IO.File]::WriteAllText($stdout,'pre-send-stdout',[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText($stderr,'pre-send-stderr',[Text.UTF8Encoding]::new($false))
  $state=New-MIR441FactorioConsoleStartup -Definition $startup
  Add-MIR441FactorioConsoleStartupOutput -State $state -Kind stdout -Path $stdout
  Add-MIR441FactorioConsoleStartupOutput -State $state -Kind stderr -Path $stderr
  $priorGetItem=if(Test-Path -LiteralPath Function:Get-Item){(Get-Item -LiteralPath Function:Get-Item).ScriptBlock}else{$null}
  $failingPath=$stderr
  $mockGetItem={param([string]$LiteralPath)if($LiteralPath-ceq$failingPath){throw [IO.IOException]::new('simulated pre-write stderr boundary failure')};return Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath}.GetNewClosure()
  $memory=[IO.MemoryStream]::new();$writer=[IO.StreamWriter]::new($memory,[Text.UTF8Encoding]::new($false));$timer=[Diagnostics.Stopwatch]::StartNew();$actual=''
  try {
    Set-Item -Path Function:Get-Item -Value $mockGetItem
    try {Send-MIR441FactorioConsoleStartupLine -State $state -Writer $writer -Timer $timer -Kind command}catch{$actual=$_.Exception.Message}
  } finally {
    if($null-ne$priorGetItem){Set-Item -Path Function:Get-Item -Value $priorGetItem}else{Remove-Item -Path Function:Get-Item -ErrorAction SilentlyContinue}
    $writer.Dispose()
  }
  $payload=$memory.ToArray();$memory.Dispose();$timer.Stop()
  Assert-Probe ($actual.Contains('[mir441-factorio-console-baseline]')-and$state.receipt.send_count-eq0-and$state.receipt.sends.Count-eq0-and$payload.Length-eq0-and$null-eq$state.streams[0].confirmation_start_offset-and$null-eq$state.streams[1].confirmation_start_offset) 'console-prewrite-boundary-failure-refuses-before-send'
}
function Assert-FactorioConsolePostFlushBoundaryFailure {
  $consoleRoot=Join-Path $root 'factorio-console-postflush-boundary-failure';[IO.Directory]::CreateDirectory($consoleRoot)|Out-Null
  $startup=[ordered]@{command='/c game.print("mir-native-console-boundary-failure")';ready_marker='MIR_CONSOLE_READY'}
  $stdout=Join-Path $consoleRoot 'stdout.txt';$stderr=Join-Path $consoleRoot 'stderr.txt'
  [IO.File]::WriteAllText($stdout,'pre-send-stdout',[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($stderr,'pre-send-stderr',[Text.UTF8Encoding]::new($false))
  $state=New-MIR441FactorioConsoleStartup -Definition $startup
  Add-MIR441FactorioConsoleStartupOutput -State $state -Kind stdout -Path $stdout
  Add-MIR441FactorioConsoleStartupOutput -State $state -Kind stderr -Path $stderr
  $priorGetItem=if(Test-Path -LiteralPath Function:Get-Item){(Get-Item -LiteralPath Function:Get-Item).ScriptBlock}else{$null}
  $failingPath=$stderr;$boundaryReadState=[pscustomobject]@{stderr_reads=0}
  $mockGetItem={
    param([string]$LiteralPath)
    if($LiteralPath-ceq$failingPath){
      $boundaryReadState.stderr_reads++
      if($boundaryReadState.stderr_reads-eq2){throw [IO.IOException]::new('simulated post-flush stderr boundary failure')}
    }
    return Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath
  }.GetNewClosure()
  $memory=[IO.MemoryStream]::new();$writer=[IO.StreamWriter]::new($memory,[Text.UTF8Encoding]::new($false));$timer=[Diagnostics.Stopwatch]::StartNew();$actual=''
  try {
    Set-Item -Path Function:Get-Item -Value $mockGetItem
    try {Send-MIR441FactorioConsoleStartupLine -State $state -Writer $writer -Timer $timer -Kind command}catch{$actual=$_.Exception.Message}
  } finally {
    if($null-ne$priorGetItem){Set-Item -Path Function:Get-Item -Value $priorGetItem}else{Remove-Item -Path Function:Get-Item -ErrorAction SilentlyContinue}
    $writer.Dispose();$memory.Dispose()
  }
  $boundaries=@($state.receipt.sends[0].output_boundaries)
  Assert-Probe ($actual.Contains('[mir441-factorio-console-baseline]')-and$state.receipt.send_count-eq1-and$state.receipt.sends.Count-eq1-and$state.receipt.sends[0].kind-ceq'command'-and-not$state.receipt.sends[0].output_boundaries_complete-and$boundaries.Count-eq1-and$boundaries[0].kind-ceq'stdout'-and$boundaries[0].path-ceq$stdout-and$boundaries[0].bytes-eq([int64][IO.File]::ReadAllBytes($stdout).Length)-and$state.streams[0].confirmation_start_offset-eq([int64][IO.File]::ReadAllBytes($stdout).Length)-and$state.streams[1].confirmation_start_offset-eq([int64][IO.File]::ReadAllBytes($stderr).Length)-and$boundaryReadState.stderr_reads-eq2) 'console-postflush-boundary-failure-retains-successful-send'
}
function Assert-FactorioConsoleDeliveryFailureReceipt {
  $startup=[ordered]@{command='/c game.print("mir-native-console-delivery-fault")';ready_marker='MIR_CONSOLE_READY'}
  foreach($faultPhase in @('write','flush')){
    $state=New-MIR441FactorioConsoleStartup -Definition $startup
    $memory=[IO.MemoryStream]::new();$writer=New-FactorioConsoleFaultingWriter -Destination $memory -FaultPhase $faultPhase;$timer=[Diagnostics.Stopwatch]::StartNew();$actual=''
    try {Send-MIR441FactorioConsoleStartupLine -State $state -Writer $writer -Timer $timer -Kind command}catch{$actual=$_.Exception.Message}finally{$writer.Dispose();$timer.Stop()}
    $attempts=@($state.receipt.send_attempts);$attempt=if($attempts.Count-eq1){$attempts[0]}else{$null};$members=if($null-ne$attempt){@($attempt.exception_chain.members)}else{@()};$receiptJson=$state.receipt|ConvertTo-Json -Depth 16 -Compress
    $expectedFaultType=if($faultPhase-ceq'write'){'System.IO.IOException'}else{'System.InvalidOperationException'}
    $expectedFaultHResult=if($faultPhase-ceq'write'){-2146232800L}else{-2146233079L}
    Assert-Probe ($actual.Contains('[mir441-factorio-console-write]')-and$state.receipt.send_count-eq0-and$state.receipt.sends.Count-eq0-and$state.receipt.send_attempt_count-eq1-and$state.receipt.delivery_unknown-and$attempts.Count-eq1-and$attempt.order-eq1-and$attempt.kind-ceq'command'-and$attempt.phase-ceq$faultPhase-and$attempt.delivery-ceq'unknown'-and$members.Count-ge1-and@($members|Where-Object {[string]::IsNullOrWhiteSpace([string]$_.type)-or($_.hresult -isnot [long])}).Count-eq0-and@($members|Where-Object {$_.type-ceq$expectedFaultType-and[long]$_.hresult-eq$expectedFaultHResult}).Count-eq1-and-not$receiptJson.Contains($startup.command)) "console-$faultPhase-failure-records-sanitized-unknown-delivery"
    Refuses-Probe {Send-MIR441FactorioConsoleStartupLine -State $state -Writer $writer -Timer $timer -Kind command} '[mir441-factorio-console-delivery-unknown]'
    Assert-Probe ($state.receipt.send_attempt_count-eq1-and$state.receipt.send_attempts.Count-eq1-and$state.receipt.send_count-eq0-and$state.receipt.sends.Count-eq0) "console-$faultPhase-failure-never-replays-unknown-delivery"
    $memory.Dispose()
  }
  $successState=New-MIR441FactorioConsoleStartup -Definition $startup
  $successMemory=[IO.MemoryStream]::new();$successWriter=[IO.StreamWriter]::new($successMemory,[Text.UTF8Encoding]::new($false));$successTimer=[Diagnostics.Stopwatch]::StartNew()
  try {Send-MIR441FactorioConsoleStartupLine -State $successState -Writer $successWriter -Timer $successTimer -Kind command} finally {$successWriter.Dispose();$successTimer.Stop()}
  $successAttempt=@($successState.receipt.send_attempts)[0]
  Assert-Probe ($successState.receipt.send_count-eq1-and$successState.receipt.sends.Count-eq1-and$successState.receipt.send_attempt_count-eq1-and$successState.receipt.send_attempts.Count-eq1-and-not$successState.receipt.delivery_unknown-and$successAttempt.order-eq1-and$successAttempt.kind-ceq'command'-and$successAttempt.phase-ceq'flush'-and$successAttempt.delivery-ceq'writer-flushed'-and$null-eq$successAttempt.exception_chain) 'console-successful-flush-is-observed-separately-from-delivery'
  $successMemory.Dispose()
}
function Assert-FactorioConsoleStartup {
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Child)
  $consoleRoot=Join-Path $Context.root 'factorio-console-startup';[IO.Directory]::CreateDirectory($consoleRoot)|Out-Null
  $actor=Join-Path $consoleRoot 'fake-factorio-console.ps1'
  [IO.File]::WriteAllText($actor,@'
param([Parameter(Mandatory)][string]$Record,[Parameter(Mandatory)][string]$PidPath,[ValidateSet("ordinary","confirmation","failure","timeout")][string]$Mode="ordinary")
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($PidPath,[string]$PID,$utf8)
$reader=[IO.StreamReader]::new([Console]::OpenStandardInput(),[Text.UTF8Encoding]::new($false),$false,1024,$false)
try {
  $first=$reader.ReadLineAsync()
  $early=$first.Wait(150)
  [Console]::Out.WriteLine("MIR_CONSOLE_EARLY_INPUT=$early")
  Start-Sleep -Milliseconds 180
  [Console]::Out.WriteLine("MIR_CONSOLE_READY")
  $lines=[Collections.Generic.List[string]]::new()
  $lines.Add($first.GetAwaiter().GetResult())
  if($Mode -ceq "confirmation") {
    [Console]::Error.WriteLine("MIR_CONSOLE_CONFIRMATION")
    $lines.Add($reader.ReadLineAsync().GetAwaiter().GetResult())
    [Console]::Error.WriteLine("MIR_CONSOLE_CONFIRMATION")
  } else {
    # A repeated ready line is not a reason to resend the first command.
    [Console]::Out.WriteLine("MIR_CONSOLE_READY")
  }
  [IO.File]::WriteAllLines($Record,$lines,$utf8)
  if($Mode -ceq "failure") {exit 17}
  if($Mode -ceq "timeout") {Start-Sleep -Seconds 10}
} finally {$reader.Dispose()}
'@,[Text.UTF8Encoding]::new($false))
  $command='/c game.print("mir-native-console-probe")'
  $startup=[ordered]@{command=$command;ready_marker='MIR_CONSOLE_READY';confirmation_marker='MIR_CONSOLE_CONFIRMATION'}
  $expectedHash=Get-MIR441TextSha256 -Text $command
  $burstReady=New-MIR441FactorioConsoleStartup -Definition $startup
  $burstReadyPath=Join-Path $consoleRoot 'ready-burst.txt'
  [IO.File]::WriteAllText($burstReadyPath,('MIR_CONSOLE_READY'+('x'*9000)),[Text.UTF8Encoding]::new($false))
  Add-MIR441FactorioConsoleStartupOutput -State $burstReady -Kind stdout -Path $burstReadyPath
  Assert-Probe ((Update-MIR441FactorioConsoleStartupOutput -State $burstReady)-and$burstReady.ready_marker_seen) 'console-ready-burst-marker-retained'
  $burstConfirmation=New-MIR441FactorioConsoleStartup -Definition $startup
  $burstConfirmation.receipt.send_count=1
  $burstConfirmationPath=Join-Path $consoleRoot 'confirmation-burst.txt'
  [IO.File]::WriteAllText($burstConfirmationPath,('MIR_CONSOLE_CONFIRMATION'+('x'*9000)),[Text.UTF8Encoding]::new($false))
  Add-MIR441FactorioConsoleStartupOutput -State $burstConfirmation -Kind stderr -Path $burstConfirmationPath
  Assert-Probe ((Update-MIR441FactorioConsoleStartupOutput -State $burstConfirmation)-and$burstConfirmation.confirmation_marker_seen) 'console-confirmation-burst-marker-retained'
  $closedState=New-MIR441FactorioConsoleStartup -Definition $startup
  $closedStream=[IO.MemoryStream]::new();$closedWriter=[IO.StreamWriter]::new($closedStream,[Text.UTF8Encoding]::new($false));$closedWriter.Dispose();$closedWriterError='';$closedTimer=[Diagnostics.Stopwatch]::StartNew()
  try {Send-MIR441FactorioConsoleStartupLine -State $closedState -Writer $closedWriter -Timer $closedTimer -Kind command}catch{$closedWriterError=$_.Exception.Message}finally{$closedStream.Dispose()}
  Assert-Probe ($closedWriterError.Contains('[mir441-factorio-console-write]')-and$closedState.receipt.send_count-eq0-and$closedState.receipt.sends.Count-eq0) 'console-closed-writer-refusal'
  Assert-FactorioConsoleDeliveryFailureReceipt
  $ordinaryRecord=Join-Path $consoleRoot 'ordinary-input.txt';$ordinaryPid=Join-Path $consoleRoot 'ordinary.pid'
  $ordinary=Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$ordinaryRecord,'-PidPath',$ordinaryPid,'-Mode','ordinary') -TimeoutSeconds 20 -ConsoleStartup $startup
  $ordinaryInput=@(Get-Content -LiteralPath $ordinaryRecord)
  $ordinaryReceipt=$ordinary.result.console_startup
  $ordinaryOut=Get-Content -Raw -LiteralPath $ordinary.stdout
  Assert-Probe ($ordinary.status-ceq'passed'-and$ordinaryInput.Count-eq1-and$ordinaryInput[0]-ceq$command) 'console-delayed-ready-single-delivery'
  $ordinaryBoundaries=@($ordinaryReceipt.sends[0].output_boundaries)
  Assert-Probe ($ordinaryOut.Contains('MIR_CONSOLE_EARLY_INPUT=False')-and$ordinaryReceipt.ready_marker_observed-and$ordinaryReceipt.ready_elapsed_monotonic_milliseconds-ge150-and$ordinaryReceipt.send_count-eq1-and$ordinaryReceipt.sends.Count-eq1-and$ordinaryReceipt.sends[0].order-eq1-and$ordinaryReceipt.sends[0].kind-ceq'command'-and$ordinaryReceipt.sends[0].command_sha256-ceq$expectedHash-and$ordinaryReceipt.sends[0].elapsed_monotonic_milliseconds-ge$ordinaryReceipt.ready_elapsed_monotonic_milliseconds-and$ordinaryReceipt.sends[0].output_boundaries_complete-and$ordinaryBoundaries.Count-eq2-and$ordinaryBoundaries[0].kind-ceq'stdout'-and$ordinaryBoundaries[0].path-ceq$ordinary.stdout-and$ordinaryBoundaries[1].kind-ceq'stderr'-and$ordinaryBoundaries[1].path-ceq$ordinary.stderr) 'console-ready-gate-receipt'
  Assert-Probe ((-not$ordinaryReceipt.confirmation_marker_observed)-and$ordinaryReceipt.command_sha256-ceq$expectedHash-and($ordinaryReceipt|ConvertTo-Json -Depth 12 -Compress).Contains($command)-eq$false) 'console-single-receipt-hash-only'
  $confirmationRecord=Join-Path $consoleRoot 'confirmation-input.txt';$confirmationPid=Join-Path $consoleRoot 'confirmation.pid'
  $confirmation=Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$confirmationRecord,'-PidPath',$confirmationPid,'-Mode','confirmation') -TimeoutSeconds 20 -ConsoleStartup $startup
  $confirmationInput=@(Get-Content -LiteralPath $confirmationRecord)
  $confirmationReceipt=$confirmation.result.console_startup
  Assert-Probe ($confirmation.status-ceq'passed'-and$confirmationInput.Count-eq2-and@($confirmationInput|Where-Object {$_-cne$command}).Count-eq0) 'console-confirmation-replays-same-command'
  $confirmationFirstBoundaries=@($confirmationReceipt.sends[0].output_boundaries);$confirmationReplayBoundaries=@($confirmationReceipt.sends[1].output_boundaries)
  Assert-Probe ($confirmationReceipt.confirmation_marker_observed-and$confirmationReceipt.send_count-eq2-and$confirmationReceipt.sends.Count-eq2-and$confirmationReceipt.sends[0].kind-ceq'command'-and$confirmationReceipt.sends[1].kind-ceq'confirmation-replay'-and$confirmationReceipt.sends[1].order-eq2-and$confirmationReceipt.sends[1].command_sha256-ceq$expectedHash-and$confirmationReceipt.sends[1].elapsed_monotonic_milliseconds-ge$confirmationReceipt.confirmation_elapsed_monotonic_milliseconds-and$confirmationReceipt.sends[0].output_boundaries_complete-and$confirmationReceipt.sends[1].output_boundaries_complete-and$confirmationFirstBoundaries.Count-eq2-and$confirmationReplayBoundaries.Count-eq2-and$confirmationReplayBoundaries[0].bytes-ge$confirmationFirstBoundaries[0].bytes-and$confirmationReplayBoundaries[1].bytes-ge$confirmationFirstBoundaries[1].bytes) 'console-confirmation-bounded-receipt'
  $invalidLaunch=Join-Path $consoleRoot 'invalid-launch.txt';$invalidPid=Join-Path $consoleRoot 'invalid.pid';$beforeIndex=$Context.process_index
  Refuses-Probe {Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$invalidLaunch,'-PidPath',$invalidPid) -TimeoutSeconds 20 -ConsoleStartup ([ordered]@{command="/c invalid`nsecond";ready_marker='MIR_CONSOLE_READY'})} '[mir441-factorio-console-startup-newline]'
  Refuses-Probe {Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$invalidLaunch,'-PidPath',$invalidPid) -TimeoutSeconds 20 -ConsoleStartup ([ordered]@{command=('/c '+('x'*16382));ready_marker='MIR_CONSOLE_READY'})} '[mir441-factorio-console-startup-command]'
  Refuses-Probe {Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$invalidLaunch,'-PidPath',$invalidPid) -TimeoutSeconds 20 -ConsoleStartup ([ordered]@{command=$command;ready_marker='MIR_CONSOLÉ_READY'})} '[mir441-factorio-console-startup-marker]'
  Assert-Probe ($Context.process_index-eq$beforeIndex-and-not(Test-Path -LiteralPath $invalidLaunch)-and-not(Test-Path -LiteralPath $invalidPid)) 'console-invalid-refused-before-launch'
  $failureRecord=Join-Path $consoleRoot 'failure-input.txt';$failurePid=Join-Path $consoleRoot 'failure.pid';$failureError=''
  try {Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$failureRecord,'-PidPath',$failurePid,'-Mode','failure') -TimeoutSeconds 20 -ConsoleStartup $startup|Out-Null}catch{$failureError=$_.Exception.Message}
  $failureRun=$Context.runs[$Context.runs.Count-1]
  Assert-Probe ($failureError.Contains('[mir441-process-exit] 17')-and$failureRun.status-ceq'failed'-and$failureRun.console_startup.command_sha256-ceq$expectedHash-and$failureRun.console_startup.send_count-eq1-and$null-eq(Get-Process -Id ([int](Get-Content -Raw -LiteralPath $failurePid)) -ErrorAction SilentlyContinue)) 'console-natural-failure-propagates-and-cleans'
  $timeoutRecord=Join-Path $consoleRoot 'timeout-input.txt';$timeoutPid=Join-Path $consoleRoot 'timeout.pid';$timeoutError=''
  try {Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$timeoutRecord,'-PidPath',$timeoutPid,'-Mode','timeout') -TimeoutSeconds 2 -ConsoleStartup $startup|Out-Null}catch{$timeoutError=$_.Exception.Message}
  $timeoutRun=$Context.runs[$Context.runs.Count-1]
  Assert-Probe ($timeoutError.Contains('[mir441-process-timeout]')-and$timeoutRun.status-ceq'interrupted'-and$timeoutRun.console_startup.command_sha256-ceq$expectedHash-and$timeoutRun.console_startup.send_count-eq1-and$null-eq(Get-Process -Id ([int](Get-Content -Raw -LiteralPath $timeoutPid)) -ErrorAction SilentlyContinue)) 'console-timeout-propagates-and-cleans'
  $sender=${function:Send-MIR441FactorioConsoleStartupLine};$seamRecord=Join-Path $consoleRoot 'send-error-input.txt';$seamPid=Join-Path $consoleRoot 'send-error.pid';$seamError=''
  try {
    Set-Item -Path Function:Send-MIR441FactorioConsoleStartupLine -Value {param($State,$Writer,$Timer,$Kind)throw '[mir5-native-probe-console-owned-send-error]'}
    try {Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$seamRecord,'-PidPath',$seamPid,'-Mode','ordinary') -TimeoutSeconds 20 -ConsoleStartup $startup|Out-Null}catch{$seamError=$_.Exception.Message}
  } finally {Set-Item -Path Function:Send-MIR441FactorioConsoleStartupLine -Value $sender}
  $seamRun=$Context.runs[$Context.runs.Count-1]
  Assert-Probe ($seamError.Contains('[mir5-native-probe-console-owned-send-error]')-and$seamRun.status-ceq'interrupted'-and$seamRun.console_startup.command_sha256-ceq$expectedHash-and$seamRun.console_startup.ready_marker_observed-and$seamRun.console_startup.send_count-eq0-and$null-eq(Get-Process -Id ([int](Get-Content -Raw -LiteralPath $seamPid)) -ErrorAction SilentlyContinue)) 'console-writer-failure-cleans'
  # A write-side primary can leave buffered input while its base stream is
  # already closed. This reproduces the cleanup masking boundary without an
  # engine: the primary identity and receipt must survive every later cleanup.
  $primaryDisposeRecord=Join-Path $consoleRoot 'primary-dispose-input.txt';$primaryDisposePid=Join-Path $consoleRoot 'primary-dispose.pid';$primaryDisposeError=$null
  $expectedPrimary=[InvalidOperationException]::new('[mir441-factorio-console-write] controlled-primary')
  $expectedPrimary.Data['controlled_primary_data']='preserved'
  try {
    $primaryDisposeSender={
      param($State,$Writer,$Timer,$Kind)
      $Writer.AutoFlush=$false
      $Writer.Write('pending-buffered-input')
      $Writer.BaseStream.Dispose()
      throw $expectedPrimary
    }.GetNewClosure()
    Set-Item -Path Function:Send-MIR441FactorioConsoleStartupLine -Value $primaryDisposeSender
    try {Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$primaryDisposeRecord,'-PidPath',$primaryDisposePid,'-Mode','ordinary') -TimeoutSeconds 20 -ConsoleStartup $startup|Out-Null}catch{$primaryDisposeError=$_}
  } finally {Set-Item -Path Function:Send-MIR441FactorioConsoleStartupLine -Value $sender}
  $primaryDisposeRun=$Context.runs[$Context.runs.Count-1]
  $primaryDisposeFacts=@($primaryDisposeError.Exception.Data['mir441_process_cleanup_facts'])
  $primaryStdinFact=@($primaryDisposeFacts|Where-Object {$_.step-ceq'stdinwriter-dispose'})
  $primaryLaterFacts=@($primaryDisposeFacts|Where-Object {$_.step-in@('process-dispose','temporary-root-remove','main-lock-dispose')})
  $primaryCleanupSteps=@('process-stop-on-failure','interrupted-ledger-write','process-stop-finally','output-copy-wait','output-stream-dispose','stdinwriter-dispose','process-dispose','temporary-root-remove','account-lock-dispose','main-lock-dispose')
  $primaryObservedSteps=@($primaryDisposeFacts|ForEach-Object {$_.step})
  Assert-Probe ($null-ne$primaryDisposeError-and[object]::ReferenceEquals($primaryDisposeError.Exception,$expectedPrimary)-and$primaryDisposeError.Exception.Data['controlled_primary_data']-ceq'preserved'-and$primaryDisposeRun.status-ceq'interrupted'-and$primaryDisposeRun.console_startup.command_sha256-ceq$expectedHash-and$primaryDisposeRun.console_startup.ready_marker_observed-and$primaryDisposeRun.cleanup_facts.Count-eq$primaryDisposeFacts.Count-and$primaryStdinFact.Count-eq1-and-not$primaryStdinFact[0].succeeded-and$primaryLaterFacts.Count-eq3-and@($primaryLaterFacts|Where-Object {-not $_.attempted-or-not $_.succeeded}).Count-eq0-and@($primaryCleanupSteps|Where-Object {$_-notin$primaryObservedSteps}).Count-eq0-and$null-eq(Get-Process -Id ([int](Get-Content -Raw -LiteralPath $primaryDisposePid)) -ErrorAction SilentlyContinue)) 'console-primary-dispose-preserves-primary-and-later-cleanup'
  $heavyLock=Join-Path $repo 'build/tmp/mir-heavy.lock';$reacquiredLock=$null
  try {$reacquiredLock=[IO.File]::Open($heavyLock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);Assert-Probe $true 'console-primary-dispose-releases-main-lock'} finally {if($null-ne$reacquiredLock){$reacquiredLock.Dispose()}}
  # A disposal error after an otherwise successful send must still be adverse:
  # the command receipt remains available, but no natural result is invented.
  $cleanupOnlyRecord=Join-Path $consoleRoot 'cleanup-only-input.txt';$cleanupOnlyPid=Join-Path $consoleRoot 'cleanup-only.pid';$cleanupOnlyError=$null
  try {
    $cleanupOnlySender={
      param($State,$Writer,$Timer,$Kind)
      & $sender $State $Writer $Timer $Kind
      $Writer.AutoFlush=$false
      $Writer.Write('pending-buffered-input')
      $Writer.BaseStream.Dispose()
    }.GetNewClosure()
    Set-Item -Path Function:Send-MIR441FactorioConsoleStartupLine -Value $cleanupOnlySender
    try {Invoke-MIRNativeProbeFactorioProcess -Context $Context -FilePath $Child -Arguments @('-NoProfile','-File',$actor,'-Record',$cleanupOnlyRecord,'-PidPath',$cleanupOnlyPid,'-Mode','ordinary') -TimeoutSeconds 20 -ConsoleStartup $startup|Out-Null}catch{$cleanupOnlyError=$_}
  } finally {Set-Item -Path Function:Send-MIR441FactorioConsoleStartupLine -Value $sender}
  $cleanupOnlyRun=$Context.runs[$Context.runs.Count-1]
  $cleanupOnlyFacts=@($cleanupOnlyError.Exception.Data['mir441_process_cleanup_facts']|Where-Object {$null-ne$_})
  $cleanupOnlyStdinFact=@($cleanupOnlyFacts|Where-Object {$null-ne$_.PSObject.Properties['step']-and$_.step-ceq'stdinwriter-dispose'})
  Assert-Probe ($null-ne$cleanupOnlyError-and$cleanupOnlyError.Exception.Message-ceq'[mir441-process-cleanup]'-and$cleanupOnlyRun.status-ceq'interrupted'-and$cleanupOnlyRun.console_startup.command_sha256-ceq$expectedHash-and$cleanupOnlyRun.console_startup.send_count-eq1-and$cleanupOnlyRun.cleanup_facts.Count-eq$cleanupOnlyFacts.Count-and$cleanupOnlyStdinFact.Count-eq1-and-not$cleanupOnlyStdinFact[0].succeeded-and$null-eq($cleanupOnlyRun.PSObject.Properties['result'])-and$null-eq(Get-Process -Id ([int](Get-Content -Raw -LiteralPath $cleanupOnlyPid)) -ErrorAction SilentlyContinue)) 'console-cleanup-only-failure-remains-adverse-with-receipt'
}
try {
  [IO.Directory]::CreateDirectory($root)|Out-Null
  if($ConsoleStartupDeliveryFaultOnly){
    Assert-FactorioConsoleDeliveryFailureReceipt
    [pscustomobject]@{status='passed';checks=$checks;native_execution=$false;package_materialization=$false;scope='console-startup-delivery-faults'}|ConvertTo-Json -Compress
    return
  }
  $scan=Join-Path $root 'scan-diagnostics';$scanTarget=Join-Path $root 'scan-target'
  [IO.Directory]::CreateDirectory($scan)|Out-Null;[IO.Directory]::CreateDirectory($scanTarget)|Out-Null
  [IO.File]::WriteAllBytes((Join-Path $scan 'regular.bin'),[byte[]]@(1,2,3))
  [IO.File]::WriteAllBytes((Join-Path $scanTarget 'excluded.bin'),[byte[]]::new(9))
  $usage=Get-MIR441TreeUsage -Path $scan
  Assert-Probe ($usage.complete-and$usage.files-eq1-and$usage.bytes-eq3-and$null-eq$usage.stopped_by-and$usage.elapsed_ms-ge0-and$usage.reparse_points-eq0) 'complete-scan-diagnostics'
  $scanLink=Join-Path $scan 'excluded'
  try {
    New-Item -ItemType $(if($IsWindows){'Junction'}else{'SymbolicLink'}) -Path $scanLink -Target $scanTarget|Out-Null
    $usage=Get-MIR441TreeUsage -Path $scan
    Assert-Probe (-not$usage.complete-and$usage.files-eq1-and$usage.bytes-eq3-and$usage.stopped_by-ceq'reparse-point'-and$usage.reparse_points-eq1-and$usage.elapsed_ms-ge0) 'reparse-scan-diagnostics'
    $scanError='';try{Get-MIRNativeProbeRemainingOutputBytes -Context ([pscustomobject]@{aliases=@();root=$scan})|Out-Null}catch{$scanError=$_.Exception.Message}
    Assert-Probe ($scanError.StartsWith('[mir441-resource-output-scan-incomplete] ')-and$scanError.Contains('"stopped_by":"reparse-point"')-and$scanError.Contains('"reparse_points":1')) 'incomplete-scan-refusal-diagnostics'
  } finally {if(Test-Path -LiteralPath $scanLink){[IO.Directory]::Delete($scanLink)}}
  Assert-ImportBoundary
  Assert-OwnedChildExitRace
  Assert-FactorioConsoleConfirmationBoundary
  Assert-FactorioConsoleSynchronousConfirmationBoundary
  Assert-FactorioConsolePreWriteBoundaryFailure
  Assert-FactorioConsolePostFlushBoundaryFailure
  $child=(Get-Command pwsh -ErrorAction Stop).Source
  Refuses-Probe {New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot (Join-Path $root 'zero') -ExpectedPeakMemoryMiB 0} '[mir441-resource-peak-budget-required]'
  $occupied=Join-Path $root 'occupied';[IO.Directory]::CreateDirectory($occupied)|Out-Null;[IO.File]::WriteAllText((Join-Path $occupied 'row'),'x')
  Refuses-Probe {New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $occupied -ExpectedPeakMemoryMiB 64 -UseExactOutputRoot} '[mir-native-probe-exact-output-not-empty]'
  $admissionRoot=Join-Path $root 'eight-gib-admission-boundary';[IO.Directory]::CreateDirectory($admissionRoot)|Out-Null
  $admissionPolicy=[pscustomobject]@{minimum_free_ram_gib=4}
  $eightGiB=[int64]8GB
  $boundarySnapshot=[pscustomobject]@{
    observed_at='test';memory=[pscustomobject]@{total_bytes=[int64]64GB;free_bytes=[int64]64GB;commit_limit_bytes=[int64]64GB;committed_bytes=0L}
    work_volume=[pscustomobject]@{name='W:';mount_id=[int64]1;device='8:1';free_bytes=[int64]100GB;total_bytes=[int64]200GB}
    system_volume=[pscustomobject]@{name='S:';mount_id=[int64]1;device='8:1';free_bytes=[int64]100GB;total_bytes=[int64]200GB}
  }
  $admissionLimits=Get-MIR441ResourceLimits -Policy $admissionPolicy -Snapshot $boundarySnapshot
  $requiredDisk=[int64]$admissionLimits.work_bytes+2*$eightGiB
  Assert-Probe ($requiredDisk-[int64]$admissionLimits.work_bytes-eq16GB) 'eight-gib-double-output-reserve'
  $boundarySnapshot.work_volume.free_bytes=$requiredDisk;$boundarySnapshot.system_volume.free_bytes=$requiredDisk
  $priorSnapshot=${function:Get-MIR441ResourceSnapshot}
  try {
    Set-Item -Path Function:Get-MIR441ResourceSnapshot -Value {param([string]$WorkRoot) return $boundarySnapshot}.GetNewClosure()
    $null=Assert-MIR441ResourceAdmission -Policy $admissionPolicy -WorkRoot $admissionRoot -EstimatedPeakBytes $eightGiB -ExpectedPeakMemoryBytes 1024MB
    $boundarySnapshot.work_volume.free_bytes=$requiredDisk-1
    Refuses-Probe {Assert-MIR441ResourceAdmission -Policy $admissionPolicy -WorkRoot $admissionRoot -EstimatedPeakBytes $eightGiB -ExpectedPeakMemoryBytes 1024MB} '[mir441-resource-admission-work-disk]'
    Refuses-Probe {Assert-MIR441ResourceAdmission -Policy $admissionPolicy -WorkRoot $admissionRoot -EstimatedPeakBytes ($eightGiB+1) -ExpectedPeakMemoryBytes 1024MB} '[mir441-resource-staging-budget]'
    Refuses-Probe {Assert-MIR441ResourceAdmission -Policy $admissionPolicy -WorkRoot $admissionRoot -EstimatedPeakBytes -1 -ExpectedPeakMemoryBytes 1024MB} '[mir441-resource-staging-budget]'
  } finally {
    Set-Item -Path Function:Get-MIR441ResourceSnapshot -Value $priorSnapshot
  }
  Assert-LinuxDistinctSystemDiskAccounting -AdmissionRoot $admissionRoot
  $defaultBudget=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot (Join-Path $root 'default-budget') -ExpectedPeakMemoryMiB 1024 -UseExactOutputRoot
  Assert-Probe ([int64]$defaultBudget.max_new_output_bytes -eq [int64]120MB) 'default-output-budget'
  $boundarySnapshot.work_volume.free_bytes=$requiredDisk;$boundarySnapshot.system_volume.free_bytes=$requiredDisk
  $priorSnapshot=${function:Get-MIR441ResourceSnapshot}
  try {
    Set-Item -Path Function:Get-MIR441ResourceSnapshot -Value {param([string]$WorkRoot) return $boundarySnapshot}.GetNewClosure()
    $eightGiBBudget=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot (Join-Path $root 'eight-gib-budget') -ExpectedPeakMemoryMiB 1024 -MaxNewOutputMiB 8192 -UseExactOutputRoot
    Assert-Probe ([int64]$eightGiBBudget.max_new_output_bytes -eq [int64]8192MB) 'eight-gib-output-budget-admitted'
  } finally {
    Set-Item -Path Function:Get-MIR441ResourceSnapshot -Value $priorSnapshot
  }
  $tenGiB=[int64]10GB
  $tenGiBMemoryRequired=[int64]$admissionLimits.physical_bytes+$tenGiB
  $boundarySnapshot.memory.free_bytes=$tenGiBMemoryRequired
  $priorSnapshot=${function:Get-MIR441ResourceSnapshot}
  try {
    Set-Item -Path Function:Get-MIR441ResourceSnapshot -Value {param([string]$WorkRoot) return ($boundarySnapshot|Select-Object *)}.GetNewClosure()
    $tenGiBBudget=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot (Join-Path $root 'ten-gib-peak-budget') -ExpectedPeakMemoryMiB 10240 -MaxNewOutputMiB 1 -UseExactOutputRoot
    Assert-Probe ([int64]$tenGiBBudget.peak_memory_bytes -eq $tenGiB) 'ten-gib-declared-peak-admitted'
    [IO.Directory]::CreateDirectory($tenGiBBudget.root)|Out-Null
    $tenGiBRelease=Join-Path $tenGiBBudget.root 'two-samples.release'
    $tenGiBChild=Join-Path $tenGiBBudget.root 'wait-for-two-samples.ps1'
    [IO.File]::WriteAllText($tenGiBChild,@'
param([Parameter(Mandatory)][string]$ReleasePath)
$deadline=[DateTime]::UtcNow.AddSeconds(10)
while(-not(Test-Path -LiteralPath $ReleasePath -PathType Leaf)){
  if([DateTime]::UtcNow-ge$deadline){exit 17}
  Start-Sleep -Milliseconds 50
}
'@,[Text.UTF8Encoding]::new($false))
    $tenGiBState=[pscustomobject]@{sample_events=0}
    $tenGiBSample={
      param($event)
      $tenGiBState.sample_events++
      if($tenGiBState.sample_events-eq2){[IO.File]::WriteAllText($tenGiBRelease,'observed',[Text.UTF8Encoding]::new($false))}
    }.GetNewClosure()
    $tenGiBRun=Invoke-MIRNativeProbeProcess -Context $tenGiBBudget -FilePath $child -Arguments @('-NoProfile','-File',$tenGiBChild,'-ReleasePath',$tenGiBRelease) -TimeoutSeconds 20 -SampleMilliseconds 250 -OwnedProcessSampleCallback $tenGiBSample
    $tenGiBRunning=@(Get-Content -LiteralPath $tenGiBRun.ledger|ForEach-Object {$_|ConvertFrom-Json -Depth 12}|Where-Object {$null-ne$_.PSObject.Properties['process']})
    Assert-Probe ($tenGiBRun.status-ceq'passed'-and$tenGiBState.sample_events-ge2-and(Test-Path -LiteralPath $tenGiBRelease)-and$tenGiBRunning.Count-ge2-and@($tenGiBRunning|Where-Object {[int64]$_.process.expected_peak_memory_bytes-ne$tenGiB}).Count-eq0) 'ten-gib-process-budget-forwarded-across-samples'
    Assert-Probe ($null-eq$boundarySnapshot.PSObject.Properties['process']) 'snapshot-source-not-mutated-across-samples'
    $boundarySnapshot.memory.free_bytes=$tenGiBMemoryRequired-1
    Refuses-Probe {New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot (Join-Path $root 'ten-gib-insufficient-memory') -ExpectedPeakMemoryMiB 10240 -MaxNewOutputMiB 1 -UseExactOutputRoot} '[mir441-resource-admission-memory]'
  } finally {
    Set-Item -Path Function:Get-MIR441ResourceSnapshot -Value $priorSnapshot
  }
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
    $runRecord=Invoke-MIRNativeProbeProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','[Console]::Out.Write("controlled")') -TimeoutSeconds 20
    Assert-Probe ($runRecord.status-ceq'passed'-and(Test-Path -LiteralPath $runRecord.ledger)-and(Test-Path -LiteralPath $runRecord.stdout)) 'governed-process'
    Assert-Probe ($null-eq$runRecord.result.PSObject.Properties['sample_milliseconds']) 'default-governor-result-shape'
    $benchmarkRoot=Join-Path $context.root 'benchmark-observation';[IO.Directory]::CreateDirectory($benchmarkRoot)|Out-Null
    $benchmarkSampler=New-MIROwnedProcessMemorySampler -Context benchmark -ExpectedSlots @([pscustomobject]@{phase='benchmark';role='factorio'})
    $benchmarkLedger=Join-Path $benchmarkRoot 'resources.jsonl'
    # Keep the controlled child alive until two real callbacks occur. A fixed
    # 900 ms sleep could expire during loaded-host resource scans before the
    # second 250 ms observation. Short-lived exit races are tested separately.
    $benchmarkReady=Join-Path $benchmarkRoot 'two-samples.ready'
    $benchmarkCallbacks=New-BenchmarkMemoryCallbacks -Sampler $benchmarkSampler -ReleasePath $benchmarkReady
    $benchmarkChild=Join-Path $benchmarkRoot 'wait-for-samples.ps1'
    [IO.File]::WriteAllText($benchmarkChild,@'
param([Parameter(Mandatory)][string]$Ready)
$deadline=[DateTime]::UtcNow.AddSeconds(10)
while(-not(Test-Path -LiteralPath $Ready -PathType Leaf)){
  if([DateTime]::UtcNow-ge$deadline){exit 17}
  Start-Sleep -Milliseconds 50
}
'@,[Text.UTF8Encoding]::new($false))
    $benchmarkRun=Invoke-MIR441MonitoredProcess -FilePath $child -Arguments @('-NoProfile','-File',$benchmarkChild,'-Ready',$benchmarkReady) -WorkRoot $benchmarkRoot -LedgerPath $benchmarkLedger -Policy $context.policy -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 1024MB -TimeoutSeconds 20 -SampleMilliseconds 250 -OwnedProcessSampleCallback $benchmarkCallbacks.sample -OwnedProcessExitCallback $benchmarkCallbacks.exit
    $benchmarkReceipt=Get-MIROwnedProcessMemoryObservationReceipt -Sampler $benchmarkSampler
    Assert-Probe ($benchmarkRun.status-ceq'passed'-and(Test-Path -LiteralPath $benchmarkReady)-and$benchmarkCallbacks.state.sample_events-ge2-and$benchmarkCallbacks.state.exit_events-eq1-and$benchmarkReceipt.status-ceq'complete-observation'-and$benchmarkReceipt.context-ceq'benchmark'-and$benchmarkReceipt.observations.Count-ge2) 'benchmark-natural-exit-observation'
    Assert-Probe (@($benchmarkReceipt.observations|Where-Object {$_.phase-cne'benchmark'-or$_.role-cne'factorio'-or$_.pid-le0-or$_.working_set_bytes-lt0-or$_.private_bytes-lt0}).Count-eq0) 'benchmark-observation-identity'
    $probeSampler=New-MIROwnedProcessMemorySampler -Context benchmark -ExpectedSlots @([pscustomobject]@{phase='benchmark';role='factorio'})
    $probeReady=Join-Path $benchmarkRoot 'two-samples-probe.ready'
    $probeCallbacks=New-BenchmarkMemoryCallbacks -Sampler $probeSampler -ReleasePath $probeReady
    $probeRun=Invoke-MIRNativeProbeProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-File',$benchmarkChild,'-Ready',$probeReady) -TimeoutSeconds 20 -SampleMilliseconds 250 -OwnedProcessSampleCallback $probeCallbacks.sample -OwnedProcessExitCallback $probeCallbacks.exit
    $probeReceipt=Get-MIROwnedProcessMemoryObservationReceipt -Sampler $probeSampler
    $probeObservationPassed=($probeRun.status-ceq'passed'-and(Test-Path -LiteralPath $probeReady)-and$probeCallbacks.state.sample_events-ge2-and$probeCallbacks.state.exit_events-eq1-and$probeReceipt.status-ceq'complete-observation'-and$probeReceipt.observations.Count-ge2)
    if(-not$probeObservationPassed){
      # Keep the failed CI observation visible even when finally removes its
      # disposable context. Emit only bounded statuses/counts and fixed reasons.
      $probeObservationDiagnostic=[ordered]@{
        run_status=$probeRun.status
        sample_events=$probeCallbacks.state.sample_events
        exit_events=$probeCallbacks.state.exit_events
        receipt_status=$probeReceipt.status
        observation_count=$probeReceipt.observations.Count
        incomplete_reasons=@($probeReceipt.incomplete_reasons|Select-Object -First 8)
      }
      Write-Host ('[mir5-native-probe-observation-details] '+($probeObservationDiagnostic|ConvertTo-Json -Compress))
    }
    Assert-Probe $probeObservationPassed 'probe-wrapper-benchmark-observation'
    $factorioSampler=New-MIROwnedProcessMemorySampler -Context benchmark -ExpectedSlots @([pscustomobject]@{phase='benchmark';role='factorio'})
    $factorioReady=Join-Path $benchmarkRoot 'two-samples-factorio.ready'
    $factorioCallbacks=New-BenchmarkMemoryCallbacks -Sampler $factorioSampler -ReleasePath $factorioReady
    $factorioObservation=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-File',$benchmarkChild,'-Ready',$factorioReady) -TimeoutSeconds 20 -SampleMilliseconds 250 -OwnedProcessSampleCallback $factorioCallbacks.sample -OwnedProcessExitCallback $factorioCallbacks.exit
    $factorioReceipt=Get-MIROwnedProcessMemoryObservationReceipt -Sampler $factorioSampler
    $factorioObservationPassed=$factorioObservation.status-ceq'passed'-and$factorioObservation.result.duration_measurement.scope-ceq'direct-native-executable-start-to-exit'-and(Test-Path -LiteralPath $factorioReady)-and$factorioCallbacks.state.sample_events-ge2-and$factorioCallbacks.state.exit_events-eq1-and$factorioReceipt.status-ceq'complete-observation'-and$factorioReceipt.observations.Count-ge2
    if(-not$factorioObservationPassed){
      $details=[ordered]@{run_status=$factorioObservation.status;sample_events=$factorioCallbacks.state.sample_events;exit_events=$factorioCallbacks.state.exit_events;receipt_status=$factorioReceipt.status;observation_count=$factorioReceipt.observations.Count;incomplete_reasons=@($factorioReceipt.incomplete_reasons|Select-Object -First 8)}
      Write-Host ('[mir5-native-factorio-observation-details] '+($details|ConvertTo-Json -Compress))
    }
    Assert-Probe $factorioObservationPassed 'factorio-wrapper-benchmark-observation'
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
    Refuses-Probe {Invoke-MIRNativeProbeProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','exit 0') -SampleMilliseconds 500} 'SampleMilliseconds'
    Refuses-Probe {Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','exit 0') -SampleMilliseconds 500} 'SampleMilliseconds'
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
    $nonzeroRun=$context.runs[$context.runs.Count-1]
    if($nonzeroRun.status-cne'failed'){
      Write-Host ('Natural nonzero original receipt: '+($nonzeroRun|ConvertTo-Json -Depth 12 -Compress))
      Write-Host ('Natural nonzero original ledger: '+((Get-Content -LiteralPath $nonzeroRun.ledger)-join"`n"))
    }
    Assert-Probe ($nonzeroRun.status-ceq'failed'-and$null-ne$nonzeroRun.PSObject.Properties['result']) 'natural-nonzero-result'
    Assert-Probe ($nonzeroRun.result.exit_code-eq7-and$nonzeroRun.result.status-ceq'failed'-and-not$nonzeroRun.result.passed-and-not$nonzeroRun.result.timed_out-and-not$nonzeroRun.result.completion_predicate_observed) 'natural-nonzero-still-refused'
    $nonzeroRows=@(Get-Content -LiteralPath $nonzeroRun.ledger|ForEach-Object {$_|ConvertFrom-Json -Depth 12})
    Assert-Probe ($nonzeroRows[-1].phase-ceq'completed'-and$nonzeroRows[-1].exit_code-eq7-and-not$nonzeroRows[-1].completion_predicate_observed-and@($nonzeroRows|Where-Object {$null-ne$_.PSObject.Properties['phase']-and$_.phase-ceq'interrupted'}).Count-eq0) 'natural-nonzero-completed-ledger'
    $nonzeroPids=@($nonzeroRows|Where-Object {$null-ne$_.PSObject.Properties['process']}|ForEach-Object {$_.process.id}|Select-Object -Unique)
    Assert-Probe ($nonzeroPids.Count-eq1-and$nonzeroPids[0]-gt0-and$null-eq(Get-Process -Id $nonzeroPids[0] -ErrorAction SilentlyContinue)) 'natural-nonzero-owned-pid-exited'
    $interruptionError=''
    try{Invoke-MIRNativeProbeProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 3') -TimeoutSeconds 20 -CompletionPredicate {throw '[mir5-native-probe-controlled-interruption]'}|Out-Null}catch{$interruptionError=$_.Exception.Message}
    $interruptionRun=$context.runs[$context.runs.Count-1]
    $interruptionRows=@(Get-Content -LiteralPath $interruptionRun.ledger|ForEach-Object {$_|ConvertFrom-Json -Depth 12})
    Assert-Probe ($interruptionError.Contains('[mir5-native-probe-controlled-interruption]')-and$interruptionRun.status-ceq'interrupted'-and$null-eq$interruptionRun.PSObject.Properties['result']) 'unrelated-interruption-no-natural-result'
    Assert-Probe ($interruptionRows[-1].phase-ceq'interrupted'-and-not$interruptionRows[-1].timed_out) 'unrelated-interruption-ledger'
    # A callback error cannot manufacture the governor's natural-exit receipt.
    Refuses-Probe {Invoke-MIRNativeProbeProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 3') -TimeoutSeconds 20 -CompletionPredicate {
      $fake=[InvalidOperationException]::new('[mir441-process-exit] 7')
      $fake.Data['mir441_process_result']=[pscustomobject]@{status='failed';exit_code=7;passed=$false;timed_out=$false;completion_predicate_observed=$false}
      throw $fake
    }} '[mir441-process-exit] 7'
    $counterfeitRun=$context.runs[$context.runs.Count-1]
    Assert-Probe ($counterfeitRun.status-ceq'interrupted'-and$null-eq$counterfeitRun.PSObject.Properties['result']) 'callback-cannot-forge-natural-result'
    $counterfeitRows=@(Get-Content -LiteralPath $counterfeitRun.ledger|ForEach-Object {$_|ConvertFrom-Json -Depth 12})
    Assert-Probe ($counterfeitRows[-1].phase-ceq'interrupted'-and-not$counterfeitRows[-1].timed_out) 'callback-counterfeit-ledger'
    $timeoutError=''
    try {Invoke-MIRNativeProbeProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 3') -TimeoutSeconds 1|Out-Null}catch{$timeoutError=$_.Exception.Message}
    Assert-Probe ($timeoutError.Contains('[mir441-process-timeout]')) 'timeout-refusal'
    $timeoutLedger=Join-Path $context.root ('process-'+$context.process_index+'.resources.jsonl')
    $timeoutRows=@(Get-Content -LiteralPath $timeoutLedger|ForEach-Object {$_|ConvertFrom-Json -Depth 12})
    Assert-Probe ($timeoutRows.Count-gt0-and$timeoutRows[-1].phase-ceq'interrupted'-and[bool]$timeoutRows[-1].timed_out) 'timeout-ledger'
    $timeoutRun=$context.runs[$context.runs.Count-1]
    Assert-Probe ($timeoutRun.status-ceq'interrupted'-and$null-eq$timeoutRun.PSObject.Properties['result']) 'timeout-no-natural-result'
    $factorioRecord=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $child -Arguments @('-NoProfile','-Command','[Console]::Out.Write($env:SteamAppId+"/"+$env:SteamGameId)') -TimeoutSeconds 20 -AdmissionWaitSeconds 1 -AdmissionPhase 'native-probe-control'
    $text=Get-Content -Raw -LiteralPath $factorioRecord.stdout
    Assert-Probe ($text-ceq'427520/427520'-and$factorioRecord.result.duration_measurement.scope-ceq'direct-native-executable-start-to-exit'-and$factorioRecord.admission_wait.phase-ceq'native-probe-control'-and$factorioRecord.admission_wait.status-ceq'admitted-without-wait'-and$factorioRecord.admission_wait.attempt_count-ge1) 'factorio-actor-admission-wait'
    Assert-Probe ($null-eq$factorioRecord.result.PSObject.Properties['console_startup']) 'factorio-console-default-no-input'
    Assert-FactorioConsoleStartup -Context $context -Child $child
    Refuses-Probe {Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $child -Arguments @('x'*20000)} '[mir-native-probe-argument-budget]'
    $resultRecord=[ordered]@{kind='MIR5NativeProbeControlV1';status='passed'}
    $resultPath=Join-Path $context.root 'result.json'
    Write-MIRNativeProbeResult -Context $context -Record $resultRecord
    $resultBytes=[IO.File]::ReadAllBytes($resultPath)
    Assert-Probe ((Test-Path -LiteralPath $resultPath)-and($resultBytes.Length-gt0)) 'result-fresh-exclusive-create'
    Refuses-AnyProbe {Write-MIRNativeProbeResult -Context $context -Record ([ordered]@{kind='MIR5NativeProbeControlV1';status='second-write-must-refuse'})} 'result-second-write-refused'
    Assert-Probe ([Convert]::ToHexString([IO.File]::ReadAllBytes($resultPath))-ceq[Convert]::ToHexString($resultBytes)) 'result-second-write-preserves-first-record'
    $sentinelContext=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot (Join-Path $root 'result-sentinel') -ExpectedPeakMemoryMiB 1024 -MaxNewOutputMiB 8 -UseExactOutputRoot
    [IO.Directory]::CreateDirectory($sentinelContext.root)|Out-Null
    $sentinelPath=Join-Path $sentinelContext.root 'result.json';$sentinelBytes=[Text.UTF8Encoding]::new($false).GetBytes('original terminal receipt sentinel')
    [IO.File]::WriteAllBytes($sentinelPath,$sentinelBytes)
    Refuses-AnyProbe {Write-MIRNativeProbeResult -Context $sentinelContext -Record $resultRecord} 'result-preexisting-sentinel-refused'
    Assert-Probe ([Convert]::ToHexString([IO.File]::ReadAllBytes($sentinelPath))-ceq[Convert]::ToHexString($sentinelBytes)) 'result-preexisting-sentinel-preserved'
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
