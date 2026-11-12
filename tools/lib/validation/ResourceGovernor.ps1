Set-StrictMode -Version Latest

function Get-MIR441PhysicalMemorySnapshot {
  if (-not $IsWindows) { throw '[mir441-resource-monitor-windows-required]' }
  if ($null -eq ('MIR441MemoryNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MIR441MemoryNative {
  [StructLayout(LayoutKind.Sequential)] public struct Info {
    public uint Size;
    public UIntPtr CommitTotal,CommitLimit,CommitPeak,PhysicalTotal,PhysicalAvailable,SystemCache,KernelTotal,KernelPaged,KernelNonpaged,PageSize;
    public uint Handles,Processes,Threads;
  }
  [DllImport("psapi.dll",SetLastError=true)] static extern bool GetPerformanceInfo(out Info info,uint size);
  public static Info Read() {
    Info info;
    if(!GetPerformanceInfo(out info,(uint)Marshal.SizeOf(typeof(Info)))) throw new System.ComponentModel.Win32Exception();
    return info;
  }
}
'@
  }
  $info=[MIR441MemoryNative]::Read();$page=$info.PageSize.ToUInt64()
  return [pscustomobject][ordered]@{total_bytes=[int64]($info.PhysicalTotal.ToUInt64()*$page);free_bytes=[int64]($info.PhysicalAvailable.ToUInt64()*$page);committed_bytes=[int64]($info.CommitTotal.ToUInt64()*$page);commit_limit_bytes=[int64]($info.CommitLimit.ToUInt64()*$page)}
}

function Resolve-MIR441RecoveryScratchPath {
  param([Parameter(Mandatory)][string]$Path)
  $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
  $full=[IO.Path]::GetFullPath($Path);$admitted=$false
  foreach($relative in @('build/tmp','build/p')) {
    $root=[IO.Path]::GetFullPath((Join-Path $repo $relative)).TrimEnd('\','/')
    if($full.Equals($root,[StringComparison]::OrdinalIgnoreCase)-or$full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$admitted=$true}
  }
  if(-not$admitted){throw "[mir441-resource-output-root] $full"}
  $current=$full
  while($current){
    if(Test-Path -LiteralPath $current){if((Get-Item -LiteralPath $current -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw '[mir441-resource-output-reparse]'}}
    $current=Split-Path -Parent $current
  }
  return $full
}

function Get-MIR441ResourceSnapshot {
  param([Parameter(Mandatory)][string]$WorkRoot)
  $memory=Get-MIR441PhysicalMemorySnapshot
  $workDrive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($WorkRoot)))
  $systemDrive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot([Environment]::SystemDirectory))
  return [pscustomobject][ordered]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');memory=$memory;work_volume=[ordered]@{name=$workDrive.Name;free_bytes=[int64]$workDrive.AvailableFreeSpace;total_bytes=[int64]$workDrive.TotalSize};system_volume=[ordered]@{name=$systemDrive.Name;free_bytes=[int64]$systemDrive.AvailableFreeSpace;total_bytes=[int64]$systemDrive.TotalSize}}
}

function Get-MIR441ResourceLimits {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$Snapshot)
  # Physical headroom retains the authored caller policy.  CommitLimit includes
  # pagefile capacity, so its reserve instead tracks installed physical memory:
  # a pagefile resize must not change the retained execution margin.
  $value={param($name) $property=$Policy.PSObject.Properties[$name];if($null-ne$property){[double]$property.Value*1GB}else{[double]0}}
  return [pscustomobject]@{
    physical_bytes=[int64][Math]::Max([Math]::Max(2GB,[double]$Snapshot.memory.total_bytes*.2),[Math]::Max((&$value 'minimum_free_ram_gib'),(&$value 'hard_stop_free_ram_gib')))
    commit_bytes=[int64][Math]::Max(2GB,[double]$Snapshot.memory.total_bytes*.2)
    system_bytes=[int64][Math]::Max(20GB,[Math]::Max((&$value 'system_drive_hard_stop_free_gib'),(&$value 'system_drive_target_free_gib')))
    work_bytes=[int64][Math]::Max(20GB,(&$value 'work_volume_reserve_gib'))
  }
}

function Assert-MIR441ResourceAdmission {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)][string]$WorkRoot,[int64]$EstimatedPeakBytes=0,[int64]$ExpectedPeakMemoryBytes=0)
  $null=Resolve-MIR441RecoveryScratchPath -Path $WorkRoot
  if($EstimatedPeakBytes-lt0-or$EstimatedPeakBytes-gt8GB-or$ExpectedPeakMemoryBytes-lt0){throw '[mir441-resource-staging-budget]'}
  $snapshot=Get-MIR441ResourceSnapshot -WorkRoot $WorkRoot;$limits=Get-MIR441ResourceLimits -Policy $Policy -Snapshot $snapshot
  $failure=''
  if([int64]$snapshot.memory.free_bytes-lt$limits.physical_bytes+$ExpectedPeakMemoryBytes){$failure='[mir441-resource-admission-memory]'}
  elseif([int64]$snapshot.memory.commit_limit_bytes-[int64]$snapshot.memory.committed_bytes-lt$limits.commit_bytes+$ExpectedPeakMemoryBytes){$failure='[mir441-resource-admission-commit]'}
  elseif([int64]$snapshot.system_volume.free_bytes-lt$limits.system_bytes+2*$EstimatedPeakBytes){$failure='[mir441-resource-admission-system-disk]'}
  elseif([int64]$snapshot.work_volume.free_bytes-lt$limits.work_bytes+2*$EstimatedPeakBytes){$failure='[mir441-resource-admission-work-disk]'}
  if($failure){
    # Retain the actual throwing snapshot; a later sample cannot explain a
    # prelaunch refusal or live interruption. Admission thresholds are exact.
    $exception=[InvalidOperationException]::new($failure)
    $exception.Data['mir441_resource_admission']=[ordered]@{
      snapshot=$snapshot;limits=$limits;estimated_peak_bytes=$EstimatedPeakBytes;
      expected_peak_memory_bytes=$ExpectedPeakMemoryBytes
    }
    throw $exception
  }
  return $snapshot
}

# This is deliberately a pre-start helper.  It uses the governor's existing
# admission decision and thresholds, but gives a transient physical-memory or
# commit refusal a bounded opportunity to recover before an owned process has
# been created.  A state object may be supplied to span the ordinary first
# check and the under-lock recheck with one deadline.
function New-MIR441PreStartAdmissionWait {
  param(
    [ValidateRange(0,300)][int]$AdmissionWaitSeconds=0,
    [Parameter(Mandatory)][string]$Phase
  )
  $started=[DateTimeOffset]::UtcNow
  [pscustomobject][ordered]@{
    phase=$Phase;admission_wait_seconds=$AdmissionWaitSeconds;status='not-requested';
    attempt_count=0;refusal_count=0;elapsed_seconds=0.0;first_refusal=$null;
    last_refusal=$null;last_error=$null;started_at=$started.ToString('o');
    deadline_at=$started.AddSeconds($AdmissionWaitSeconds).ToString('o');admission=$null
  }
}

function Wait-MIR441PreStartResourceAdmission {
  param(
    [Parameter(Mandatory)]$Policy,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][int64]$EstimatedPeakBytes,
    [Parameter(Mandatory)][int64]$ExpectedPeakMemoryBytes,
    [Parameter(Mandatory)]$State
  )
  if([int]$State.admission_wait_seconds -eq 0){return $State}
  $started=[DateTimeOffset]::Parse([string]$State.started_at)
  $deadline=[DateTimeOffset]::Parse([string]$State.deadline_at)
  while($true){
    if([DateTimeOffset]::UtcNow -ge $deadline){
      $State.status='capacity-timeout'
      $State.elapsed_seconds=[Math]::Round(([DateTimeOffset]::UtcNow-$started).TotalSeconds,3)
      $timeout=[InvalidOperationException]::new($(if([int]$State.refusal_count -gt 0){[string]$State.last_error}else{'[mir441-resource-admission-wait-timeout]'}))
      $timeout.Data['mir_direct_startup_admission_wait']=$State
      $timeout.Data['mir441_prestart_admission_wait']=$State
      throw $timeout
    }
    $State.attempt_count=[int]$State.attempt_count+1
    try {
      $admission=Assert-MIR441ResourceAdmission -Policy $Policy -WorkRoot $WorkRoot -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes
      $State.status=if([int]$State.refusal_count -gt 0){'admitted-after-wait'}else{'admitted-without-wait'}
      $State.elapsed_seconds=[Math]::Round(([DateTimeOffset]::UtcNow-$started).TotalSeconds,3)
      $State.admission=$admission
      return $State
    } catch {
      $message=$_.Exception.Message
      if($message -cnotin @('[mir441-resource-admission-memory]','[mir441-resource-admission-commit]')){throw}
      $snapshot=Get-MIR441ResourceSnapshot -WorkRoot $WorkRoot
      $refusal=[ordered]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');error=$message;snapshot=$snapshot}
      if($null -eq $State.first_refusal){$State.first_refusal=$refusal}
      $State.last_refusal=$refusal;$State.last_error=$message
      $State.refusal_count=[int]$State.refusal_count+1
      $State.elapsed_seconds=[Math]::Round(([DateTimeOffset]::UtcNow-$started).TotalSeconds,3)
      if([DateTimeOffset]::UtcNow -ge $deadline){
        $State.status='capacity-timeout'
        $_.Exception.Data['mir_direct_startup_admission_wait']=$State
        $_.Exception.Data['mir441_prestart_admission_wait']=$State
        throw
      }
      $remaining=[Math]::Max(0.0,($deadline-[DateTimeOffset]::UtcNow).TotalSeconds)
      # Leave a small bounded scheduling margin for the last exact governor
      # check.  The deadline itself still rejects a late launch.
      $sleepMilliseconds=[Math]::Max(1,[Math]::Min(500,[int][Math]::Floor($remaining*1000)-25))
      Start-Sleep -Milliseconds $sleepMilliseconds
    }
  }
}

function Assert-MIR441PreStartAdmissionWaitState {
  param([Parameter(Mandatory)]$State)
  try {
    $seconds=[int]$State.admission_wait_seconds
    $phase=[string]$State.phase
    $started=[DateTimeOffset]::Parse([string]$State.started_at)
    $deadline=[DateTimeOffset]::Parse([string]$State.deadline_at)
  } catch { throw '[mir441-resource-prestart-wait-state]' }
  if($seconds -lt 1 -or $seconds -gt 300 -or [string]::IsNullOrWhiteSpace($phase) -or $deadline -ne $started.AddSeconds($seconds)){
    throw '[mir441-resource-prestart-wait-state]'
  }
}

function Test-MIR441RetiredDirectory {
  param([Parameter(Mandatory)][IO.DirectoryInfo]$Directory)
  return -not([IO.Directory]::Exists($Directory.FullName)-or[IO.File]::Exists($Directory.FullName))
}

function Get-MIR441TreeUsage {
  param([Parameter(Mandatory)][string]$Path)
  [int64]$bytes=0;[int64]$files=0;$complete=$true;$reparsePoints=0;$watch=[Diagnostics.Stopwatch]::StartNew()
  if(Test-Path -LiteralPath $Path -PathType Container){
    $pending=[Collections.Generic.Stack[IO.DirectoryInfo]]::new();$pending.Push([IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Path)))
    while($pending.Count){
      $directory=$pending.Pop()
      try {
        foreach($item in $directory.EnumerateFileSystemInfos()){
          if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){$complete=$false;$reparsePoints++;continue}
          if($item-is[IO.DirectoryInfo]){$pending.Push($item)}else{$bytes+=$item.Length;$files++}
          if($files-ge10000-or$watch.Elapsed.TotalSeconds-ge2){return [pscustomobject][ordered]@{files=$files;bytes=$bytes;complete=$false;stopped_by=$(if($files-ge10000){'file-limit'}else{'time-limit'});elapsed_ms=$watch.Elapsed.TotalMilliseconds;reparse_points=$reparsePoints}}
        }
      } catch [IO.DirectoryNotFoundException] {
        # A constructor can retire a queued directory while this live scan is
        # running. Ignore only actual disappearance; replacements and all
        # other I/O failures still stop the governed process.
        if(-not(Test-MIR441RetiredDirectory -Directory $directory)){throw}
      }
    }
  }
  return [pscustomobject][ordered]@{files=$files;bytes=$bytes;complete=$complete;stopped_by=$(if($complete){$null}else{'reparse-point'});elapsed_ms=$watch.Elapsed.TotalMilliseconds;reparse_points=$reparsePoints}
}

function Get-MIR441OwnedProcessTree {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process,[Parameter(Mandatory)][datetime]$StartedUtc)
  # Query only direct children of processes we have already established as
  # owned.  A full Win32_Process snapshot retained every machine process on
  # each watchdog sample even when the governed process had no children.
  $ids=[Collections.Generic.HashSet[int]]::new();$owned=[Collections.Generic.List[int]]::new();$pending=[Collections.Generic.Queue[int]]::new();$createdUtcById=[Collections.Generic.Dictionary[int,datetime]]::new()
  $rootId=[int]$Process.Id;[void]$ids.Add($rootId);$owned.Add($rootId);$pending.Enqueue($rootId)
  while($pending.Count){
    $parentId=$pending.Dequeue()
    foreach($row in @(Get-CimInstance -ClassName Win32_Process -Filter ("ParentProcessId=$parentId") -ErrorAction Stop)){
      $childId=[int]$row.ProcessId
      $createdUtc=$null
      if($row.CreationDate){$createdUtc=$row.CreationDate.ToUniversalTime()}
      if($null-ne$createdUtc-and$createdUtc-ge$StartedUtc-and$ids.Add($childId)){
        [void]$createdUtcById.Add($childId,$createdUtc);$owned.Add($childId);$pending.Enqueue($childId)
      }
    }
  }
  [int64]$working=0;[int64]$private=0;$children=@()
  foreach($id in $owned){
    $p=$null
    try{
      $p=Get-Process -Id $id -ErrorAction Stop
      if($id-ne$rootId){
        if($p.HasExited){continue}
        $childStarted=$p.StartTime
        if($null-eq$childStarted){
          if($p.HasExited){continue}
          throw '[mir441-owned-child-identity]'
        }
        $childStartedUtc=$childStarted.ToUniversalTime();$capturedStartedUtc=$createdUtcById[$id]
        # Win32_Process CreationDate is microsecond precision.  Bind only at
        # that common precision, while retaining the complete process value.
        [int64]$childTicks=$childStartedUtc.Ticks;[int64]$capturedTicks=$capturedStartedUtc.Ticks
        if(($childTicks-($childTicks%10))-ne($capturedTicks-($capturedTicks%10))){throw '[mir441-owned-child-identity]'}
      }
      $working+=$p.WorkingSet64;$private+=$p.PrivateMemorySize64
      if($id-ne$rootId){$children+=[pscustomobject]@{id=$p.Id;started_utc=$childStartedUtc}}
    }catch [Microsoft.PowerShell.Commands.ProcessCommandException]{}catch [InvalidOperationException]{
      if($null-ne$p-and$p.HasExited){continue}
      throw
    }finally{if($null-ne$p){$p.Dispose()}}
  }
  return [pscustomobject]@{working_set_bytes=$working;private_bytes=$private;children=$children}
}

function Stop-MIR441OwnedProcess {
  param([Diagnostics.Process]$Process,[object[]]$Children=@())
  if($null-ne$Process-and-not$Process.HasExited){[void]$Process.CloseMainWindow();if(-not$Process.WaitForExit(200)){$Process.Kill($true);[void]$Process.WaitForExit(3000)}}
  foreach($child in $Children){
    $p=$null
    try{
      $p=Get-Process -Id $child.id -ErrorAction Stop
      if($p.HasExited){continue}
      $childStarted=$p.StartTime
      if($null-eq$childStarted){
        if($p.HasExited){continue}
        throw '[mir441-owned-child-identity]'
      }
      if($childStarted.ToUniversalTime()-eq$child.started_utc){$p.Kill($true);[void]$p.WaitForExit(3000)}
    }catch [Microsoft.PowerShell.Commands.ProcessCommandException]{}catch [InvalidOperationException]{
      if($null-ne$p-and$p.HasExited){continue}
      throw
    }finally{if($null-ne$p){$p.Dispose()}}
  }
}

function Invoke-MIR441OwnedProcessObservation {
  param(
    [scriptblock]$Callback,
    [Parameter(Mandatory)][Diagnostics.Process]$Process,
    [Parameter(Mandatory)][datetime]$StartedUtc,
    [Parameter(Mandatory)][Diagnostics.Stopwatch]$Timer,
    [switch]$NaturalExit
  )
  if ($null -eq $Callback) { return }
  $event = [pscustomobject][ordered]@{
    process = $Process
    pid = [int]$Process.Id
    started_utc = $StartedUtc.ToString('o')
    elapsed_monotonic_milliseconds = [Math]::Round([double]$Timer.Elapsed.TotalMilliseconds, 3)
    natural_exit = [bool]$NaturalExit
  }
  $output = @(& $Callback $event)
  if ($output.Count -ne 0) { throw '[mir441-resource-observation-callback-output]' }
}

# A direct Factorio server accepts one stdin line as a console command. This is
# deliberately one reviewed /c input, not a general command queue or callback
# surface. The receipt keeps hashes and timing, never command or log text.
function Get-MIR441TextSha256 {
  param([Parameter(Mandatory)][string]$Text)
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Text)
  $hash=[Security.Cryptography.SHA256]::HashData($bytes)
  return ([Convert]::ToHexString($hash)).ToLowerInvariant()
}

function Get-MIR441FactorioConsoleStartupField {
  param([Parameter(Mandatory)]$Definition,[Parameter(Mandatory)][string]$Name,[switch]$Optional)
  if($Definition-is[Collections.IDictionary]) {
    if(-not$Definition.Contains($Name)) {if($Optional){return $null};throw '[mir441-factorio-console-startup-field]'}
    return $Definition[$Name]
  }
  $property=$Definition.PSObject.Properties[$Name]
  if($null-eq$property) {if($Optional){return $null};throw '[mir441-factorio-console-startup-field]'}
  return $property.Value
}

function New-MIR441FactorioConsoleStartup {
  param([Parameter(Mandatory)]$Definition)
  $names=if($Definition-is[Collections.IDictionary]){@($Definition.Keys|ForEach-Object {[string]$_})}else{@($Definition.PSObject.Properties.Name)}
  if(@($names|Where-Object {$_-notin @('command','ready_marker','confirmation_marker')}).Count-ne0) {throw '[mir441-factorio-console-startup-field]'}
  $command=Get-MIR441FactorioConsoleStartupField -Definition $Definition -Name command
  $ready=Get-MIR441FactorioConsoleStartupField -Definition $Definition -Name ready_marker
  $confirmation=Get-MIR441FactorioConsoleStartupField -Definition $Definition -Name confirmation_marker -Optional
  if($command-isnot[string]-or$ready-isnot[string]-or($null-ne$confirmation-and$confirmation-isnot[string])) {throw '[mir441-factorio-console-startup-field]'}
  if($null-eq$confirmation){$confirmation=''}
  foreach($value in @($command,$ready,$confirmation)) {
    if($value.IndexOf([char]0)-ge0-or$value.IndexOf("`r")-ge0-or$value.IndexOf("`n")-ge0) {throw '[mir441-factorio-console-startup-newline]'}
  }
  $utf8=[Text.UTF8Encoding]::new($false,$true)
  try {$commandBytes=$utf8.GetByteCount($command);$readyBytes=$utf8.GetByteCount($ready);$confirmationBytes=$utf8.GetByteCount($confirmation)}catch{throw '[mir441-factorio-console-startup-utf8]'}
  if($commandBytes-lt4-or$commandBytes-gt4096-or-not$command.StartsWith('/c ',[StringComparison]::Ordinal)-or[string]::IsNullOrWhiteSpace($command.Substring(3))) {throw '[mir441-factorio-console-startup-command]'}
  if($readyBytes-lt1-or$readyBytes-gt512-or($confirmationBytes-ne0-and($confirmationBytes-lt1-or$confirmationBytes-gt512))){throw '[mir441-factorio-console-startup-marker]'}
  if($confirmationBytes-ne0-and$ready-ceq$confirmation){throw '[mir441-factorio-console-startup-marker]'}
  return [pscustomobject][ordered]@{
    command=$command;ready_marker=$ready;confirmation_marker=$confirmation
    receipt=[ordered]@{
      schema=1;kind='MIR441FactorioConsoleStartupReceiptV1'
      command_sha256=Get-MIR441TextSha256 $command;command_bytes=$commandBytes
      ready_marker_sha256=Get-MIR441TextSha256 $ready;confirmation_marker_sha256=$(if($confirmationBytes-eq0){$null}else{Get-MIR441TextSha256 $confirmation})
      ready_marker_observed=$false;ready_elapsed_monotonic_milliseconds=$null
      confirmation_marker_observed=$false;confirmation_elapsed_monotonic_milliseconds=$null
      send_count=0;sends=[Collections.Generic.List[object]]::new()
    }
    streams=[Collections.Generic.List[object]]::new()
  }
}

function Add-MIR441FactorioConsoleStartupOutput {
  param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$Kind,[Parameter(Mandatory)][string]$Path)
  $State.streams.Add([pscustomobject]@{kind=$Kind;path=$Path;offset=0L;tail='';confirmation_tail=''})
}

function Update-MIR441FactorioConsoleStartupOutput {
  param([Parameter(Mandatory)]$State,[ValidateRange(1024,1048576)][int]$MaximumBytes=65536)
  $updated=$false;$buffer=[byte[]]::new($MaximumBytes);$encoding=[Text.UTF8Encoding]::new($false)
  foreach($stream in $State.streams){
    if(-not(Test-Path -LiteralPath $stream.path -PathType Leaf)){continue}
    $reader=$null
    try {
      $reader=[IO.File]::Open($stream.path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
      if($reader.Length-lt$stream.offset){throw '[mir441-factorio-console-output-regressed]'}
      $reader.Position=$stream.offset
      $read=$reader.Read($buffer,0,$buffer.Length)
      if($read-le0){continue}
      $stream.offset+=$read
      $text=$encoding.GetString($buffer,0,$read)
      $stream.tail=($stream.tail+$text)
      if($stream.tail.Length-gt8192){$stream.tail=$stream.tail.Substring($stream.tail.Length-8192)}
      if($State.receipt.send_count-ge1){
        $stream.confirmation_tail=($stream.confirmation_tail+$text)
        if($stream.confirmation_tail.Length-gt8192){$stream.confirmation_tail=$stream.confirmation_tail.Substring($stream.confirmation_tail.Length-8192)}
      }
      $updated=$true
    } finally {if($null-ne$reader){$reader.Dispose()}}
  }
  return $updated
}

function Test-MIR441FactorioConsoleStartupMarker {
  param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$Marker,[switch]$ConfirmationOnly)
  foreach($stream in $State.streams){
    $text=if($ConfirmationOnly){[string]$stream.confirmation_tail}else{[string]$stream.tail}
    if($text.IndexOf($Marker,[StringComparison]::Ordinal)-ge0){return $true}
  }
  return $false
}

function Send-MIR441FactorioConsoleStartupLine {
  param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][IO.StreamWriter]$Writer,[Parameter(Mandatory)][Diagnostics.Stopwatch]$Timer,[Parameter(Mandatory)][ValidateSet('command','confirmation-replay')][string]$Kind)
  if(($Kind-ceq'command'-and$State.receipt.send_count-ne0)-or($Kind-ceq'confirmation-replay'-and$State.receipt.send_count-ne1)){throw '[mir441-factorio-console-send-order]'}
  try {$Writer.WriteLine($State.command);$Writer.Flush()}catch{throw '[mir441-factorio-console-write]'}
  $State.receipt.send_count++
  $State.receipt.sends.Add([ordered]@{order=$State.receipt.send_count;kind=$Kind;command_sha256=Get-MIR441TextSha256 $State.command;elapsed_monotonic_milliseconds=[Math]::Round([double]$Timer.Elapsed.TotalMilliseconds,3)})
  if($Kind-ceq'command'){foreach($stream in $State.streams){$stream.confirmation_tail=''}}
}

function Invoke-MIR441MonitoredProcess {
  param(
    [Parameter(Mandatory)][string]$FilePath,[Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$WorkRoot,[Parameter(Mandatory)][string]$LedgerPath,[Parameter(Mandatory)]$Policy,
    [int64]$EstimatedPeakBytes=0,[int64]$ExpectedPeakMemoryBytes=0,
    [ValidateRange(1,5)][int]$SampleSeconds=1,[ValidateRange(1,86400)][int]$TimeoutSeconds=900,
    [ValidateSet(0,250)][int]$SampleMilliseconds=0,
    [scriptblock]$OwnedProcessSampleCallback=$null,
    [scriptblock]$OwnedProcessExitCallback=$null,
    [string]$StdoutPath='',[string]$StderrPath='',[switch]$AllowNonZeroExit,
    [switch]$FactorioSteamIdentity,
    $PreStartAdmissionWait=$null,
    [scriptblock]$CompletionPredicate=$null,
    $FactorioConsoleStartup=$null
  )
  if ($SampleMilliseconds -eq 250 -and $null -eq $OwnedProcessSampleCallback) { throw '[mir441-resource-observation-callback-required]' }
  if ($SampleMilliseconds -eq 0 -and $null -ne $OwnedProcessSampleCallback) { throw '[mir441-resource-observation-cadence-required]' }
  if ($null -ne $OwnedProcessExitCallback -and $null -eq $OwnedProcessSampleCallback) { throw '[mir441-resource-observation-exit-callback-requires-sample]' }
  # Benchmark observations close on natural exit; live marker endpoints keep
  # the existing completion-predicate path without observation callbacks.
  if ($null -ne $CompletionPredicate -and $null -ne $OwnedProcessSampleCallback) { throw '[mir441-resource-observation-completion-predicate]' }
  $consoleStartup=$null
  if($null-ne$FactorioConsoleStartup){
    if(-not$FactorioSteamIdentity){throw '[mir441-factorio-console-identity-required]'}
    $consoleStartup=New-MIR441FactorioConsoleStartup -Definition $FactorioConsoleStartup
    if([string]::IsNullOrWhiteSpace($StdoutPath)-and[string]::IsNullOrWhiteSpace($StderrPath)){throw '[mir441-factorio-console-output-required]'}
  }
  $work=Resolve-MIR441RecoveryScratchPath -Path $WorkRoot;$ledger=Resolve-MIR441RecoveryScratchPath -Path $LedgerPath
  foreach($path in @($ledger,$StdoutPath,$StderrPath)|Where-Object {$_}){
    $resolved=Resolve-MIR441RecoveryScratchPath -Path $path
    if(-not$resolved.StartsWith($work.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw '[mir441-resource-output-work-root]'}
  }
  if($EstimatedPeakBytes-le0-or$ExpectedPeakMemoryBytes-le0){throw '[mir441-resource-peak-budget-required]'}
  if($null -ne $PreStartAdmissionWait){Assert-MIR441PreStartAdmissionWaitState -State $PreStartAdmissionWait}
  if($null -ne $PreStartAdmissionWait){
    $admission=(Wait-MIR441PreStartResourceAdmission -Policy $Policy -WorkRoot $work -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes -State $PreStartAdmissionWait).admission
  }else{
    $admission=Assert-MIR441ResourceAdmission -Policy $Policy -WorkRoot $work -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes
  }
  $before=Get-MIR441TreeUsage -Path $work;if(-not$before.complete){throw ('[mir441-resource-output-scan-incomplete] '+($before|ConvertTo-Json -Compress))}
  $lockPath=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'build/tmp/mir-heavy.lock'
  $null=Resolve-MIR441RecoveryScratchPath -Path $lockPath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $lockPath)|Out-Null
  try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw '[mir441-resource-heavy-job-active]'}
  $process=$null;$streams=@();$copies=@();$children=@();$temp=Join-Path $work ('temp-'+[guid]::NewGuid().ToString('N'));$peak=0L;$privatePeak=0L;$started=$null;$timer=$null;$timedOut=$false;$completionObserved=$false;$naturalExitFailure=$null;$inputWriter=$null
  try{
    # Check again under the lock, before any job output or worker is allocated.
    if($null -ne $PreStartAdmissionWait){
      $admission=(Wait-MIR441PreStartResourceAdmission -Policy $Policy -WorkRoot $work -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes -State $PreStartAdmissionWait).admission
    }else{
      $null=Assert-MIR441ResourceAdmission -Policy $Policy -WorkRoot $work -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes
    }
    New-Item -ItemType Directory -Force -Path $temp|Out-Null
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$FilePath;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WorkingDirectory=$work
    $start.Environment['TEMP']=$temp;$start.Environment['TMP']=$temp
    # Factorio only needs these fixed Steam identifiers in its owned child.
    # Keep this narrow option separate from the governor's custody variables:
    # callers cannot supply arbitrary child environment keys or replace TEMP/TMP.
    if($FactorioSteamIdentity){$start.Environment['SteamAppId']='427520';$start.Environment['SteamGameId']='427520'}
    foreach($argument in $Arguments){[void]$start.ArgumentList.Add($argument)}
    $start.RedirectStandardOutput=[bool]$StdoutPath;$start.RedirectStandardError=[bool]$StderrPath
    $start.RedirectStandardInput=($null-ne$consoleStartup)
    if($null-ne$consoleStartup){$start.StandardInputEncoding=[Text.UTF8Encoding]::new($false)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    if(-not$process.Start()){throw '[mir441-process-start]'}
    $started=$process.StartTime.ToUniversalTime();$timer=[Diagnostics.Stopwatch]::StartNew()
    # Streaming capture avoids retaining the complete child output in RAM.
    foreach($pair in @(@($StdoutPath,'StandardOutput'),@($StderrPath,'StandardError'))){if($pair[0]){
      # A console marker must become visible before the child exits. Keep the
      # existing buffered capture for ordinary actors; the opt-in tail reader
      # uses a one-byte destination buffer so its shared read observes writes.
      $stream=if($null-ne$consoleStartup){[IO.FileStream]::new($pair[0],[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::Read,1,[IO.FileOptions]::Asynchronous)}else{[IO.File]::Create($pair[0])}
      $streams+=$stream;$copies+=$process.($pair[1]).BaseStream.CopyToAsync($stream)
    }}
    if($null-ne$consoleStartup){
      $inputWriter=$process.StandardInput;$inputWriter.NewLine="`n";$inputWriter.AutoFlush=$true
      if($StdoutPath){Add-MIR441FactorioConsoleStartupOutput -State $consoleStartup -Kind stdout -Path $StdoutPath}
      if($StderrPath){Add-MIR441FactorioConsoleStartupOutput -State $consoleStartup -Kind stderr -Path $StderrPath}
    }
    while($true){
      $tree=Get-MIR441OwnedProcessTree -Process $process -StartedUtc $started;$children=@($children+$tree.children|Sort-Object id,started_utc -Unique);$peak=[Math]::Max($peak,[int64]$tree.working_set_bytes)
      $privatePeak=[Math]::Max($privatePeak,[int64]$tree.private_bytes)
      # A reaction margin cancels before the retained reserve, subject to sampling latency.
      $sample=Assert-MIR441ResourceAdmission -Policy $Policy -WorkRoot $work -EstimatedPeakBytes 32MB -ExpectedPeakMemoryBytes 64MB
      # Preserve the triggering process observation before enforcing its budget.
      # Private bytes can exceed working set during graphical resource loading.
      $sample|Add-Member -NotePropertyName process -NotePropertyValue ([ordered]@{id=$process.Id;working_set_bytes=$tree.working_set_bytes;private_bytes=$tree.private_bytes;peak_working_set_bytes=$peak;peak_sampled_private_bytes=$privatePeak;expected_peak_memory_bytes=$ExpectedPeakMemoryBytes;phase='running';memory_enforcement='sampled-watchdog-not-hard-cap'})
      Write-MIR441Json -Value $sample -Path $ledger -Append
      if($tree.working_set_bytes-gt$ExpectedPeakMemoryBytes-or$tree.private_bytes-gt$ExpectedPeakMemoryBytes){throw '[mir441-resource-process-budget]'}
      $usage=Get-MIR441TreeUsage -Path $work;if(-not$usage.complete){throw ('[mir441-resource-output-scan-incomplete] '+($usage|ConvertTo-Json -Compress))}
      if($usage.bytes-$before.bytes-gt$EstimatedPeakBytes){throw '[mir441-resource-output-budget]'}
      if($process.HasExited){
        Invoke-MIR441OwnedProcessObservation -Callback $OwnedProcessExitCallback -Process $process -StartedUtc $started -Timer $timer -NaturalExit
        break
      }
      if($null-ne$consoleStartup-and(Update-MIR441FactorioConsoleStartupOutput -State $consoleStartup)){
        if(-not$consoleStartup.receipt.ready_marker_observed-and(Test-MIR441FactorioConsoleStartupMarker -State $consoleStartup -Marker $consoleStartup.ready_marker)){
          $consoleStartup.receipt.ready_marker_observed=$true
          $consoleStartup.receipt.ready_elapsed_monotonic_milliseconds=[Math]::Round([double]$timer.Elapsed.TotalMilliseconds,3)
          Send-MIR441FactorioConsoleStartupLine -State $consoleStartup -Writer $inputWriter -Timer $timer -Kind command
        }
        if($consoleStartup.receipt.send_count-eq1-and$consoleStartup.confirmation_marker.Length-gt0-and(Test-MIR441FactorioConsoleStartupMarker -State $consoleStartup -Marker $consoleStartup.confirmation_marker -ConfirmationOnly)){
          $consoleStartup.receipt.confirmation_marker_observed=$true
          $consoleStartup.receipt.confirmation_elapsed_monotonic_milliseconds=[Math]::Round([double]$timer.Elapsed.TotalMilliseconds,3)
          Send-MIR441FactorioConsoleStartupLine -State $consoleStartup -Writer $inputWriter -Timer $timer -Kind confirmation-replay
        }
      }
      if($timer.Elapsed.TotalSeconds-ge$TimeoutSeconds){$timedOut=$true;throw '[mir441-process-timeout]'}
      if($null-ne$CompletionPredicate){
        $decision=@(& $CompletionPredicate)
        if($decision.Count-ne1-or$decision[0]-isnot[bool]){throw '[mir441-process-completion-predicate-invalid]'}
        if($decision[0]){$completionObserved=$true;break}
      }
      Invoke-MIR441OwnedProcessObservation -Callback $OwnedProcessSampleCallback -Process $process -StartedUtc $started -Timer $timer
      $waitMilliseconds=if($SampleMilliseconds -eq 250){250}else{$SampleSeconds*1000}
      [void]$process.WaitForExit($waitMilliseconds)
    }
    Stop-MIR441OwnedProcess -Process $process -Children $children
    foreach($copy in $copies){$null=$copy.GetAwaiter().GetResult()}
    $process.Refresh();$peak=[Math]::Max($peak,[int64]$process.PeakWorkingSet64)
    $passed=$completionObserved-or$process.ExitCode-eq0
    Write-MIR441Json -Value ([ordered]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');phase='completed';exit_code=$process.ExitCode;peak_working_set_bytes=$peak;peak_sampled_private_bytes=$privatePeak;completion_predicate_observed=$completionObserved}) -Path $ledger -Append
    # Native process timestamps keep watchdog sampling overhead out of engine timing.
    $completed=[pscustomobject][ordered]@{status=$(if($passed){'passed'}else{'failed'});exit_code=$process.ExitCode;timed_out=$false;passed=$passed;completion_predicate_observed=$completionObserved;duration_seconds=[Math]::Round(($process.ExitTime-$process.StartTime).TotalSeconds,6);peak_working_set_bytes=$peak;peak_sampled_private_bytes=$privatePeak;admission=$admission}
    if($null-ne$consoleStartup){$completed|Add-Member -NotePropertyName console_startup -NotePropertyValue $consoleStartup.receipt}
    if($null -ne $PreStartAdmissionWait){$completed|Add-Member -NotePropertyName admission_wait -NotePropertyValue $PreStartAdmissionWait}
    if($process.ExitCode-ne0-and-not$AllowNonZeroExit-and-not$completionObserved){
      # Preserve the observed terminal before the same strict nonzero refusal.
      # Callers can retain this failed result without treating it as a timeout.
      $naturalExitFailure=[InvalidOperationException]::new("[mir441-process-exit] $($process.ExitCode)")
      $naturalExitFailure.Data['mir441_process_result']=$completed
      throw $naturalExitFailure
    }
    return $completed
  }catch{
    $failure=$_
    if($null-ne$consoleStartup){$failure.Exception.Data['mir441_factorio_console_startup']=$consoleStartup.receipt}
    $isNaturalExitFailure=[object]::ReferenceEquals($failure.Exception,$naturalExitFailure)
    # A callback or unrelated failure cannot supply this reserved terminal.
    if(-not$isNaturalExitFailure){$failure.Exception.Data.Remove('mir441_process_result')}
    if($null-ne$process){try{$tree=Get-MIR441OwnedProcessTree -Process $process -StartedUtc $started;$children=@($children+$tree.children)}catch{}}
    Stop-MIR441OwnedProcess -Process $process -Children $children
    if(-not$isNaturalExitFailure){
      Write-MIR441Json -Value ([ordered]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');phase='interrupted';timed_out=$timedOut;error=$failure.Exception.Message;resource_admission=$failure.Exception.Data['mir441_resource_admission'];peak_working_set_bytes=$peak;peak_sampled_private_bytes=$privatePeak}) -Path $ledger -Append
    }
    throw $failure
  }finally{
    try{Stop-MIR441OwnedProcess -Process $process -Children $children}finally{
      try{
        foreach($copy in $copies){try{$null=$copy.Wait(3000)}catch{}}
        foreach($stream in $streams){$stream.Dispose()};if($null-ne$inputWriter){$inputWriter.Dispose()};if($null-ne$process){$process.Dispose()}
        if(Test-Path -LiteralPath $temp){$null=Resolve-MIR441RecoveryScratchPath -Path $temp;Remove-Item -LiteralPath $temp -Recurse -Force}
      }finally{$lock.Dispose()}
    }
  }
}
