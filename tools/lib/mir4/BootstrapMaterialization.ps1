if (-not (Get-Command Get-MIRPackageSourceRoots -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot "../validation/PackageIdentity.ps1")
}

function Get-MIR4Sha256Bytes {
  param([Parameter(Mandatory)][byte[]]$Bytes)

  $algorithm = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace("-", "")
  } finally {
    $algorithm.Dispose()
  }
}

function Get-MIR4Sha256String {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

  return Get-MIR4Sha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Value))
}

function Get-MIR4DomainSha256 {
  param(
    [Parameter(Mandatory)][string]$Domain,
    [Parameter(Mandatory)][Collections.IDictionary]$Fields
  )

  if ($Domain -notmatch '^mir4\.[a-z0-9.-]+\.v[0-9]+$') { throw "Invalid MIR 4 digest domain: $Domain" }
  $material = [pscustomobject][ordered]@{ domain = $Domain; fields = $Fields }
  return Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $material)
}

function Get-MIR4Sha256File {
  param([Parameter(Mandatory)][string]$Path)

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIR4BootstrapTextSha256 {
  param([Parameter(Mandatory)][string]$Path)

  $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
  $canonical = $text.Replace("`r`n", "`n").Replace("`r", "`n")
  return Get-MIR4Sha256String -Value $canonical
}

function ConvertTo-MIR4BootstrapCanonicalJson {
  param([Parameter(Mandatory)]$Value)

  # BootstrapCanonicalJsonV1 is intentionally narrow: tool-created ordered objects,
  # integer numbers, arrays in authority order, UTF-8, no BOM, no insignificant space.
  return (($Value | ConvertTo-Json -Depth 100 -Compress) -replace "`r`n", "`n" -replace "`r", "`n")
}

function Get-MIR4BootstrapRecordSha256 {
  param([Parameter(Mandatory)]$Record)

  $unsigned = [ordered]@{}
  foreach ($property in $Record.PSObject.Properties) {
    if ($property.Name -ne "record_sha256") {
      $unsigned[$property.Name] = $property.Value
    }
  }
  return Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value ([pscustomobject]$unsigned))
}

function Write-MIR4BootstrapRecord {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path
  )

  $hash = Get-MIR4BootstrapRecordSha256 -Record $Record
  if ($Record -is [Collections.IDictionary]) {
    $Record["record_sha256"] = $hash
  } else {
    $existing = $Record.PSObject.Properties["record_sha256"]
    if ($null -eq $existing) {
      $Record | Add-Member -NotePropertyName record_sha256 -NotePropertyValue $hash
    } else {
      $existing.Value = $hash
    }
  }

  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $json = ConvertTo-MIR4BootstrapCanonicalJson -Value $Record
  [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
  return $hash
}

function Test-MIR4BootstrapRecordHash {
  param([Parameter(Mandatory)]$Record)

  $expected = [string]$Record.record_sha256
  return $expected -match '^[A-F0-9]{64}$' -and $expected -eq (Get-MIR4BootstrapRecordSha256 -Record $Record)
}

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
    if ([string]$row.path -cne $expectedCandidate -or
        [string]$row.source_capsule_path -cne $expectedCapsule) {
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
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)' -or $relative.Contains(':')) {
      throw "Unsafe package-relative path: $relative"
    }
    $key = $relative.ToLowerInvariant()
    if ($caseKeys.ContainsKey($key) -and $caseKeys[$key] -cne $relative) {
      throw "Case-colliding package paths: $($caseKeys[$key]) and $relative"
    }
    $caseKeys[$key] = $relative
  }
}

function Get-MIR4SourceFiles {
  param([Parameter(Mandatory)][string]$SourceRoot)

  Assert-MIR4SourceTreeSafe -SourceRoot $SourceRoot
  return @(Get-MIRPackageSourceFiles -RepoRoot $SourceRoot | Sort-Object -Unique)
}

function Write-MIR4DeterministicArchive {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$EntryRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ContainmentRoot,
    [ValidateSet("Fastest", "NoCompression", "Optimal")]
    [string]$CompressionLevel = "Optimal"
  )

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $source = (Resolve-Path -LiteralPath $SourceRoot).Path
  $OutputPath = Assert-MIR4DescendantPath -Root $ContainmentRoot -Path $OutputPath
  $null = Assert-MIR4NoReparseAncestors -Root $ContainmentRoot -Path $OutputPath
  $files = @(Get-MIR4SourceFiles -SourceRoot $source)
  if ($files.Count -eq 0) { throw "The MIR 4 archive source is empty: $source" }
  if ($EntryRoot -notmatch '^[a-z0-9][a-z0-9._-]*$') { throw "Unsafe archive entry root: $EntryRoot" }

  $parent = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $temp = "$OutputPath.new"
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }

  $fileStream = [IO.File]::Open($temp, [IO.FileMode]::CreateNew)
  $archive = [IO.Compression.ZipArchive]::new($fileStream, [IO.Compression.ZipArchiveMode]::Create, $false)
  $fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
  $compression = [IO.Compression.CompressionLevel]::$CompressionLevel
  try {
    foreach ($relative in $files) {
      $entry = $archive.CreateEntry("$EntryRoot/$($relative.Replace('\', '/'))", $compression)
      $entry.LastWriteTime = $fixedTimestamp
      $entry.ExternalAttributes = 0
      $output = $entry.Open()
      try {
        $sourcePath = Join-Path $source $relative
        if (Test-MIRTextFingerprintPath -RelativePath $relative) {
          $text = [IO.File]::ReadAllText($sourcePath).Replace("`r`n", "`n").Replace("`r", "`n")
          $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
          $output.Write($bytes, 0, $bytes.Length)
        } else {
          $input = [IO.File]::OpenRead($sourcePath)
          try { $input.CopyTo($output) } finally { $input.Dispose() }
        }
      } finally {
        $output.Dispose()
      }
    }
  } finally {
    $archive.Dispose()
    $fileStream.Dispose()
  }

  if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
  Move-Item -LiteralPath $temp -Destination $OutputPath
}

function Get-MIR4ArchiveInventory {
  param([Parameter(Mandatory)][string]$Path)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $zip = [IO.Compression.ZipFile]::OpenRead($resolved)
  try {
    $allEntries = @($zip.Entries)
    if ($allEntries.Count -eq 0) { throw "MIR 4 archives cannot be empty: $Path" }
    $allNames = @{}
    $rootSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $allEntries) {
      $originalName = [string]$entry.FullName
      if ([string]::IsNullOrWhiteSpace($originalName) -or $originalName.Contains('\') -or
          $originalName.StartsWith('/') -or $originalName.Contains(':') -or
          $originalName -match '(^|/)(?:\.{1,2})(?:/|$)' -or $originalName.Contains('//')) {
        throw "Unsafe MIR 4 archive entry: $originalName"
      }
      $normalizedName = $originalName.TrimEnd('/')
      if ([string]::IsNullOrWhiteSpace($normalizedName)) { throw "Unsafe empty MIR 4 archive path." }
      $segments = @($normalizedName -split '/')
      $null = $rootSet.Add([string]$segments[0])
      $entryKey = $normalizedName.ToLowerInvariant()
      if ($allNames.ContainsKey($entryKey)) {
        throw "Duplicate or case-colliding MIR 4 archive entries: $($allNames[$entryKey]) and $originalName"
      }
      $allNames[$entryKey] = $originalName
      if (-not [string]::IsNullOrEmpty($entry.Name) -and $segments.Count -lt 2) {
        throw "MIR 4 archive files must live beneath one package root: $originalName"
      }
    }
    $roots = @($rootSet | Sort-Object -CaseSensitive)
    if ($roots.Count -ne 1 -or [string]::IsNullOrWhiteSpace($roots[0])) {
      throw "MIR 4 archives require exactly one package root: $Path"
    }
    if ($roots[0] -notmatch '^[a-z0-9][a-z0-9._-]*$') { throw "Unsafe MIR 4 archive root: $($roots[0])" }
    $files = @($allEntries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
    $seen = @{}
    $entries = @(
      foreach ($entry in @($files | Sort-Object FullName)) {
        $name = $entry.FullName.Replace('\', '/')
        if ($name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)' -or $name.Contains(':')) {
          throw "Unsafe MIR 4 archive entry: $name"
        }
        $relative = $name.Substring($roots[0].Length + 1)
        if ([string]::IsNullOrWhiteSpace($relative)) { throw "MIR 4 archive contains an empty file path under its root." }
        $key = $relative.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
          throw "Duplicate or case-colliding MIR 4 archive entries: $($seen[$key]) and $relative"
        }
        $seen[$key] = $relative
        $identity = Get-MIRZipEntryContentIdentity -Entry $entry -RelativePath $relative
        $rawStream = $entry.Open()
        $rawAlgorithm = [Security.Cryptography.SHA256]::Create()
        try {
          $rawSha256 = ([BitConverter]::ToString($rawAlgorithm.ComputeHash($rawStream))).Replace('-', '')
        } finally {
          $rawAlgorithm.Dispose()
          $rawStream.Dispose()
        }
        [pscustomobject][ordered]@{
          path = $relative
          bytes = [long]$identity.Length
          sha256 = [string]$identity.Sha256
          raw_sha256 = $rawSha256
        }
      }
    )
  } finally {
    $zip.Dispose()
  }

  $rows = @($entries | ForEach-Object { "$($_.path)`t$($_.bytes)`t$($_.sha256)" })
  return [pscustomobject][ordered]@{
    root = $roots[0]
    archive_sha256 = Get-MIR4Sha256File -Path $resolved
    content_sha256 = Get-MIRZipContentFingerprint -Path $resolved
    bytes = [long](Get-Item -LiteralPath $resolved).Length
    entry_count = $entries.Count
    entries = $entries
  }
}

function Read-MIR4ArchiveText {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RelativePath
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
  try {
    $entry = @($zip.Entries | Where-Object {
      -not [string]::IsNullOrEmpty($_.Name) -and
      $_.FullName.Replace('\', '/').EndsWith("/$RelativePath", [StringComparison]::Ordinal)
    })
    if ($entry.Count -ne 1) { throw "Expected one $RelativePath entry in $Path; found $($entry.Count)." }
    $stream = $entry[0].Open()
    $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false), $true)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose(); $stream.Dispose() }
  } finally {
    $zip.Dispose()
  }
}

function Read-MIR4ArchiveBytes {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RelativePath
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
  try {
    $entry = @($zip.Entries | Where-Object {
      -not [string]::IsNullOrEmpty($_.Name) -and
      $_.FullName.Replace('\', '/').EndsWith("/$RelativePath", [StringComparison]::Ordinal)
    })
    if ($entry.Count -ne 1) { throw "Expected one $RelativePath entry in $Path; found $($entry.Count)." }
    $stream = $entry[0].Open()
    $buffer = [IO.MemoryStream]::new()
    try {
      $stream.CopyTo($buffer)
      return ,([byte[]]$buffer.ToArray())
    } finally {
      $buffer.Dispose()
      $stream.Dispose()
    }
  } finally {
    $zip.Dispose()
  }
}

function ConvertTo-MIR4InfoVersionProjection {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][string]$Version
  )

  if ($Version -notmatch '^4\.[0-9]+\.[0-9]{5}$') { throw "Invalid MIR 4 distribution version: $Version" }
  $pattern = '(?m)("version"\s*:\s*")[^"]+("\s*[,}])'
  $matches = [Text.RegularExpressions.Regex]::Matches($Text, $pattern)
  if ($matches.Count -ne 1) { throw "Expected one info.json version property; found $($matches.Count)." }
  $updated = [Text.RegularExpressions.Regex]::Replace($Text, $pattern, "`${1}$Version`${2}")
  $null = $updated | ConvertFrom-Json
  return $updated
}

function Get-MIR4ComparableInfoJson {
  param([Parameter(Mandatory)][string]$Json)

  $value = $Json | ConvertFrom-Json
  if ($null -eq $value.PSObject.Properties['version']) { throw "info.json is missing version." }
  $value.PSObject.Properties.Remove('version')
  return ConvertTo-MIR4BootstrapCanonicalJson -Value $value
}

function Compare-MIR4BootstrapCandidate {
  param(
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$PredecessorPath,
    [Parameter(Mandatory)][string]$ExpectedCandidateRoot,
    [Parameter(Mandatory)][string]$ExpectedPredecessorRoot,
    [Parameter(Mandatory)][string]$ExpectedCandidateVersion,
    [Parameter(Mandatory)][string]$ExpectedPredecessorVersion,
    [switch]$ThrowOnDifference
  )

  $candidate = Get-MIR4ArchiveInventory -Path $CandidatePath
  $predecessor = Get-MIR4ArchiveInventory -Path $PredecessorPath
  $rootEquivalent =
    [string]$candidate.root -ceq $ExpectedCandidateRoot -and
    [string]$predecessor.root -ceq $ExpectedPredecessorRoot
  $candidateMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($entry in $candidate.entries) { $candidateMap.Add([string]$entry.path, $entry) }
  $predecessorMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($entry in $predecessor.entries) { $predecessorMap.Add([string]$entry.path, $entry) }
  $added = @($candidateMap.Keys | Where-Object { -not $predecessorMap.ContainsKey($_) } | Sort-Object)
  $removed = @($predecessorMap.Keys | Where-Object { -not $candidateMap.ContainsKey($_) } | Sort-Object)
  $changed = @($candidateMap.Keys | Where-Object {
    $predecessorMap.ContainsKey($_) -and $candidateMap[$_].raw_sha256 -cne $predecessorMap[$_].raw_sha256
  } | Sort-Object)

  $candidateInfoBytes = [byte[]](Read-MIR4ArchiveBytes -Path $CandidatePath -RelativePath 'info.json')
  $predecessorInfoBytes = [byte[]](Read-MIR4ArchiveBytes -Path $PredecessorPath -RelativePath 'info.json')
  $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
  try {
    $candidateInfoText = $strictUtf8.GetString($candidateInfoBytes)
    $predecessorInfoText = $strictUtf8.GetString($predecessorInfoBytes)
  } catch {
    throw "MIR 4 bootstrap info.json entries must be valid UTF-8: $($_.Exception.Message)"
  }
  $candidateInfo = $candidateInfoText | ConvertFrom-Json
  $predecessorInfo = $predecessorInfoText | ConvertFrom-Json
  $expectedCandidateInfoText = ConvertTo-MIR4InfoVersionProjection `
    -Text $predecessorInfoText `
    -Version $ExpectedCandidateVersion
  $expectedCandidateInfoBytes = [Text.UTF8Encoding]::new($false).GetBytes($expectedCandidateInfoText)
  $exactInfoProjection = [Linq.Enumerable]::SequenceEqual(
    [byte[]]$candidateInfoBytes,
    [byte[]]$expectedCandidateInfoBytes
  )
  $metadataEquivalent =
    $rootEquivalent -and
    [string]$candidateInfo.version -eq $ExpectedCandidateVersion -and
    [string]$predecessorInfo.version -eq $ExpectedPredecessorVersion -and
    $exactInfoProjection -and
    (Get-MIR4ComparableInfoJson -Json $candidateInfoText) -ceq (Get-MIR4ComparableInfoJson -Json $predecessorInfoText)

  $equivalent = $added.Count -eq 0 -and $removed.Count -eq 0 -and
    $changed.Count -eq 1 -and $changed[0] -ceq 'info.json' -and $metadataEquivalent
  $result = [pscustomobject][ordered]@{
    equivalent = $equivalent
    policy = 'MIR4BootstrapPackageEquivalenceV1'
    allowed_differences = @('generated-package-root', 'info.json#/version')
    added = $added
    removed = $removed
    changed = $changed
    metadata_equivalent = $metadataEquivalent
    candidate = [pscustomobject][ordered]@{
      archive_sha256 = $candidate.archive_sha256
      content_sha256 = $candidate.content_sha256
      bytes = $candidate.bytes
      entry_count = $candidate.entry_count
    }
    predecessor = [pscustomobject][ordered]@{
      archive_sha256 = $predecessor.archive_sha256
      content_sha256 = $predecessor.content_sha256
      bytes = $predecessor.bytes
      entry_count = $predecessor.entry_count
    }
  }
  if ($ThrowOnDifference -and -not $equivalent) {
    throw "Candidate differs outside the MIR4 bootstrap allowlist (added=$($added -join ','), removed=$($removed -join ','), changed=$($changed -join ','))."
  }
  return $result
}

function Expand-MIR4SafeArchive {
  param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$OutputRoot
  )

  $inventory = Get-MIR4ArchiveInventory -Path $ArchivePath
  $safeDestination = Assert-MIR4DescendantPath -Root $OutputRoot -Path $Destination
  if (Test-Path -LiteralPath $safeDestination) {
    Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path $safeDestination
  }
  New-Item -ItemType Directory -Force -Path $safeDestination | Out-Null
  $null = Assert-MIR4NoReparseAncestors -Root $OutputRoot -Path $safeDestination
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath).Path)
  try {
    foreach ($entry in @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object FullName)) {
      $name = $entry.FullName.Replace('\', '/')
      $relative = $name.Substring($inventory.root.Length + 1)
      if ([string]::IsNullOrWhiteSpace($relative)) { throw "MIR 4 extraction encountered an empty file path." }
      $destinationPath = Assert-MIR4DescendantPath -Root $safeDestination -Path (Join-Path $safeDestination $name)
      $parent = Split-Path -Parent $destinationPath
      if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
      $null = Assert-MIR4NoReparseAncestors -Root $safeDestination -Path $destinationPath
      $input = $entry.Open()
      $output = [IO.File]::Open($destinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
    }
  } finally {
    $zip.Dispose()
  }
}

function Set-MIR4InfoVersion {
  param(
    [Parameter(Mandatory)][string]$InfoPath,
    [Parameter(Mandatory)][string]$Version
  )

  $text = [IO.File]::ReadAllText($InfoPath)
  $updated = ConvertTo-MIR4InfoVersionProjection -Text $text -Version $Version
  [IO.File]::WriteAllText($InfoPath, $updated, [Text.UTF8Encoding]::new($false))
}

function Get-MIR4GitTree {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Commit
  )

  $tree = @(& git -C $RepoRoot rev-parse "$Commit^{tree}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $tree.Count -ne 1 -or [string]::IsNullOrWhiteSpace($tree[0])) {
    throw "Unable to resolve source tree for $Commit."
  }
  return ([string]$tree[0]).Trim()
}

function New-MIR4BootstrapSourceCapsule {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidatePattern('^[A-Z]$')]
    [string]$CapsuleId = 'A'
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $output = [IO.Path]::GetFullPath($OutputRoot)
  $output = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build/mir4') -Path $output
  $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $output
  if (-not (Test-Path -LiteralPath $output -PathType Container)) { New-Item -ItemType Directory -Force -Path $output | Out-Null }
  $targetRoot = Join-Path $output "capsules\$($Target.target_key)\$CapsuleId"
  $workRoot = Join-Path $targetRoot 'work'
  Remove-MIR4BuildTree -OutputRoot $output -Path $targetRoot
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

  $actualTree = Get-MIR4GitTree -RepoRoot $repo -Commit ([string]$Target.source.candidate_commit)
  if ($actualTree -ne [string]$Target.source.source_tree) {
    throw "Source tree mismatch for $($Target.target_key): expected $($Target.source.source_tree), got $actualTree."
  }

  $existingRoots = @()
  foreach ($root in @(Get-MIRPackageSourceRoots)) {
    & git -C $repo cat-file -e "$($Target.source.candidate_commit):$root" 2>$null
    if ($LASTEXITCODE -eq 0) { $existingRoots += $root }
  }
  if ($existingRoots.Count -eq 0) { throw "No package roots exist at $($Target.source.candidate_commit)." }

  $gitArchive = Join-Path $workRoot 'git-source.zip'
  [string[]]$archiveArgs = @('-C', $repo, 'archive', '--format=zip', '--prefix=source/', "--output=$gitArchive", [string]$Target.source.candidate_commit, '--') + @($existingRoots)
  & git @archiveArgs
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $gitArchive -PathType Leaf)) {
    throw "git archive failed for $($Target.target_key)."
  }

  $extractContainer = Join-Path $workRoot 'extract'
  Expand-MIR4SafeArchive -ArchivePath $gitArchive -Destination $extractContainer -OutputRoot $output
  $extractRoot = Join-Path $extractContainer 'source'
  Assert-MIR4SourceTreeSafe -SourceRoot $extractRoot

  $capsulePath = Join-Path $targetRoot 'source-capsule.zip'
  Write-MIR4DeterministicArchive -SourceRoot $extractRoot -EntryRoot 'source' -OutputPath $capsulePath -ContainmentRoot $output
  $inventory = Get-MIR4ArchiveInventory -Path $capsulePath
  if ([string]$inventory.root -cne 'source') {
    throw "MIR 4 source capsules require the exact archive root 'source'; got '$($inventory.root)'."
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4BootstrapSourceCapsuleV1'
    status = 'local-unpublished-input'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    target_key = [string]$Target.target_key
    factorio_line = [string]$Target.factorio_line
    source = $Target.source
    predecessor = $Target.predecessor
    package_membership = [pscustomobject][ordered]@{
      authority = 'tools/lib/validation/PackageIdentity.ps1#Get-MIRPackageSourceRoots'
      authority_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
      capsule_tool = 'tools/lib/mir4/BootstrapMaterialization.ps1#New-MIR4BootstrapSourceCapsule'
      capsule_tool_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
      shipped_sidecars = @()
      evidence_inside_package = $false
    }
    capsule = [pscustomobject][ordered]@{
      path = 'source-capsule.zip'
      archive_sha256 = $inventory.archive_sha256
      content_sha256 = $inventory.content_sha256
      bytes = $inventory.bytes
      entry_count = $inventory.entry_count
    }
    record_sha256 = ''
  }
  $recordPath = Join-Path $targetRoot 'source-capsule.json'
  $null = Write-MIR4BootstrapRecord -Record $record -Path $recordPath
  if (Get-Command Test-Json -ErrorAction SilentlyContinue) {
    $schemaPath = Join-Path $repo 'spec/schemas/mir4-bootstrap-source-capsule.schema.json'
    if (-not ((Get-Content -Raw -LiteralPath $recordPath) | Test-Json -SchemaFile $schemaPath)) {
      throw "Generated MIR 4 source capsule record failed schema validation for $($Target.target_key)/$CapsuleId."
    }
  }
  Remove-MIR4BuildTree -OutputRoot $output -Path $workRoot
  return [pscustomobject][ordered]@{ archive_path = $capsulePath; record_path = $recordPath; record = $record }
}
