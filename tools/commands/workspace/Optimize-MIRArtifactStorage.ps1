[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RepoRoot = '',
  [string[]]$LibraryRoot = @(),
  [ValidateRange(0, 3650)]
  [int]$OlderThanDays = 7,
  [ValidateRange(1, 100000)]
  [int]$MaxFiles = 10000,
  [ValidateRange(1, 10000000)]
  [int]$MaxScannedEntries = 250000,
  [ValidateRange(1, 1000000)]
  [int]$MaxPendingDirectories = 100000,
  [ValidateRange(1, 86400)]
  [int]$MaxScanSeconds = 300,
  [switch]$Apply,
  [switch]$PassThru,
  [Parameter(DontShow)]
  [scriptblock]$BeforeApplyTestHook,
  [Parameter(DontShow)]
  [scriptblock]$AfterReplacementTestHook
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $PSScriptRoot '../../lib/validation/ImmutableInputStaging.ps1')

function Test-MIRStoragePathWithin {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root)
  $fullPath = [IO.Path]::GetFullPath($Path)
  $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  return $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-MIRStoragePlainDirectory {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Name is absent: $Path" }
  $item = Get-Item -LiteralPath $Path -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Name may not be a reparse point: $Path" }
  return $item.FullName
}

function Test-MIRStoragePlainPathChain {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root)
  $current = [IO.Path]::GetFullPath($Path)
  $boundary = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  while ($true) {
    if (-not (Test-Path -LiteralPath $current)) { return $false }
    $item = Get-Item -LiteralPath $current -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    if ($current.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) -ceq $boundary) { return $true }
    $parent = Split-Path -Parent $current
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $current) { return $false }
    $current = $parent
  }
}

function Test-MIRStorageCompletedRun {
  param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][datetime]$Cutoff)
  if (-not (Test-Path -LiteralPath $RunRoot -PathType Container)) { return $false }
  $runItem = Get-Item -LiteralPath $RunRoot -Force
  $resultPath = Join-Path $RunRoot 'result.json'
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { return $false }
  try {
    $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json -Depth 20
    $terminalStatus = [string]$result.status
  } catch {
    return $false
  }
  return (($runItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
    $runItem.Name -cmatch '^[0-9a-f]{32}$' -and
    $runItem.LastWriteTimeUtc -lt $Cutoff -and
    (Test-MIRStorageTerminalStatus -Status $terminalStatus) -and
    -not (Test-Path -LiteralPath (Join-Path $RunRoot 'mir-immutable-input-lease.json')) -and
    -not (Test-Path -LiteralPath (Join-Path $RunRoot 'mir-immutable-input-lease.lock')))
}

function Test-MIRStorageTerminalStatus {
  param([AllowEmptyString()][string]$Status)
  return ($Status -cmatch '^passed(?:-[a-z0-9]+)*$' -or
    $Status -cin @('failed','blocked','skipped','cancelled','error','observed-not-admitted','withheld-by-acyclic-guard'))
}

function Assert-MIRStorageScanBudget {
  param([Parameter(Mandatory)]$State,[switch]$CountEntry)
  if ($CountEntry) { $State.scanned_entries = [long]$State.scanned_entries + 1 }
  if ([long]$State.scanned_entries -gt [long]$State.max_scanned_entries) {
    throw "Storage optimization exceeded its bounded $($State.max_scanned_entries)-entry scan; nothing was changed."
  }
  if ($State.watch.Elapsed.TotalSeconds -gt [int]$State.max_scan_seconds) {
    throw "Storage optimization exceeded its bounded $($State.max_scan_seconds)-second scan; nothing was changed."
  }
}

function Get-MIRStorageLibraryIndex {
  param(
    [Parameter(Mandatory)][string[]]$Roots,
    [Parameter(Mandatory)]$ScanState
  )
  $index = @{}
  foreach ($root in $Roots) {
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($root)) {
      Assert-MIRStorageScanBudget -State $ScanState -CountEntry
      $item = Get-Item -LiteralPath $path -Force
      if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Extension -cne '.zip') { continue }
      $key = $item.Name.ToLowerInvariant() + '|' + $item.Length
      if (-not $index.ContainsKey($key)) { $index[$key] = [Collections.Generic.List[object]]::new() }
      [void]$index[$key].Add($item)
    }
  }
  return $index
}

function Get-MIRStorageDefaultLibraryRoots {
  param([Parameter(Mandatory)][string]$RepositoryRoot)
  $primaryRoot = $RepositoryRoot
  try {
    $commonDirectory = [string](& git -C $RepositoryRoot rev-parse --path-format=absolute --git-common-dir 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($commonDirectory)) {
      $commonDirectory = [IO.Path]::GetFullPath($commonDirectory.Trim())
      if ((Split-Path -Leaf $commonDirectory) -ceq '.git') {
        $primaryRoot = Split-Path -Parent $commonDirectory
      }
    }
  } catch {
    # A copied repository without Git metadata retains the direct-parent fallback.
  }
  $factorioRoot = Split-Path -Parent $primaryRoot
  return @((Join-Path $factorioRoot 'testmods/2.0'), (Join-Path $factorioRoot 'testmods/2.1'))
}

$buildRoot = Join-Path $RepoRoot 'build/tests'
if (-not (Test-Path -LiteralPath $buildRoot -PathType Container)) {
  if ($PassThru) { return @() }
  Write-Host '[storage] build/tests is absent; nothing to optimize.'
  return
}
$buildRoot = Assert-MIRStoragePlainDirectory -Path $buildRoot -Name 'MIR test artifact root'

if ($LibraryRoot.Count -eq 0) {
  $LibraryRoot = @(Get-MIRStorageDefaultLibraryRoots -RepositoryRoot $RepoRoot)
}
$resolvedLibraries = [Collections.Generic.List[string]]::new()
foreach ($root in $LibraryRoot) {
  if ([string]::IsNullOrWhiteSpace($root)) { continue }
  $resolved = Assert-MIRStoragePlainDirectory -Path ([IO.Path]::GetFullPath($root)) -Name 'Immutable mod library'
  if (-not $resolvedLibraries.Contains($resolved)) { [void]$resolvedLibraries.Add($resolved) }
}
if ($resolvedLibraries.Count -eq 0) { throw 'At least one immutable mod library is required.' }

$cutoff = [DateTime]::UtcNow.AddDays(-$OlderThanDays)
$scanState = [pscustomobject]@{
  scanned_entries = [long]0
  max_scanned_entries = [long]$MaxScannedEntries
  max_scan_seconds = $MaxScanSeconds
  watch = [Diagnostics.Stopwatch]::StartNew()
}
$libraryIndex = Get-MIRStorageLibraryIndex -Roots $resolvedLibraries.ToArray() -ScanState $scanState
$libraryHashes = @{}
$plan = [Collections.Generic.List[object]]::new()
$pendingDirectories = [Collections.Generic.Stack[string]]::new()
$pendingDirectories.Push($buildRoot)
while ($pendingDirectories.Count -gt 0) {
  Assert-MIRStorageScanBudget -State $scanState
  $directory = $pendingDirectories.Pop()
  foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($directory)) {
    Assert-MIRStorageScanBudget -State $scanState -CountEntry
    $entry = Get-Item -LiteralPath $path -Force
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
    if ($entry.PSIsContainer) {
      if ($pendingDirectories.Count -ge $MaxPendingDirectories) { throw "Storage optimization exceeded its bounded $MaxPendingDirectories-directory pending scan; nothing was changed." }
      $pendingDirectories.Push($entry.FullName)
      continue
    }
    if ($entry.Extension -cne '.zip') { continue }
  $modsToken = [IO.Path]::DirectorySeparatorChar + 'mods' + [IO.Path]::DirectorySeparatorChar
  if ($path.IndexOf($modsToken, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
  $item = $entry
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or [string]$item.LinkType -ceq 'HardLink') { continue }

  $modsRoot = Split-Path -Parent $item.FullName
  $runRoot = Split-Path -Parent $modsRoot
  if (-not (Test-MIRStorageCompletedRun -RunRoot $runRoot -Cutoff $cutoff) -or
      -not (Test-MIRStoragePlainPathChain -Path $item.FullName -Root $buildRoot)) { continue }
  if (-not (Test-MIRStoragePathWithin -Path $item.FullName -Root $buildRoot)) { throw "Artifact escaped build/tests: $($item.FullName)" }

  $key = $item.Name.ToLowerInvariant() + '|' + $item.Length
  if (-not $libraryIndex.ContainsKey($key)) { continue }
  $artifactSha = Get-MIRImmutableInputSha256 -Path $item.FullName
  Assert-MIRStorageScanBudget -State $scanState
  $source = $null
  foreach ($candidate in @($libraryIndex[$key])) {
    if ([IO.Path]::GetPathRoot($candidate.FullName) -cne [IO.Path]::GetPathRoot($item.FullName)) { continue }
    if (-not $libraryHashes.ContainsKey($candidate.FullName)) {
      $libraryHashes[$candidate.FullName] = Get-MIRImmutableInputSha256 -Path $candidate.FullName
      Assert-MIRStorageScanBudget -State $scanState
    }
    if ([string]$libraryHashes[$candidate.FullName] -ceq $artifactSha) { $source = $candidate; break }
  }
  if ($null -eq $source) { continue }
  if ($plan.Count -ge $MaxFiles) { throw "Storage optimization exceeded its bounded $MaxFiles-file plan; nothing was changed." }
  [void]$plan.Add([pscustomobject][ordered]@{
    status = 'eligible'
    artifact = $item.FullName
    source = $source.FullName
    run = $runRoot
    bytes = [long]$item.Length
    sha256 = $artifactSha
  })
  }
}

if (-not $Apply) {
  if ($PassThru) { return @($plan) }
  $bytes = if ($plan.Count -eq 0) { [long]0 } else { [long](($plan | Measure-Object bytes -Sum).Sum) }
  Write-Host ('[storage] eligible={0} logical_size={1:N2} GiB apply=false' -f $plan.Count, ($bytes / 1GB))
  return
}

if ($null -ne $BeforeApplyTestHook) { & $BeforeApplyTestHook @($plan) }
if (Get-Process factorio -ErrorAction SilentlyContinue) { throw 'Factorio is running; storage optimization was not started.' }
$converted = [Collections.Generic.List[object]]::new()
foreach ($row in $plan) {
  if (Get-Process factorio -ErrorAction SilentlyContinue) { throw "Factorio started after $($converted.Count) conversions; no further artifact was changed." }
  $target = [IO.Path]::GetFullPath([string]$row.artifact)
  $source = [IO.Path]::GetFullPath([string]$row.source)
  $sourceLibraries = @($resolvedLibraries | Where-Object { Test-MIRStoragePathWithin -Path $source -Root $_ })
  if (-not (Test-MIRStoragePathWithin -Path $target -Root $buildRoot) -or $sourceLibraries.Count -ne 1) {
    throw "Storage optimization boundary changed: $target"
  }
  if (-not (Test-MIRStorageCompletedRun -RunRoot ([string]$row.run) -Cutoff $cutoff) -or
      -not (Test-MIRStoragePlainPathChain -Path $target -Root $buildRoot) -or
      -not (Test-MIRStoragePlainPathChain -Path $source -Root $sourceLibraries[0])) {
    throw "Storage optimization eligibility changed after planning: $target"
  }
  if (-not $PSCmdlet.ShouldProcess($target, "replace verified duplicate with hard link to $source")) { continue }

  $temporary = Join-Path (Split-Path -Parent $target) ('.mir-relink-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $rollback = Join-Path (Split-Path -Parent $target) ('.mir-relink-' + [guid]::NewGuid().ToString('N') + '.rollback')
  $sourceHandle = $null
  $targetHandle = $null
  $replacementInstalled = $false
  try {
    $sourceHandle = [IO.File]::Open($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $targetHandle = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
    $current = Get-Item -LiteralPath $target -Force
    if ([string]$current.LinkType -ceq 'HardLink') { continue }
    if ($current.Length -ne [long]$row.bytes -or
        (Get-MIRImmutableInputSha256 -Path $target) -cne [string]$row.sha256 -or
        (Get-MIRImmutableInputSha256 -Path $source) -cne [string]$row.sha256) {
      throw "Artifact identity changed after planning: $target"
    }
    New-Item -ItemType HardLink -Path $temporary -Target $source -ErrorAction Stop | Out-Null
    if ((Get-MIRImmutableInputFileIdentity -Path $temporary) -cne (Get-MIRImmutableInputFileIdentity -Path $source) -or
        (Get-MIRImmutableInputSha256 -Path $temporary) -cne [string]$row.sha256) {
      throw "Temporary hard-link verification failed: $target"
    }
    Move-Item -LiteralPath $target -Destination $rollback -ErrorAction Stop
    Move-Item -LiteralPath $temporary -Destination $target -ErrorAction Stop
    $replacementInstalled = $true
    if ($null -ne $AfterReplacementTestHook) { & $AfterReplacementTestHook $row }
    if ((Get-MIRImmutableInputFileIdentity -Path $target) -cne (Get-MIRImmutableInputFileIdentity -Path $source) -or
        (Get-MIRImmutableInputSha256 -Path $target) -cne [string]$row.sha256) {
      throw "Final hard-link verification failed: $target"
    }
    $targetHandle.Dispose()
    $targetHandle = $null
    Remove-Item -LiteralPath $rollback -Force -ErrorAction Stop
    [void]$converted.Add([pscustomobject][ordered]@{
      status = 'relinked'
      artifact = $target
      source = $source
      run = [string]$row.run
      bytes = [long]$row.bytes
      sha256 = [string]$row.sha256
    })
  } catch {
    if ($null -ne $targetHandle) { $targetHandle.Dispose(); $targetHandle = $null }
    if ($null -ne $sourceHandle) { $sourceHandle.Dispose(); $sourceHandle = $null }
    if (Test-Path -LiteralPath $rollback -PathType Leaf) {
      if ($replacementInstalled -and (Test-Path -LiteralPath $target -PathType Leaf)) { Remove-Item -LiteralPath $target -Force }
      if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { Move-Item -LiteralPath $rollback -Destination $target -ErrorAction Stop }
    }
    throw
  } finally {
    if ($null -ne $targetHandle) { $targetHandle.Dispose() }
    if ($null -ne $sourceHandle) { $sourceHandle.Dispose() }
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  }
}

if ($PassThru) { return @($converted) }
$convertedBytes = if ($converted.Count -eq 0) { [long]0 } else { [long](($converted | Measure-Object bytes -Sum).Sum) }
Write-Host ('[storage] relinked={0} logical_size={1:N2} GiB apply=true' -f $converted.Count, ($convertedBytes / 1GB))
