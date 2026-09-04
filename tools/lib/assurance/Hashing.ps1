Set-Variable -Name MIRAssuranceCanonicalTextDigestPolicyId -Scope Script -Option ReadOnly -Value "utf8-nfc-lf-final-newline-v1" -ErrorAction SilentlyContinue
Set-Variable -Name MIRAssuranceCanonicalJsonDigestPolicyId -Scope Script -Option ReadOnly -Value "json-sorted-properties-utf8-nfc-lf-final-newline-v1" -ErrorAction SilentlyContinue

function Get-MIRAssuranceCanonicalTextDigest {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

  $normalized = $Text
  if ($normalized.StartsWith([char]0xFEFF)) { $normalized = $normalized.Substring(1) }
  $normalized = $normalized.Normalize([Text.NormalizationForm]::FormC)
  $normalized = $normalized.Replace("`r`n", "`n").Replace("`r", "`n")
  $normalized = $normalized.TrimEnd("`n") + "`n"
  return [ordered]@{
    policy_id=$script:MIRAssuranceCanonicalTextDigestPolicyId
    sha256=(Get-MIRAssuranceTextHash -Text $normalized)
    normalized_bytes=[Text.UTF8Encoding]::new($false).GetByteCount($normalized)
  }
}

function ConvertTo-MIRAssuranceCanonicalJsonValue {
  param($Value)

  if ($null -eq $Value) { return $null }
  if ($Value -is [Collections.IDictionary]) {
    $map = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
      $map[$key] = ConvertTo-MIRAssuranceCanonicalJsonValue -Value $Value[$key]
    }
    return $map
  }
  if ($Value -is [Management.Automation.PSCustomObject]) {
    $map = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
      $map[$property.Name] = ConvertTo-MIRAssuranceCanonicalJsonValue -Value $property.Value
    }
    return $map
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    return @($Value | ForEach-Object { ConvertTo-MIRAssuranceCanonicalJsonValue -Value $_ })
  }
  if ($Value -is [string]) { return $Value.Normalize([Text.NormalizationForm]::FormC) }
  return $Value
}

function Get-MIRAssuranceCanonicalJsonDigest {
  param([Parameter(Mandatory)]$Value)

  $canonical = ConvertTo-MIRAssuranceCanonicalJsonValue -Value $Value
  $json = $canonical | ConvertTo-Json -Depth 100 -Compress
  $textDigest = Get-MIRAssuranceCanonicalTextDigest -Text $json
  return [ordered]@{
    policy_id=$script:MIRAssuranceCanonicalJsonDigestPolicyId
    sha256=[string]$textDigest.sha256
    normalized_bytes=[int]$textDigest.normalized_bytes
  }
}

function Get-MIRAssuranceCanonicalTextFileHash {
  param([Parameter(Mandatory)][string]$Path)
  return [string](Get-MIRAssuranceCanonicalTextDigest -Text ([IO.File]::ReadAllText($Path))).sha256
}

function Get-MIRAssuranceCanonicalJsonFileHash {
  param([Parameter(Mandatory)][string]$Path)
  $value = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
  return [string](Get-MIRAssuranceCanonicalJsonDigest -Value $value).sha256
}

function Get-MIRAssuranceGitIndexFingerprint {
  param([Parameter(Mandatory)][string[]]$Pathspecs)

  $rows = @()
  foreach ($line in @(& git -C $repo ls-files -s -- @Pathspecs)) {
    if ($line -match '^\d+\s+([0-9a-fA-F]+)\s+0\t(.+)$') {
      $rows += "$($Matches[2].Replace('\','/'))`t$($Matches[1].ToLowerInvariant())"
    }
  }
  if ($LASTEXITCODE -ne 0) { throw "Unable to fingerprint the Git index paths: $($Pathspecs -join ', ')" }
  return [ordered]@{
    kind="git-index"
    file_count=$rows.Count
    sha256=(Get-MIRAssuranceTextHash -Text (($rows | Sort-Object) -join "`n"))
  }
}

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
  . (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1")
  $layout = Get-MIRPackageSourceLayoutAtCommit -RepoRoot $repo -Commit $resolvedCommit
  $roots = @($layout.roots)
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
    . (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1")
    $layout = Get-MIRPackageSourceLayoutAtCommit -RepoRoot $repo -Commit $resolvedCommit
    $roots = @($layout.roots)
    & git -C $repo archive --format=zip --output=$sourceArchive $resolvedCommit -- @roots 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract committed package inputs for $resolvedCommit." }
    Expand-Archive -LiteralPath $sourceArchive -DestinationPath $sourceRoot
    if ([string]$layout.kind -ceq 'canonical-materializer-source') {
      return Get-MIRPackageSourceFingerprint -RepoRoot $sourceRoot
    }
    return Get-MIRLegacyRootPackageSourceFingerprint -RepoRoot $sourceRoot
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
  . (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1")
  $roots = @((Get-MIRPackageSourceLayoutAtCommit -RepoRoot $repo -Commit $packageCommit).roots)
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
  . (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1")
  $referenceLayout = Get-MIRPackageSourceLayoutAtCommit -RepoRoot $repo -Commit $reference
  $differenceLayout = Get-MIRPackageSourceLayoutAtCommit -RepoRoot $repo -Commit $difference
  $roots = @(@($referenceLayout.roots) + @($differenceLayout.roots) | Sort-Object -Unique)
  & git -C $repo diff --quiet $reference $difference -- @roots
  return $LASTEXITCODE -eq 0
}
