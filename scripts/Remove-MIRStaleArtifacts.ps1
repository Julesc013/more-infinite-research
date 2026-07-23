[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RepoRoot = "",
  [ValidateRange(0, 3650)]
  [int]$OlderThanDays = 7,
  [switch]$AllWorktrees,
  [switch]$Apply,
  [switch]$PassThru,
  [Parameter(DontShow)]
  [switch]$SkipActiveProcessCheck
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$protectedArtifactNames = @("assurance", "validation")
$comparison = [System.StringComparison]::OrdinalIgnoreCase
$now = [DateTime]::UtcNow
$cutoff = $now.AddDays(-$OlderThanDays)

function Test-MIRArtifactPathWithin {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Root
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
  return $fullPath.StartsWith($rootPrefix, $comparison)
}

function Get-MIRArtifactWorktrees {
  param(
    [Parameter(Mandatory)][string]$CurrentRepoRoot,
    [switch]$IncludeAll
  )

  if (-not $IncludeAll) { return @($CurrentRepoRoot) }

  $projectRoot = Split-Path -Parent $CurrentRepoRoot
  $worktreeLines = @(& git -C $CurrentRepoRoot worktree list --porcelain)
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate registered Git worktrees." }

  $worktrees = @()
  foreach ($line in $worktreeLines) {
    if (-not $line.StartsWith("worktree ", [System.StringComparison]::Ordinal)) { continue }
    $candidate = [System.IO.Path]::GetFullPath($line.Substring(9))
    if (-not (Test-MIRArtifactPathWithin -Path $candidate -Root $projectRoot)) {
      Write-Warning "Skipping registered worktree outside the current project directory: $candidate"
      continue
    }
    if (Test-Path -LiteralPath $candidate -PathType Container) { $worktrees += $candidate }
  }

  return @($worktrees | Sort-Object -Unique)
}

function Get-MIRArtifactItemFacts {
  param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)

  $entries = @($Item)
  if ($Item.PSIsContainer) {
    $entries += @(Get-ChildItem -LiteralPath $Item.FullName -Force -Recurse -ErrorAction Stop)
  }

  $reparsePoints = @($entries | Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 })
  [long]$logicalBytes = 0
  foreach ($file in @($entries | Where-Object { -not $_.PSIsContainer })) {
    $logicalBytes += [long]$file.Length
  }

  $latestWrite = @($entries | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
  return [pscustomobject]@{
    logical_bytes = $logicalBytes
    latest_write_utc = if ($latestWrite.Count -gt 0) { $latestWrite[0].LastWriteTimeUtc } else { $Item.LastWriteTimeUtc }
    has_reparse_point = ($reparsePoints.Count -gt 0)
  }
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
  if ($Bytes -ge 1GB) { return ("{0:N2} GiB" -f ($Bytes / 1GB)) }
  if ($Bytes -ge 1MB) { return ("{0:N2} MiB" -f ($Bytes / 1MB)) }
  if ($Bytes -ge 1KB) { return ("{0:N2} KiB" -f ($Bytes / 1KB)) }
  return "$Bytes B"
}

$worktrees = @(Get-MIRArtifactWorktrees -CurrentRepoRoot $RepoRoot -IncludeAll:$AllWorktrees)
$results = @()

foreach ($worktree in $worktrees) {
  $artifactRootCandidate = Join-Path $worktree "artifacts"
  if (-not (Test-Path -LiteralPath $artifactRootCandidate -PathType Container)) { continue }
  $artifactRoot = (Resolve-Path -LiteralPath $artifactRootCandidate).Path

  if (-not (Test-MIRArtifactPathWithin -Path $artifactRoot -Root $worktree)) {
    throw "Artifact root escaped its worktree: $artifactRoot"
  }

  foreach ($item in @(Get-ChildItem -LiteralPath $artifactRoot -Force | Sort-Object Name)) {
    $facts = Get-MIRArtifactItemFacts -Item $item
    $relativePath = [System.IO.Path]::GetRelativePath($worktree, $item.FullName).Replace("\", "/")
    $isProtected = $item.PSIsContainer -and $item.Name -in $protectedArtifactNames
    $isIgnored = Test-MIRArtifactIgnored -WorktreeRoot $worktree -RelativePath $relativePath
    $status = if ($isProtected) {
      "protected"
    } elseif ($facts.has_reparse_point) {
      "unsafe-reparse"
    } elseif (-not $isIgnored) {
      "not-ignored"
    } elseif ($facts.latest_write_utc -gt $cutoff) {
      "recent"
    } else {
      "eligible"
    }

    $results += [pscustomobject]@{
      worktree = Split-Path -Leaf $worktree
      item = $item.Name
      kind = if ($item.PSIsContainer) { "directory" } else { "file" }
      status = $status
      age_days = [Math]::Round(($now - $facts.latest_write_utc).TotalDays, 1)
      logical_bytes = [long]$facts.logical_bytes
      logical_size = Format-MIRArtifactBytes -Bytes $facts.logical_bytes
      full_path = $item.FullName
      artifact_root = $artifactRoot
      relative_path = $relativePath
    }
  }
}

$eligible = @($results | Where-Object { $_.status -eq "eligible" })

if ($Apply -and $eligible.Count -gt 0 -and -not $SkipActiveProcessCheck) {
  $factorioProcesses = @(Get-Process -Name "factorio" -ErrorAction SilentlyContinue)
  if ($factorioProcesses.Count -gt 0) {
    throw "Refusing artifact cleanup while Factorio is running. Finish the active run before cleaning artifacts."
  }
}

if ($Apply) {
  foreach ($row in $eligible) {
    $fullPath = [System.IO.Path]::GetFullPath($row.full_path)
    $artifactRoot = [System.IO.Path]::GetFullPath($row.artifact_root)
    $parentPath = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not $parentPath.Equals($artifactRoot, $comparison)) {
      throw "Cleanup target is not an immediate artifact-root child: $fullPath"
    }
    if (-not (Test-MIRArtifactPathWithin -Path $fullPath -Root $artifactRoot)) {
      throw "Cleanup target escaped its artifact root: $fullPath"
    }
    if (-not (Test-Path -LiteralPath $fullPath)) { continue }
    if (-not (Test-MIRArtifactIgnored -WorktreeRoot (Split-Path -Parent $artifactRoot) -RelativePath $row.relative_path)) {
      throw "Cleanup target is not ignored by Git: $fullPath"
    }

    $currentItem = Get-Item -LiteralPath $fullPath -Force
    $currentFacts = Get-MIRArtifactItemFacts -Item $currentItem
    if ($currentFacts.has_reparse_point) { throw "Cleanup target contains a reparse point: $fullPath" }
    if ($currentFacts.latest_write_utc -gt $cutoff) { throw "Cleanup target changed after the audit and is now too recent: $fullPath" }

    if ($PSCmdlet.ShouldProcess($fullPath, "permanently remove stale ignored artifact")) {
      Remove-Item -LiteralPath $fullPath -Recurse -Force
      $row.status = "deleted"
    }
  }
}

if (-not $PassThru) {
  if ($results.Count -gt 0) {
    $results |
      Select-Object worktree, status, kind, age_days, logical_size, item |
      Format-Table -AutoSize
  } else {
    Write-Host "No artifact roots were found."
  }

  $matched = @($results | Where-Object { $_.status -in @("eligible", "deleted") })
  [long]$matchedBytes = ($matched | Measure-Object -Property logical_bytes -Sum).Sum
  $mode = if ($Apply) { "apply" } else { "dry-run" }
  Write-Host ("[storage] mode={0} retention_days={1} matched={2} logical_size={3}" -f $mode, $OlderThanDays, $matched.Count, (Format-MIRArtifactBytes -Bytes $matchedBytes))
  Write-Host "[storage] Logical size counts every hardlink path; physical disk reclaimed can be lower."
  if (-not $Apply -and $eligible.Count -gt 0) {
    Write-Host "[storage] Nothing was deleted. Re-run with -Apply after reviewing the exact targets."
  }
}

if ($PassThru) { return $results }
