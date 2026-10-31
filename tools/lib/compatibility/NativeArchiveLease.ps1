. (Join-Path $PSScriptRoot '../validation/ImmutableInputStaging.ps1')
. (Join-Path $PSScriptRoot 'LibraryActivation.ps1')

$script:MIRNativeArchiveLeaseNames = @(
  'more-infinite-research_5.0.21000.zip',
  'mir-fixture-mir5-api-beta_0.1.0.zip',
  'mir-fixture-mir5-library-multiplayer_0.3.0.zip'
)

function Write-MIRNativeArchiveLeaseRecord {
  param([Parameter(Mandatory)][Collections.IDictionary]$Record,[Parameter(Mandatory)][string]$Path)
  $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
  try {
    [IO.File]::WriteAllText($temporary, (($Record | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary, $Path, $true)
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { [IO.File]::Delete($temporary) }
  }
}

function Get-MIRNativeArchiveLeaseRecord {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Native archive lease journal is missing: $Path" }
  Assert-MIRLibraryPath $Path
  if ((Get-Item -LiteralPath $Path).Length -gt 1MB) { throw '[mir-native-archive-lease-size]' }
  return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -DateKind String
}

function Assert-MIRNativeArchiveLeaseRecord {
  param([Parameter(Mandatory)][Collections.IDictionary]$Record,[Parameter(Mandatory)][string]$LibraryDirectory)
  $output = [IO.Path]::GetFullPath([string]$Record.output_root).TrimEnd('\','/')
  $outputPrefix = $output + [IO.Path]::DirectorySeparatorChar
  $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')).TrimEnd('\','/')
  $repoPrefix = $repo + [IO.Path]::DirectorySeparatorChar
  Assert-MIRLibraryPath $output
  if (-not $output.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase) -or
      [string]$Record.receipt_path -cne [IO.Path]::GetFullPath((Join-Path $output 'direct-library-archive-lease-receipt.json')) -or
      $Record.kind -cne 'MIRNativeArchiveLeaseV1' -or [int]$Record.schema -ne 1 -or
      [IO.Path]::GetFullPath([string]$Record.library) -cne [IO.Path]::GetFullPath($LibraryDirectory) -or
      $Record.entries -isnot [array] -or $Record.entries.Count -ne $script:MIRNativeArchiveLeaseNames.Count) {
    throw '[mir-native-archive-lease-identity]'
  }
  $names = @($Record.entries | ForEach-Object { [string]$_.file_name })
  if ((@($names | Sort-Object -Unique) -join '|') -cne (@($script:MIRNativeArchiveLeaseNames | Sort-Object) -join '|')) {
    throw '[mir-native-archive-lease-members]'
  }
  foreach ($row in $Record.entries) {
    if ([string]$row.file_name -cnotin $script:MIRNativeArchiveLeaseNames -or
        $row.original_exists -isnot [bool] -or $row.unchanged -isnot [bool] -or
        $row.candidate_bytes -isnot [long] -or $row.original_bytes -isnot [long]) {
      throw '[mir-native-archive-lease-entry-type]'
    }
    $unchanged = [bool]$row.unchanged
    $candidateTemp = [string]$row.candidate_temp
    $backupPath = [string]$row.backup_path
    $validCandidateTemp = $false
    if ($unchanged) {
      $validCandidateTemp = -not [bool]$row.original_exists -or $candidateTemp -ceq ''
    } elseif ($candidateTemp) {
      $fullTemp = [IO.Path]::GetFullPath($candidateTemp)
      $validCandidateTemp = [IO.Path]::GetDirectoryName($fullTemp) -ceq [IO.Path]::GetFullPath($LibraryDirectory) -and
        [IO.Path]::GetFileName($fullTemp) -cmatch ('^' + [regex]::Escape([string]$row.file_name) + '[.]mir-preview-[0-9a-f]{32}[.]tmp$')
    }
    $validBackup = $false
    if ([bool]$row.original_exists -and -not $unchanged -and $backupPath) {
      $fullBackup = [IO.Path]::GetFullPath($backupPath)
      $validBackup = $fullBackup.StartsWith($outputPrefix,[StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($fullBackup) -ceq ([string]$row.file_name + '.original')
    } elseif (-not [bool]$row.original_exists -or $unchanged) { $validBackup = $backupPath -ceq '' }
    $validHashes = [string]$row.candidate_sha256 -cmatch '^[A-F0-9]{64}$' -and
      [string]$row.candidate_identity -cmatch '^[A-F0-9]{8}:[A-F0-9]{16}$'
    if (-not $validHashes -or -not $validCandidateTemp -or -not $validBackup -or
        ([bool]$row.original_exists -and ([string]$row.original_sha256 -cnotmatch '^[A-F0-9]{64}$' -or
          [string]$row.original_identity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$')) -or
        (-not [bool]$row.original_exists -and ($row.original_sha256 -cne '' -or $row.original_identity -cne '')) -or
        ($unchanged -and (-not [bool]$row.original_exists -or [string]$row.original_sha256 -cne [string]$row.candidate_sha256 -or
          [string]$row.original_identity -cne [string]$row.candidate_identity))) {
      throw '[mir-native-archive-lease-entry]'
    }
  }
}

function Restore-MIRNativeArchiveLeaseRecord {
  param(
    [Parameter(Mandatory)][Collections.IDictionary]$Record,
    [Parameter(Mandatory)][string]$JournalPath,
    [Parameter(Mandatory)][string]$LibraryDirectory,
    [switch]$KeepLock
  )
  if ([IO.Path]::GetFullPath($JournalPath) -cne [IO.Path]::GetFullPath((Join-Path $LibraryDirectory '.mir-library-preview-archive.json'))) {
    throw '[mir-native-archive-lease-journal-path]'
  }
  Assert-MIRLibraryIdle -WaitMilliseconds 3000
  Assert-MIRNativeArchiveLeaseRecord -Record $Record -LibraryDirectory $LibraryDirectory
  $operations = [Collections.Generic.List[object]]::new()
  foreach ($row in $Record.entries) {
    $destination = Join-Path $LibraryDirectory ([string]$row.file_name)
    if (Test-Path -LiteralPath $destination) {
      Assert-MIRLibraryPath $destination
      if ((Get-Item -LiteralPath $destination).PSIsContainer) { throw '[mir-native-archive-lease-target-type]' }
      $destinationHash = Get-MIRImmutableInputSha256 -Path $destination
      $destinationIdentity = Get-MIRImmutableInputFileIdentity -Path $destination
    } else { $destinationHash = ''; $destinationIdentity = '' }
    $backupExists = [bool]$row.original_exists -and -not [bool]$row.unchanged -and (Test-Path -LiteralPath ([string]$row.backup_path) -PathType Leaf)
    if ($backupExists) {
      Assert-MIRLibraryPath ([string]$row.backup_path)
      if ((Get-MIRImmutableInputSha256 -Path ([string]$row.backup_path)) -cne [string]$row.original_sha256 -or
          (Get-MIRImmutableInputFileIdentity -Path ([string]$row.backup_path)) -cne [string]$row.original_identity -or
          (Get-Item -LiteralPath ([string]$row.backup_path)).Length -ne [long]$row.original_bytes) {
        throw '[mir-native-archive-lease-backup-changed]'
      }
    }
    $isOriginal = [bool]$row.original_exists -and $destinationHash -ceq [string]$row.original_sha256 -and $destinationIdentity -ceq [string]$row.original_identity
    $isCandidate = $destinationHash -ceq [string]$row.candidate_sha256 -and $destinationIdentity -ceq [string]$row.candidate_identity
    if ($destinationHash -and -not $isOriginal -and -not $isCandidate) { throw '[mir-native-archive-lease-target-changed]' }
    if ($isOriginal -and (Get-Item -LiteralPath $destination).Length -ne [long]$row.original_bytes) { throw '[mir-native-archive-lease-original-size]' }
    if ($isCandidate -and (Get-Item -LiteralPath $destination).Length -ne [long]$row.candidate_bytes) { throw '[mir-native-archive-lease-candidate-size]' }
    if ($isOriginal -and $backupExists) { throw '[mir-native-archive-lease-duplicate-original]' }
    if ([bool]$row.original_exists -and -not $isOriginal -and -not $backupExists) { throw '[mir-native-archive-lease-original-unrecoverable]' }
    if (-not [bool]$row.original_exists -and $backupExists) { throw '[mir-native-archive-lease-unexpected-backup]' }
    $tempExists = [string]$row.candidate_temp -and (Test-Path -LiteralPath ([string]$row.candidate_temp) -PathType Leaf)
    if ($tempExists) {
      Assert-MIRLibraryPath ([string]$row.candidate_temp)
      if ((Get-MIRImmutableInputSha256 -Path ([string]$row.candidate_temp)) -cne [string]$row.candidate_sha256 -or
          (Get-MIRImmutableInputFileIdentity -Path ([string]$row.candidate_temp)) -cne [string]$row.candidate_identity) {
        throw '[mir-native-archive-lease-temp-changed]'
      }
    }
    $operations.Add([pscustomobject]@{row=$row;destination=$destination;is_original=$isOriginal;is_candidate=$isCandidate;backup_exists=$backupExists;temp_exists=$tempExists})
  }

  foreach ($operation in $operations) {
    $row = $operation.row
    if ($operation.backup_exists) {
      if ($operation.is_candidate) { [IO.File]::Delete($operation.destination) }
      [IO.File]::Move([string]$row.backup_path, $operation.destination, $false)
    } elseif (-not [bool]$row.original_exists -and $operation.is_candidate) {
      [IO.File]::Delete($operation.destination)
    }
    if ($operation.temp_exists) { [IO.File]::Delete([string]$row.candidate_temp) }
  }

  foreach ($row in $Record.entries) {
    $destination = Join-Path $LibraryDirectory ([string]$row.file_name)
    if ([bool]$row.original_exists) {
      if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
          (Get-MIRImmutableInputSha256 -Path $destination) -cne [string]$row.original_sha256 -or
          (Get-MIRImmutableInputFileIdentity -Path $destination) -cne [string]$row.original_identity -or
          (Get-Item -LiteralPath $destination).Length -ne [long]$row.original_bytes) {
        throw '[mir-native-archive-lease-restore-verification]'
      }
    } elseif (Test-Path -LiteralPath $destination) { throw '[mir-native-archive-lease-absence-verification]' }
  }
  $Record.state = 'completed'
  $Record.completed_utc = [DateTime]::UtcNow.ToString('o')
  $Record.owner_pid = $null
  $Record.terminal_record_sha256 = Get-MIRImmutableInputRecordSha256 -Record $Record
  Write-MIRNativeArchiveLeaseRecord -Record $Record -Path ([string]$Record.receipt_path)
  if (Test-Path -LiteralPath $JournalPath -PathType Leaf) { [IO.File]::Delete($JournalPath) }
}

function Start-MIRNativeArchiveLease {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$LibraryDirectory,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][Collections.IDictionary[]]$ArchiveSources
  )
  $library = (Resolve-Path -LiteralPath $LibraryDirectory).Path
  $output = (Resolve-Path -LiteralPath $OutputRoot).Path
  Assert-MIRLibraryPath $library
  Assert-MIRLibraryPath $output
  $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')).TrimEnd('\','/')
  $repoPrefix = $repo + [IO.Path]::DirectorySeparatorChar
  if (-not $output.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir-native-archive-lease-output-outside-checkout]' }
  if ([IO.Path]::GetPathRoot($library) -cne [IO.Path]::GetPathRoot($output)) { throw '[mir-native-archive-lease-volume]' }
  Assert-MIRLibraryIdle -WaitMilliseconds 3000
  $lockPath = Join-Path $library '.mir-library-preview-archive.lock'
  $journalPath = Join-Path $library '.mir-library-preview-archive.json'
  if (Test-Path -LiteralPath $lockPath) { Assert-MIRLibraryPath $lockPath }
  if (Test-Path -LiteralPath $journalPath) { Assert-MIRLibraryPath $journalPath }
  try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
  catch { throw '[mir-native-archive-lease-busy]' }
  $lease = $null
  $preStaged = [Collections.Generic.List[object]]::new()
  $sourceHandles = [Collections.Generic.List[object]]::new()
  try {
    Assert-MIRLibraryIdle -WaitMilliseconds 3000
    if (Test-Path -LiteralPath $journalPath) {
      $old = Get-MIRNativeArchiveLeaseRecord -Path $journalPath
      $owner = Get-Process -Id ([int]$old.owner_pid) -ErrorAction SilentlyContinue
      if ($null -ne $owner -and $owner.StartTime.ToUniversalTime().ToString('o') -ceq [string]$old.owner_started_utc) {
        throw '[mir-native-archive-lease-owner-alive]'
      }
      Restore-MIRNativeArchiveLeaseRecord -Record $old -JournalPath $journalPath -LibraryDirectory $library -KeepLock
    }
    if ($ArchiveSources.Count -ne $script:MIRNativeArchiveLeaseNames.Count) { throw '[mir-native-archive-lease-source-count]' }
    $backupRoot = Join-Path $output 'direct-library-originals'
    if (Test-Path -LiteralPath $backupRoot) { throw '[mir-native-archive-lease-output-exists]' }
    $null = [IO.Directory]::CreateDirectory($backupRoot)
    $names = @($ArchiveSources | ForEach-Object { [string]$_.file_name })
    if ((@($names | Sort-Object -Unique) -join '|') -cne (@($script:MIRNativeArchiveLeaseNames | Sort-Object) -join '|')) {
      throw '[mir-native-archive-lease-source-members]'
    }
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($input in $ArchiveSources) {
      $fileName = [string]$input.file_name
      $candidate = (Resolve-Path -LiteralPath ([string]$input.source_path)).Path
      Assert-MIRLibraryPath $candidate
      $candidatePrefix = $library.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
      if ($candidate.StartsWith($candidatePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "[mir-native-archive-lease-source-in-library] $fileName" }
      $candidateSha = ([string]$input.sha256).ToUpperInvariant()
      if ($candidateSha -cnotmatch '^[A-F0-9]{64}$' -or (Get-MIRImmutableInputSha256 -Path $candidate) -cne $candidateSha) {
        throw "[mir-native-archive-lease-candidate-hash] $fileName"
      }
      $sourceHandle = [IO.File]::Open($candidate,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      $sourceHandles.Add($sourceHandle)
      $destination = Join-Path $library $fileName
      $originalExists = Test-Path -LiteralPath $destination -PathType Leaf
      if ((Test-Path -LiteralPath $destination) -and -not $originalExists) { throw "[mir-native-archive-lease-target-type] $fileName" }
      if ($originalExists) {
        Assert-MIRLibraryPath $destination
        $originalSha = Get-MIRImmutableInputSha256 -Path $destination
        $originalIdentity = Get-MIRImmutableInputFileIdentity -Path $destination
        $originalBytes = (Get-Item -LiteralPath $destination).Length
      } else { $originalSha = ''; $originalIdentity = ''; $originalBytes = 0L }
      $candidateTemp = Join-Path $library ($fileName + '.mir-preview-' + [guid]::NewGuid().ToString('N') + '.tmp')
      $unchanged = $originalExists -and $originalSha -ceq $candidateSha
      $candidateIdentity = if ($unchanged) { $originalIdentity } else {
        [IO.File]::Copy($candidate, $candidateTemp, $false)
        $stagedIdentity = Get-MIRImmutableInputFileIdentity -Path $candidateTemp
        $preStaged.Add([pscustomobject]@{path=$candidateTemp;sha256=$candidateSha;identity=$stagedIdentity})
        if ((Get-MIRImmutableInputSha256 -Path $candidateTemp) -cne $candidateSha) { throw "[mir-native-archive-lease-stage-hash] $fileName" }
        $stagedIdentity
      }
      $backupPath = if ($originalExists -and -not $unchanged) { Join-Path $backupRoot ($fileName + '.original') } else { '' }
      $entries.Add([ordered]@{
        file_name=$fileName;candidate_sha256=$candidateSha;candidate_bytes=[long](Get-Item -LiteralPath $candidate).Length
        candidate_source=$candidate;candidate_temp=$(if($unchanged){''}else{$candidateTemp});candidate_identity=$candidateIdentity
        original_exists=[bool]$originalExists;original_sha256=$originalSha;original_bytes=[long]$originalBytes
        original_identity=$originalIdentity;backup_path=$backupPath;unchanged=[bool]$unchanged;state='prepared'
      })
    }
    foreach ($row in $entries) {
      if ($row.unchanged) { continue }
      if ($row.original_exists) {
        if ([IO.Path]::GetPathRoot([string]$row.backup_path) -cne [IO.Path]::GetPathRoot($library)) { throw '[mir-native-archive-lease-backup-volume]' }
      }
    }
    $record = [ordered]@{
      schema=1;kind='MIRNativeArchiveLeaseV1';state='prepared';library=$library;output_root=$output
      owner_pid=$PID;owner_started_utc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
      started_utc=[DateTime]::UtcNow.ToString('o');receipt_path=(Join-Path $output 'direct-library-archive-lease-receipt.json')
      entries=@($entries.ToArray())
    }
    Assert-MIRNativeArchiveLeaseRecord -Record $record -LibraryDirectory $library
    $lease = [pscustomobject]@{record=$record;journal_path=$journalPath;library=$library;lock=$lock;closed=$false}
    $lease | Add-Member -NotePropertyName source_handles -NotePropertyValue $sourceHandles
    Write-MIRNativeArchiveLeaseRecord -Record $record -Path $journalPath
    Write-MIRNativeArchiveLeaseRecord -Record $record -Path (Join-Path $output 'direct-library-archive-lease-prepared.json')
    foreach ($row in $record.entries) {
      if ($row.unchanged) { continue }
      $row.state = 'installing';$record.state = 'installing'
      Write-MIRNativeArchiveLeaseRecord -Record $record -Path $journalPath
      if ($row.original_exists) { [IO.File]::Move((Join-Path $library $row.file_name), [string]$row.backup_path, $false) }
      [IO.File]::Move([string]$row.candidate_temp, (Join-Path $library $row.file_name), $false)
      if ((Get-MIRImmutableInputSha256 -Path (Join-Path $library $row.file_name)) -cne [string]$row.candidate_sha256 -or
          (Get-MIRImmutableInputFileIdentity -Path (Join-Path $library $row.file_name)) -cne [string]$row.candidate_identity) {
        throw "[mir-native-archive-lease-installed-identity] $($row.file_name)"
      }
      $row.state = 'installed';Write-MIRNativeArchiveLeaseRecord -Record $record -Path $journalPath
    }
    $record.state = 'active';Write-MIRNativeArchiveLeaseRecord -Record $record -Path $journalPath
    Write-MIRNativeArchiveLeaseRecord -Record $record -Path (Join-Path $output 'direct-library-archive-lease-prepared.json')
    return $lease
  } catch {
    if ($null -ne $lease) {
      try { Restore-MIRNativeArchiveLeaseRecord -Record $lease.record -JournalPath $journalPath -LibraryDirectory $library } catch { $_ | Out-Null }
    } else {
      foreach ($staged in $preStaged) {
        if ((Test-Path -LiteralPath $staged.path -PathType Leaf) -and
            (Get-MIRImmutableInputSha256 -Path $staged.path) -ceq $staged.sha256 -and
            (Get-MIRImmutableInputFileIdentity -Path $staged.path) -ceq $staged.identity) {
          [IO.File]::Delete($staged.path)
        }
      }
    }
    foreach ($handle in $sourceHandles) { $handle.Dispose() }
    $lock.Dispose()
    throw
  }
}

function Complete-MIRNativeArchiveLease {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Lease)
  if ($Lease.closed) { throw '[mir-native-archive-lease-closed]' }
  try {
    if ([int]$Lease.record.owner_pid -ne $PID) { throw '[mir-native-archive-lease-owner]' }
    Restore-MIRNativeArchiveLeaseRecord -Record $Lease.record -JournalPath $Lease.journal_path -LibraryDirectory $Lease.library
    return [pscustomobject]$Lease.record
  } finally {
    $Lease.closed = $true
    foreach ($handle in @($Lease.source_handles)) { $handle.Dispose() }
    $Lease.lock.Dispose()
  }
}

