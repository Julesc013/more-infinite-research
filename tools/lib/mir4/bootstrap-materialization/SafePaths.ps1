function Assert-MIR4DescendantPath {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Path
  )

  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  $pathFull = [IO.Path]::GetFullPath($Path)
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if (-not $pathFull.StartsWith($rootFull, $comparison)) {
    throw "Path escapes the intended MIR 4 output root: $pathFull"
  }
  return $pathFull
}

function Assert-MIR4NoReparseAncestors {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Path
  )

  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
  $pathFull = Assert-MIR4DescendantPath -Root $rootFull -Path $Path
  $cursor = $rootFull
  $relative = [IO.Path]::GetRelativePath($rootFull, $pathFull)
  foreach ($segment in @($relative -split '[\\/]')) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.') { continue }
    $cursor = Join-Path $cursor $segment
    if (Test-Path -LiteralPath $cursor) {
      $item = Get-Item -LiteralPath $cursor -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "MIR 4 output paths cannot traverse a reparse point: $cursor"
      }
    }
  }
  return $pathFull
}

function Resolve-MIR4ArtifactPath {
  param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$RelativePath
  )

  if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains('\') -or
      $RelativePath -match '(^|/)\.{1,2}(/|$)' -or $RelativePath.Contains('//') -or $RelativePath.Contains(':')) {
    throw "Unsafe MIR 4 artifact-relative path: $RelativePath"
  }
  $safePath = Assert-MIR4DescendantPath -Root $OutputRoot -Path (Join-Path $OutputRoot $RelativePath)
  $null = Assert-MIR4NoReparseAncestors -Root $OutputRoot -Path $safePath
  return $safePath
}

function Remove-MIR4BuildTree {
  param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$Path
  )

  $safePath = Assert-MIR4DescendantPath -Root $OutputRoot -Path $Path
  $null = Assert-MIR4NoReparseAncestors -Root $OutputRoot -Path $safePath
  if (Test-Path -LiteralPath $safePath) {
    Remove-Item -LiteralPath $safePath -Recurse -Force
  }
}

function Get-MIR4PortablePath {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Path
  )

  $safePath = Assert-MIR4DescendantPath -Root $Root -Path $Path
  return [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root), $safePath).Replace('\', '/')
}

function Assert-MIR4BootstrapCandidateArtifactLayout {
  param([Parameter(Mandatory)]$Manifest)

  $target = [string]$Manifest.target_key
  $version = [string]$Manifest.distribution_version
  if ($target -notmatch '^f(?:210|200|110|100)$' -or $version -notmatch '^4\.[0-9]+\.[0-9]{5}$') {
    throw "Invalid MIR 4 bootstrap manifest target or distribution version."
  }
  $archiveName = "more-infinite-research_$version.zip"
  $expectedDistribution = "distributions/$archiveName"
  $expectedPrimaryCapsule = "capsules/$target/A/source-capsule.zip"
  if ([string]$Manifest.local_distribution.path -cne $expectedDistribution -or
      [string]$Manifest.source_capsule.path -cne $expectedPrimaryCapsule) {
    throw "MIR 4 bootstrap manifest artifact paths do not match the governed target layout."
  }

  $rows = @($Manifest.reconstructions)
  if ($rows.Count -ne 3 -or (@($rows.id) -join '|') -cne 'A|B|C') {
    throw "MIR 4 bootstrap manifest requires exact ordered A/B/C construction rows."
  }
  foreach ($row in $rows) {
    $id = [string]$row.id
    $expectedCandidate = "candidates/$target/$id/$archiveName"
    $expectedCapsule = "capsules/$target/$id/source-capsule.zip"
    $expectedEnvelope = "capsules/$target/$id/source-capsule.json"
    $expectedRunner = "capsules/$target/$id/Invoke-MIR4BootstrapCapsule.ps1"
    $expectedReceipt = "receipts/$target/$id/reconstruction.json"
    if ([string]$row.path -cne $expectedCandidate -or
        [string]$row.source_capsule_path -cne $expectedCapsule -or
        [string]$row.source_capsule_envelope_path -cne $expectedEnvelope -or
        [string]$row.reconstruction_runner_path -cne $expectedRunner -or
        [string]$row.receipt_path -cne $expectedReceipt) {
      throw "MIR 4 bootstrap construction row $id aliases or escapes its governed artifact path."
    }
  }
}

function Assert-MIR4SourceTreeSafe {
  param([Parameter(Mandatory)][string]$SourceRoot)

  $root = (Resolve-Path -LiteralPath $SourceRoot).Path
  $caseKeys = @{}
  foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -Force)) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Source capsules cannot contain reparse points: $($item.FullName)"
    }
    if ($item.PSIsContainer) { continue }
    $file = $item
    $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
    Assert-MIR4PortableArchivePath -Path $relative
    $key = $relative.ToLowerInvariant()
    if ($caseKeys.ContainsKey($key) -and $caseKeys[$key] -cne $relative) {
      throw "Case-colliding package paths: $($caseKeys[$key]) and $relative"
    }
    $caseKeys[$key] = $relative
  }
}

function Assert-MIR4PortableArchivePath {
  param([Parameter(Mandatory)][string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
      $Path -notmatch '^[A-Za-z0-9._/-]+$' -or $Path.StartsWith('/') -or
      $Path.Contains('\') -or $Path.Contains(':') -or $Path.Contains('//') -or
      $Path -match '(^|/)\.{1,2}(/|$)') {
    throw "Unsafe or non-portable MIR 4 archive path: $Path"
  }
  foreach ($segment in @($Path -split '/')) {
    if ([string]::IsNullOrEmpty($segment) -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) {
      throw "MIR 4 archive paths cannot contain empty or trailing-dot/space segments: $Path"
    }
    if ($segment -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)') {
      throw "MIR 4 archive paths cannot contain a DOS device alias: $Path"
    }
  }
}

function Add-MIR4PortableArchivePath {
  param(
    [Parameter(Mandatory)][Collections.Generic.Dictionary[string, object]]$PathMap,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][bool]$IsDirectory
  )

  Assert-MIR4PortableArchivePath -Path $Path
  $key = $Path.ToLowerInvariant()
  if ($PathMap.ContainsKey($key)) { throw "Duplicate or ordinal-case-colliding MIR 4 archive paths: $($PathMap[$key].path) and $Path" }
  $segments = @($key -split '/')
  for ($index = 1; $index -lt $segments.Count; $index++) {
    $ancestorKey = @($segments[0..($index - 1)]) -join '/'
    if ($PathMap.ContainsKey($ancestorKey) -and -not [bool]$PathMap[$ancestorKey].is_directory) {
      throw "MIR 4 archive file/prefix collision: $($PathMap[$ancestorKey].path) and $Path"
    }
  }
  if (-not $IsDirectory) {
    foreach ($existingKey in $PathMap.Keys) {
      if ($existingKey.StartsWith("$key/", [StringComparison]::Ordinal)) {
        throw "MIR 4 archive file/prefix collision: $Path and $($PathMap[$existingKey].path)"
      }
    }
  }
  $PathMap.Add($key, [pscustomobject][ordered]@{ path = $Path; is_directory = $IsDirectory })
}

function Get-MIR4SourceFiles {
  param([Parameter(Mandatory)][string]$SourceRoot)

  Assert-MIR4SourceTreeSafe -SourceRoot $SourceRoot
  return @(Get-MIRPackageSourceFiles -RepoRoot $SourceRoot | Sort-Object -Unique)
}
