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

