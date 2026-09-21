Set-StrictMode -Version Latest

function Get-MIRImmutableInputSha256 {
  param([Parameter(Mandatory)][string]$Path)

  $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  try {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))
  } finally {
    $stream.Dispose()
  }
}

function Get-MIRImmutableInputProperty {
  param(
    [Parameter(Mandatory)]$InputObject,
    [Parameter(Mandatory)][string]$Name,
    $Default = $null
  )

  if ($InputObject -is [Collections.IDictionary]) {
    if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
    return $Default
  }
  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Assert-MIRImmutableInputPathWithin {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Context
  )

  $fullPath = [IO.Path]::GetFullPath($Path)
  $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
  if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$Context must remain below ${fullRoot}: $fullPath"
  }
  return $fullPath
}

function Assert-MIRImmutableInputDirectory {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Context)

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "$Context does not exist: $Path"
  }
  $item = Get-Item -LiteralPath $Path -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "$Context may not be a reparse point: $Path"
  }
}

function Get-MIRImmutableInputFileIdentity {
  param([Parameter(Mandatory)][string]$Path)

  if ($null -eq ('MIRImmutableInputNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class MIRImmutableInputNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct BY_HANDLE_FILE_INFORMATION
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        IntPtr hFile,
        out BY_HANDLE_FILE_INFORMATION lpFileInformation);

    public static string GetIdentity(SafeFileHandle handle)
    {
        BY_HANDLE_FILE_INFORMATION information;
        if (!GetFileInformationByHandle(handle.DangerousGetHandle(), out information))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        ulong fileIndex = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
        return information.VolumeSerialNumber.ToString("X8") + ":" + fileIndex.ToString("X16");
    }
}
'@
  }

  $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  try {
    return [MIRImmutableInputNative]::GetIdentity($stream.SafeFileHandle)
  } finally {
    $stream.Dispose()
  }
}

function Assert-MIRImmutableInputCopyCapacity {
  param(
    [Parameter(Mandatory)][string]$DestinationDirectory,
    [Parameter(Mandatory)][long]$RequiredBytes,
    [long]$ReserveBytes = 536870912
  )

  $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($DestinationDirectory))
  if ([string]::IsNullOrWhiteSpace($root)) {
    throw "Cannot determine the destination volume for immutable input staging: $DestinationDirectory"
  }
  $drive = [IO.DriveInfo]::new($root)
  $requiredFree = $RequiredBytes + $ReserveBytes
  if ($drive.AvailableFreeSpace -lt $requiredFree) {
    throw "Immutable input copy requires $requiredFree free bytes on $root but only $($drive.AvailableFreeSpace) are available."
  }
}

function Write-MIRImmutableInputLeaseRecord {
  param(
    [Parameter(Mandatory)][Collections.IDictionary]$Record,
    [Parameter(Mandatory)][string]$Path
  )

  $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
  try {
    [IO.File]::WriteAllText($temporary, (($Record | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) {
      Remove-Item -LiteralPath $temporary -Force
    }
  }
}

function Get-MIRImmutableInputRecordSha256 {
  param([Parameter(Mandatory)]$Record)

  $unsigned = [ordered]@{}
  if ($Record -is [Collections.IDictionary]) {
    foreach ($name in $Record.Keys) {
      if ([string]$name -cne 'terminal_record_sha256') { $unsigned[[string]$name] = $Record[$name] }
    }
  } else {
    foreach ($property in $Record.PSObject.Properties) {
      if ($property.Name -cne 'terminal_record_sha256') { $unsigned[$property.Name] = $property.Value }
    }
  }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($unsigned | ConvertTo-Json -Depth 20 -Compress))
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Assert-MIRImmutableInputTerminalReceipt {
  param([Parameter(Mandatory)]$Receipt, [string]$Context = 'Immutable input terminal receipt')

  if ([int](Get-MIRImmutableInputProperty $Receipt 'schema' 0) -ne 1 -or
      [string](Get-MIRImmutableInputProperty $Receipt 'kind') -cne 'MIRImmutableInputLeaseV1' -or
      [string](Get-MIRImmutableInputProperty $Receipt 'state') -cne 'completed' -or
      [string](Get-MIRImmutableInputProperty $Receipt 'outcome') -cne 'passed' -or
      -not [bool](Get-MIRImmutableInputProperty $Receipt 'inputs_sha256_match' $false) -or
      $null -ne (Get-MIRImmutableInputProperty $Receipt 'owner_pid')) {
    throw "$Context is not a completed passed immutable-input receipt."
  }
  $completedOwner = 0
  if (-not [int]::TryParse([string](Get-MIRImmutableInputProperty $Receipt 'completed_owner_pid'), [ref]$completedOwner) -or $completedOwner -le 0) {
    throw "$Context does not identify its completed owner."
  }
  foreach ($timestampName in @('started_utc', 'receipt_captured_utc', 'completed_utc')) {
    $timestampValue = Get-MIRImmutableInputProperty $Receipt $timestampName
    $timestamp = [DateTimeOffset]::MinValue
    $validTimestamp = $timestampValue -is [DateTime] -or $timestampValue -is [DateTimeOffset]
    if (-not $validTimestamp) {
      $validTimestamp = [DateTimeOffset]::TryParse([string]$timestampValue, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$timestamp)
    }
    if (-not $validTimestamp) {
      throw "$Context has an invalid $timestampName value."
    }
  }
  $inputs = @(Get-MIRImmutableInputProperty $Receipt 'inputs' @())
  if ($inputs.Count -eq 0) { throw "$Context contains no immutable inputs." }
  $seenNames = @{}
  foreach ($input in $inputs) {
    $fileName = [string](Get-MIRImmutableInputProperty $input 'file_name')
    $expected = [string](Get-MIRImmutableInputProperty $input 'expected_sha256')
    $bytes = -1L
    if ($fileName -notmatch '^[^\\/:*?"<>|]+$' -or $fileName -in @('.', '..') -or $seenNames.ContainsKey($fileName)) {
      throw "$Context contains an invalid or duplicated input file name."
    }
    $seenNames[$fileName] = $true
    if ($expected -notmatch '^[0-9A-F]{64}$' -or
        [string](Get-MIRImmutableInputProperty $input 'source_pre_sha256') -cne $expected -or
        [string](Get-MIRImmutableInputProperty $input 'staged_pre_sha256') -cne $expected -or
        [string](Get-MIRImmutableInputProperty $input 'source_post_sha256') -cne $expected -or
        [string](Get-MIRImmutableInputProperty $input 'staged_post_sha256') -cne $expected -or
        -not [bool](Get-MIRImmutableInputProperty $input 'hashes_match' $false)) {
      throw "$Context contains an input without complete matching pre/post hashes: $fileName"
    }
    if (-not [long]::TryParse([string](Get-MIRImmutableInputProperty $input 'bytes'), [ref]$bytes) -or $bytes -lt 0 -or
        [string]::IsNullOrWhiteSpace([string](Get-MIRImmutableInputProperty $input 'source_path')) -or
        [string]::IsNullOrWhiteSpace([string](Get-MIRImmutableInputProperty $input 'stage_path')) -or
        [string]::IsNullOrWhiteSpace([string](Get-MIRImmutableInputProperty $input 'role'))) {
      throw "$Context contains an incomplete immutable input: $fileName"
    }
  }
  $recordSha256 = [string](Get-MIRImmutableInputProperty $Receipt 'terminal_record_sha256')
  if ($recordSha256 -notmatch '^[0-9A-F]{64}$' -or $recordSha256 -cne (Get-MIRImmutableInputRecordSha256 -Record $Receipt)) {
    throw "$Context failed its terminal-record integrity check."
  }
  return $Receipt
}

function Close-MIRImmutableInputLeaseHandles {
  param([Parameter(Mandatory)]$Lease)

  foreach ($handle in @($Lease.staged_handles)) {
    if ($null -ne $handle) { $handle.Dispose() }
  }
  foreach ($handle in @($Lease.source_handles)) {
    if ($null -ne $handle) { $handle.Dispose() }
  }
  if ($null -ne $Lease.lease_handle) { $Lease.lease_handle.Dispose() }
  $Lease.closed = $true
}

function New-MIRImmutableInputLease {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$StageDirectory,
    [Parameter(Mandatory)][object[]]$Inputs,
    [ValidateRange(0, [long]::MaxValue)][long]$CopyReserveBytes = 536870912,
    [switch]$ForceCopy
  )

  $runRoot = (Resolve-Path -LiteralPath $RunRoot).Path
  Assert-MIRImmutableInputDirectory -Path $runRoot -Context 'Immutable input run root'
  $stageDirectory = Assert-MIRImmutableInputPathWithin -Path $StageDirectory -Root $runRoot -Context 'Immutable input stage directory'
  if (-not (Test-Path -LiteralPath $stageDirectory)) {
    New-Item -ItemType Directory -Force -Path $stageDirectory | Out-Null
  }
  Assert-MIRImmutableInputDirectory -Path $stageDirectory -Context 'Immutable input stage directory'
  if (@(Get-ChildItem -LiteralPath $stageDirectory -Force).Count -ne 0) {
    throw "Immutable input stage directory must be empty before staging: $stageDirectory"
  }
  if ($Inputs.Count -eq 0) { throw 'Immutable input staging requires at least one input.' }

  $recordPath = Join-Path $runRoot 'mir-immutable-input-lease.json'
  $lockPath = Join-Path $runRoot 'mir-immutable-input-lease.lock'
  if ((Test-Path -LiteralPath $recordPath) -or (Test-Path -LiteralPath $lockPath)) {
    throw "Immutable input lease already exists for this run: $runRoot"
  }

  $record = [ordered]@{
    schema = 1
    kind = 'MIRImmutableInputLeaseV1'
    lease_id = [guid]::NewGuid().ToString('N')
    owner_pid = $PID
    started_utc = [DateTime]::UtcNow.ToString('o')
    state = 'staging'
    run_root = $runRoot
    stage_directory = $stageDirectory
    copy_reserve_bytes = $CopyReserveBytes
    inputs = @()
  }
  $lease = [pscustomobject]@{
    record = $record
    record_path = $recordPath
    lock_path = $lockPath
    lease_handle = $null
    source_handles = @()
    staged_handles = @()
    closed = $false
  }

  try {
    $lease.lease_handle = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $seenNames = @{}
    foreach ($input in $Inputs) {
      $source = Get-MIRImmutableInputProperty -InputObject $input -Name 'source_path'
      $fileName = [string](Get-MIRImmutableInputProperty -InputObject $input -Name 'file_name')
      $expectedSha256 = [string](Get-MIRImmutableInputProperty -InputObject $input -Name 'expected_sha256')
      $role = [string](Get-MIRImmutableInputProperty -InputObject $input -Name 'role')
      $identity = Get-MIRImmutableInputProperty -InputObject $input -Name 'identity'
      $provenance = Get-MIRImmutableInputProperty -InputObject $input -Name 'provenance'
      $immutable = [bool](Get-MIRImmutableInputProperty -InputObject $input -Name 'immutable' -Default $false)
      if ([string]::IsNullOrWhiteSpace([string]$source) -or -not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Immutable input source is absent: $source"
      }
      if ($fileName -notmatch '^[^\\/:*?"<>|]+$' -or $fileName -in @('.', '..')) {
        throw "Immutable input file name is unsafe: $fileName"
      }
      if ($seenNames.ContainsKey($fileName)) { throw "Immutable input file name is duplicated: $fileName" }
      $seenNames[$fileName] = $true
      if ($expectedSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "Immutable input requires an exact SHA-256: $fileName"
      }
      if ([string]::IsNullOrWhiteSpace($role) -or $null -eq $identity -or $null -eq $provenance) {
        throw "Immutable input requires role, identity, and provenance: $fileName"
      }

      $sourceFull = (Resolve-Path -LiteralPath $source).Path
      $runPrefix = $runRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
      if ($sourceFull.StartsWith($runPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Immutable input source may not be staged from its own private run root: $sourceFull"
      }
      $sourceItem = Get-Item -LiteralPath $sourceFull -Force
      if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Immutable input source may not be a reparse point: $sourceFull"
      }
      $sourceHandle = [IO.File]::Open($sourceFull, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
      $lease.source_handles += $sourceHandle
      $sourceHash = Get-MIRImmutableInputSha256 -Path $sourceFull
      if ($sourceHash -cne $expectedSha256.ToUpperInvariant()) {
        throw "Immutable input hash differs before staging: $fileName"
      }
      $destination = Join-Path $stageDirectory $fileName
      $mode = 'copy'
      $sourceIdentity = $null
      $stageIdentity = $null
      $linkError = $null
      if ($immutable -and -not $ForceCopy) {
        try {
          $sourceIdentity = Get-MIRImmutableInputFileIdentity -Path $sourceFull
          New-Item -ItemType HardLink -Path $destination -Target $sourceFull -ErrorAction Stop | Out-Null
          $stageIdentity = Get-MIRImmutableInputFileIdentity -Path $destination
          if ($sourceIdentity -cne $stageIdentity) {
            throw "Hard-link file identity proof differs for $fileName"
          }
          $mode = 'hardlink'
        } catch {
          $linkError = $_.Exception.Message
        }
      } elseif (-not $immutable) {
        $linkError = 'source was not declared immutable after exact hash verification'
      } else {
        $linkError = 'copy mode was explicitly selected'
      }
      if ($mode -ne 'hardlink') {
        Assert-MIRImmutableInputCopyCapacity -DestinationDirectory $stageDirectory -RequiredBytes $sourceItem.Length -ReserveBytes $CopyReserveBytes
        Copy-Item -LiteralPath $sourceFull -Destination $destination -ErrorAction Stop
      }

      $stageHash = Get-MIRImmutableInputSha256 -Path $destination
      if ($stageHash -cne $sourceHash) {
        throw "Immutable input hash differs after staging: $fileName"
      }
      $stageHandle = [IO.File]::Open($destination, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
      $lease.staged_handles += $stageHandle
      $record.inputs += [ordered]@{
        role = $role
        identity = $identity
        provenance = $provenance
        file_name = $fileName
        source_path = $sourceFull
        stage_path = $destination
        bytes = [long]$sourceItem.Length
        expected_sha256 = $expectedSha256.ToUpperInvariant()
        source_pre_sha256 = $sourceHash
        staged_pre_sha256 = $stageHash
        immutable = $immutable
        staging_mode = $mode
        hardlink_file_identity = if ($mode -eq 'hardlink') { [ordered]@{ source = $sourceIdentity; staged = $stageIdentity; verified = $true } } else { $null }
        hardlink_fallback_reason = if ($mode -eq 'copy') { $linkError } else { $null }
      }
    }
    $record.state = 'active'
    Write-MIRImmutableInputLeaseRecord -Record $record -Path $recordPath
    return $lease
  } catch {
    $record.state = 'staging-failed'
    $record.failed_utc = [DateTime]::UtcNow.ToString('o')
    $record.failure = $_.Exception.Message
    try { Write-MIRImmutableInputLeaseRecord -Record $record -Path $recordPath } catch {}
    Close-MIRImmutableInputLeaseHandles -Lease $lease
    throw
  }
}

function Get-MIRImmutableInputLeaseReceipt {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Lease)

  if ($Lease.closed) { throw 'Immutable input lease is already closed.' }
  $matches = $true
  foreach ($input in @($Lease.record.inputs)) {
    $input.source_post_sha256 = Get-MIRImmutableInputSha256 -Path $input.source_path
    $input.staged_post_sha256 = Get-MIRImmutableInputSha256 -Path $input.stage_path
    $input.hashes_match = ($input.source_post_sha256 -ceq $input.expected_sha256 -and $input.staged_post_sha256 -ceq $input.expected_sha256)
    if (-not $input.hashes_match) { $matches = $false }
  }
  $Lease.record.state = 'receipt-captured'
  $Lease.record.receipt_captured_utc = [DateTime]::UtcNow.ToString('o')
  $Lease.record.inputs_sha256_match = $matches
  Write-MIRImmutableInputLeaseRecord -Record $Lease.record -Path $Lease.record_path
  if (-not $matches) {
    throw 'Immutable input lease detected an input mutation before its receipt could be captured; private run output was retained for investigation.'
  }
  return (($Lease.record | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
}

function Complete-MIRImmutableInputLease {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Lease,
    [ValidateSet('passed', 'failed')][string]$Outcome = 'passed'
  )

  if ($Lease.closed) { throw 'Immutable input lease is already closed.' }
  $receipt = Get-MIRImmutableInputLeaseReceipt -Lease $Lease
  $matches = [bool]$receipt.inputs_sha256_match
  $Lease.record.state = if ($Outcome -eq 'passed' -and $matches) { 'completed' } else { 'failed' }
  $Lease.record.outcome = $Outcome
  $Lease.record.completed_utc = [DateTime]::UtcNow.ToString('o')
  $Lease.record.inputs_sha256_match = $matches
  $Lease.record.completed_owner_pid = $Lease.record.owner_pid
  $Lease.record.owner_pid = $null
  $Lease.record['terminal_record_sha256'] = Get-MIRImmutableInputRecordSha256 -Record $Lease.record
  Write-MIRImmutableInputLeaseRecord -Record $Lease.record -Path $Lease.record_path
  Close-MIRImmutableInputLeaseHandles -Lease $Lease
  if (-not $matches) {
    throw 'Immutable input lease detected an input mutation; private run output was retained for investigation.'
  }
  return [pscustomobject]$Lease.record
}

function ConvertTo-MIRImmutableInputArtifact {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Receipt,
    [Parameter(Mandatory)][Alias('Input')]$InputRecord,
    [Parameter(Mandatory)][string]$Locator
  )

  $null = Assert-MIRImmutableInputTerminalReceipt -Receipt $Receipt
  if ([string]::IsNullOrWhiteSpace($Locator)) { throw 'Immutable input artifact requires a non-empty logical locator.' }
  $fileName = [string](Get-MIRImmutableInputProperty $InputRecord 'file_name')
  $sourcePath = [string](Get-MIRImmutableInputProperty $InputRecord 'source_path')
  $stagePath = [string](Get-MIRImmutableInputProperty $InputRecord 'stage_path')
  $expected = [string](Get-MIRImmutableInputProperty $InputRecord 'expected_sha256')
  $matches = @(@(Get-MIRImmutableInputProperty $Receipt 'inputs' @()) | Where-Object {
    [string](Get-MIRImmutableInputProperty $_ 'file_name') -ceq $fileName -and
    [string](Get-MIRImmutableInputProperty $_ 'source_path') -ceq $sourcePath -and
    [string](Get-MIRImmutableInputProperty $_ 'stage_path') -ceq $stagePath -and
    [string](Get-MIRImmutableInputProperty $_ 'expected_sha256') -ceq $expected
  })
  if ($matches.Count -ne 1) { throw "Immutable input artifact does not identify exactly one terminal receipt input: $fileName" }
  return [pscustomobject][ordered]@{
    path = $Locator
    bytes = [long](Get-MIRImmutableInputProperty $matches[0] 'bytes')
    raw_sha256 = $expected
  }
}

function Get-MIRImmutableInputLeaseLiveness {
  param([Parameter(Mandatory)][string]$RunRoot)

  $recordPath = Join-Path $RunRoot 'mir-immutable-input-lease.json'
  $lockPath = Join-Path $RunRoot 'mir-immutable-input-lease.lock'
  if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
      try {
        $probe = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $probe.Dispose()
      } catch [IO.IOException] {
        return [pscustomobject]@{ present = $true; active = $true; ambiguous = $false; state = 'missing-record'; reason = 'lease lock is held but its record is absent'; record = $null }
      }
      return [pscustomobject]@{ present = $true; active = $false; ambiguous = $false; state = 'missing-record'; reason = 'lease lock remains without a record'; record = $null }
    }
    return [pscustomobject]@{ present = $false; active = $false; ambiguous = $false; state = $null; reason = $null; record = $null }
  }
  try {
    $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json -Depth 20 -DateKind String -ErrorAction Stop
  } catch {
    return [pscustomobject]@{ present = $true; active = $false; ambiguous = $true; state = 'invalid'; reason = 'lease record is invalid'; record = $null }
  }
  if ($record.kind -cne 'MIRImmutableInputLeaseV1') {
    return [pscustomobject]@{ present = $true; active = $false; ambiguous = $true; state = 'invalid'; reason = 'lease record kind is unrecognized'; record = $record }
  }
  $lockHeld = $false
  if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
    try {
      $probe = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
      $probe.Dispose()
    } catch [IO.IOException] {
      $lockHeld = $true
    }
  }
  if ($lockHeld) {
    return [pscustomobject]@{ present = $true; active = $true; ambiguous = $false; state = [string]$record.state; reason = 'lease lock is held'; record = $record }
  }
  if ([string]$record.state -in @('completed', 'failed')) {
    return [pscustomobject]@{ present = $true; active = $false; ambiguous = $false; state = [string]$record.state; reason = 'terminal lease record is unlocked'; record = $record }
  }
  $ownerAlive = $false
  $ownerId = 0
  if ([int]::TryParse([string]$record.owner_pid, [ref]$ownerId) -and $ownerId -gt 0) {
    $ownerAlive = $null -ne (Get-Process -Id $ownerId -ErrorAction SilentlyContinue)
  }
  if ($ownerAlive) {
    return [pscustomobject]@{ present = $true; active = $false; ambiguous = $true; state = [string]$record.state; reason = 'lease owner PID is live but the lease lock is absent'; record = $record }
  }
  return [pscustomobject]@{ present = $true; active = $false; ambiguous = $false; state = [string]$record.state; reason = 'lease lock is not held and owner PID is not live'; record = $record }
}

function Assert-MIRImmutableInputLeaseReclaimable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$Context
  )

  $liveness = Get-MIRImmutableInputLeaseLiveness -RunRoot $RunRoot
  # Only a completed lease with verified terminal hashes and a released owner
  # is safe to reclaim. Any other record is active, ambiguous, failed, or
  # orphaned recovery custody.
  $completed = $liveness.present -and
    -not $liveness.active -and
    -not $liveness.ambiguous -and
    $liveness.state -ceq 'completed' -and
    $null -ne $liveness.record
  $terminalError = $null
  if ($completed) {
    try { $null = Assert-MIRImmutableInputTerminalReceipt -Receipt $liveness.record -Context $Context } catch { $completed = $false; $terminalError = $_.Exception.Message }
  }
  if ($liveness.present -and -not $completed) {
    $reason = if ([string]::IsNullOrWhiteSpace($terminalError)) { $liveness.reason } else { $terminalError }
    throw "$Context retains immutable-input custody and may not be removed: state=$($liveness.state); reason=$reason"
  }
  return $liveness
}
