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
  # Recovery keeps the existing 20 GiB development reserve and stricter caller limits.
  $value={param($name) $property=$Policy.PSObject.Properties[$name];if($null-ne$property){[double]$property.Value*1GB}else{[double]0}}
  return [pscustomobject]@{
    physical_bytes=[int64][Math]::Max([Math]::Max(2GB,[double]$Snapshot.memory.total_bytes*.2),[Math]::Max((&$value 'minimum_free_ram_gib'),(&$value 'hard_stop_free_ram_gib')))
    commit_bytes=[int64][Math]::Max(2GB,[double]$Snapshot.memory.commit_limit_bytes*.2)
    system_bytes=[int64][Math]::Max(20GB,[Math]::Max((&$value 'system_drive_hard_stop_free_gib'),(&$value 'system_drive_target_free_gib')))
    work_bytes=[int64][Math]::Max(20GB,(&$value 'work_volume_reserve_gib'))
  }
}

function Assert-MIR441ResourceAdmission {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)][string]$WorkRoot,[int64]$EstimatedPeakBytes=0,[int64]$ExpectedPeakMemoryBytes=0)
  $null=Resolve-MIR441RecoveryScratchPath -Path $WorkRoot
  if($EstimatedPeakBytes-lt0-or$EstimatedPeakBytes-gt2GB-or$ExpectedPeakMemoryBytes-lt0){throw '[mir441-resource-staging-budget]'}
  $snapshot=Get-MIR441ResourceSnapshot -WorkRoot $WorkRoot;$limits=Get-MIR441ResourceLimits -Policy $Policy -Snapshot $snapshot
  if([int64]$snapshot.memory.free_bytes-lt$limits.physical_bytes+$ExpectedPeakMemoryBytes){throw '[mir441-resource-admission-memory]'}
  if([int64]$snapshot.memory.commit_limit_bytes-[int64]$snapshot.memory.committed_bytes-lt$limits.commit_bytes+$ExpectedPeakMemoryBytes){throw '[mir441-resource-admission-commit]'}
  if([int64]$snapshot.system_volume.free_bytes-lt$limits.system_bytes+2*$EstimatedPeakBytes){throw '[mir441-resource-admission-system-disk]'}
  if([int64]$snapshot.work_volume.free_bytes-lt$limits.work_bytes+2*$EstimatedPeakBytes){throw '[mir441-resource-admission-work-disk]'}
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
  $all=@(Get-CimInstance Win32_Process -ErrorAction Stop);$ids=[Collections.Generic.HashSet[int]]::new();[void]$ids.Add($Process.Id)
  do{$changed=$false;foreach($row in $all){if($row.CreationDate-and$row.CreationDate.ToUniversalTime()-ge$StartedUtc-and$ids.Contains([int]$row.ParentProcessId)-and$ids.Add([int]$row.ProcessId)){$changed=$true}}}while($changed)
  [int64]$working=0;[int64]$private=0;$children=@()
  foreach($row in $all){if(-not$ids.Contains([int]$row.ProcessId)){continue};try{$p=Get-Process -Id $row.ProcessId -ErrorAction Stop;$working+=$p.WorkingSet64;$private+=$p.PrivateMemorySize64;if($row.ProcessId-ne$Process.Id){$children+=[pscustomobject]@{id=$p.Id;started_utc=$p.StartTime.ToUniversalTime()}};$p.Dispose()}catch [Microsoft.PowerShell.Commands.ProcessCommandException]{}}
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
  $process=$null;$streams=@();$copies=@();$children=@();$temp=Join-Path $work ('temp-'+[guid]::NewGuid().ToString('N'));$peak=0L;$started=[DateTime]::UtcNow;$timer=[Diagnostics.Stopwatch]::StartNew();$timedOut=$false;$completionObserved=$false
  try{
    # Check again under the lock, before any job output or worker is allocated.
    $null=Assert-MIR441ResourceAdmission -Policy $Policy -WorkRoot $work -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes
    New-Item -ItemType Directory -Force -Path $temp|Out-Null
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$FilePath;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WorkingDirectory=$work
    $start.Environment['TEMP']=$temp;$start.Environment['TMP']=$temp
    foreach($argument in $Arguments){[void]$start.ArgumentList.Add($argument)}
    $start.RedirectStandardOutput=[bool]$StdoutPath;$start.RedirectStandardError=[bool]$StderrPath
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    if(-not$process.Start()){throw '[mir441-process-start]'}
    # Streaming capture avoids retaining the complete child output in RAM.
    foreach($pair in @(@($StdoutPath,'StandardOutput'),@($StderrPath,'StandardError'))){if($pair[0]){$stream=[IO.File]::Create($pair[0]);$streams+=$stream;$copies+=$process.($pair[1]).BaseStream.CopyToAsync($stream)}}
    while($true){
      $tree=Get-MIR441OwnedProcessTree -Process $process -StartedUtc $started;$children=@($children+$tree.children|Sort-Object id,started_utc -Unique);$peak=[Math]::Max($peak,[int64]$tree.working_set_bytes)
      # A reaction margin cancels before the retained reserve, subject to sampling latency.
      $sample=Assert-MIR441ResourceAdmission -Policy $Policy -WorkRoot $work -EstimatedPeakBytes 32MB -ExpectedPeakMemoryBytes 64MB
      if($tree.working_set_bytes-gt$ExpectedPeakMemoryBytes-or$tree.private_bytes-gt$ExpectedPeakMemoryBytes){throw '[mir441-resource-process-budget]'}
      $usage=Get-MIR441TreeUsage -Path $work;if(-not$usage.complete){throw '[mir441-resource-output-scan-incomplete]'}
      if($usage.bytes-$before.bytes-gt$EstimatedPeakBytes){throw '[mir441-resource-output-budget]'}
      $sample|Add-Member -NotePropertyName process -NotePropertyValue ([ordered]@{id=$process.Id;working_set_bytes=$tree.working_set_bytes;private_bytes=$tree.private_bytes;peak_working_set_bytes=$peak;phase='running';memory_enforcement='sampled-watchdog-not-hard-cap'})
      Write-MIR441Json -Value $sample -Path $ledger -Append
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
    Write-MIR441Json -Value ([ordered]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');phase='completed';exit_code=$process.ExitCode;peak_working_set_bytes=$peak;completion_predicate_observed=$completionObserved}) -Path $ledger -Append
    # Native process timestamps keep watchdog sampling overhead out of engine timing.
    return [pscustomobject][ordered]@{status=$(if($passed){'passed'}else{'failed'});exit_code=$process.ExitCode;timed_out=$false;passed=$passed;completion_predicate_observed=$completionObserved;duration_seconds=[Math]::Round(($process.ExitTime-$process.StartTime).TotalSeconds,6);peak_working_set_bytes=$peak;admission=$admission}
  }catch{
    $failure=$_
    if($null-ne$process){try{$tree=Get-MIR441OwnedProcessTree -Process $process -StartedUtc $started;$children=@($children+$tree.children)}catch{}}
    Stop-MIR441OwnedProcess -Process $process -Children $children
    Write-MIR441Json -Value ([ordered]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');phase='interrupted';timed_out=$timedOut;error=$failure.Exception.Message}) -Path $ledger -Append
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
