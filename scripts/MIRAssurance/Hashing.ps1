function Initialize-MIRAssuranceGitIdentityCache {
  if ($null -ne $script:MIRAssuranceGitIndexBlobs) { return }
  $script:MIRAssuranceGitIndexBlobs = @{}
  $script:MIRAssuranceDirtyPaths = @{}
  $script:MIRAssuranceBlobCache = @{}
  $script:MIRAssuranceTreeHashCache = @{}
  foreach ($line in @(& git -C $repo ls-files -s)) {
    if ($line -match '^\d+\s+([0-9a-fA-F]+)\s+0\t(.+)$') {
      $script:MIRAssuranceGitIndexBlobs[$Matches[2].Replace("\", "/")] = $Matches[1]
    }
  }
  foreach ($line in @(& git -C $repo status --porcelain --untracked-files=all)) {
    if ($line.Length -lt 4) { continue }
    $path = $line.Substring(3)
    if ($path -match " -> ") { $path = ($path -split " -> ")[-1] }
    $script:MIRAssuranceDirtyPaths[$path.Replace("\", "/")] = $true
  }
}

function Get-MIRAssuranceRepositoryBlobId {
  param([Parameter(Mandatory)][string]$Path)
  Initialize-MIRAssuranceGitIdentityCache
  $full = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Repository file not found: $Path" }
  $relative = Get-MIRAssuranceRepoRelativePath -Path $full
  $item = Get-Item -LiteralPath $full
  $cacheKey = "$relative|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
  if ($script:MIRAssuranceBlobCache.ContainsKey($cacheKey)) { return $script:MIRAssuranceBlobCache[$cacheKey] }
  if (-not $script:MIRAssuranceDirtyPaths.ContainsKey($relative) -and $script:MIRAssuranceGitIndexBlobs.ContainsKey($relative)) {
    $script:MIRAssuranceBlobCache[$cacheKey] = [string]$script:MIRAssuranceGitIndexBlobs[$relative]
    return $script:MIRAssuranceBlobCache[$cacheKey]
  }
  # Dirty and untracked files are evidence inputs in their exact worktree byte
  # form. Hash them in-process instead of spawning one git process per file.
  $script:MIRAssuranceBlobCache[$cacheKey] = "worktree-sha256:" + (Get-MIRAssuranceSha256 -Path $full)
  return $script:MIRAssuranceBlobCache[$cacheKey]
}

function Get-MIRAssuranceRepositoryFileHash {
  param([Parameter(Mandatory)][string]$Path)
  $full = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  $relative = Get-MIRAssuranceRepoRelativePath -Path $full
  return Get-MIRAssuranceTextHash -Text "$relative`t$(Get-MIRAssuranceRepositoryBlobId -Path $full)"
}

function Get-MIRAssuranceTreeHash {
  param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths)
  Initialize-MIRAssuranceGitIdentityCache
  $normalizedPaths = @($Paths | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
  $treeCacheKey = $normalizedPaths -join "`n"
  if ($script:MIRAssuranceTreeHashCache.ContainsKey($treeCacheKey)) { return $script:MIRAssuranceTreeHashCache[$treeCacheKey] }
  $rows = @()
  foreach ($path in $normalizedPaths) {
    $full = if ([IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $repo $path }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      $relative = Get-MIRAssuranceRepoRelativePath -Path $full
      $rows += "$relative`t$(Get-MIRAssuranceRepositoryBlobId -Path $full)"
    } else {
      $rows += "$(([string]$path).Replace('\','/'))`tMISSING"
    }
  }
  if ($rows.Count -eq 0) { $rows += "EMPTY" }
  $script:MIRAssuranceTreeHashCache[$treeCacheKey] = Get-MIRAssuranceTextHash -Text (($rows | Sort-Object) -join "`n")
  return $script:MIRAssuranceTreeHashCache[$treeCacheKey]
}

function Resolve-MIRAssuranceCommit {
  param([Parameter(Mandatory)][string]$Commit)

  $resolved = @(& git -C $repo rev-parse "$Commit^{commit}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $resolved.Count -ne 1 -or [string]$resolved[0] -notmatch '^[0-9a-fA-F]{40}$') {
    throw "Unable to resolve Git commit: $Commit"
  }
  return ([string]$resolved[0]).ToLowerInvariant()
}

function Get-MIRAssuranceCommitPackageBlobs {
  param([Parameter(Mandatory)][string]$Commit)

  $resolvedCommit = Resolve-MIRAssuranceCommit -Commit $Commit
  . (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
  $roots = @(Get-MIRPackageSourceRoots)
  $blobs = [ordered]@{}
  foreach ($line in @(& git -C $repo ls-tree -r $resolvedCommit -- @roots 2>$null)) {
    if ($line -notmatch '^\d+\s+blob\s+([0-9a-fA-F]+)\t(.+)$') { continue }
    $path = ([string]$Matches[2]).Replace("\", "/")
    $blobs[$path] = ([string]$Matches[1]).ToLowerInvariant()
  }
  if ($LASTEXITCODE -ne 0 -or $blobs.Count -eq 0) {
    throw "Unable to enumerate package files at commit $resolvedCommit."
  }
  return $blobs
}

function Get-MIRAssuranceCommitPackageSourceHash {
  param([Parameter(Mandatory)][string]$Commit)

  $resolvedCommit = Resolve-MIRAssuranceCommit -Commit $Commit
  $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-package-source-" + [guid]::NewGuid().ToString("N"))
  $sourceArchive = Join-Path $temporaryRoot "source.zip"
  $sourceRoot = Join-Path $temporaryRoot "source"
  try {
    New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
    . (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
    $roots = @(Get-MIRPackageSourceRoots)
    & git -C $repo archive --format=zip --output=$sourceArchive $resolvedCommit -- @roots 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract committed package inputs for $resolvedCommit." }
    Expand-Archive -LiteralPath $sourceArchive -DestinationPath $sourceRoot
    return Get-MIRPackageSourceFingerprint -RepoRoot $sourceRoot
  } finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
      Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
  }
}

function Get-MIRAssurancePackageAuthorityHash {
  param(
    [Parameter(Mandatory)][string]$PackageSourceCommit,
    [string]$ContentCommit = "",
    [Parameter(Mandatory)]$Material
  )

  $packageCommit = Resolve-MIRAssuranceCommit -Commit $PackageSourceCommit
  $contentCommit = Resolve-MIRAssuranceCommit -Commit $(if ($ContentCommit) { $ContentCommit } else { $packageCommit })
  if ([int]$Material.schema -ne 1) {
    throw "Unsupported package-source material descriptor."
  }
  $algorithm = [string]$Material.hash_algorithm
  if ($algorithm -eq "git-commit-normalized-package-v1") {
    if ([string]$Material.source_tree -notmatch '^[0-9a-f]{40}$' -or [int]$Material.file_count -le 0) {
      throw "Clean-commit package-source material descriptor is invalid."
    }
    $packageTree = @(& git -C $repo rev-parse "$packageCommit^{tree}" 2>$null)
    if ($LASTEXITCODE -ne 0 -or $packageTree.Count -ne 1 -or [string]$packageTree[0] -ne [string]$Material.source_tree) {
      throw "Clean-commit package-source material descriptor has the wrong source tree."
    }
    $packageBlobs = Get-MIRAssuranceCommitPackageBlobs -Commit $packageCommit
    $contentBlobs = Get-MIRAssuranceCommitPackageBlobs -Commit $contentCommit
    if ($packageBlobs.Count -ne [int]$Material.file_count -or $contentBlobs.Count -ne $packageBlobs.Count) {
      throw "Clean-commit package-source material file count changed."
    }
    foreach ($entry in $packageBlobs.GetEnumerator()) {
      if (-not $contentBlobs.Contains($entry.Key) -or [string]$contentBlobs[$entry.Key] -ne [string]$entry.Value) {
        throw "Package file '$($entry.Key)' changed after the clean package-source commit."
      }
    }
    return [pscustomobject]@{
      package_source_commit = $packageCommit
      content_commit = $contentCommit
      sha256 = Get-MIRAssuranceCommitPackageSourceHash -Commit $contentCommit
      file_count = $packageBlobs.Count
      source_delta_file_count = 0
    }
  }
  if ($algorithm -ne "git-index-with-captured-worktree-v1") {
    throw "Unsupported package-source material descriptor."
  }
  $parent = Resolve-MIRAssuranceCommit -Commit "$packageCommit^"
  if ((Resolve-MIRAssuranceCommit -Commit ([string]$Material.source_parent_commit)) -ne $parent) {
    throw "Package-source material descriptor has the wrong source parent."
  }
  . (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
  $roots = @(Get-MIRPackageSourceRoots)
  $changedPaths = @(& git -C $repo diff --name-only $parent $packageCommit -- @roots 2>$null | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
  if ($LASTEXITCODE -ne 0) { throw "Unable to inspect the package-source commit delta." }
  $changed = @{}
  foreach ($entry in @($Material.changed_files)) {
    $path = ([string]$entry.path).Replace("\", "/")
    if ([string]::IsNullOrWhiteSpace($path) -or $changed.ContainsKey($path)) {
      throw "Package-source material paths must be nonempty and unique."
    }
    if ([string]$entry.git_blob -notmatch '^[0-9a-f]{40}$' -or [string]$entry.captured_worktree_sha256 -notmatch '^[0-9A-F]{64}$') {
      throw "Package-source material identity is invalid for $path."
    }
    $changed[$path] = $entry
  }
  if (@(Compare-Object -ReferenceObject $changedPaths -DifferenceObject @($changed.Keys | Sort-Object)).Count -ne 0) {
    throw "Package-source material paths do not match the package-source commit delta."
  }
  $packageBlobs = Get-MIRAssuranceCommitPackageBlobs -Commit $packageCommit
  $contentBlobs = Get-MIRAssuranceCommitPackageBlobs -Commit $contentCommit
  if ($packageBlobs.Count -ne $contentBlobs.Count) {
    throw "Package file count changed after the package-source commit."
  }
  $rows = foreach ($entry in $packageBlobs.GetEnumerator()) {
    $path = [string]$entry.Key
    if (-not $contentBlobs.Contains($path) -or [string]$contentBlobs[$path] -ne [string]$entry.Value) {
      throw "Package file '$path' changed after the package-source commit."
    }
    $identity = if ($changed.ContainsKey($path)) {
      $captured = $changed[$path]
      if ([string]$captured.git_blob -ne [string]$entry.Value) {
        throw "Captured package-source blob does not match '$path'."
      }
      "worktree-sha256:" + [string]$captured.captured_worktree_sha256
    } else {
      [string]$entry.Value
    }
    "$path`t$identity"
  }
  return [pscustomobject]@{
    package_source_commit = $packageCommit
    content_commit = $contentCommit
    sha256 = Get-MIRAssuranceTextHash -Text (($rows | Sort-Object) -join "`n")
    file_count = $packageBlobs.Count
    source_delta_file_count = $changed.Count
  }
}

function Test-MIRAssurancePackageRootsEqual {
  param(
    [Parameter(Mandatory)][string]$ReferenceCommit,
    [Parameter(Mandatory)][string]$DifferenceCommit
  )

  $reference = Resolve-MIRAssuranceCommit -Commit $ReferenceCommit
  $difference = Resolve-MIRAssuranceCommit -Commit $DifferenceCommit
  . (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
  $roots = @(Get-MIRPackageSourceRoots)
  & git -C $repo diff --quiet $reference $difference -- @roots
  return $LASTEXITCODE -eq 0
}

