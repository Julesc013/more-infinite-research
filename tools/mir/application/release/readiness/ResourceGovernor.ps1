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
  $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
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
  if($EstimatedPeakBytes-lt0-or$EstimatedPeakBytes-gt2GB-or$ExpectedPeakMemoryBytes-lt0){throw '[mir441-resource-staging-budget]'}
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

function Test-MIR441RetiredDirectory {
  param([Parameter(Mandatory)][IO.DirectoryInfo]$Directory)
  return -not([IO.Directory]::Exists($Directory.FullName)-or[IO.File]::Exists($Directory.FullName))
}

function Get-MIR441TreeUsage {
  param([Parameter(Mandatory)][string]$Path)
  [int64]$bytes=0;[int64]$files=0;$complete=$true;$watch=[Diagnostics.Stopwatch]::StartNew()
  if(Test-Path -LiteralPath $Path -PathType Container){
    $pending=[Collections.Generic.Stack[IO.DirectoryInfo]]::new();$pending.Push([IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Path)))
    while($pending.Count){
      $directory=$pending.Pop()
      try {
        foreach($item in $directory.EnumerateFileSystemInfos()){
          if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){$complete=$false;continue}
          if($item-is[IO.DirectoryInfo]){$pending.Push($item)}else{$bytes+=$item.Length;$files++}
          if($files-ge10000-or$watch.Elapsed.TotalSeconds-ge2){return [pscustomobject]@{files=$files;bytes=$bytes;complete=$false}}
        }
      } catch [IO.DirectoryNotFoundException] {
        # A constructor can retire a queued directory while this live scan is
        # running. Ignore only actual disappearance; replacements and all
        # other I/O failures still stop the governed process.
        if(-not(Test-MIR441RetiredDirectory -Directory $directory)){throw}
      }
    }
  }
  return [pscustomobject][ordered]@{files=$files;bytes=$bytes;complete=$complete}
}

function Get-MIR441OwnedProcessTree {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process,[Parameter(Mandatory)][datetime]$StartedUtc)
  # Query only direct children of processes we have already established as
  # owned.  A full Win32_Process snapshot retained every machine process on
  # each watchdog sample even when the governed process had no children.
  $ids=[Collections.Generic.HashSet[int]]::new();$owned=[Collections.Generic.List[int]]::new();$pending=[Collections.Generic.Queue[int]]::new()
  $rootId=[int]$Process.Id;[void]$ids.Add($rootId);$owned.Add($rootId);$pending.Enqueue($rootId)
  while($pending.Count){
    $parentId=$pending.Dequeue()
    foreach($row in @(Get-CimInstance -ClassName Win32_Process -Filter ("ParentProcessId=$parentId") -ErrorAction Stop)){
      $childId=[int]$row.ProcessId
      if($row.CreationDate-and$row.CreationDate.ToUniversalTime()-ge$StartedUtc-and$ids.Add($childId)){
        $owned.Add($childId);$pending.Enqueue($childId)
      }
    }
  }
  [int64]$working=0;[int64]$private=0;$children=@()
  foreach($id in $owned){try{$p=Get-Process -Id $id -ErrorAction Stop;$working+=$p.WorkingSet64;$private+=$p.PrivateMemorySize64;if($id-ne$rootId){$children+=[pscustomobject]@{id=$p.Id;started_utc=$p.StartTime.ToUniversalTime()}};$p.Dispose()}catch [Microsoft.PowerShell.Commands.ProcessCommandException]{}}
  return [pscustomobject]@{working_set_bytes=$working;private_bytes=$private;children=$children}
}

function Stop-MIR441OwnedProcess {
  param([Diagnostics.Process]$Process,[object[]]$Children=@())
  if($null-ne$Process-and-not$Process.HasExited){[void]$Process.CloseMainWindow();if(-not$Process.WaitForExit(200)){$Process.Kill($true);[void]$Process.WaitForExit(3000)}}
  foreach($child in $Children){
    try{$p=Get-Process -Id $child.id -ErrorAction Stop;if($p.StartTime.ToUniversalTime()-eq$child.started_utc){$p.Kill($true);[void]$p.WaitForExit(3000)};$p.Dispose()}catch [Microsoft.PowerShell.Commands.ProcessCommandException]{}
  }
}

function Invoke-MIR441MonitoredProcess {
  param(
    [Parameter(Mandatory)][string]$FilePath,[Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$WorkRoot,[Parameter(Mandatory)][string]$LedgerPath,[Parameter(Mandatory)]$Policy,
    [int64]$EstimatedPeakBytes=0,[int64]$ExpectedPeakMemoryBytes=0,
    [ValidateRange(1,5)][int]$SampleSeconds=1,[ValidateRange(1,86400)][int]$TimeoutSeconds=900,
    [string]$StdoutPath='',[string]$StderrPath='',[switch]$AllowNonZeroExit,
    [switch]$FactorioSteamIdentity,
    [scriptblock]$CompletionPredicate=$null
  )
  $work=Resolve-MIR441RecoveryScratchPath -Path $WorkRoot;$ledger=Resolve-MIR441RecoveryScratchPath -Path $LedgerPath
  foreach($path in @($ledger,$StdoutPath,$StderrPath)|Where-Object {$_}){
    $resolved=Resolve-MIR441RecoveryScratchPath -Path $path
    if(-not$resolved.StartsWith($work.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw '[mir441-resource-output-work-root]'}
  }
  if($EstimatedPeakBytes-le0-or$ExpectedPeakMemoryBytes-le0){throw '[mir441-resource-peak-budget-required]'}
  $admission=Assert-MIR441ResourceAdmission -Policy $Policy -WorkRoot $work -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes
  $before=Get-MIR441TreeUsage -Path $work;if(-not$before.complete){throw '[mir441-resource-output-scan-incomplete]'}
  $lockPath=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'build/tmp/mir-heavy.lock'
  $null=Resolve-MIR441RecoveryScratchPath -Path $lockPath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $lockPath)|Out-Null
  try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw '[mir441-resource-heavy-job-active]'}
  $process=$null;$streams=@();$copies=@();$children=@();$temp=Join-Path $work ('temp-'+[guid]::NewGuid().ToString('N'));$peak=0L;$privatePeak=0L;$started=[DateTime]::UtcNow;$timer=[Diagnostics.Stopwatch]::StartNew();$timedOut=$false;$completionObserved=$false
  try{
    # Check again under the lock, before any job output or worker is allocated.
    $null=Assert-MIR441ResourceAdmission -Policy $Policy -WorkRoot $work -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes
    New-Item -ItemType Directory -Force -Path $temp|Out-Null
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$FilePath;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WorkingDirectory=$work
    $start.Environment['TEMP']=$temp;$start.Environment['TMP']=$temp
    # Factorio only needs these fixed Steam identifiers in its owned child.
    # Keep this narrow option separate from the governor's custody variables:
    # callers cannot supply arbitrary child environment keys or replace TEMP/TMP.
    if($FactorioSteamIdentity){$start.Environment['SteamAppId']='427520';$start.Environment['SteamGameId']='427520'}
    foreach($argument in $Arguments){[void]$start.ArgumentList.Add($argument)}
    $start.RedirectStandardOutput=[bool]$StdoutPath;$start.RedirectStandardError=[bool]$StderrPath
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    if(-not$process.Start()){throw '[mir441-process-start]'}
    # Streaming capture avoids retaining the complete child output in RAM.
    foreach($pair in @(@($StdoutPath,'StandardOutput'),@($StderrPath,'StandardError'))){if($pair[0]){$stream=[IO.File]::Create($pair[0]);$streams+=$stream;$copies+=$process.($pair[1]).BaseStream.CopyToAsync($stream)}}
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
      $usage=Get-MIR441TreeUsage -Path $work;if(-not$usage.complete){throw '[mir441-resource-output-scan-incomplete]'}
      if($usage.bytes-$before.bytes-gt$EstimatedPeakBytes){throw '[mir441-resource-output-budget]'}
      if($process.HasExited){break}
      if($timer.Elapsed.TotalSeconds-ge$TimeoutSeconds){$timedOut=$true;throw '[mir441-process-timeout]'}
      if($null-ne$CompletionPredicate){
        $decision=@(& $CompletionPredicate)
        if($decision.Count-ne1-or$decision[0]-isnot[bool]){throw '[mir441-process-completion-predicate-invalid]'}
        if($decision[0]){$completionObserved=$true;break}
      }
      [void]$process.WaitForExit($SampleSeconds*1000)
    }
    Stop-MIR441OwnedProcess -Process $process -Children $children
    foreach($copy in $copies){$null=$copy.GetAwaiter().GetResult()}
    $process.Refresh();$peak=[Math]::Max($peak,[int64]$process.PeakWorkingSet64)
    if($process.ExitCode-ne0-and-not$AllowNonZeroExit-and-not$completionObserved){throw "[mir441-process-exit] $($process.ExitCode)"}
    $passed=$completionObserved-or$process.ExitCode-eq0
    Write-MIR441Json -Value ([ordered]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');phase='completed';exit_code=$process.ExitCode;peak_working_set_bytes=$peak;peak_sampled_private_bytes=$privatePeak;completion_predicate_observed=$completionObserved}) -Path $ledger -Append
    # Native process timestamps keep watchdog sampling overhead out of engine timing.
    return [pscustomobject][ordered]@{status=$(if($passed){'passed'}else{'failed'});exit_code=$process.ExitCode;timed_out=$false;passed=$passed;completion_predicate_observed=$completionObserved;duration_seconds=[Math]::Round(($process.ExitTime-$process.StartTime).TotalSeconds,6);peak_working_set_bytes=$peak;peak_sampled_private_bytes=$privatePeak;admission=$admission}
  }catch{
    $failure=$_
    if($null-ne$process){try{$tree=Get-MIR441OwnedProcessTree -Process $process -StartedUtc $started;$children=@($children+$tree.children)}catch{}}
    Stop-MIR441OwnedProcess -Process $process -Children $children
    Write-MIR441Json -Value ([ordered]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');phase='interrupted';timed_out=$timedOut;error=$failure.Exception.Message;resource_admission=$failure.Exception.Data['mir441_resource_admission'];peak_working_set_bytes=$peak;peak_sampled_private_bytes=$privatePeak}) -Path $ledger -Append
    throw $failure
  }finally{
    try{Stop-MIR441OwnedProcess -Process $process -Children $children}finally{
      try{
        foreach($copy in $copies){try{$null=$copy.Wait(3000)}catch{}}
        foreach($stream in $streams){$stream.Dispose()};if($null-ne$process){$process.Dispose()}
        if(Test-Path -LiteralPath $temp){$null=Resolve-MIR441RecoveryScratchPath -Path $temp;Remove-Item -LiteralPath $temp -Recurse -Force}
      }finally{$lock.Dispose()}
    }
  }
}
