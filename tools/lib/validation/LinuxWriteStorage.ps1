Set-StrictMode -Version Latest

# Opt-in storage for the native-fixture actor only. This is a fixed set of
# write destinations, not an alternate scheduler or an archive staging API.
function Resolve-MIRLinuxWritePath {
  param([Parameter(Mandatory)][string]$Path)
  if(-not [IO.Path]::IsPathFullyQualified($Path)){throw '[mir-linux-storage-absolute-path]'}
  $full=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
  if(-not $full){throw '[mir-linux-storage-root-path]'}
  $current=$full
  while($current){
    if(Test-Path -LiteralPath $current){
      $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
      if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '[mir-linux-storage-reparse]'}
      if($current -ceq $full -and $item -isnot [IO.DirectoryInfo]){throw '[mir-linux-storage-directory]'}
    }
    $current=Split-Path -Parent $current
  }
  return $full
}

function Get-MIRLinuxLibraryControlBytes {
  param([Parameter(Mandatory)][string]$Path)
  [int64]$bytes=0
  # Do not enumerate or charge the dependency archive collection.
  foreach($name in @('mod-list.json','mod-settings.dat','.mir-active-profile.json')){
    foreach($suffix in @('','.mir-new')){
      $file=Join-Path $Path ($name+$suffix)
      if(Test-Path -LiteralPath $file){
        $item=Get-Item -LiteralPath $file -Force -ErrorAction Stop
        if($item -isnot [IO.FileInfo] -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '[mir-linux-storage-library-control]'}
        $bytes += $item.Length
      }
    }
  }
  return $bytes
}

function Read-MIRLinuxWriteStorage {
  param(
    [Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Sha256,
    [Parameter(Mandatory)][string]$ControlRoot,[Parameter(Mandatory)][string]$LibraryRoot,
    [Parameter(Mandatory)][int64]$MaxNewOutputBytes
  )
  if(-not $IsLinux){throw '[mir-linux-storage-linux-required]'}
  $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if($item -isnot [IO.FileInfo] -or $item.Length -gt 16KB -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
      $Sha256 -cnotmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $Sha256.ToUpperInvariant()){
    throw '[mir-linux-storage-plan-identity]'
  }
  $plan=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
  if($plan.schema -ne 1 -or $plan.execution_account -isnot [string] -or $plan.execution_account -cne [Environment]::UserName){throw '[mir-linux-storage-execution-account]'}
  if(@($plan.roots).Count -ne 3){throw '[mir-linux-storage-roles]'}
  $roots=[Collections.Generic.List[object]]::new();[int64]$total=0
  foreach($role in @('control','data','library')){
    $rows=@($plan.roots | Where-Object {$_.role -ceq $role})
    if($rows.Count -ne 1){throw '[mir-linux-storage-roles]'}
    $row=$rows[0];$full=Resolve-MIRLinuxWritePath -Path $row.path
    foreach($field in @('peak_new_bytes','reserve_bytes')){
      $value=$row.$field
      if(($value -isnot [int] -and $value -isnot [long]) -or $value -le 0 -or $value -gt 8GB){throw '[mir-linux-storage-budget]'}
    }
    if($row.mount_point -isnot [string] -or $row.filesystem_type -isnot [string] -or [string]::IsNullOrWhiteSpace($row.filesystem_type)){throw '[mir-linux-storage-mount-pin]'}
    $null=Get-MIR441LinuxVolumeDevice -Volume $row
    $mountPoint=Resolve-MIRLinuxWritePath -Path $row.mount_point
    if(-not (Test-MIR441PathContained -Root $mountPoint -Path $full)){throw '[mir-linux-storage-job-directory]'}
    if($role -ceq 'control'){
      if((Resolve-MIR441RecoveryScratchPath -Path $full) -cne [IO.Path]::GetFullPath($ControlRoot) -or $row.filesystem_type -cne 'ext4'){throw '[mir-linux-storage-control-root]'}
    }elseif($role -ceq 'library'){
      if($full -cne [IO.Path]::GetFullPath($LibraryRoot) -or -not (Test-Path -LiteralPath $full -PathType Container)){throw '[mir-linux-storage-library-root]'}
    }else{
      $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
      if(Test-MIR441PathContained -Root $repo -Path $full -AllowEqual){throw '[mir-linux-storage-data-external]'}
    }
    if($role -cne 'library' -and (Test-Path -LiteralPath $full) -and @(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop).Count -ne 0){throw '[mir-linux-storage-job-not-empty]'}
    foreach($previous in $roots){
      if((Test-MIR441PathContained -Root $previous.path -Path $full -AllowEqual) -or (Test-MIR441PathContained -Root $full -Path $previous.path -AllowEqual)){throw '[mir-linux-storage-overlap]'}
    }
    $baseline=if($role -ceq 'library'){Get-MIRLinuxLibraryControlBytes -Path $full}else{0L}
    $roots.Add([pscustomobject]@{role=$role;path=$full;mount_id=$row.mount_id;device=$row.device;mount_point=$row.mount_point;filesystem_type=$row.filesystem_type;peak_new_bytes=[int64]$row.peak_new_bytes;reserve_bytes=[int64]$row.reserve_bytes;baseline_bytes=[int64]$baseline})
    $total += [int64]$row.peak_new_bytes
  }
  if($total -gt $MaxNewOutputBytes){throw '[mir-linux-storage-total-budget]'}
  $storage=[pscustomobject]@{schema=1;execution_account=$plan.execution_account;plan_sha256=$Sha256.ToUpperInvariant();roots=@($roots)}
  # Account/repository locks write only on the admitted control filesystem.
  # Refuse a fourth write device rather than silently charging the system disk.
  $control=@($storage.roots | Where-Object role -CEQ 'control')[0]
  $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
  foreach($lockPath in @((Join-Path $repo 'build/tmp/mir-heavy.lock'),(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local/state/mir/native-heavy.lock'))){
    $null=Resolve-MIRLinuxWritePath -Path (Split-Path -Parent $lockPath)
    $mount=Invoke-MIR441LinuxResourceObservation -Operation mount-identity -Path $lockPath
    if((Get-MIR441LinuxVolumeDevice -Volume $mount) -cne (Get-MIR441LinuxVolumeDevice -Volume $control)){throw '[mir-linux-storage-lock-filesystem]'}
  }
  $null=Get-MIRLinuxWriteStorageObservation -Storage $storage
  return $storage
}

# Kept separate from observation so byte-exact capacity rules can be exercised
# on every host. Bind mounts share capacity by device, even with different IDs.
function Assert-MIRLinuxWriteCapacity {
  param([Parameter(Mandatory)][object[]]$Rows)
  $volumes=@{}
  foreach($row in $Rows){
    $device=Get-MIR441LinuxVolumeDevice -Volume $row
    foreach($field in @('free_bytes','used_new_bytes','peak_new_bytes','reserve_bytes')){
      if(($row.$field -isnot [long] -and $row.$field -isnot [int]) -or $row.$field -lt 0){throw '[mir-linux-storage-observation]'}
    }
    if($row.used_new_bytes -gt $row.peak_new_bytes){throw '[mir441-resource-output-budget]'}
    if(-not $volumes.ContainsKey($device)){$volumes[$device]=[pscustomobject]@{device=$device;free_bytes=[int64]$row.free_bytes;remaining_bytes=0L;reserve_bytes=0L}}
    $volume=$volumes[$device]
    $volume.free_bytes=[Math]::Min($volume.free_bytes,[int64]$row.free_bytes)
    $volume.remaining_bytes += [int64]$row.peak_new_bytes-[int64]$row.used_new_bytes
    $volume.reserve_bytes=[Math]::Max($volume.reserve_bytes,[int64]$row.reserve_bytes)
  }
  foreach($volume in $volumes.Values){
    if($volume.free_bytes -lt $volume.remaining_bytes+$volume.reserve_bytes){
      $failure=[InvalidOperationException]::new('[mir-linux-storage-capacity]')
      $failure.Data['mir_linux_write_storage']=[ordered]@{roots=$Rows;volumes=@($volumes.Values)}
      throw $failure
    }
  }
  return @($volumes.Values | Sort-Object device)
}

function Get-MIRLinuxWriteStorageObservation {
  param([Parameter(Mandatory)]$Storage)
  if(-not $IsLinux -or $Storage.execution_account -cne [Environment]::UserName){throw '[mir-linux-storage-execution-account]'}
  $observed=[Collections.Generic.List[object]]::new()
  foreach($root in $Storage.roots){
    $null=Resolve-MIRLinuxWritePath -Path $root.path
    $mount=Invoke-MIR441LinuxResourceObservation -Operation mount-identity -Path $root.path
    if($mount.mount_id -ne $root.mount_id -or $mount.device -cne $root.device -or $mount.mount_point -cne $root.mount_point -or $mount.filesystem_type -cne $root.filesystem_type){throw '[mir-linux-storage-mount-changed]'}
    $drive=[IO.DriveInfo]::new((Resolve-MIR441ExistingDirectoryAncestor -Path $root.path))
    if(-not $drive.IsReady){throw '[mir-linux-storage-volume-unavailable]'}
    if($root.role -ceq 'library'){$bytes=Get-MIRLinuxLibraryControlBytes -Path $root.path}else{
      $usage=Get-MIR441TreeUsage -Path $root.path
      if(-not $usage.complete){throw '[mir441-resource-output-scan-incomplete]'}
      $bytes=[int64]$usage.bytes
    }
    $observed.Add([pscustomobject]@{role=$root.role;path=$root.path;device=$mount.device;mount_id=$mount.mount_id;free_bytes=[int64]$drive.AvailableFreeSpace;used_new_bytes=[int64][Math]::Max(0L,$bytes-$root.baseline_bytes);peak_new_bytes=$root.peak_new_bytes;reserve_bytes=$root.reserve_bytes})
  }
  $volumes=Assert-MIRLinuxWriteCapacity -Rows @($observed)
  return [pscustomobject]@{roots=@($observed);volumes=@($volumes);enforcement='sampled-watchdog-not-filesystem-quota'}
}

function Resolve-MIR441ProcessOutputPath {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)][string]$Path)
  $property=$Policy.PSObject.Properties['linux_write_storage']
  if($null -eq $property){return Resolve-MIR441RecoveryScratchPath -Path $Path}
  $full=[IO.Path]::GetFullPath($Path)
  $data=@($property.Value.roots | Where-Object role -CEQ 'data')[0]
  if(-not (Test-MIR441PathContained -Root $data.path -Path $full)){throw '[mir-linux-storage-output-path]'}
  $mount=Invoke-MIR441LinuxResourceObservation -Operation mount-identity -Path $full
  if($mount.mount_id -ne $data.mount_id -or $mount.device -cne $data.device -or $mount.mount_point -cne $data.mount_point -or $mount.filesystem_type -cne $data.filesystem_type){throw '[mir-linux-storage-mount-changed]'}
  $null=Resolve-MIRLinuxWritePath -Path (Split-Path -Parent $full)
  if((Test-Path -LiteralPath $full) -and ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '[mir-linux-storage-reparse]'}
  return $full
}
