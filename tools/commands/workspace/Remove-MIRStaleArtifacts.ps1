[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RepoRoot = "",
  [ValidateRange(0, 3650)]
  [int]$OlderThanDays = 7,
  [ValidateRange(1, 100000)]
  [int]$MaxPlanEntries = 10000,
  # A plan entry is not a useful memory bound when one candidate contains an
  # entire copied test checkout.  Keep both the individual no-follow walk and
  # the whole audit bounded so a stale local-delivery tree cannot turn a
  # preview into an unbounded metadata scan.
  [ValidateRange(1, 10000000)]
  [int]$MaxScannedEntriesPerCandidate = 250000,
  # A scan entry cap alone does not prevent a wide directory from retaining
  # that many child paths before any are processed.  Bound the pending path
  # stack independently and fail closed before adding another child path.
  [ValidateRange(1, 1000000)]
  [int]$MaxPendingDirectoriesPerCandidate = 8192,
  # Candidate discovery has a separate path stack from the per-candidate
  # facts scan.  Keep it bounded too: no cleanup may proceed after an
  # incomplete recursive discovery pass.
  [ValidateRange(1, 1000000)]
  [int]$MaxPendingCandidateDiscoveryDirectories = 8192,
  [ValidateRange(1, 10000000)]
  [int]$MaxCandidateDiscoveryEntries = 250000,
  [ValidateRange(1, 3600)]
  [int]$MaxAuditSeconds = 90,
  [ValidateRange(16, 1048576)]
  [int]$MaxTrackedReferencePathCharacters = 16384,
  [ValidateSet('result', 'test', 'package', 'campaign')]
  [string[]]$ArtifactType = @('result', 'test', 'package', 'campaign'),
  # Optional one-campaign scope for pruning superseded child runs without
  # treating the whole governed campaign as disposable. The path must name
  # exactly one direct child of build/mir4.
  [string]$CampaignRoot = '',
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

$campaignRelativeRoot = 'build/mir4'
$campaignNonPinningCustodyMarkers = @()
$trackedReferenceLeafFallback = $true
if (-not [string]::IsNullOrWhiteSpace($CampaignRoot)) {
  if ($ArtifactType.Count -ne 1 -or [string]$ArtifactType[0] -cne 'campaign') {
    throw '-CampaignRoot requires -ArtifactType campaign as the only selected artifact type.'
  }
  if ([IO.Path]::IsPathRooted($CampaignRoot)) {
    throw '-CampaignRoot must be repository-relative.'
  }
  $campaignRelativeRoot = $CampaignRoot.Replace('\', '/').Trim('/')
  if ($campaignRelativeRoot -notmatch '^build/mir4/[^/]+$') {
    throw '-CampaignRoot must name exactly one direct child of build/mir4.'
  }
  $campaignBase = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/mir4')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $campaignFull = [IO.Path]::GetFullPath((Join-Path $RepoRoot $campaignRelativeRoot))
  if (-not $campaignFull.StartsWith($campaignBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '-CampaignRoot escaped build/mir4.'
  }
  # A child run's result.json identifies the run but does not by itself make
  # every abandoned attempt permanent custody. Exact tracked references,
  # other custody markers, nested leases, age, ignored status and the full
  # second audit still protect governed or live runs.
  $campaignNonPinningCustodyMarkers = @('result.json')
  # The exact campaign-relative path is unambiguous. Generic child names such
  # as `candidate` or prefixes of a retained successor would otherwise make a
  # bounded batched grep both noisy and over-conservative.
  $trackedReferenceLeafFallback = $false
}

. (Join-Path $PSScriptRoot '../../lib/validation/ImmutableInputStaging.ps1')

$comparison = [StringComparison]::OrdinalIgnoreCase
$now = [DateTime]::UtcNow
$cutoff = $now.AddDays(-$OlderThanDays)
$auditStopwatch = [Diagnostics.Stopwatch]::StartNew()
$progressStopwatch = [Diagnostics.Stopwatch]::StartNew()
$progressIntervalSeconds = 5
$currentAuditWorktreeRoot = $null
$currentAuditArtifactRoot = $null
$currentAuditCandidateCount = 0
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
  [pscustomobject]@{ relative_path = 'build/results'; artifact_type = 'result'; direct_children_only = $true; excluded_child_names = @(); non_pinning_custody_markers = @(); check_tracked_reference = $false; canonical_guid_leaf_only = $false; canonical_guid_run_boundary = $false; scan_descendant_custody = $false },
  # Test runners use a canonical GUID leaf for their private run state.  It is
  # an ownership boundary, not an invitation to individually inspect every
  # file in a copied repo/source fixture.  The contents are still walked once
  # no-follow before that exact leaf can be selected for deletion.
  [pscustomobject]@{ relative_path = 'build/tests'; artifact_type = 'test'; direct_children_only = $false; excluded_child_names = @(); non_pinning_custody_markers = @(); check_tracked_reference = $false; canonical_guid_leaf_only = $false; canonical_guid_run_boundary = $true; scan_descendant_custody = $true },
  [pscustomobject]@{ relative_path = 'build/packages'; artifact_type = 'package'; direct_children_only = $true; excluded_child_names = @('development-contracts'); non_pinning_custody_markers = @(); check_tracked_reference = $false; canonical_guid_leaf_only = $false; canonical_guid_run_boundary = $false; scan_descendant_custody = $false },
  # Development-contract package expansion is an implementation detail of one
  # deterministic test.  Its only disposable children are the 32-hex run
  # directories created by that test; report every other child, but never
  # promote it into the deletion set.
  [pscustomobject]@{ relative_path = 'build/packages/development-contracts'; artifact_type = 'package'; direct_children_only = $true; excluded_child_names = @(); non_pinning_custody_markers = @('receipt.json'); check_tracked_reference = $true; canonical_guid_leaf_only = $true; canonical_guid_run_boundary = $false; scan_descendant_custody = $false },
  # Long campaign roots contain whole test runs, transient candidate copies,
  # and occasionally the only local result record.  They are a separate,
  # direct-child-only class: never infer that every build/ child is removable.
  # A campaign must be ignored, stale, unreferenced in every selected
  # worktree, free of direct or descendant custody, lease-free, and pass the
  # same no-follow re-audit before it can be selected.
  [pscustomobject]@{ relative_path = $campaignRelativeRoot; artifact_type = 'campaign'; direct_children_only = $true; excluded_child_names = @(); non_pinning_custody_markers = @($campaignNonPinningCustodyMarkers); check_tracked_reference = $true; canonical_guid_leaf_only = $false; canonical_guid_run_boundary = $false; scan_descendant_custody = $true }
) | Where-Object { $_.artifact_type -in $ArtifactType })

function Assert-MIRArtifactAuditBudget {
  if ($auditStopwatch.Elapsed.TotalSeconds -ge $MaxAuditSeconds) {
    throw "Artifact cleanup audit reached its bounded $MaxAuditSeconds-second limit; no removal was attempted. Narrow -ArtifactType or investigate the reported roots before retrying."
  }
}

function Write-MIRArtifactAuditProgress {
  if ($PassThru -or $progressStopwatch.Elapsed.TotalSeconds -lt $progressIntervalSeconds) { return }
  $worktree = if ([string]::IsNullOrWhiteSpace([string]$currentAuditWorktreeRoot)) { '-' } else { Split-Path -Leaf $currentAuditWorktreeRoot }
  $root = if ([string]::IsNullOrWhiteSpace([string]$currentAuditArtifactRoot)) { '-' } else { $currentAuditArtifactRoot }
  Write-Host ('[storage] scanning worktree={0} root={1} candidates={2} elapsed_seconds={3:N1}' -f $worktree, $root, $currentAuditCandidateCount, $auditStopwatch.Elapsed.TotalSeconds)
  $progressStopwatch.Restart()
}

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
  param(
    [Parameter(Mandatory)]$Definition,
    [Parameter(Mandatory)][System.IO.FileSystemInfo]$Item
  )

  if (-not $Item.PSIsContainer) { return $true }
  if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
  # GUID leaves are created by MIR test runners as a complete private run
  # directory.  Treating one as a boundary avoids converting every file in a
  # copied checkout into an independent cleanup candidate.  The complete leaf
  # still receives a no-follow facts walk and second pre-delete audit.
  if ([bool]$Definition.canonical_guid_run_boundary -and $Item.Name -cmatch '^[0-9a-f]{32}$') { return $true }
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
  $discoveryEntryCount = [long]0
  if ($Definition.direct_children_only) {
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($rootItem.FullName)) {
      Assert-MIRArtifactAuditBudget
      Write-MIRArtifactAuditProgress
      if ($discoveryEntryCount -ge $MaxCandidateDiscoveryEntries) {
        throw "Artifact candidate discovery reached its bounded $MaxCandidateDiscoveryEntries-entry limit before completing $($Definition.relative_path); no removal was attempted. Narrow the artifact type or raise -MaxCandidateDiscoveryEntries after reviewing the tree."
      }
      $discoveryEntryCount++
      $item = Get-Item -LiteralPath $path -Force
      if ($item.Name -in @($Definition.excluded_child_names)) { continue }
      # Explicit campaign scope owns immediate child run directories. Files at
      # the campaign root are campaign metadata/evidence, never run candidates.
      if ([string]$Definition.artifact_type -ceq 'campaign' -and -not $item.PSIsContainer) { continue }
      [pscustomobject]@{
        item = $item
        boundary = 'direct-child'
        canonical_candidate = (Test-MIRArtifactCanonicalCandidate -Definition $Definition -Item $item)
      }
    }
    return
  }

  # Keep directory paths only.  This remains bounded by the plan limit and
  # avoids retaining a FileSystemInfo object for every structural child while
  # discovering old layouts that do not yet contain a run marker.
  $pendingDirectories = [Collections.Generic.Stack[string]]::new()
  foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($rootItem.FullName)) {
    Assert-MIRArtifactAuditBudget
    Write-MIRArtifactAuditProgress
    if ($discoveryEntryCount -ge $MaxCandidateDiscoveryEntries) {
      throw "Artifact candidate discovery reached its bounded $MaxCandidateDiscoveryEntries-entry limit before completing $($Definition.relative_path); no removal was attempted. Narrow the artifact type or raise -MaxCandidateDiscoveryEntries after reviewing the tree."
    }
    $discoveryEntryCount++
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $item.Name -in $protectedNames -or
        (Test-MIRArtifactRunBoundary -Definition $Definition -Item $item)) {
      [pscustomobject]@{ item = $item; boundary = 'run-or-file'; canonical_candidate = $true }
      continue
    }
    if ($pendingDirectories.Count -ge $MaxPendingCandidateDiscoveryDirectories) {
      throw "Artifact candidate discovery reached its bounded $MaxPendingCandidateDiscoveryDirectories-directory pending limit before completing $($Definition.relative_path); no removal was attempted. Narrow the artifact type or raise -MaxPendingCandidateDiscoveryDirectories after reviewing the tree."
    }
    $pendingDirectories.Push($item.FullName)
  }
  while ($pendingDirectories.Count -gt 0) {
    Assert-MIRArtifactAuditBudget
    Write-MIRArtifactAuditProgress
    try {
      $directoryItem = Get-Item -LiteralPath $pendingDirectories.Pop() -Force
    } catch {
      continue
    }
    $hasChild = $false
    try {
      foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($directoryItem.FullName)) {
        Assert-MIRArtifactAuditBudget
        Write-MIRArtifactAuditProgress
        $hasChild = $true
        if ($discoveryEntryCount -ge $MaxCandidateDiscoveryEntries) {
          throw "Artifact candidate discovery reached its bounded $MaxCandidateDiscoveryEntries-entry limit before completing $($Definition.relative_path); no removal was attempted. Narrow the artifact type or raise -MaxCandidateDiscoveryEntries after reviewing the tree."
        }
        $discoveryEntryCount++
        $item = Get-Item -LiteralPath $path -Force
        if (-not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $item.Name -in $protectedNames -or
            (Test-MIRArtifactRunBoundary -Definition $Definition -Item $item)) {
          [pscustomobject]@{ item = $item; boundary = 'run-or-file'; canonical_candidate = $true }
          continue
        }
        if ($pendingDirectories.Count -ge $MaxPendingCandidateDiscoveryDirectories) {
          throw "Artifact candidate discovery reached its bounded $MaxPendingCandidateDiscoveryDirectories-directory pending limit before completing $($Definition.relative_path); no removal was attempted. Narrow the artifact type or raise -MaxPendingCandidateDiscoveryDirectories after reviewing the tree."
        }
        $pendingDirectories.Push($item.FullName)
      }
    } catch {
      if ($_.Exception.Message -like 'Artifact candidate discovery reached its bounded *') { throw }
      [pscustomobject]@{ item = $directoryItem; boundary = 'unreadable-directory'; canonical_candidate = $true }
      continue
    }
    if (-not $hasChild) {
      [pscustomobject]@{ item = $directoryItem; boundary = 'empty-directory'; canonical_candidate = $true }
    }
  }
}

function Get-MIRArtifactItemFacts {
  param(
    [Parameter(Mandatory)][System.IO.FileSystemInfo]$Item,
    [switch]$InspectDescendantCustody,
    [switch]$InspectDescendantLeases,
    [string[]]$IgnoreCustodyMarkerNames = @()
  )

  $facts = [ordered]@{
    logical_bytes = [long]0
    file_count = [long]0
    latest_write_utc = $Item.LastWriteTimeUtc
    has_reparse_point = $false
    scan_error = $null
    scan_budget_exceeded = $false
    scan_stack_budget_exceeded = $false
    scan_budget_reason = $null
    scan_skipped = $false
    scan_entry_count = [long]0
    descendant_custody_marker = $null
    descendant_lease = $null
  }

  # Hold only a bounded number of directory paths, never a FileSystemInfo
  # object for every entry in a copied mod library.  Register every child
  # before it can enter the stack: a wide `mods` directory must fail closed
  # rather than accumulating unbounded paths before processing any member.
  $pendingDirectories = [Collections.Generic.Stack[string]]::new()
  if ($pendingDirectories.Count -ge $MaxPendingDirectoriesPerCandidate) {
    $facts.scan_budget_exceeded = $true
    $facts.scan_stack_budget_exceeded = $true
    $facts.scan_budget_reason = "no-follow scan reached its bounded $MaxPendingDirectoriesPerCandidate-directory pending limit"
    return [pscustomobject]$facts
  }
  $facts.scan_entry_count++
  $pendingDirectories.Push($Item.FullName)
  while ($pendingDirectories.Count -gt 0) {
    Assert-MIRArtifactAuditBudget
    Write-MIRArtifactAuditProgress
    $currentPath = $pendingDirectories.Pop()
    try {
      $current = Get-Item -LiteralPath $currentPath -Force
    } catch {
      $facts.scan_error = $_.Exception.Message
      break
    }
    if ($current.LastWriteTimeUtc -gt $facts.latest_write_utc) { $facts.latest_write_utc = $current.LastWriteTimeUtc }
    if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      $facts.has_reparse_point = $true
      continue
    }
    if (-not $current.PSIsContainer) {
      $facts.logical_bytes = [long]$facts.logical_bytes + [long]$current.Length
      $facts.file_count = [long]$facts.file_count + 1
      if ($InspectDescendantCustody -and $null -eq $facts.descendant_custody_marker -and
          ($current.Name -in $directCustodyMarkers -or $current.Name -like '*pin*.json') -and
          $current.Name -notin $IgnoreCustodyMarkerNames) {
        $facts.descendant_custody_marker = $current.Name
      }
      continue
    }
    try {
      foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($current.FullName)) {
        Assert-MIRArtifactAuditBudget
        Write-MIRArtifactAuditProgress
        if ($facts.scan_entry_count -ge $MaxScannedEntriesPerCandidate) {
          $facts.scan_budget_exceeded = $true
          $facts.scan_budget_reason = "no-follow scan exceeded the bounded $MaxScannedEntriesPerCandidate-entry per-candidate limit"
          break
        }
        $facts.scan_entry_count++
        try {
          $child = Get-Item -LiteralPath $path -Force
        } catch {
          $facts.scan_error = $_.Exception.Message
          break
        }
        if ($child.LastWriteTimeUtc -gt $facts.latest_write_utc) { $facts.latest_write_utc = $child.LastWriteTimeUtc }
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          $facts.has_reparse_point = $true
          continue
        }
        if ($child.PSIsContainer) {
          if ($pendingDirectories.Count -ge $MaxPendingDirectoriesPerCandidate) {
            $facts.scan_budget_exceeded = $true
            $facts.scan_stack_budget_exceeded = $true
            $facts.scan_budget_reason = "no-follow scan reached its bounded $MaxPendingDirectoriesPerCandidate-directory pending limit"
            break
          }
          $pendingDirectories.Push($child.FullName)
          continue
        }
        $facts.logical_bytes = [long]$facts.logical_bytes + [long]$child.Length
        $facts.file_count = [long]$facts.file_count + 1
        if ($InspectDescendantCustody -and $null -eq $facts.descendant_custody_marker -and
            ($child.Name -in $directCustodyMarkers -or $child.Name -like '*pin*.json') -and
            $child.Name -notin $IgnoreCustodyMarkerNames) {
          $facts.descendant_custody_marker = $child.Name
        }
        if ($InspectDescendantLeases -and $child.Name -in @('mir-immutable-input-lease.json', 'mir-immutable-input-lease.lock')) {
          Add-MIRArtifactDescendantLeaseFact -Facts $facts -LeasePath $child.FullName
        }
      }
    } catch {
      $facts.scan_error = $_.Exception.Message
    }
    if ($null -ne $facts.scan_error -or $facts.scan_budget_exceeded) { break }
  }
  return [pscustomobject]$facts
}

function Get-MIRArtifactLeaseProtectionStatus {
  param($Lease)

  if ($null -eq $Lease -or -not [bool]$Lease.present) { return $null }
  if ([bool]$Lease.active) { return 'active-lease' }
  if ([bool]$Lease.ambiguous) { return 'ambiguous-lease' }
  if ([string]$Lease.state -in @('active', 'staging', 'receipt-captured', 'staging-failed', 'failed', 'missing-record')) {
    return 'interrupted-lease'
  }
  return $null
}

function Add-MIRArtifactDescendantLeaseFact {
  param(
    [Parameter(Mandatory)][Collections.IDictionary]$Facts,
    [Parameter(Mandatory)][string]$LeasePath
  )

  # Keep the first cleanup-blocking result.  A valid, unlocked terminal lease
  # is intentionally not a custody pin, but any live, corrupt, ambiguous, or
  # interrupted nested lease prevents campaign removal.  Probe through the
  # shared liveness helper rather than inferring state from a filename.
  if ($null -ne $Facts['descendant_lease']) { return }
  try {
    $lease = Get-MIRImmutableInputLeaseLiveness -RunRoot (Split-Path -Parent $LeasePath)
  } catch {
    $lease = [pscustomobject]@{
      present = $true
      active = $false
      ambiguous = $true
      state = 'invalid'
      reason = "could not inspect nested immutable-input lease: $($_.Exception.Message)"
      record = $null
    }
  }
  $status = Get-MIRArtifactLeaseProtectionStatus -Lease $lease
  if ($null -eq $status) { return }
  $Facts['descendant_lease'] = [pscustomobject]@{
    path = $LeasePath
    status = $status
    state = [string]$lease.state
    reason = [string]$lease.reason
  }
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
    [ValidateRange(16,1048576)][int]$MaxPathCharacters = 16384
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
    [Parameter(Mandatory)][string]$RelativePath,
    [bool]$IncludeLeafFallback = $true,
    [hashtable]$ReferenceIndex = $null
  )

  if ($null -ne $ReferenceIndex) {
    if ($ReferenceIndex.ContainsKey('__unsafe-reference-scan__')) { return '__unsafe-reference-scan__' }
    if ($ReferenceIndex.ContainsKey($RelativePath)) { return [string]$ReferenceIndex[$RelativePath] }
    return $null
  }
  $needles = if ($IncludeLeafFallback) { @($RelativePath, (Split-Path -Leaf $RelativePath)) | Select-Object -Unique } else { @($RelativePath) }
  foreach ($referenceWorktreeRoot in @($ReferenceWorktreeRoots | Sort-Object -Unique)) {
    foreach ($needle in $needles) {
      try { $match = Get-MIRArtifactFirstGitGrepMatch -WorktreeRoot $referenceWorktreeRoot -Needle $needle -MaxPathCharacters $MaxTrackedReferencePathCharacters }
      catch { return '__unsafe-reference-scan__' }
      if (-not [string]::IsNullOrWhiteSpace([string]$match)) {
        return ("{0}:{1}" -f (Split-Path -Leaf $referenceWorktreeRoot), [string]$match)
      }
    }
  }
  return $null
}

function Get-MIRArtifactTrackedReferenceIndex {
  param(
    [Parameter(Mandatory)][string[]]$ReferenceWorktreeRoots,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RelativePaths,
    [bool]$IncludeLeafFallback = $true
  )

  $index = @{}
  $relativePaths = @($RelativePaths | Sort-Object -Unique)
  if ($relativePaths.Count -eq 0) { return $index }

  # The old per-candidate implementation started Git grep once for every
  # candidate/path/worktree pair.  Development-contract expansion alone can
  # therefore rescan a whole worktree hundreds of times.  Batch all exact
  # candidate paths and their unambiguous leaf fallbacks per selected
  # worktree, consume output one line at a time, and fail closed on an
  # unexpected/bounded result instead of retaining it in an unbounded array.
  $needleToRelativePaths = @{}
  foreach ($relativePath in $relativePaths) {
    $referenceNeedles = if ($IncludeLeafFallback) { @($relativePath, (Split-Path -Leaf $relativePath)) | Select-Object -Unique } else { @($relativePath) }
    foreach ($needle in $referenceNeedles) {
      if (-not $needleToRelativePaths.ContainsKey($needle)) {
        $needleToRelativePaths[$needle] = [Collections.Generic.List[string]]::new()
      }
      $needleToRelativePaths[$needle].Add($relativePath)
    }
  }
  $needles = @($needleToRelativePaths.Keys | Sort-Object)
  $batchSize = 128
  $matchedLineLimit = [Math]::Max($MaxPlanEntries, 1)
  $matchedLineCount = 0

  try {
    foreach ($referenceWorktreeRoot in @($ReferenceWorktreeRoots | Sort-Object -Unique)) {
      for ($offset = 0; $offset -lt $needles.Count; $offset += $batchSize) {
        Assert-MIRArtifactAuditBudget
        Write-MIRArtifactAuditProgress
        $batchEnd = [Math]::Min($offset + $batchSize - 1, $needles.Count - 1)
        $batch = @($needles[$offset..$batchEnd])
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'git'
        $startInfo.ArgumentList.Add('-C')
        $startInfo.ArgumentList.Add($referenceWorktreeRoot)
        $startInfo.ArgumentList.Add('grep')
        $startInfo.ArgumentList.Add('-n')
        $startInfo.ArgumentList.Add('-F')
        foreach ($needle in $batch) {
          $startInfo.ArgumentList.Add('-e')
          $startInfo.ArgumentList.Add($needle)
        }
        $startInfo.ArgumentList.Add('--')
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $false
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        try {
          while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
            Assert-MIRArtifactAuditBudget
            Write-MIRArtifactAuditProgress
            $matchedLineCount++
            if ($matchedLineCount -gt $matchedLineLimit) {
              throw "Git reference batch scan exceeded its bounded $matchedLineLimit-match limit."
            }
            $separator = $line.IndexOf(':')
            if ($separator -le 0) {
              throw 'Git reference batch scan returned a non-text or unparseable match.'
            }
            $trackedPath = $line.Substring(0, $separator)
            if ($trackedPath.Length -gt $MaxTrackedReferencePathCharacters) {
              throw 'Git reference batch scan exceeded the bounded tracked-path length.'
            }
            $payload = $line.Substring($separator + 1)
            foreach ($needle in $batch) {
              if ($payload.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) { continue }
              foreach ($relativePath in $needleToRelativePaths[$needle]) {
                if (-not $index.ContainsKey($relativePath)) {
                  $index[$relativePath] = ('{0}:{1}' -f (Split-Path -Leaf $referenceWorktreeRoot), $trackedPath)
                }
              }
            }
          }
          $process.WaitForExit()
          if ($process.ExitCode -notin @(0, 1)) {
            throw "Git reference batch scan failed with exit code $($process.ExitCode)."
          }
        } finally {
          if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
          $process.Dispose()
        }
      }
    }
  } catch {
    return @{ '__unsafe-reference-scan__' = $_.Exception.Message }
  }
  return $index
}

function Get-MIRArtifactRow {
  param(
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)]$Definition,
    [Parameter(Mandatory)][string]$ArtifactRoot,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)][string[]]$ReferenceWorktreeRoots,
    [hashtable]$ReferenceIndex = $null
  )

  $item = $Candidate.item
  $relativePath = [IO.Path]::GetRelativePath($WorktreeRoot, $item.FullName).Replace('\', '/')
  $isProtected = $item.PSIsContainer -and $item.Name -in $protectedNames
  $lease = if ($item.PSIsContainer) { Get-MIRImmutableInputLeaseLiveness -RunRoot $item.FullName } else { $null }
  $leaseStatus = Get-MIRArtifactLeaseProtectionStatus -Lease $lease
  $trackedReference = if ([bool]$Definition.check_tracked_reference) { Get-MIRArtifactTrackedReference -ReferenceWorktreeRoots $ReferenceWorktreeRoots -RelativePath $relativePath -ReferenceIndex $ReferenceIndex } else { $null }
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
  } elseif ($null -ne $leaseStatus) {
    $status = $leaseStatus; $reason = $lease.reason
  } elseif ($custodyMarker -ceq '__unsafe-inspection__') {
    $status = 'unsafe-inspection'; $reason = 'could not inspect direct custody markers'
  } elseif ($null -ne $custodyMarker) {
    $status = 'pinned-custody'; $reason = "direct custody marker: $custodyMarker"
  } elseif ((($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) -and -not (Test-MIRArtifactIgnored -WorktreeRoot $WorktreeRoot -RelativePath $relativePath)) {
    # Check ignore policy before considering the inexpensive timestamp
    # shortcut.  A tracked/current file remains an explicit non-candidate;
    # it must not be presented as merely recent.
    $status = 'not-ignored'; $reason = 'Git does not ignore this artifact'
  } elseif ((($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) -and $item.LastWriteTimeUtc -gt $cutoff) {
    # A candidate directory newer than the cutoff is conclusively ineligible
    # without walking every copied mod/repository member.  No deletion can
    # reach this branch: the full no-follow scan remains mandatory whenever a
    # stale candidate could become eligible, and again immediately before
    # deletion.
    $status = 'recent'; $reason = 'candidate root is newer than retention cutoff'
  } else {
    $facts = Get-MIRArtifactItemFacts -Item $item -InspectDescendantCustody:([bool]$Definition.scan_descendant_custody) -InspectDescendantLeases:([string]$Definition.artifact_type -ceq 'campaign') -IgnoreCustodyMarkerNames @($Definition.non_pinning_custody_markers)
    if ($null -ne $facts.scan_error) {
      $status = 'unsafe-inspection'; $reason = $facts.scan_error
    } elseif ($facts.has_reparse_point) {
      $status = 'unsafe-reparse'; $reason = 'reparse point encountered during no-follow traversal'
    } elseif ($null -ne $facts.descendant_lease) {
      $status = $facts.descendant_lease.status; $reason = "nested immutable-input lease ($($facts.descendant_lease.state)): $($facts.descendant_lease.reason)"
    } elseif ($facts.scan_budget_exceeded) {
      $status = 'scan-budget-exceeded'; $reason = $facts.scan_budget_reason
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$facts.descendant_custody_marker)) {
      $status = 'pinned-custody'; $reason = "descendant custody marker: $($facts.descendant_custody_marker)"
    } elseif ($facts.latest_write_utc -gt $cutoff) {
      $status = 'recent'; $reason = 'newer than retention cutoff'
    } else {
      $status = 'eligible'; $reason = 'ignored, stale, unpinned, and no lease is live'
    }
  }
  if ($null -eq $facts) {
    $facts = [pscustomobject]@{ logical_bytes = [long]0; file_count = [long]0; latest_write_utc = $item.LastWriteTimeUtc; has_reparse_point = $false; scan_error = $null; scan_budget_exceeded = $false; scan_stack_budget_exceeded = $false; scan_budget_reason = $null; scan_skipped = $true; scan_entry_count = [long]0; descendant_custody_marker = $null; descendant_lease = $null }
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
    logical_size = if ([bool]$facts.scan_skipped) { 'not-scanned' } else { Format-MIRArtifactBytes -Bytes $facts.logical_bytes }
    file_count = [long]$facts.file_count
    full_path = $item.FullName
    artifact_root = $ArtifactRoot
    artifact_root_relative_path = $Definition.relative_path
    relative_path = $relativePath
    audit_latest_write_utc = $facts.latest_write_utc
    audit_file_count = [long]$facts.file_count
    audit_scan_entry_count = [long]$facts.scan_entry_count
    audit_scan_complete = (-not $facts.scan_skipped -and -not $facts.scan_budget_exceeded -and $null -eq $facts.scan_error)
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
    if ($null -ne (Get-MIRArtifactLeaseProtectionStatus -Lease $lease)) {
      throw "Cleanup target has a live, ambiguous, or interrupted lease: $fullPath"
    }
  }
  $relativePath = [IO.Path]::GetRelativePath($WorktreeRoot, $fullPath).Replace('\', '/')
  if ([bool]$Definition.check_tracked_reference) {
    $trackedReference = Get-MIRArtifactTrackedReference -ReferenceWorktreeRoots $ReferenceWorktreeRoots -RelativePath $relativePath -IncludeLeafFallback:$trackedReferenceLeafFallback
    if (-not [string]::IsNullOrWhiteSpace([string]$trackedReference)) {
      throw "Cleanup target acquired a tracked reference after audit: $fullPath"
    }
  }
  if ($null -ne (Get-MIRArtifactCustodyMarker -Item $item -IgnoreNames @($Definition.non_pinning_custody_markers))) {
    throw "Cleanup target acquired a direct custody marker after audit: $fullPath"
  }
  $facts = Get-MIRArtifactItemFacts -Item $item -InspectDescendantCustody:([bool]$Definition.scan_descendant_custody) -InspectDescendantLeases:($Definition.artifact_type -ceq 'campaign') -IgnoreCustodyMarkerNames @($Definition.non_pinning_custody_markers)
  if ($null -ne $facts.scan_error -or $facts.has_reparse_point -or $facts.scan_budget_exceeded) {
    throw "Cleanup target is no longer safe for no-follow removal: $fullPath"
  }
  if (-not [string]::IsNullOrWhiteSpace([string]$facts.descendant_custody_marker)) {
    throw "Cleanup target acquired a descendant custody marker after audit: $fullPath"
  }
  if ($null -ne $facts.descendant_lease) {
    throw "Cleanup target has a live, ambiguous, or interrupted descendant lease: $fullPath"
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
$candidatePlans = [Collections.Generic.List[object]]::new()
$definitionsByRoot = @{}
$worktrees = @(Get-MIRArtifactWorktrees -CurrentRepoRoot $RepoRoot -IncludeAll:$AllWorktrees)
if (-not $PassThru) {
  Write-Host ('[storage] audit started worktrees={0} retention_days={1} max_audit_seconds={2} max_scanned_entries_per_candidate={3}' -f $worktrees.Count, $OlderThanDays, $MaxAuditSeconds, $MaxScannedEntriesPerCandidate)
}
foreach ($worktree in $worktrees) {
  foreach ($definition in $artifactRootDefinitions) {
    Assert-MIRArtifactAuditBudget
    $currentAuditWorktreeRoot = $worktree
    $currentAuditArtifactRoot = $definition.relative_path
    $currentAuditCandidateCount = $results.Count
    Write-MIRArtifactAuditProgress
    $artifactRoot = Get-MIRArtifactRoot -WorktreeRoot $worktree -Definition $definition
    if ($null -eq $artifactRoot) { continue }
    $definitionsByRoot[("{0}|{1}" -f $worktree, $definition.relative_path)] = $definition
    foreach ($candidate in (Get-MIRArtifactCandidates -WorktreeRoot $worktree -Definition $definition -ArtifactRoot $artifactRoot)) {
      Assert-MIRArtifactAuditBudget
      $currentAuditCandidateCount = $candidatePlans.Count
      Write-MIRArtifactAuditProgress
      if ($candidatePlans.Count -ge $MaxPlanEntries) {
        throw "Artifact cleanup plan exceeded its bounded $MaxPlanEntries-entry limit; no removal was attempted. Narrow the scope or raise -MaxPlanEntries after reviewing storage capacity."
      }
      $candidatePlans.Add([pscustomobject]@{
        worktree_root = $worktree
        definition = $definition
        artifact_root = $artifactRoot
        candidate = $candidate
      })
    }
  }
}

$trackedReferenceRelativePaths = @(
  foreach ($plan in $candidatePlans) {
    if (-not [bool]$plan.definition.check_tracked_reference) { continue }
    [IO.Path]::GetRelativePath([string]$plan.worktree_root, [string]$plan.candidate.item.FullName).Replace('\', '/')
  }
)
$trackedReferenceIndex = Get-MIRArtifactTrackedReferenceIndex -ReferenceWorktreeRoots $worktrees -RelativePaths $trackedReferenceRelativePaths -IncludeLeafFallback:$trackedReferenceLeafFallback
foreach ($plan in $candidatePlans) {
  Assert-MIRArtifactAuditBudget
  $currentAuditWorktreeRoot = [string]$plan.worktree_root
  $currentAuditArtifactRoot = [string]$plan.definition.relative_path
  $currentAuditCandidateCount = $results.Count
  Write-MIRArtifactAuditProgress
  $results.Add((Get-MIRArtifactRow -WorktreeRoot $plan.worktree_root -Definition $plan.definition -ArtifactRoot $plan.artifact_root -Candidate $plan.candidate -ReferenceWorktreeRoots $worktrees -ReferenceIndex $trackedReferenceIndex))
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
  Write-Host ('[storage] mode={0} retention_days={1} matched={2} logical_size={3} elapsed_seconds={4:N1}' -f $mode, $OlderThanDays, $matched.Count, (Format-MIRArtifactBytes -Bytes $matchedBytes), $auditStopwatch.Elapsed.TotalSeconds)
  Write-Host '[storage] Logical size counts every hardlink path; physical disk reclaimed can be lower.'
  if ($Apply) {
    Write-Host ('[storage] physical_free_delta_bytes={0}' -f ([long]$physicalFreeAfter - [long]$physicalFreeBefore))
  } elseif ($eligible.Count -gt 0) {
    Write-Host '[storage] Nothing was deleted. Re-run with -Apply after reviewing the exact targets.'
  }
}

if ($PassThru) { return @($results) }
