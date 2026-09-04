Set-StrictMode -Version Latest

function Get-MIR441PhysicalMemorySnapshot {
  if ($IsWindows) {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -Property FreePhysicalMemory,TotalVisibleMemorySize
    return [pscustomobject][ordered]@{total_bytes=[int64]$os.TotalVisibleMemorySize*1KB;free_bytes=[int64]$os.FreePhysicalMemory*1KB}
  }
  $info = [GC]::GetGCMemoryInfo()
  return [pscustomobject][ordered]@{total_bytes=[int64]$info.TotalAvailableMemoryBytes;free_bytes=[int64]($info.TotalAvailableMemoryBytes-$info.MemoryLoadBytes)}
}

function Get-MIR441ResourceSnapshot {
  param([Parameter(Mandatory)][string]$WorkRoot)
  $memory = Get-MIR441PhysicalMemorySnapshot
  $workDrive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($WorkRoot)))
  $systemDrive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot([Environment]::SystemDirectory))
  return [pscustomobject][ordered]@{
    observed_at=[DateTimeOffset]::UtcNow.ToString('o')
    memory=$memory
    work_volume=[ordered]@{name=$workDrive.Name;free_bytes=[int64]$workDrive.AvailableFreeSpace;total_bytes=[int64]$workDrive.TotalSize}
    system_volume=[ordered]@{name=$systemDrive.Name;free_bytes=[int64]$systemDrive.AvailableFreeSpace;total_bytes=[int64]$systemDrive.TotalSize}
  }
}

function Assert-MIR441ResourceAdmission {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)][string]$WorkRoot,[int64]$EstimatedPeakBytes=0)
  $snapshot = Get-MIR441ResourceSnapshot -WorkRoot $WorkRoot
  $gib = 1GB
  if ([int64]$snapshot.memory.free_bytes -lt [int64]([double]$Policy.minimum_free_ram_gib*$gib)) { throw '[mir441-resource-admission-memory]' }
  if ([int64]$snapshot.system_volume.free_bytes -lt [int64]([double]$Policy.system_drive_hard_stop_free_gib*$gib)) { throw '[mir441-resource-admission-system-disk]' }
  $required = [int64]($EstimatedPeakBytes*2 + [double]$Policy.work_volume_reserve_gib*$gib)
  if ([int64]$snapshot.work_volume.free_bytes -lt $required) { throw '[mir441-resource-admission-work-disk]' }
  return $snapshot
}

function Get-MIR441TreeUsage {
  param([Parameter(Mandatory)][string]$Path)
  [int64]$bytes=0;[int64]$files=0
  if (Test-Path -LiteralPath $Path -PathType Container) {
    foreach($item in [IO.Directory]::EnumerateFiles([IO.Path]::GetFullPath($Path),'*',[IO.SearchOption]::AllDirectories)) {
      try {$bytes += [IO.FileInfo]::new($item).Length;$files++} catch {}
    }
  }
  return [pscustomobject][ordered]@{files=$files;bytes=$bytes}
}

function Invoke-MIR441MonitoredProcess {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$LedgerPath,
    [Parameter(Mandatory)]$Policy,
    [int]$SampleSeconds=5
  )
  $admission = Assert-MIR441ResourceAdmission -Policy $Policy -WorkRoot $WorkRoot
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName=$FilePath;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
  foreach($argument in $Arguments){[void]$start.ArgumentList.Add($argument)}
  $process=[Diagnostics.Process]::new();$process.StartInfo=$start
  $started=[DateTimeOffset]::UtcNow;[int64]$peak=0
  try {
    if(-not $process.Start()){throw '[mir441-process-start]'}
    $initial=Get-MIR441ResourceSnapshot -WorkRoot $WorkRoot
    $initial|Add-Member -NotePropertyName process -NotePropertyValue ([ordered]@{id=$process.Id;working_set_bytes=[int64]$process.WorkingSet64;peak_working_set_bytes=[int64]$process.WorkingSet64;phase='started'})
    Write-MIR441Json -Value $initial -Path $LedgerPath -Append
    while(-not $process.WaitForExit($SampleSeconds*1000)){
      $process.Refresh();$peak=[Math]::Max($peak,[int64]$process.WorkingSet64)
      $sample=Get-MIR441ResourceSnapshot -WorkRoot $WorkRoot
      $sample|Add-Member -NotePropertyName process -NotePropertyValue ([ordered]@{id=$process.Id;working_set_bytes=[int64]$process.WorkingSet64;peak_working_set_bytes=$peak})
      Write-MIR441Json -Value $sample -Path $LedgerPath -Append
      if([int64]$sample.memory.free_bytes -lt [int64]([double]$Policy.hard_stop_free_ram_gib*1GB) -or
         [int64]$sample.system_volume.free_bytes -lt [int64]([double]$Policy.system_drive_hard_stop_free_gib*1GB) -or
         [int64]$sample.work_volume.free_bytes -lt [int64]([double]$Policy.work_volume_reserve_gib*1GB)){
        try{$process.Kill($true)}catch{};throw '[mir441-resource-hard-stop]'
      }
    }
    $process.Refresh();$peak=[Math]::Max($peak,[int64]$process.PeakWorkingSet64)
    if($process.ExitCode-ne0){throw "[mir441-process-exit] $($process.ExitCode)"}
    $final=Get-MIR441ResourceSnapshot -WorkRoot $WorkRoot
    $final|Add-Member -NotePropertyName process -NotePropertyValue ([ordered]@{id=$process.Id;working_set_bytes=0;peak_working_set_bytes=$peak;phase='completed'})
    Write-MIR441Json -Value $final -Path $LedgerPath -Append
    return [pscustomobject][ordered]@{status='passed';exit_code=$process.ExitCode;duration_seconds=[Math]::Round(([DateTimeOffset]::UtcNow-$started).TotalSeconds,3);peak_working_set_bytes=$peak;admission=$admission}
  } finally {$process.Dispose()}
}
