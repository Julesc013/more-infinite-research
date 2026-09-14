[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RepoRoot = "",
  [ValidateRange(0, 3650)]
  [int]$OlderThanDays = 7,
  [ValidateRange(1, 100000)]
  [int]$MaxPlanEntries = 10000,
  [ValidateRange(16, 1048576)]
  [int]$MaxTrackedReferencePathCharacters = 16384,
  [ValidateSet('result', 'test', 'package')]
  [string[]]$ArtifactType = @('result', 'test', 'package'),
  [switch]$AllWorktrees,
  [switch]$Apply,
  [switch]$PassThru,
  [Parameter(DontShow)]
  [switch]$SkipActiveProcessCheck
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $PSScriptRoot '../../lib/validation/ImmutableInputStaging.ps1')

$comparison = [StringComparison]::OrdinalIgnoreCase
$now = [DateTime]::UtcNow
$cutoff = $now.AddDays(-$OlderThanDays)
$protectedNames = @('assurance', 'validation')
$directCustodyMarkers = @(
  'result.json', 'receipt.json', 'evidence.json', 'candidate.json', 'predecessor.json',
  'offline-inputs.json', 'package-custody.json', 'seal.json', 'source-proof.json'
)
$runBoundaryNames = @(
  'mir-immutable-input-lease.json', 'mir-immutable-input-lease.lock', 'config.ini', 'mod-list.json', 'server-settings.json',
  'result.json', 'receipt.json', 'userdata', 'mods'
)
$artifactRootDefinitions = @(@(
  [pscustomobject]@{ relative_path = 'build/results'; artifact_type = 'result'; direct_children_only = $true; excluded_child_names = @(); non_pinning_custody_markers = @(); check_tracked_reference = $false; canonical_guid_leaf_only = $false },
  [pscustomobject]@{ relative_path = 'build/tests'; artifact_type = 'test'; direct_children_only = $false; excluded_child_names = @(); non_pinning_custody_markers = @(); check_tracked_reference = $false; canonical_guid_leaf_only = $false },
  [pscustomobject]@{ relative_path = 'build/packages'; artifact_type = 'package'; direct_children_only = $true; excluded_child_names = @('development-contracts'); non_pinning_custody_markers = @(); check_tracked_reference = $false; canonical_guid_leaf_only = $false },
  # Development-contract package expansion is an implementation detail of one
  # deterministic test.  Its only disposable children are the 32-hex run
  # directories created by that test; report every other child, but never
  # promote it into the deletion set.
  [pscustomobject]@{ relative_path = 'build/packages/development-contracts'; artifact_type = 'package'; direct_children_only = $true; excluded_child_names = @(); non_pinning_custody_markers = @('receipt.json'); check_tracked_reference = $true; canonical_guid_leaf_only = $true }
) | Where-Object { $_.artifact_type -in $ArtifactType })

function Test-MIRArtifactPathWithin {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Root
  )

  $fullPath = [IO.Path]::GetFullPath($Path)
  $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
  return $fullPath.StartsWith($prefix, $comparison)
}

function Test-MIRArtifactPathWithinOrEqual {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Root
  )

  $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  return $fullPath.Equals($fullRoot, $comparison) -or (Test-MIRArtifactPathWithin -Path $fullPath -Root $fullRoot)
}

function Assert-MIRArtifactDirectory {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Context)

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "$Context is absent: $Path"
  }
  $item = Get-Item -LiteralPath $Path -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "$Context may not be a reparse point: $Path"
  }
  return $item
}

function Get-MIRArtifactWorktrees {
  param(
    [Parameter(Mandatory)][string]$CurrentRepoRoot,
    [switch]$IncludeAll
  )

  if (-not $IncludeAll) { return @($CurrentRepoRoot) }
  # The registered-worktree list and common Git directory are the authority.
  # Do not infer the primary checkout from the common-directory parent: a
  # repository initialized with --separate-git-dir deliberately has no such
  # relationship.  Every returned root must instead prove that it resolves to
  # this exact common Git directory.
  $commonGitDirectory = @(& git -C $CurrentRepoRoot rev-parse --path-format=absolute --git-common-dir)
  if ($LASTEXITCODE -ne 0 -or $commonGitDirectory.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$commonGitDirectory[0])) {
    throw 'Unable to resolve the common Git directory for registered-worktree cleanup.'
  }
  $commonGitDirectory = [IO.Path]::GetFullPath(([string]$commonGitDirectory[0]).Trim())
  $configuredPrimaryWorktree = @(& git -C $CurrentRepoRoot config --path --get core.worktree)
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
    throw 'Unable to resolve the configured primary worktree from Git metadata.'
  }
  if ($configuredPrimaryWorktree.Count -gt 1) {
    throw 'Git metadata supplied more than one configured primary worktree.'
  }
  $configuredPrimaryWorktree = if ($configuredPrimaryWorktree.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$configuredPrimaryWorktree[0])) {
    [IO.Path]::GetFullPath(([string]$configuredPrimaryWorktree[0]).Trim())
  } else { $null }
  $worktreeLines = @(& git -C $CurrentRepoRoot worktree list --porcelain)
  if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate registered Git worktrees.' }

  $worktrees = [Collections.Generic.List[string]]::new()
  foreach ($line in $worktreeLines) {
    if (-not $line.StartsWith('worktree ', [StringComparison]::Ordinal)) { continue }
    $candidate = [IO.Path]::GetFullPath($line.Substring(9))
    # `git init --separate-git-dir` represents the primary record by the
    # common Git directory. Its configured core.worktree is the registered
    # primary checkout; never substitute a directory parent as a guess.
    if ($candidate.Equals($commonGitDirectory, [StringComparison]::OrdinalIgnoreCase)) {
      if ($null -eq $configuredPrimaryWorktree -or -not (Test-Path -LiteralPath $configuredPrimaryWorktree -PathType Container)) {
        throw 'A separate-Git-directory primary worktree lacks a usable core.worktree metadata path.'
      }
      $candidate = $configuredPrimaryWorktree
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
    $candidateCommonDirectory = @(& git -C $candidate rev-parse --path-format=absolute --git-common-dir)
    if ($LASTEXITCODE -ne 0 -or $candidateCommonDirectory.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$candidateCommonDirectory[0])) {
      throw "Unable to resolve the common Git directory for registered worktree: $candidate"
    }
    $candidateCommonDirectory = [IO.Path]::GetFullPath(([string]$candidateCommonDirectory[0]).Trim())
    if (-not $candidateCommonDirectory.Equals($commonGitDirectory, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Registered worktree did not resolve to the current common Git directory: $candidate"
    }
    $worktrees.Add($candidate)
  }
  return @($worktrees | Sort-Object -Unique)
}

function Test-MIRArtifactCanonicalCandidate {
  param(
    [Parameter(Mandatory)]$Definition,
    [Parameter(Mandatory)][System.IO.FileSystemInfo]$Item
  )

  if (-not [bool]$Definition.canonical_guid_leaf_only) { return $true }
  return $Item.PSIsContainer -and $Item.Name -cmatch '^[0-9a-f]{32}$'
}

function Test-MIRArtifactIgnored {
  param(
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)][string]$RelativePath
  )

  & git -C $WorktreeRoot check-ignore -q -- $RelativePath 2>$null
  return ($LASTEXITCODE -eq 0)
}

function Format-MIRArtifactBytes {
  param([long]$Bytes)
  if ($Bytes -ge 1GB) { return ('{0:N2} GiB' -f ($Bytes / 1GB)) }
  if ($Bytes -ge 1MB) { return ('{0:N2} MiB' -f ($Bytes / 1MB)) }
  if ($Bytes -ge 1KB) { return ('{0:N2} KiB' -f ($Bytes / 1KB)) }
  return "$Bytes B"
}

function Get-MIRArtifactRoot {
  param(
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)]$Definition
  )

  $candidate = Join-Path $WorktreeRoot $Definition.relative_path
  if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { return $null }
  $item = Assert-MIRArtifactDirectory -Path $candidate -Context "Artifact root $($Definition.relative_path)"
  if (-not (Test-MIRArtifactPathWithin -Path $item.FullName -Root $WorktreeRoot)) {
    throw "Artifact root escaped its worktree: $($item.FullName)"
  }
  return $item.FullName
}

function Test-MIRArtifactRunBoundary {
  param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)

  if (-not $Item.PSIsContainer) { return $true }
  if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
  foreach ($name in $runBoundaryNames) {
    if (Test-Path -LiteralPath (Join-Path $Item.FullName $name)) { return $true }
  }
  return $false
}

function Get-MIRArtifactCandidates {
  param(
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)]$Definition,
    [Parameter(Mandatory)][string]$ArtifactRoot
  )

  $rootItem = Get-Item -LiteralPath $ArtifactRoot -Force
  if ($Definition.direct_children_only) {
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($rootItem.FullName)) {
      $item = Get-Item -LiteralPath $path -Force
      if ($item.Name -in @($Definition.excluded_child_names)) { continue }
      [pscustomobject]@{
        item = $item
        boundary = 'direct-child'
        canonical_candidate = (Test-MIRArtifactCanonicalCandidate -Definition $Definition -Item $item)
      }
    }
    return
  }

  $pendingDirectories = [Collections.Generic.Stack[System.IO.FileSystemInfo]]::new()
  foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($rootItem.FullName)) {
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $item.Name -in $protectedNames -or
        (Test-MIRArtifactRunBoundary -Item $item)) {
      [pscustomobject]@{ item = $item; boundary = 'run-or-file'; canonical_candidate = $true }
      continue
    }
    $pendingDirectories.Push($item)
  }
  while ($pendingDirectories.Count -gt 0) {
    $directoryItem = $pendingDirectories.Pop()
    $hasChild = $false
    try {
      foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($directoryItem.FullName)) {
        $hasChild = $true
        $item = Get-Item -LiteralPath $path -Force
        if (-not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $item.Name -in $protectedNames -or
            (Test-MIRArtifactRunBoundary -Item $item)) {
          [pscustomobject]@{ item = $item; boundary = 'run-or-file'; canonical_candidate = $true }
          continue
        }
        $pendingDirectories.Push($item)
      }
    } catch {
      [pscustomobject]@{ item = $directoryItem; boundary = 'unreadable-directory'; canonical_candidate = $true }
      continue
    }
    if (-not $hasChild) {
      [pscustomobject]@{ item = $directoryItem; boundary = 'empty-directory'; canonical_candidate = $true }
    }
  }
}

function Get-MIRArtifactItemFacts {
  param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)

  $facts = [ordered]@{
    logical_bytes = [long]0
    file_count = [long]0
    latest_write_utc = $Item.LastWriteTimeUtc
    has_reparse_point = $false
    scan_error = $null
  }
  $pendingItems = [Collections.Generic.Stack[System.IO.FileSystemInfo]]::new()
  $pendingItems.Push($Item)
  while ($pendingItems.Count -gt 0) {
    $current = $pendingItems.Pop()
    if ($Current.LastWriteTimeUtc -gt $facts.latest_write_utc) { $facts.latest_write_utc = $Current.LastWriteTimeUtc }
    if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      $facts.has_reparse_point = $true
      continue
    }
    if (-not $current.PSIsContainer) {
      $facts.logical_bytes = [long]$facts.logical_bytes + [long]$Current.Length
      $facts.file_count = [long]$facts.file_count + 1
      continue
    }
    try {
      foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($current.FullName)) {
        if ($null -ne $facts.scan_error) { break }
        $pendingItems.Push((Get-Item -LiteralPath $path -Force))
      }
    } catch {
      $facts.scan_error = $_.Exception.Message
    }
  }
  return [pscustomobject]$facts
}

function Get-MIRArtifactCustodyMarker {
  param(
    [Parameter(Mandatory)][System.IO.FileSystemInfo]$Item,
    [string[]]$IgnoreNames = @()
  )

  if (-not $Item.PSIsContainer) {
    if (($Item.Name -in $directCustodyMarkers -or $Item.Name -like '*pin*.json') -and $Item.Name -notin $IgnoreNames) { return $Item.Name }
    return $null
  }
  if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
  foreach ($name in $directCustodyMarkers) {
    if ($name -in $IgnoreNames) { continue }
    if (Test-Path -LiteralPath (Join-Path $Item.FullName $name) -PathType Leaf) { return $name }
  }
  try {
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($Item.FullName)) {
      $child = Get-Item -LiteralPath $path -Force
      if (-not $child.PSIsContainer -and $child.Name -like '*pin*.json') { return $child.Name }
    }
  } catch {
    return '__unsafe-inspection__'
  }
  return $null
}

function Get-MIRArtifactFirstGitGrepMatch {
  param(
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)][string]$Needle,
    [ValidateRange(256,1048576)][int]$MaxPathCharacters = 16384
  )

  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = 'git'
  $startInfo.ArgumentList.Add('-C')
  $startInfo.ArgumentList.Add($WorktreeRoot)
  $startInfo.ArgumentList.Add('grep')
  $startInfo.ArgumentList.Add('-l')
  $startInfo.ArgumentList.Add('-F')
  $startInfo.ArgumentList.Add('--')
  $startInfo.ArgumentList.Add($Needle)
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  # The bounded first-match reader must not retain a second arbitrary stream.
  # Git writes diagnostics to its inherited stream; nonzero status below is a
  # fail-closed inspection error.
  $startInfo.RedirectStandardError = $false
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $builder = [Text.StringBuilder]::new()
  $buffer = New-Object char[] 1024
  try {
    while (($read = $process.StandardOutput.Read($buffer, 0, $buffer.Length)) -gt 0) {
      for ($index = 0; $index -lt $read; $index++) {
        $character = $buffer[$index]
        if ($character -eq "`n") {
          $match = $builder.ToString().TrimEnd("`r")
          if ($match.Length -eq 0) { throw 'Git reference scan emitted an empty path.' }
          # A single matching tracked path is sufficient to pin an artifact.
          # Stop the process before it can fill memory with more matches.
          if (-not $process.HasExited) { $process.Kill($true) }
          $process.WaitForExit()
          return $match
        }
        [void]$builder.Append($character)
        if ($builder.Length -gt $MaxPathCharacters) {
          throw 'Git reference scan exceeded the bounded first-path length.'
        }
      }
    }
    $process.WaitForExit()
    if ($builder.Length -ne 0) { throw 'Git reference scan ended with an unterminated path.' }
    if ($process.ExitCode -eq 1) { return $null }
    if ($process.ExitCode -ne 0) { throw "Git reference scan failed with exit code $($process.ExitCode)." }
    throw 'Git reference scan succeeded without a path.'
  } catch {
    if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    throw
  } finally {
    $process.Dispose()
  }
}

function Get-MIRArtifactTrackedReference {
  param(
    [Parameter(Mandatory)][string[]]$ReferenceWorktreeRoots,
    [Parameter(Mandatory)][string]$RelativePath
  )

  foreach ($referenceWorktreeRoot in @($ReferenceWorktreeRoots | Sort-Object -Unique)) {
    foreach ($needle in @($RelativePath, (Split-Path -Leaf $RelativePath)) | Select-Object -Unique) {
      try { $match = Get-MIRArtifactFirstGitGrepMatch -WorktreeRoot $referenceWorktreeRoot -Needle $needle -MaxPathCharacters $MaxTrackedReferencePathCharacters }
      catch { return '__unsafe-reference-scan__' }
      if (-not [string]::IsNullOrWhiteSpace([string]$match)) {
        return ("{0}:{1}" -f (Split-Path -Leaf $referenceWorktreeRoot), [string]$match)
      }
    }
  }
  return $null
}

function Get-MIRArtifactRow {
  param(
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)]$Definition,
    [Parameter(Mandatory)][string]$ArtifactRoot,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)][string[]]$ReferenceWorktreeRoots
  )

  $item = $Candidate.item
  $relativePath = [IO.Path]::GetRelativePath($WorktreeRoot, $item.FullName).Replace('\', '/')
  $isProtected = $item.PSIsContainer -and $item.Name -in $protectedNames
  $lease = if ($item.PSIsContainer) { Get-MIRImmutableInputLeaseLiveness -RunRoot $item.FullName } else { $null }
  $trackedReference = if ([bool]$Definition.check_tracked_reference) { Get-MIRArtifactTrackedReference -ReferenceWorktreeRoots $ReferenceWorktreeRoots -RelativePath $relativePath } else { $null }
  $custodyMarker = if ($isProtected -or ($null -ne $lease -and ($lease.active -or $lease.ambiguous))) { $null } else { Get-MIRArtifactCustodyMarker -Item $item -IgnoreNames @($Definition.non_pinning_custody_markers) }
  $facts = $null
  $status = $null
  $reason = $null
  if (-not [bool]$Candidate.canonical_candidate) {
    $status = 'noncanonical-child'; $reason = 'only canonical 32-hex GUID leaf directories are eligible in this artifact root'
  } elseif ($isProtected) {
    $status = 'protected'; $reason = 'protected artifact root'
  } elseif ($trackedReference -ceq '__unsafe-reference-scan__') {
    $status = 'unsafe-inspection'; $reason = 'could not inspect tracked references'
  } elseif (-not [string]::IsNullOrWhiteSpace([string]$trackedReference)) {
    $status = 'pinned-reference'; $reason = "tracked reference: $trackedReference"
  } elseif ($null -ne $lease -and $lease.active) {
    $status = 'active-lease'; $reason = $lease.reason
  } elseif ($null -ne $lease -and $lease.ambiguous) {
    $status = 'ambiguous-lease'; $reason = $lease.reason
  } elseif ($null -ne $lease -and $lease.present -and $lease.state -in @('active', 'staging', 'receipt-captured', 'staging-failed', 'failed', 'missing-record')) {
    $status = 'interrupted-lease'; $reason = $lease.reason
  } elseif ($custodyMarker -ceq '__unsafe-inspection__') {
    $status = 'unsafe-inspection'; $reason = 'could not inspect direct custody markers'
  } elseif ($null -ne $custodyMarker) {
    $status = 'pinned-custody'; $reason = "direct custody marker: $custodyMarker"
  } else {
    $facts = Get-MIRArtifactItemFacts -Item $item
    if ($null -ne $facts.scan_error) {
      $status = 'unsafe-inspection'; $reason = $facts.scan_error
    } elseif ($facts.has_reparse_point) {
      $status = 'unsafe-reparse'; $reason = 'reparse point encountered during no-follow traversal'
    } elseif (-not (Test-MIRArtifactIgnored -WorktreeRoot $WorktreeRoot -RelativePath $relativePath)) {
      $status = 'not-ignored'; $reason = 'Git does not ignore this artifact'
    } elseif ($facts.latest_write_utc -gt $cutoff) {
      $status = 'recent'; $reason = 'newer than retention cutoff'
    } else {
      $status = 'eligible'; $reason = 'ignored, stale, unpinned, and no lease is live'
    }
  }
  if ($null -eq $facts) {
    $facts = [pscustomobject]@{ logical_bytes = [long]0; file_count = [long]0; latest_write_utc = $item.LastWriteTimeUtc; has_reparse_point = $false; scan_error = $null }
  }
  return [pscustomobject]@{
    worktree = Split-Path -Leaf $WorktreeRoot
    worktree_root = $WorktreeRoot
    item = $item.Name
    kind = if ($item.PSIsContainer) { 'directory' } else { 'file' }
    artifact_type = $Definition.artifact_type
    boundary = $Candidate.boundary
    status = $status
    reason = $reason
    age_days = [Math]::Round(($now - $facts.latest_write_utc).TotalDays, 1)
    logical_bytes = [long]$facts.logical_bytes
    logical_size = Format-MIRArtifactBytes -Bytes $facts.logical_bytes
    file_count = [long]$facts.file_count
    full_path = $item.FullName
    artifact_root = $ArtifactRoot
    artifact_root_relative_path = $Definition.relative_path
    relative_path = $relativePath
    audit_latest_write_utc = $facts.latest_write_utc
    audit_file_count = [long]$facts.file_count
    lease_state = if ($null -ne $lease) { $lease.state } else { $null }
  }
}

function Test-MIRArtifactStillCandidate {
  param(
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)]$Definition,
    [Parameter(Mandatory)][string]$ArtifactRoot,
    [Parameter(Mandatory)][string]$Path
  )

  foreach ($candidate in (Get-MIRArtifactCandidates -WorktreeRoot $WorktreeRoot -Definition $Definition -ArtifactRoot $ArtifactRoot)) {
    if ([bool]$candidate.canonical_candidate -and [IO.Path]::GetFullPath($candidate.item.FullName).Equals([IO.Path]::GetFullPath($Path), $comparison)) { return $true }
  }
  return $false
}

function Assert-MIRArtifactEligibleForDeletion {
  param(
    [Parameter(Mandatory)]$Row,
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)]$Definition,
    [Parameter(Mandatory)][string[]]$ReferenceWorktreeRoots
  )

  $artifactRoot = Get-MIRArtifactRoot -WorktreeRoot $WorktreeRoot -Definition $Definition
  if ($null -eq $artifactRoot -or -not $artifactRoot.Equals($Row.artifact_root, $comparison)) {
    throw "Artifact root changed after audit: $($Row.full_path)"
  }
  $fullPath = [IO.Path]::GetFullPath($Row.full_path)
  if (-not (Test-MIRArtifactPathWithin -Path $fullPath -Root $artifactRoot)) {
    throw "Cleanup target escaped its typed artifact root: $fullPath"
  }
  if (-not (Test-Path -LiteralPath $fullPath)) { return $false }
  if (-not (Test-MIRArtifactStillCandidate -WorktreeRoot $WorktreeRoot -Definition $Definition -ArtifactRoot $artifactRoot -Path $fullPath)) {
    throw "Cleanup target is no longer an exact typed-root candidate: $fullPath"
  }
  $item = Get-Item -LiteralPath $fullPath -Force
  $relativePath = [IO.Path]::GetRelativePath($WorktreeRoot, $fullPath).Replace('\', '/')
  if (-not (Test-MIRArtifactIgnored -WorktreeRoot $WorktreeRoot -RelativePath $relativePath)) {
    throw "Cleanup target is no longer ignored by Git: $fullPath"
  }
  if ($item.PSIsContainer -and $item.Name -in $protectedNames) {
    throw "Cleanup target is a protected artifact root: $fullPath"
  }
  if ($item.PSIsContainer) {
    $lease = Get-MIRImmutableInputLeaseLiveness -RunRoot $item.FullName
    if ($lease.active -or $lease.ambiguous -or ($lease.present -and $lease.state -in @('active', 'staging', 'receipt-captured', 'staging-failed', 'failed', 'missing-record'))) {
      throw "Cleanup target has a live, ambiguous, or interrupted lease: $fullPath"
    }
  }
  $relativePath = [IO.Path]::GetRelativePath($WorktreeRoot, $fullPath).Replace('\', '/')
  if ([bool]$Definition.check_tracked_reference) {
    $trackedReference = Get-MIRArtifactTrackedReference -ReferenceWorktreeRoots $ReferenceWorktreeRoots -RelativePath $relativePath
    if (-not [string]::IsNullOrWhiteSpace([string]$trackedReference)) {
      throw "Cleanup target acquired a tracked reference after audit: $fullPath"
    }
  }
  if ($null -ne (Get-MIRArtifactCustodyMarker -Item $item -IgnoreNames @($Definition.non_pinning_custody_markers))) {
    throw "Cleanup target acquired a direct custody marker after audit: $fullPath"
  }
  $facts = Get-MIRArtifactItemFacts -Item $item
  if ($null -ne $facts.scan_error -or $facts.has_reparse_point) {
    throw "Cleanup target is no longer safe for no-follow removal: $fullPath"
  }
  if ($facts.latest_write_utc -gt $cutoff) {
    throw "Cleanup target changed after the audit and is now too recent: $fullPath"
  }
  if ($facts.latest_write_utc -gt $Row.audit_latest_write_utc -or
      $facts.logical_bytes -ne $Row.logical_bytes -or
      $facts.file_count -ne $Row.audit_file_count) {
    throw "Cleanup target received a write after the audit: $fullPath"
  }
  return $true
}

function Get-MIRArtifactDriveFreeBytes {
  param([Parameter(Mandatory)][string]$Path)
  $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
  return [IO.DriveInfo]::new($root).AvailableFreeSpace
}

$results = [Collections.Generic.List[object]]::new()
$definitionsByRoot = @{}
$worktrees = @(Get-MIRArtifactWorktrees -CurrentRepoRoot $RepoRoot -IncludeAll:$AllWorktrees)
foreach ($worktree in $worktrees) {
  foreach ($definition in $artifactRootDefinitions) {
    $artifactRoot = Get-MIRArtifactRoot -WorktreeRoot $worktree -Definition $definition
    if ($null -eq $artifactRoot) { continue }
    $definitionsByRoot[("{0}|{1}" -f $worktree, $definition.relative_path)] = $definition
    foreach ($candidate in (Get-MIRArtifactCandidates -WorktreeRoot $worktree -Definition $definition -ArtifactRoot $artifactRoot)) {
      if ($results.Count -ge $MaxPlanEntries) {
        throw "Artifact cleanup plan exceeded its bounded $MaxPlanEntries-entry limit; no removal was attempted. Narrow the scope or raise -MaxPlanEntries after reviewing storage capacity."
      }
      $results.Add((Get-MIRArtifactRow -WorktreeRoot $worktree -Definition $definition -ArtifactRoot $artifactRoot -Candidate $candidate -ReferenceWorktreeRoots $worktrees))
    }
  }
}

$eligible = @($results | Where-Object { $_.status -eq 'eligible' })
if ($Apply -and $eligible.Count -gt 0 -and -not $SkipActiveProcessCheck) {
  $factorioProcesses = @(Get-Process -Name 'factorio' -ErrorAction SilentlyContinue)
  if ($factorioProcesses.Count -gt 0) {
    throw 'Refusing artifact cleanup while Factorio is running. Finish the active run before cleaning artifacts.'
  }
}

$physicalFreeBefore = if ($Apply) { Get-MIRArtifactDriveFreeBytes -Path $RepoRoot } else { $null }
if ($Apply) {
  $revalidatedWorktrees = @(Get-MIRArtifactWorktrees -CurrentRepoRoot $RepoRoot -IncludeAll:$AllWorktrees)
  if ((@($revalidatedWorktrees | Sort-Object) -join "`n") -cne (@($worktrees | Sort-Object) -join "`n")) {
    throw 'Registered worktree scope changed after the cleanup audit; refusing deletion.'
  }
  foreach ($row in $eligible) {
    $worktreeRoot = [string]$row.worktree_root
    if (-not ($worktreeRoot -in $worktrees)) { throw "Unable to resolve audited worktree for cleanup target: $($row.full_path)" }
    $definition = $definitionsByRoot[("{0}|{1}" -f $worktreeRoot, $row.artifact_root_relative_path)]
    if ($null -eq $definition) { throw "Unable to resolve typed artifact root for cleanup target: $($row.full_path)" }
    if (-not (Assert-MIRArtifactEligibleForDeletion -Row $row -WorktreeRoot $worktreeRoot -Definition $definition -ReferenceWorktreeRoots $worktrees)) {
      $row.status = 'already-absent'; $row.reason = 'removed by another process before re-audit'; continue
    }
    if ($PSCmdlet.ShouldProcess($row.full_path, 'permanently remove stale ignored artifact')) {
      Remove-Item -LiteralPath $row.full_path -Recurse -Force
      $row.status = 'deleted'
      $row.reason = 'deleted after second typed-root audit'
    }
  }
}
$physicalFreeAfter = if ($Apply) { Get-MIRArtifactDriveFreeBytes -Path $RepoRoot } else { $null }

if (-not $PassThru) {
  if ($results.Count -gt 0) {
    $results | Sort-Object worktree, artifact_type, full_path |
      Select-Object worktree, artifact_type, status, kind, age_days, logical_size, item, reason |
      Format-Table -AutoSize
  } else {
    Write-Host 'No typed artifact roots were found.'
  }
  $matched = @($results | Where-Object { $_.status -in @('eligible', 'deleted') })
  [long]$matchedBytes = if ($matched.Count -eq 0) { 0 } else { [long]($matched | Measure-Object -Property logical_bytes -Sum).Sum }
  $mode = if ($Apply) { 'apply' } else { 'dry-run' }
  Write-Host ('[storage] mode={0} retention_days={1} matched={2} logical_size={3}' -f $mode, $OlderThanDays, $matched.Count, (Format-MIRArtifactBytes -Bytes $matchedBytes))
  Write-Host '[storage] Logical size counts every hardlink path; physical disk reclaimed can be lower.'
  if ($Apply) {
    Write-Host ('[storage] physical_free_delta_bytes={0}' -f ([long]$physicalFreeAfter - [long]$physicalFreeBefore))
  } elseif ($eligible.Count -gt 0) {
    Write-Host '[storage] Nothing was deleted. Re-run with -Apply after reviewing the exact targets.'
  }
}

if ($PassThru) { return @($results) }
