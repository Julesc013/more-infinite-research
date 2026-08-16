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

function Get-MIR4RawFileIdentity {
  param([Parameter(Mandatory)][string]$Path)

  $resolved = (Resolve-Path -LiteralPath $Path).Path
  return [pscustomobject][ordered]@{
    bytes = [long](Get-Item -LiteralPath $resolved).Length
    sha256 = Get-MIR4Sha256File -Path $resolved
  }
}

function Get-MIR4GitObjectSha1 {
  param(
    [Parameter(Mandatory)][ValidateSet('blob', 'tree', 'commit')][string]$Type,
    [Parameter(Mandatory)][byte[]]$Bytes
  )

  $prefix = [Text.Encoding]::ASCII.GetBytes("$Type $($Bytes.Length)`0")
  $material = [byte[]]::new($prefix.Length + $Bytes.Length)
  [Array]::Copy($prefix, 0, $material, 0, $prefix.Length)
  [Array]::Copy($Bytes, 0, $material, $prefix.Length, $Bytes.Length)
  $algorithm = [Security.Cryptography.SHA1]::Create()
  try {
    return ([BitConverter]::ToString($algorithm.ComputeHash($material))).Replace('-', '').ToLowerInvariant()
  } finally {
    $algorithm.Dispose()
  }
}

function Get-MIR4GitBlobSha1File {
  param([Parameter(Mandatory)][string]$Path)
  return Get-MIR4GitObjectSha1 -Type blob -Bytes ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path))
}

function ConvertTo-MIR4BootstrapCanonicalValue {
  param([Parameter(Mandatory)]$Value)

  if ($Value -is [string]) {
    if ($Value -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') {
      return [DateTime]::Parse(
        $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind
      )
    }
    if ($Value -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?[+-]\d{2}:\d{2}$') {
      return [DateTimeOffset]::Parse(
        $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind
      )
    }
    return $Value
  }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in $Value.Keys) {
      $result[$key] = ConvertTo-MIR4BootstrapCanonicalValue -Value $Value[$key]
    }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
      $result[$property.Name] = ConvertTo-MIR4BootstrapCanonicalValue -Value $property.Value
    }
    return [pscustomobject]$result
  }
  if ($Value -is [Collections.IEnumerable]) {
    $items = [Collections.Generic.List[object]]::new()
    foreach ($item in $Value) {
      $items.Add((ConvertTo-MIR4BootstrapCanonicalValue -Value $item))
    }
    return ,$items.ToArray()
  }
  return $Value
}

function ConvertTo-MIR4BootstrapCanonicalJson {
  param([Parameter(Mandatory)]$Value)

  # BootstrapCanonicalJsonV1 is intentionally narrow: tool-created ordered objects,
  # integer numbers, arrays in authority order, lexical RFC 3339 timestamps,
  # UTF-8, no BOM, and no insignificant space. Timestamp normalization preserves
  # an explicit offset (or Z) so record hashes cannot depend on the runner timezone.
  $canonicalValue = ConvertTo-MIR4BootstrapCanonicalValue -Value $Value
  return (($canonicalValue | ConvertTo-Json -Depth 100 -Compress) -replace "`r`n", "`n" -replace "`r", "`n")
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
  Assert-MIR4PortableArchivePath -Path $EntryRoot
  $sourcePathMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($relative in $files) { Add-MIR4PortableArchivePath -PathMap $sourcePathMap -Path ([string]$relative).Replace('\', '/') -IsDirectory $false }

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

function Read-MIR4BoundedZipEntryBytes {
  param(
    [Parameter(Mandatory)][IO.Compression.ZipArchiveEntry]$Entry,
    [ValidateRange(1, 2147483647)][long]$MaximumBytes = 268435456
  )

  if ([long]$Entry.Length -lt 0 -or [long]$Entry.Length -gt $MaximumBytes) {
    throw "MIR 4 archive entry exceeds the bounded expanded size: $($Entry.FullName)"
  }
  $stream = $Entry.Open()
  $buffer = [byte[]]::new(65536)
  $memory = [IO.MemoryStream]::new()
  [long]$total = 0
  try {
    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
      $total += $read
      if ($total -gt $MaximumBytes -or $total -gt [long]$Entry.Length) {
        throw "MIR 4 archive entry expanded beyond its declared or bounded size: $($Entry.FullName)"
      }
      $memory.Write($buffer, 0, $read)
    }
    if ($total -ne [long]$Entry.Length) {
      throw "MIR 4 archive entry expanded length differs from its central-directory identity: $($Entry.FullName)"
    }
    return ,([byte[]]$memory.ToArray())
  } finally {
    $memory.Dispose()
    $stream.Dispose()
  }
}

function Get-MIR4BoundedContentIdentity {
  param(
    [Parameter(Mandatory)][byte[]]$Bytes,
    [Parameter(Mandatory)][string]$RelativePath
  )

  if (Test-MIRTextFingerprintPath -RelativePath $RelativePath) {
    $memory = [IO.MemoryStream]::new($Bytes)
    $reader = [IO.StreamReader]::new($memory, [Text.UTF8Encoding]::new($false), $true, 1024, $true)
    try { return Get-MIRNormalizedTextIdentity -Text $reader.ReadToEnd() }
    finally { $reader.Dispose(); $memory.Dispose() }
  }
  return [pscustomobject][ordered]@{
    Length = [long]$Bytes.Length
    Sha256 = Get-MIR4Sha256Bytes -Bytes $Bytes
  }
}

function Get-MIR4ArchiveInventory {
  param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateRange(1, 100000)][int]$MaxEntries = 4096,
    [ValidateRange(1, 2147483647)][long]$MaxEntryBytes = 268435456,
    [ValidateRange(1, 9223372036854775807)][long]$MaxExpandedBytes = 1073741824
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $zip = [IO.Compression.ZipFile]::OpenRead($resolved)
  try {
    $allEntries = @($zip.Entries)
    if ($allEntries.Count -eq 0) { throw "MIR 4 archives cannot be empty: $Path" }
    if ($allEntries.Count -gt $MaxEntries) { throw "MIR 4 archive exceeds the bounded entry count: $Path" }
    [long]$expandedBytes = 0
    $allNames = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $rootSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $allEntries) {
      if ([long]$entry.Length -gt $MaxEntryBytes) { throw "MIR 4 archive entry exceeds the bounded expanded size: $($entry.FullName)" }
      $expandedBytes += [long]$entry.Length
      if ($expandedBytes -gt $MaxExpandedBytes) { throw "MIR 4 archive exceeds the bounded total expanded size: $Path" }
      $originalName = [string]$entry.FullName
      if ([string]::IsNullOrWhiteSpace($originalName) -or $originalName.Contains('\') -or
          $originalName.StartsWith('/') -or $originalName.Contains(':') -or
          $originalName -match '(^|/)(?:\.{1,2})(?:/|$)' -or $originalName.Contains('//')) {
        throw "Unsafe MIR 4 archive entry: $originalName"
      }
      $normalizedName = $originalName.TrimEnd('/')
      if ([string]::IsNullOrWhiteSpace($normalizedName)) { throw "Unsafe empty MIR 4 archive path." }
      Add-MIR4PortableArchivePath -PathMap $allNames -Path $normalizedName -IsDirectory ([string]::IsNullOrEmpty($entry.Name))
      $segments = @($normalizedName -split '/')
      $null = $rootSet.Add([string]$segments[0])
      if (-not [string]::IsNullOrEmpty($entry.Name) -and $segments.Count -lt 2) {
        throw "MIR 4 archive files must live beneath one package root: $originalName"
      }
    }
    $roots = @($rootSet | Sort-Object -CaseSensitive)
    if ($roots.Count -ne 1 -or [string]::IsNullOrWhiteSpace($roots[0])) {
      throw "MIR 4 archives require exactly one package root: $Path"
    }
    if ($roots[0] -notmatch '^[a-z0-9][a-z0-9._-]*$') { throw "Unsafe MIR 4 archive root: $($roots[0])" }
    $fileMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($allEntries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })) {
      $fileMap.Add([string]$entry.FullName, $entry)
    }
    $orderedFileNames = [Collections.Generic.List[string]]::new()
    foreach ($name in $fileMap.Keys) { $orderedFileNames.Add($name) }
    $orderedFileNames.Sort([StringComparer]::Ordinal)
    $seen = @{}
    $entries = @(
      foreach ($fileName in $orderedFileNames) {
        $entry = $fileMap[$fileName]
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
        $rawBytes = Read-MIR4BoundedZipEntryBytes -Entry $entry -MaximumBytes $MaxEntryBytes
        $identity = Get-MIR4BoundedContentIdentity -Bytes $rawBytes -RelativePath $relative
        $rawSha256 = Get-MIR4Sha256Bytes -Bytes $rawBytes
        [pscustomobject][ordered]@{
          path = $relative
          bytes = [long]$identity.Length
          sha256 = [string]$identity.Sha256
          raw_bytes = [long]$entry.Length
          raw_sha256 = $rawSha256
        }
      }
    )
  } finally {
    $zip.Dispose()
  }

  # PackageIdentityV1 orders content rows with PowerShell's culture-insensitive
  # Sort-Object semantics. Use an explicit invariant comparer here so bounded
  # reads preserve the sealed terminal content roots on every host.
  $contentMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  $contentPaths = [Collections.Generic.List[string]]::new()
  foreach ($entry in $entries) {
    $contentMap.Add([string]$entry.path, $entry)
    $contentPaths.Add([string]$entry.path)
  }
  $contentPaths.Sort([StringComparer]::InvariantCultureIgnoreCase)
  $rows = @($contentPaths | ForEach-Object {
    $entry = $contentMap[[string]$_]
    "$($entry.path)`t$($entry.bytes)`t$($entry.sha256)"
  })
  return [pscustomobject][ordered]@{
    root = $roots[0]
    archive_sha256 = Get-MIR4Sha256File -Path $resolved
    content_sha256 = Get-MIR4Sha256String -Value ($rows -join "`n")
    bytes = [long](Get-Item -LiteralPath $resolved).Length
    entry_count = $entries.Count
    entries = $entries
  }
}

function Read-MIR4ArchiveText {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RelativePath,
    [ValidateRange(1, 2147483647)][long]$MaximumBytes = 268435456
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
  try {
    $entry = @($zip.Entries | Where-Object {
      if ([string]::IsNullOrEmpty($_.Name)) { return $false }
      $name = $_.FullName.Replace('\', '/')
      $slash = $name.IndexOf('/')
      return $slash -ge 0 -and $name.Substring($slash + 1) -ceq $RelativePath
    })
    if ($entry.Count -ne 1) { throw "Expected one $RelativePath entry in $Path; found $($entry.Count)." }
    $bytes = Read-MIR4BoundedZipEntryBytes -Entry $entry[0] -MaximumBytes $MaximumBytes
    $stream = [IO.MemoryStream]::new($bytes)
    $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false), $true)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose(); $stream.Dispose() }
  } finally {
    $zip.Dispose()
  }
}

function Read-MIR4ArchiveBytes {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RelativePath,
    [ValidateRange(1, 2147483647)][long]$MaximumBytes = 268435456
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
  try {
    $entry = @($zip.Entries | Where-Object {
      if ([string]::IsNullOrEmpty($_.Name)) { return $false }
      $name = $_.FullName.Replace('\', '/')
      $slash = $name.IndexOf('/')
      return $slash -ge 0 -and $name.Substring($slash + 1) -ceq $RelativePath
    })
    if ($entry.Count -ne 1) { throw "Expected one $RelativePath entry in $Path; found $($entry.Count)." }
    return ,([byte[]](Read-MIR4BoundedZipEntryBytes -Entry $entry[0] -MaximumBytes $MaximumBytes))
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
  $null = $updated | ConvertFrom-Json -DateKind String
  return $updated
}

function Get-MIR4ComparableInfoJson {
  param([Parameter(Mandatory)][string]$Json)

  $value = $Json | ConvertFrom-Json -DateKind String
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
  $candidateInfo = $candidateInfoText | ConvertFrom-Json -DateKind String
  $predecessorInfo = $predecessorInfoText | ConvertFrom-Json -DateKind String
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

function Compare-MIR4BootstrapCorrectedCandidate {
  param(
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$PredecessorPath,
    [Parameter(Mandatory)][string]$ExpectedCandidateRoot,
    [Parameter(Mandatory)][string]$ExpectedPredecessorRoot,
    [Parameter(Mandatory)][string]$ExpectedCandidateVersion,
    [Parameter(Mandatory)][string]$ExpectedPredecessorVersion,
    [Parameter(Mandatory)]$Correction,
    [switch]$ThrowOnDifference
  )

  if ([string]$Correction.kind -cne 'MIR4ApprovedBootstrapCorrectionDeltaV1' -or
      [string]$Correction.finding -cne 'MIR3-TERM-0033' -or
      [string]$Correction.target_key -cne 'f210' -or
      [bool]$Correction.public_output_authorized -ne $false -or
      -not (Test-MIR4BootstrapRecordHash -Record $Correction)) {
    throw 'The approved bootstrap correction record is absent, malformed, or not self-bound.'
  }
  $candidate = Get-MIR4ArchiveInventory -Path $CandidatePath
  $predecessor = Get-MIR4ArchiveInventory -Path $PredecessorPath
  if ([string]$predecessor.archive_sha256 -cne [string]$Correction.predecessor.archive_sha256 -or
      [string]$predecessor.content_sha256 -cne [string]$Correction.predecessor.content_sha256) {
    throw 'The predecessor archive does not match the approved correction base.'
  }
  $candidateMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($entry in $candidate.entries) { $candidateMap.Add([string]$entry.path, $entry) }
  $predecessorMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($entry in $predecessor.entries) { $predecessorMap.Add([string]$entry.path, $entry) }
  $added = @($candidateMap.Keys | Where-Object { -not $predecessorMap.ContainsKey($_) } | Sort-Object)
  $removed = @($predecessorMap.Keys | Where-Object { -not $candidateMap.ContainsKey($_) } | Sort-Object)
  $changed = @($candidateMap.Keys | Where-Object {
    $predecessorMap.ContainsKey($_) -and $candidateMap[$_].raw_sha256 -cne $predecessorMap[$_].raw_sha256
  } | Sort-Object)
  $expectedChanged = @(@('info.json') + @($Correction.deltas.path) | Sort-Object)
  $exactDelta = $added.Count -eq 0 -and $removed.Count -eq 0 -and
    ($changed -join '|') -ceq ($expectedChanged -join '|')
  foreach ($delta in @($Correction.deltas)) {
    $path = [string]$delta.path
    $exactDelta = $exactDelta -and $predecessorMap.ContainsKey($path) -and $candidateMap.ContainsKey($path)
    if ($predecessorMap.ContainsKey($path) -and $candidateMap.ContainsKey($path)) {
      $exactDelta = $exactDelta -and
        [string]$predecessorMap[$path].raw_sha256 -ceq [string]$delta.before_sha256 -and
        [long]$predecessorMap[$path].bytes -eq [long]$delta.before_bytes -and
        [string]$candidateMap[$path].raw_sha256 -ceq [string]$delta.after_sha256 -and
        [long]$candidateMap[$path].bytes -eq [long]$delta.after_bytes
    }
  }
  $candidateInfoText = [Text.UTF8Encoding]::new($false, $true).GetString([byte[]](Read-MIR4ArchiveBytes -Path $CandidatePath -RelativePath 'info.json'))
  $predecessorInfoText = [Text.UTF8Encoding]::new($false, $true).GetString([byte[]](Read-MIR4ArchiveBytes -Path $PredecessorPath -RelativePath 'info.json'))
  $candidateInfo = $candidateInfoText | ConvertFrom-Json -DateKind String
  $predecessorInfo = $predecessorInfoText | ConvertFrom-Json -DateKind String
  $expectedInfo = ConvertTo-MIR4InfoVersionProjection -Text $predecessorInfoText -Version $ExpectedCandidateVersion
  $metadataEquivalent = [string]$candidate.root -ceq $ExpectedCandidateRoot -and
    [string]$predecessor.root -ceq $ExpectedPredecessorRoot -and
    [string]$candidateInfo.version -ceq $ExpectedCandidateVersion -and
    [string]$predecessorInfo.version -ceq $ExpectedPredecessorVersion -and
    $candidateInfoText -ceq $expectedInfo -and
    (Get-MIR4ComparableInfoJson -Json $candidateInfoText) -ceq (Get-MIR4ComparableInfoJson -Json $predecessorInfoText)
  $equivalent = $exactDelta -and $metadataEquivalent
  $result = [pscustomobject][ordered]@{
    equivalent = $equivalent
    policy = 'MIR4BootstrapApprovedCorrectionEquivalenceV1'
    correction_kind = [string]$Correction.kind
    correction_record_sha256 = [string]$Correction.record_sha256
    finding = [string]$Correction.finding
    added = $added
    removed = $removed
    changed = $changed
    metadata_equivalent = $metadataEquivalent
    exact_correction_delta = $exactDelta
    candidate = [pscustomobject][ordered]@{ archive_sha256=$candidate.archive_sha256; content_sha256=$candidate.content_sha256; bytes=$candidate.bytes; entry_count=$candidate.entry_count }
    predecessor = [pscustomobject][ordered]@{ archive_sha256=$predecessor.archive_sha256; content_sha256=$predecessor.content_sha256; bytes=$predecessor.bytes; entry_count=$predecessor.entry_count }
  }
  if ($ThrowOnDifference -and -not $equivalent) {
    throw "Candidate differs outside the exact approved MIR3-TERM-0033 correction (added=$($added -join ','), removed=$($removed -join ','), changed=$($changed -join ','))."
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

function Write-MIR4DeterministicRawTreeArchive {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$EntryRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ContainmentRoot
  )

  Add-Type -AssemblyName System.IO.Compression
  $source = (Resolve-Path -LiteralPath $SourceRoot).Path
  Assert-MIR4SourceTreeSafe -SourceRoot $source
  if ($EntryRoot -notmatch '^[a-z0-9][a-z0-9._-]*$') { throw "Unsafe archive entry root: $EntryRoot" }
  $files = [Collections.Generic.List[string]]::new()
  $sourcePathMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($item in @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)) {
    $relative = [IO.Path]::GetRelativePath($source, $item.FullName).Replace('\', '/')
    Add-MIR4PortableArchivePath -PathMap $sourcePathMap -Path $relative -IsDirectory $false
    $files.Add($relative)
  }
  $files.Sort([StringComparer]::Ordinal)
  if ($files.Count -eq 0) { throw "The MIR 4 capsule staging tree is empty." }
  Assert-MIR4PortableArchivePath -Path $EntryRoot

  $output = Assert-MIR4DescendantPath -Root $ContainmentRoot -Path $OutputPath
  $null = Assert-MIR4NoReparseAncestors -Root $ContainmentRoot -Path $output
  $parent = Split-Path -Parent $output
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $temp = "$output.new"
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
  $stream = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
  $timestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
  try {
    foreach ($relative in $files) {
      $entry = $archive.CreateEntry("$EntryRoot/$relative", [IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime = $timestamp
      $entry.ExternalAttributes = 0
      $input = [IO.File]::OpenRead((Join-Path $source $relative))
      $destination = $entry.Open()
      try { $input.CopyTo($destination) } finally { $destination.Dispose(); $input.Dispose() }
    }
  } finally {
    $archive.Dispose()
    $stream.Dispose()
  }
  if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
  Move-Item -LiteralPath $temp -Destination $output
}

function Invoke-MIR4GitCatFileToPath {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('blob', 'commit', 'tree')][string]$Type,
    [Parameter(Mandatory)][string]$ObjectId,
    [Parameter(Mandatory)][string]$OutputPath
  )

  $parent = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $gitCommand = @(Get-Command git -CommandType Application -ErrorAction Stop | Where-Object { Test-Path -LiteralPath $_.Source -PathType Leaf } | Select-Object -First 1)
  if ($gitCommand.Count -ne 1) { throw 'Unable to resolve one executable Git command for capsule object capture.' }
  $processInfo = [Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = [string]$gitCommand[0].Source
  $processInfo.UseShellExecute = $false
  $processInfo.CreateNoWindow = $true
  $processInfo.RedirectStandardOutput = $true
  $processInfo.RedirectStandardError = $true
  foreach ($argument in @('-C', $RepoRoot, 'cat-file', $Type, $ObjectId)) { $null = $processInfo.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $processInfo
  if (-not $process.Start()) { throw "Unable to start git cat-file for $ObjectId." }
  $output = [IO.File]::Open($OutputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $process.StandardOutput.BaseStream.CopyTo($output) } finally { $output.Dispose() }
  $errorText = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  $exitCode = $process.ExitCode
  $process.Dispose()
  if ($exitCode -ne 0) { throw "git cat-file failed for $ObjectId`: $errorText" }
}

function Read-MIR4GitTreeObject {
  param([Parameter(Mandatory)][byte[]]$Bytes)

  $entries = [Collections.Generic.List[object]]::new()
  $offset = 0
  $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
  while ($offset -lt $Bytes.Length) {
    $modeStart = $offset
    while ($offset -lt $Bytes.Length -and $Bytes[$offset] -ne 0x20) { $offset++ }
    if ($offset -ge $Bytes.Length) { throw 'Malformed Git tree object mode.' }
    $mode = [Text.Encoding]::ASCII.GetString($Bytes, $modeStart, $offset - $modeStart)
    $offset++
    $nameStart = $offset
    while ($offset -lt $Bytes.Length -and $Bytes[$offset] -ne 0) { $offset++ }
    if ($offset -ge $Bytes.Length) { throw 'Malformed Git tree object name.' }
    $name = $strictUtf8.GetString($Bytes, $nameStart, $offset - $nameStart)
    $offset++
    if ($offset + 20 -gt $Bytes.Length) { throw 'Malformed Git tree object identity.' }
    $objectBytes = [byte[]]::new(20)
    [Array]::Copy($Bytes, $offset, $objectBytes, 0, 20)
    $offset += 20
    $entries.Add([pscustomobject][ordered]@{
      mode = $mode
      name = $name
      object_id = ([BitConverter]::ToString($objectBytes)).Replace('-', '').ToLowerInvariant()
    })
  }
  return @($entries)
}

function Assert-MIR4GitSourceProof {
  param(
    [Parameter(Mandatory)][string]$CapsuleRoot,
    [Parameter(Mandatory)]$Proof
  )

  if ([string]$Proof.kind -cne 'MIR4BootstrapGitSourceProofV1') { throw 'Unexpected MIR 4 Git source proof kind.' }
  if (-not (Test-MIR4BootstrapRecordHash -Record $Proof)) { throw 'MIR 4 Git source proof self-hash mismatch.' }
  $commitPath = Join-Path $CapsuleRoot ([string]$Proof.commit.payload_path)
  $commitBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $commitPath).Path)
  if ((Get-MIR4GitObjectSha1 -Type commit -Bytes $commitBytes) -cne [string]$Proof.commit.sha1 -or
      (Get-MIR4Sha256Bytes -Bytes $commitBytes) -cne [string]$Proof.commit.sha256) {
    throw 'MIR 4 capsule Git commit object identity mismatch.'
  }
  $commitText = [Text.UTF8Encoding]::new($false, $true).GetString($commitBytes)
  $treeMatches = [Text.RegularExpressions.Regex]::Matches($commitText, '(?m)^tree ([a-f0-9]{40})$')
  if ($treeMatches.Count -ne 1 -or [string]$treeMatches[0].Groups[1].Value -cne [string]$Proof.source_tree) {
    throw 'MIR 4 capsule Git commit does not bind the governed source tree.'
  }

  $treeMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($treeRow in @($Proof.tree_objects)) {
    $treePath = Join-Path $CapsuleRoot ([string]$treeRow.payload_path)
    $treeBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $treePath).Path)
    if ((Get-MIR4GitObjectSha1 -Type tree -Bytes $treeBytes) -cne [string]$treeRow.sha1 -or
        (Get-MIR4Sha256Bytes -Bytes $treeBytes) -cne [string]$treeRow.sha256) {
      throw "MIR 4 capsule Git tree object identity mismatch: $($treeRow.sha1)"
    }
    $treeMap.Add([string]$treeRow.sha1, @(Read-MIR4GitTreeObject -Bytes $treeBytes))
  }
  if (-not $treeMap.ContainsKey([string]$Proof.source_tree)) { throw 'MIR 4 capsule omits its source root tree object.' }

  $observedFileList = [Collections.Generic.List[string]]::new()
  foreach ($relative in @(Get-MIRPackageSourceFiles -RepoRoot $CapsuleRoot)) { $observedFileList.Add([string]$relative) }
  $observedFileList.Sort([StringComparer]::Ordinal)
  $observedFiles = @($observedFileList)
  $expectedFiles = @($Proof.package_files.path)
  if (($observedFiles -join '|') -cne ($expectedFiles -join '|')) { throw 'MIR 4 capsule package-source membership differs from its Git proof.' }
  foreach ($fileRow in @($Proof.package_files)) {
    $relative = [string]$fileRow.path
    $segments = @($relative -split '/')
    $treeId = [string]$Proof.source_tree
    for ($index = 0; $index -lt $segments.Count; $index++) {
      if (-not $treeMap.ContainsKey($treeId)) { throw "MIR 4 capsule is missing a Git tree proof for $relative." }
      $matches = @($treeMap[$treeId] | Where-Object { [string]$_.name -ceq [string]$segments[$index] })
      if ($matches.Count -ne 1) { throw "MIR 4 capsule Git tree does not contain exactly one $relative path segment." }
      $entry = $matches[0]
      if ($index -lt $segments.Count - 1) {
        if ([string]$entry.mode -cne '40000') { throw "MIR 4 capsule Git path is not a tree: $relative" }
        $treeId = [string]$entry.object_id
      } else {
        if ([string]$entry.mode -cne [string]$fileRow.mode -or [string]$entry.object_id -cne [string]$fileRow.blob_sha1) {
          throw "MIR 4 capsule Git blob binding differs for $relative."
        }
      }
    }
    $filePath = Join-Path $CapsuleRoot $relative
    $identity = Get-MIR4RawFileIdentity -Path $filePath
    if ((Get-MIR4GitBlobSha1File -Path $filePath) -cne [string]$fileRow.blob_sha1 -or
        [string]$identity.sha256 -cne [string]$fileRow.sha256 -or [long]$identity.bytes -ne [long]$fileRow.bytes) {
      throw "MIR 4 capsule package source differs from its Git blob proof: $relative"
    }
  }
  return $true
}

function New-MIR4BootstrapToolchainLock {
  param([Parameter(Mandatory)][string]$PwshPath)

  $resolvedPwsh = (Resolve-Path -LiteralPath $PwshPath).Path
  $toolchainRoot = Split-Path -Parent $resolvedPwsh
  if (((Get-Item -LiteralPath $toolchainRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The bound PowerShell toolchain root cannot be a reparse point.'
  }
  $fileMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  $caseMap = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
  foreach ($item in @(Get-ChildItem -LiteralPath $toolchainRoot -Recurse -Force)) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "The bound PowerShell toolchain contains a reparse point: $($item.FullName)" }
    if ($item.PSIsContainer) { continue }
    $relative = [IO.Path]::GetRelativePath($toolchainRoot, $item.FullName).Replace('\', '/')
    Assert-MIR4PortableArchivePath -Path $relative
    $caseKey = $relative.ToLowerInvariant()
    if ($caseMap.ContainsKey($caseKey)) { throw "Case-colliding bound PowerShell toolchain paths: $($caseMap[$caseKey]) and $relative" }
    $caseMap.Add($caseKey, $relative)
    $fileMap.Add($relative, $item)
  }
  if (-not $fileMap.ContainsKey('pwsh.exe')) { throw 'The bound PowerShell toolchain omits pwsh.exe.' }
  $orderedPaths = [Collections.Generic.List[string]]::new()
  foreach ($relative in $fileMap.Keys) { $orderedPaths.Add($relative) }
  $orderedPaths.Sort([StringComparer]::Ordinal)
  $files = @()
  $contentFields = [ordered]@{}
  [long]$totalBytes = 0
  foreach ($relative in $orderedPaths) {
    $identity = Get-MIR4RawFileIdentity -Path $fileMap[$relative].FullName
    $files += [pscustomobject][ordered]@{ path = $relative; bytes = [long]$identity.bytes; sha256 = [string]$identity.sha256 }
    $contentFields[$relative] = "$([long]$identity.bytes)|$([string]$identity.sha256)"
    $totalBytes += [long]$identity.bytes
  }
  $contentRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.toolchain-content.v1' -Fields $contentFields
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4BootstrapToolchainLockV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    powershell_version = [string]$PSVersionTable.PSVersion
    dotnet_runtime_version = [string][Environment]::Version
    os_platform = [string][Environment]::OSVersion.Platform
    os_version = [string][Environment]::OSVersion.Version
    process_architecture = [string][Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
    executable = 'pwsh.exe'
    execution_culture = 'InvariantCulture'
    file_count = [int]$files.Count
    total_bytes = $totalBytes
    files = $files
    content_root_sha256 = $contentRoot
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function New-MIR4GitSourceProof {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$ExpectedTree,
    [Parameter(Mandatory)][string]$CapsuleRoot
  )

  $gitRoot = Join-Path $CapsuleRoot '.mir/capsule/git'
  New-Item -ItemType Directory -Force -Path (Join-Path $gitRoot 'trees') | Out-Null
  $commitPayload = Join-Path $gitRoot 'commit.raw'
  Invoke-MIR4GitCatFileToPath -RepoRoot $RepoRoot -Type commit -ObjectId $Commit -OutputPath $commitPayload
  $commitBytes = [IO.File]::ReadAllBytes($commitPayload)
  if ((Get-MIR4GitObjectSha1 -Type commit -Bytes $commitBytes) -cne $Commit) { throw 'Captured Git commit payload does not reproduce its object identity.' }

  $roots = @(Get-MIRPackageSourceRoots)
  $treeLines = @(& git -C $RepoRoot ls-tree -r -t $Commit -- @roots 2>$null)
  if ($LASTEXITCODE -ne 0) { throw "Unable to capture package Git tree proof for $Commit." }
  $treeIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $null = $treeIds.Add($ExpectedTree)
  $packageFileMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($line in $treeLines) {
    if ([string]$line -notmatch "^([0-9]{6}) (blob|tree) ([a-f0-9]{40})`t([A-Za-z0-9._/-]+)$") {
      throw "Unsafe or malformed Git tree proof row: $line"
    }
    $mode = [string]$Matches[1]
    $type = [string]$Matches[2]
    $objectId = [string]$Matches[3]
    $relative = [string]$Matches[4]
    if ($type -eq 'tree') {
      $null = $treeIds.Add($objectId)
      continue
    }
    if ($mode -notin @('100644', '100755')) { throw "MIR 4 package source contains a non-regular Git mode: $mode $relative" }
    $path = Join-Path $CapsuleRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Capsule staging omits package source path $relative." }
    $identity = Get-MIR4RawFileIdentity -Path $path
    if ((Get-MIR4GitBlobSha1File -Path $path) -cne $objectId) { throw "Capsule staging differs from Git blob $relative." }
    $packageFileMap.Add($relative, [pscustomobject][ordered]@{
      path = $relative
      mode = $mode
      blob_sha1 = $objectId
      bytes = $identity.bytes
      sha256 = $identity.sha256
    })
  }
  $packagePathList = [Collections.Generic.List[string]]::new()
  foreach ($relative in $packageFileMap.Keys) { $packagePathList.Add($relative) }
  $packagePathList.Sort([StringComparer]::Ordinal)
  $packageFiles = @($packagePathList | ForEach-Object { $packageFileMap[[string]$_] })
  $sourceFileList = [Collections.Generic.List[string]]::new()
  foreach ($relative in @(Get-MIRPackageSourceFiles -RepoRoot $CapsuleRoot)) { $sourceFileList.Add([string]$relative) }
  $sourceFileList.Sort([StringComparer]::Ordinal)
  $sourceFiles = @($sourceFileList)
  if (($sourceFiles -join '|') -cne (@($packageFiles.path) -join '|')) { throw 'Git package tree proof is not total over package source.' }

  $treeObjects = @()
  $treeIdList = [Collections.Generic.List[string]]::new()
  foreach ($treeId in $treeIds) { $treeIdList.Add($treeId) }
  $treeIdList.Sort([StringComparer]::Ordinal)
  foreach ($treeId in $treeIdList) {
    $relativePayload = ".mir/capsule/git/trees/$treeId.tree"
    $payload = Join-Path $CapsuleRoot $relativePayload
    Invoke-MIR4GitCatFileToPath -RepoRoot $RepoRoot -Type tree -ObjectId $treeId -OutputPath $payload
    $bytes = [IO.File]::ReadAllBytes($payload)
    if ((Get-MIR4GitObjectSha1 -Type tree -Bytes $bytes) -cne $treeId) { throw "Captured Git tree payload does not reproduce $treeId." }
    $treeObjects += [pscustomobject][ordered]@{
      sha1 = $treeId
      payload_path = $relativePayload
      bytes = [long]$bytes.Length
      sha256 = Get-MIR4Sha256Bytes -Bytes $bytes
    }
  }
  $commitIdentity = Get-MIR4RawFileIdentity -Path $commitPayload
  $proof = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4BootstrapGitSourceProofV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    candidate_commit = $Commit
    source_tree = $ExpectedTree
    commit = [pscustomobject][ordered]@{
      sha1 = $Commit
      payload_path = '.mir/capsule/git/commit.raw'
      bytes = $commitIdentity.bytes
      sha256 = $commitIdentity.sha256
    }
    tree_objects = $treeObjects
    package_files = $packageFiles
    record_sha256 = ''
  }
  $proofPath = Join-Path $gitRoot 'source-identity.json'
  $null = Write-MIR4BootstrapRecord -Record $proof -Path $proofPath
  $null = Assert-MIR4GitSourceProof -CapsuleRoot $CapsuleRoot -Proof $proof
  return $proof
}

function Get-MIR4CapsuleMemberRole {
  param([Parameter(Mandatory)][string]$RelativePath)

  if ($RelativePath -like '.mir/capsule/git/*') { return 'git-object-proof' }
  if ($RelativePath -eq '.mir/capsule/toolchain-lock.json') { return 'toolchain-lock' }
  if ($RelativePath -eq '.mir/capsule/RECONSTRUCT.md') { return 'reconstruction-instructions' }
  if ($RelativePath -like '.mir/releases/*') { return 'authority' }
  if ($RelativePath -like 'spec/schemas/*') { return 'schema' }
  if ($RelativePath -eq 'tools/commands/package/Build-MIRPackage.ps1') { return 'canonical-package-builder' }
  if ($RelativePath -like 'tools/*') { return 'reconstruction-tool' }
  return 'package-source'
}

function Get-MIR4BootstrapCapsuleControllerPaths {
  return @(
    'tools/commands/package/Build-MIRPackage.ps1',
    'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1',
    'tools/lib/validation/PackageIdentity.ps1',
    'tools/lib/validation/MIR4DistributionIdentity.ps1',
    'tools/lib/mir4/BootstrapMaterialization.ps1'
  )
}

function Get-MIR4BootstrapCapsuleAuthorityPaths {
  param([ValidateSet('emergency', 'local-playtest-shadow')][string]$Lane = 'emergency')

  $paths = @(
    '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Entry-GateV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Emergency-LaneV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Equivalence-PolicyV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Approved-Bootstrap-Correction-MIR3-TERM-0033V1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV2.json',
    '.mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv2.json',
    '.mir/releases/waves/mir4-r0/terminal-baseline-import.json',
    '.mir/releases/waves/mir4-r0/bootstrap-root-set.json',
    '.mir/releases/waves/mir4-r0/MIR4-Offline-Release-AuthorityV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Terminal-Import-ContractV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Terminal-Predecessor-RefreshV1.json',
    '.mir/releases/terminal/baselines/3.2.10/baseline-manifest.json',
    '.mir/releases/terminal/baselines/3.2.10/normalized-snapshot.json',
    '.mir/releases/terminal/baselines/3.2.10/package-composition.json',
    '.mir/releases/records/3.2.10.json',
    '.mir/releases/emergency/MIR3PostTerminalEmergencyHotfixLocalQualificationV1.json',
    '.mir/releases/emergency/findings/MIR3-TERM-0033.json',
    '.mir/releases/terminal/baselines/3.2.9/baseline-manifest.json'
  )
  if ($Lane -ceq 'local-playtest-shadow') {
    $paths += @(
      '.mir/releases/waves/mir4-r0/MIR4-Local-Playtest-Shadow-AuthorizationV1.json',
      '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Target-ReadinessV1.json',
      '.mir/targets.json',
      '.mir/releases/terminal/baselines/2.5.9/baseline-manifest.json',
      '.mir/releases/terminal/baselines/2.5.9/normalized-snapshot.json',
      '.mir/releases/terminal/baselines/2.5.9/package-composition.json',
      '.mir/releases/records/2.5.9.json',
      '.mir/releases/terminal/baselines/1.9.9/baseline-manifest.json',
      '.mir/releases/terminal/baselines/1.9.9/normalized-snapshot.json',
      '.mir/releases/terminal/baselines/1.9.9/package-composition.json',
      '.mir/releases/records/1.9.9.json',
      '.mir/releases/terminal/baselines/1.8.9/baseline-manifest.json',
      '.mir/releases/terminal/baselines/1.8.9/normalized-snapshot.json',
      '.mir/releases/terminal/baselines/1.8.9/package-composition.json',
      '.mir/releases/records/1.8.9.json'
    )
  }
  return $paths
}

function Get-MIR4BootstrapCapsuleSchemaPaths {
  param([ValidateSet('emergency', 'local-playtest-shadow')][string]$Lane = 'emergency')

  $paths = @(
    'spec/schemas/mir4-bootstrap-local-candidate-plan.schema.json',
    'spec/schemas/mir4-bootstrap-local-candidate-manifest.schema.json',
    'spec/schemas/mir4-approved-bootstrap-correction-delta.schema.json',
    'spec/schemas/mir4-bootstrap-root-set.schema.json',
    'spec/schemas/mir4-bootstrap-source-capsule.schema.json',
    'spec/schemas/mir4-bootstrap-capsule-manifest.schema.json',
    'spec/schemas/mir4-bootstrap-toolchain-lock.schema.json',
    'spec/schemas/mir3-post-terminal-hotfix-baseline-continuation.schema.json',
    'spec/schemas/mir4-bootstrap-git-source-proof.schema.json',
    'spec/schemas/mir4-bootstrap-reconstruction-receipt.schema.json',
    'spec/schemas/mir4-r0-authority.schema.json',
    'spec/schemas/mir4-target-registry-v2.schema.json',
    'spec/schemas/mir4-versioning-distribution-identity-v2.schema.json'
  )
  if ($Lane -ceq 'local-playtest-shadow') {
    $paths += @(
      'spec/schemas/mir4-local-playtest-shadow-authorization.schema.json',
      'spec/schemas/mir4-local-playtest-candidate-manifest.schema.json',
      'spec/schemas/mir4-bootstrap-target-readiness.schema.json'
    )
  }
  return $paths
}

function Assert-MIR4BootstrapCapsuleManifestClosure {
  param(
    [Parameter(Mandatory)]$Manifest,
    [Parameter(Mandatory)]$GitProof,
    [ValidateSet('emergency', 'local-playtest-shadow')][string]$Lane = 'emergency'
  )

  $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($relative in @(
    (Get-MIR4BootstrapCapsuleControllerPaths) +
    (Get-MIR4BootstrapCapsuleAuthorityPaths -Lane $Lane) +
    (Get-MIR4BootstrapCapsuleSchemaPaths -Lane $Lane) +
    @(
      '.mir/capsule/toolchain-lock.json',
      '.mir/capsule/RECONSTRUCT.md',
      '.mir/capsule/git/source-identity.json',
      '.mir/capsule/git/commit.raw'
    )
  )) {
    if (-not $expected.Add([string]$relative)) { throw "Duplicate required MIR 4 capsule closure path: $relative" }
  }
  foreach ($row in @($GitProof.tree_objects)) {
    if (-not $expected.Add([string]$row.payload_path)) { throw "Duplicate MIR 4 capsule Git-tree closure path: $($row.payload_path)" }
  }
  foreach ($row in @($GitProof.package_files)) {
    if (-not $expected.Add([string]$row.path)) { throw "Duplicate MIR 4 capsule package-source closure path: $($row.path)" }
  }

  $actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($member in @($Manifest.members)) {
    $relative = [string]$member.path
    if (-not $actual.Add($relative)) { throw "Duplicate MIR 4 capsule manifest closure path: $relative" }
    $expectedRole = Get-MIR4CapsuleMemberRole -RelativePath $relative
    if ([string]$member.role -cne $expectedRole) { throw "MIR 4 capsule member role mismatch for $relative." }
  }
  if ([int]$Manifest.member_count -ne $actual.Count) { throw 'MIR 4 capsule manifest member count is inconsistent.' }
  if ($actual.Count -ne $expected.Count) { throw 'MIR 4 capsule manifest does not contain the exact reconstruction closure.' }
  foreach ($relative in $expected) {
    if (-not $actual.Contains($relative)) { throw "MIR 4 capsule manifest omits required closure path: $relative" }
  }
  foreach ($relative in $actual) {
    if (-not $expected.Contains($relative)) { throw "MIR 4 capsule manifest contains an ungoverned closure path: $relative" }
  }
}

function Copy-MIR4CapsuleClosureFile {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CapsuleRoot,
    [Parameter(Mandatory)][string]$RelativePath
  )

  if ($RelativePath -notmatch '^[A-Za-z0-9._/-]+$' -or $RelativePath -match '(^|/)\.{1,2}(/|$)') {
    throw "Unsafe MIR 4 capsule closure path: $RelativePath"
  }
  $source = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "MIR 4 capsule closure input is absent: $RelativePath" }
  $destination = Join-Path $CapsuleRoot $RelativePath
  $parent = Split-Path -Parent $destination
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $source).Path)
  $canonicalText = $text.Replace("`r`n", "`n").Replace("`r", "`n")
  [IO.File]::WriteAllText($destination, $canonicalText, [Text.UTF8Encoding]::new($false))
}

function Assert-MIR4BootstrapCapsuleArtifact {
  param(
    [Parameter(Mandatory)][string]$CapsulePath,
    [Parameter(Mandatory)][string]$EnvelopePath,
    [Parameter(Mandatory)][string]$RunnerPath,
    [Parameter(Mandatory)][string]$SchemaRoot
  )

  $envelopeText = Get-Content -Raw -LiteralPath $EnvelopePath
  if (-not ($envelopeText | Test-Json -SchemaFile (Join-Path $SchemaRoot 'mir4-bootstrap-source-capsule.schema.json'))) {
    throw "MIR 4 source capsule envelope schema validation failed: $EnvelopePath"
  }
  $envelope = $envelopeText | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $envelope)) { throw "MIR 4 source capsule envelope self-hash mismatch: $EnvelopePath" }
  $lane = [string]$envelope.lane
  if ($lane -cnotin @('emergency', 'local-playtest-shadow')) { throw 'MIR 4 source capsule has an unknown construction lane.' }
  $inventory = Get-MIR4ArchiveInventory -Path $CapsulePath
  if ([string]$inventory.root -cne 'mir4-source-capsule') { throw 'Unexpected MIR 4 source capsule archive root.' }
  foreach ($field in @('archive_sha256', 'content_sha256', 'bytes', 'entry_count')) {
    if ([string]$inventory.$field -cne [string]$envelope.capsule.$field) { throw "MIR 4 capsule $field differs from its envelope." }
  }
  $runnerIdentity = Get-MIR4RawFileIdentity -Path $RunnerPath
  if ([string]$runnerIdentity.sha256 -cne [string]$envelope.bootstrap_runner.sha256 -or
      [long]$runnerIdentity.bytes -ne [long]$envelope.bootstrap_runner.bytes) {
    throw 'Detached MIR 4 capsule runner differs from its envelope.'
  }

  $manifestText = Read-MIR4ArchiveText -Path $CapsulePath -RelativePath '.mir/capsule/manifest.json'
  if (-not ($manifestText | Test-Json -SchemaFile (Join-Path $SchemaRoot 'mir4-bootstrap-capsule-manifest.schema.json'))) {
    throw 'MIR 4 capsule-internal manifest schema validation failed.'
  }
  $manifest = $manifestText | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $manifest)) { throw 'MIR 4 capsule-internal manifest self-hash mismatch.' }
  if ([string]$manifest.record_sha256 -cne [string]$envelope.closure.internal_manifest_record_sha256) {
    throw 'MIR 4 capsule internal-manifest binding differs from its envelope.'
  }
  if ([string]$manifest.lane -cne $lane -or
      [string]$manifest.target.target_key -cne [string]$envelope.target_key -or
      [string]$manifest.target.factorio_line -cne [string]$envelope.factorio_line -or
      [string]$manifest.target.distribution_version -cne [string]$envelope.distribution_version -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.target.source) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $envelope.source) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.target.predecessor) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $envelope.predecessor)) {
    throw 'MIR 4 capsule internal target authority differs from its detached envelope.'
  }
  if ([int]$manifest.member_count -ne @($manifest.members).Count) { throw 'MIR 4 capsule member count is inconsistent.' }
  $inventoryMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($entry in @($inventory.entries)) { $inventoryMap.Add([string]$entry.path, $entry) }
  $expectedCount = @($manifest.members).Count + 1
  if ($inventoryMap.Count -ne $expectedCount -or -not $inventoryMap.ContainsKey('.mir/capsule/manifest.json')) {
    throw 'MIR 4 capsule membership is not exactly its manifest plus the non-recursive manifest record.'
  }
  $memberFields = [ordered]@{}
  $authorityFields = [ordered]@{}
  $lastPath = ''
  foreach ($member in @($manifest.members)) {
    $relative = [string]$member.path
    if (-not [string]::IsNullOrEmpty($lastPath) -and [StringComparer]::Ordinal.Compare($lastPath, $relative) -ge 0) {
      throw 'MIR 4 capsule manifest members are not unique and ordinally ordered.'
    }
    $lastPath = $relative
    if (-not $inventoryMap.ContainsKey($relative)) { throw "MIR 4 capsule manifest member is absent: $relative" }
    $entry = $inventoryMap[$relative]
    if ([long]$entry.raw_bytes -ne [long]$member.bytes -or [string]$entry.raw_sha256 -cne [string]$member.sha256) {
      throw "MIR 4 capsule manifest member identity differs: $relative"
    }
    $memberFields[$relative] = "$([string]$member.role)|$([long]$member.bytes)|$([string]$member.sha256)"
    if ([string]$member.role -ceq 'authority') { $authorityFields[$relative] = [string]$member.sha256 }
  }
  $payloadRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-payload.v1' -Fields $memberFields
  $authorityRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-authority.v1' -Fields $authorityFields
  $contentRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-content.v1' -Fields ([ordered]@{
    payload_root_sha256 = $payloadRoot
    internal_manifest_record_sha256 = [string]$manifest.record_sha256
  })
  foreach ($row in @(
    @($payloadRoot, $manifest.payload_root_sha256, 'payload root'),
    @($payloadRoot, $envelope.closure.payload_root_sha256, 'envelope payload root'),
    @($authorityRoot, $manifest.authority_closure_root_sha256, 'authority closure root'),
    @($authorityRoot, $envelope.closure.authority_closure_root_sha256, 'envelope authority root'),
    @($contentRoot, $envelope.closure.capsule_content_root_sha256, 'capsule content root')
  )) {
    if ([string]$row[0] -cne [string]$row[1]) { throw "MIR 4 capsule $($row[2]) mismatch." }
  }
  foreach ($field in @('git_source_proof_record_sha256', 'toolchain_lock_record_sha256', 'canonical_builder_sha256', 'reconstruction_runner_sha256')) {
    if ([string]$manifest.$field -cne [string]$envelope.closure.$field) { throw "MIR 4 capsule manifest/envelope $field mismatch." }
  }
  foreach ($binding in @(
    [pscustomobject]@{ path = 'tools/commands/package/Build-MIRPackage.ps1'; field = 'canonical_builder_sha256' },
    [pscustomobject]@{ path = 'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1'; field = 'reconstruction_runner_sha256' }
  )) {
    $memberRows = @($manifest.members | Where-Object { [string]$_.path -ceq [string]$binding.path })
    if ($memberRows.Count -ne 1 -or [string]$memberRows[0].sha256 -cne [string]$manifest.($binding.field)) {
      throw "MIR 4 capsule executable closure does not bind $($binding.path)."
    }
  }
  foreach ($binding in @(
    [pscustomobject]@{ path = 'tools/lib/validation/PackageIdentity.ps1'; expected = [string]$envelope.package_membership.authority_sha256 },
    [pscustomobject]@{ path = 'tools/lib/mir4/BootstrapMaterialization.ps1'; expected = [string]$envelope.package_membership.capsule_tool_sha256 }
  )) {
    $memberRows = @($manifest.members | Where-Object { [string]$_.path -ceq [string]$binding.path })
    if ($memberRows.Count -ne 1 -or [string]$memberRows[0].sha256 -cne [string]$binding.expected) {
      throw "MIR 4 capsule package-membership closure does not bind $($binding.path)."
    }
  }

  $toolchainText = Read-MIR4ArchiveText -Path $CapsulePath -RelativePath '.mir/capsule/toolchain-lock.json'
  if (-not ($toolchainText | Test-Json -SchemaFile (Join-Path $SchemaRoot 'mir4-bootstrap-toolchain-lock.schema.json'))) {
    throw 'MIR 4 capsule toolchain lock schema validation failed.'
  }
  $toolchain = $toolchainText | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $toolchain) -or
      [string]$toolchain.record_sha256 -cne [string]$manifest.toolchain_lock_record_sha256 -or
      [string]$toolchain.record_sha256 -cne [string]$envelope.closure.toolchain_lock_record_sha256) {
    throw 'MIR 4 capsule toolchain lock binding mismatch.'
  }
  $gitText = Read-MIR4ArchiveText -Path $CapsulePath -RelativePath '.mir/capsule/git/source-identity.json'
  if (-not ($gitText | Test-Json -SchemaFile (Join-Path $SchemaRoot 'mir4-bootstrap-git-source-proof.schema.json'))) {
    throw 'MIR 4 capsule Git source proof schema validation failed.'
  }
  $gitProof = $gitText | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $gitProof) -or
      [string]$gitProof.record_sha256 -cne [string]$manifest.git_source_proof_record_sha256 -or
      [string]$gitProof.record_sha256 -cne [string]$envelope.closure.git_source_proof_record_sha256 -or
      [string]$gitProof.candidate_commit -cne [string]$envelope.source.candidate_commit -or
      [string]$gitProof.source_tree -cne [string]$envelope.source.source_tree) {
    throw 'MIR 4 capsule Git source proof binding mismatch.'
  }
  $null = Assert-MIR4BootstrapCapsuleManifestClosure -Manifest $manifest -GitProof $gitProof -Lane $lane
  $commitBytes = Read-MIR4ArchiveBytes -Path $CapsulePath -RelativePath ([string]$gitProof.commit.payload_path)
  if ((Get-MIR4GitObjectSha1 -Type commit -Bytes $commitBytes) -cne [string]$gitProof.commit.sha1 -or
      (Get-MIR4Sha256Bytes -Bytes $commitBytes) -cne [string]$gitProof.commit.sha256 -or
      [long]$commitBytes.Length -ne [long]$gitProof.commit.bytes) {
    throw 'MIR 4 capsule raw Git commit proof differs.'
  }
  $commitText = [Text.UTF8Encoding]::new($false, $true).GetString($commitBytes)
  $treeMatches = [Text.RegularExpressions.Regex]::Matches($commitText, '(?m)^tree ([a-f0-9]{40})$')
  if ($treeMatches.Count -ne 1 -or [string]$treeMatches[0].Groups[1].Value -cne [string]$gitProof.source_tree) {
    throw 'MIR 4 capsule raw Git commit does not bind its declared source tree.'
  }
  $treeMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($tree in @($gitProof.tree_objects)) {
    $treeBytes = Read-MIR4ArchiveBytes -Path $CapsulePath -RelativePath ([string]$tree.payload_path)
    if ((Get-MIR4GitObjectSha1 -Type tree -Bytes $treeBytes) -cne [string]$tree.sha1 -or
        (Get-MIR4Sha256Bytes -Bytes $treeBytes) -cne [string]$tree.sha256 -or
        [long]$treeBytes.Length -ne [long]$tree.bytes) {
      throw "MIR 4 capsule raw Git tree proof differs: $($tree.sha1)"
    }
    $treeMap.Add([string]$tree.sha1, @(Read-MIR4GitTreeObject -Bytes $treeBytes))
  }
  if (-not $treeMap.ContainsKey([string]$gitProof.source_tree)) { throw 'MIR 4 capsule raw Git proof omits its root tree.' }
  $packagePaths = @()
  foreach ($root in @(Get-MIRPackageSourceRoots)) {
    $packagePaths += @($inventory.entries.path | Where-Object { [string]$_ -ceq $root -or ([string]$_).StartsWith("$root/", [StringComparison]::Ordinal) })
  }
  $packagePathSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($relative in $packagePaths) { $null = $packagePathSet.Add([string]$relative) }
  $packagePathList = [Collections.Generic.List[string]]::new()
  foreach ($relative in $packagePathSet) { $packagePathList.Add($relative) }
  $packagePathList.Sort([StringComparer]::Ordinal)
  $packagePaths = @($packagePathList)
  if (($packagePaths -join '|') -cne (@($gitProof.package_files.path) -join '|')) {
    throw 'MIR 4 capsule Git proof is not total over package-visible source membership.'
  }
  foreach ($file in @($gitProof.package_files)) {
    $fileBytes = Read-MIR4ArchiveBytes -Path $CapsulePath -RelativePath ([string]$file.path)
    if ((Get-MIR4GitObjectSha1 -Type blob -Bytes $fileBytes) -cne [string]$file.blob_sha1 -or
        (Get-MIR4Sha256Bytes -Bytes $fileBytes) -cne [string]$file.sha256 -or
        [long]$fileBytes.Length -ne [long]$file.bytes) {
      throw "MIR 4 capsule Git blob proof differs: $($file.path)"
    }
    $segments = @([string]$file.path -split '/')
    $treeId = [string]$gitProof.source_tree
    for ($index = 0; $index -lt $segments.Count; $index++) {
      if (-not $treeMap.ContainsKey($treeId)) { throw "MIR 4 capsule Git proof omits a tree for $($file.path)." }
      $matches = @($treeMap[$treeId] | Where-Object { [string]$_.name -ceq [string]$segments[$index] })
      if ($matches.Count -ne 1) { throw "MIR 4 capsule Git proof does not uniquely traverse $($file.path)." }
      $entry = $matches[0]
      if ($index -lt $segments.Count - 1) {
        if ([string]$entry.mode -cne '40000') { throw "MIR 4 capsule Git proof has a non-tree path segment for $($file.path)." }
        $treeId = [string]$entry.object_id
      } elseif ([string]$entry.mode -cne [string]$file.mode -or [string]$entry.object_id -cne [string]$file.blob_sha1) {
        throw "MIR 4 capsule Git proof leaf differs for $($file.path)."
      }
    }
  }
  return [pscustomobject][ordered]@{
    envelope = $envelope
    manifest = $manifest
    inventory = $inventory
    toolchain_lock = $toolchain
    git_source_proof = $gitProof
  }
}

function New-MIR4BootstrapSourceCapsule {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('emergency', 'local-playtest-shadow')]
    [string]$Lane = 'emergency',
    [ValidatePattern('^[A-Z]$')]
    [string]$CapsuleId = 'A'
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $output = [IO.Path]::GetFullPath($OutputRoot)
  $output = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build/mir4') -Path $output
  $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $output
  if (-not (Test-Path -LiteralPath $output -PathType Container)) { New-Item -ItemType Directory -Force -Path $output | Out-Null }
  $validTarget = if ($Lane -ceq 'emergency') {
    [string]$Target.target_key -ceq 'f210' -and [string]$Target.admission -ceq 'admitted-local-emergency-lane'
  } else {
    [string]$Target.target_key -cin @('f200', 'f110', 'f100') -and [string]$Target.admission -ceq 'non-authoritative-shadow-blocked-by-eol'
  }
  if (-not $validTarget) {
    throw "[mir4-entry-gate] Capsule V2 construction target is not admitted by lane '$Lane'."
  }
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
  # git archive otherwise honors host core.autocrlf while producing ZIP payloads.
  # Force LF/no-conversion and let the raw Git-blob proof reject any remaining
  # attribute-level transformation.
  [string[]]$archiveArgs = @('-c', 'core.autocrlf=false', '-c', 'core.eol=lf', '-C', $repo, 'archive', '--format=zip', '--prefix=source/', "--output=$gitArchive", [string]$Target.source.candidate_commit, '--') + @($existingRoots)
  & git @archiveArgs
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $gitArchive -PathType Leaf)) {
    throw "git archive failed for $($Target.target_key)."
  }

  $extractContainer = Join-Path $workRoot 'extract'
  Expand-MIR4SafeArchive -ArchivePath $gitArchive -Destination $extractContainer -OutputRoot $output
  $capsuleRoot = Join-Path $extractContainer 'source'
  Assert-MIR4SourceTreeSafe -SourceRoot $capsuleRoot

  foreach ($relative in @((Get-MIR4BootstrapCapsuleControllerPaths) + (Get-MIR4BootstrapCapsuleAuthorityPaths -Lane $Lane) + (Get-MIR4BootstrapCapsuleSchemaPaths -Lane $Lane))) {
    Copy-MIR4CapsuleClosureFile -RepoRoot $repo -CapsuleRoot $capsuleRoot -RelativePath $relative
  }

  $toolchainLock = New-MIR4BootstrapToolchainLock -PwshPath (Get-Process -Id $PID).Path
  $toolchainLockPath = Join-Path $capsuleRoot '.mir/capsule/toolchain-lock.json'
  $null = Write-MIR4BootstrapRecord -Record $toolchainLock -Path $toolchainLockPath
  $gitProof = New-MIR4GitSourceProof `
    -RepoRoot $repo `
    -Commit ([string]$Target.source.candidate_commit) `
    -ExpectedTree ([string]$Target.source.source_tree) `
    -CapsuleRoot $capsuleRoot
  $instructionsPath = Join-Path $capsuleRoot '.mir/capsule/RECONSTRUCT.md'
  [IO.File]::WriteAllText(
    $instructionsPath,
    "MIR 4 bootstrap source capsule V2.`n`nRun the detached Invoke-MIR4BootstrapCapsule.ps1 with this capsule, its detached envelope, the exact predecessor archive, the exact bound PowerShell home, and a new output root. No repository checkout argument is accepted.`n",
    [Text.UTF8Encoding]::new($false)
  )

  $manifestRelative = '.mir/capsule/manifest.json'
  $members = @()
  foreach ($item in @(Get-ChildItem -LiteralPath $capsuleRoot -Recurse -File -Force)) {
    $relative = [IO.Path]::GetRelativePath($capsuleRoot, $item.FullName).Replace('\', '/')
    if ($relative -ceq $manifestRelative) { throw 'A stale recursive capsule manifest exists in the staging tree.' }
    $identity = Get-MIR4RawFileIdentity -Path $item.FullName
    $members += [pscustomobject][ordered]@{
      path = $relative
      role = Get-MIR4CapsuleMemberRole -RelativePath $relative
      bytes = [long]$identity.bytes
      sha256 = [string]$identity.sha256
    }
  }
  $memberMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($member in $members) { $memberMap.Add([string]$member.path, $member) }
  $orderedMemberPaths = [Collections.Generic.List[string]]::new()
  foreach ($relative in $memberMap.Keys) { $orderedMemberPaths.Add($relative) }
  $orderedMemberPaths.Sort([StringComparer]::Ordinal)
  $members = @($orderedMemberPaths | ForEach-Object { $memberMap[[string]$_] })
  $memberFields = [ordered]@{}
  $authorityFields = [ordered]@{}
  foreach ($member in $members) {
    $memberFields[[string]$member.path] = "$([string]$member.role)|$([long]$member.bytes)|$([string]$member.sha256)"
    if ([string]$member.role -ceq 'authority') { $authorityFields[[string]$member.path] = [string]$member.sha256 }
  }
  $payloadRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-payload.v1' -Fields $memberFields
  $authorityClosureRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-authority.v1' -Fields $authorityFields
  $builderIdentity = Get-MIR4RawFileIdentity -Path (Join-Path $capsuleRoot 'tools/commands/package/Build-MIRPackage.ps1')
  $runnerIdentity = Get-MIR4RawFileIdentity -Path (Join-Path $capsuleRoot 'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1')
  $targetDescriptor = [ordered]@{
    target_key = [string]$Target.target_key
    factorio_line = [string]$Target.factorio_line
    distribution_version = [string]$Target.distribution_version
    source = $Target.source
    predecessor = $Target.predecessor
  }
  $correctionBinding = $null
  if ($null -ne $Target.PSObject.Properties['correction_authority']) {
    $correctionPath = Join-Path $repo ([string]$Target.correction_authority.path)
    $correction = Get-Content -Raw -LiteralPath $correctionPath | ConvertFrom-Json -Depth 100 -DateKind String
    if (-not (Test-MIR4BootstrapRecordHash -Record $correction) -or
        [string]$correction.record_sha256 -cne [string]$Target.correction_authority.record_sha256) {
      throw '[mir4-approved-delta] Capsule construction received a stale correction binding.'
    }
    $correctionBinding = [pscustomobject][ordered]@{
      path = [string]$Target.correction_authority.path
      kind = [string]$correction.kind
      finding = [string]$correction.finding
      record_sha256 = [string]$correction.record_sha256
    }
    $targetDescriptor.correction_authority = $correctionBinding
  }
  $laneBinding = $null
  if ($Lane -ceq 'local-playtest-shadow') {
    $laneRelativePath = '.mir/releases/waves/mir4-r0/MIR4-Local-Playtest-Shadow-AuthorizationV1.json'
    $lanePath = Join-Path $repo $laneRelativePath
    $laneText = Get-Content -Raw -LiteralPath $lanePath
    if (-not ($laneText | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-local-playtest-shadow-authorization.schema.json'))) {
      throw '[mir4-local-playtest-shadow] The lane authorization fails its exact schema.'
    }
    $laneAuthority = $laneText | ConvertFrom-Json -Depth 100 -DateKind String
    if (-not (Test-MIR4BootstrapRecordHash -Record $laneAuthority)) {
      throw '[mir4-local-playtest-shadow] The lane authorization self-hash is stale.'
    }
    $laneTargets = @($laneAuthority.authorized_targets | Where-Object { [string]$_.target_key -ceq [string]$Target.target_key })
    if ($laneTargets.Count -ne 1 -or
        [string]$laneTargets[0].source_commit -cne [string]$Target.source.candidate_commit -or
        [string]$laneTargets[0].source_tree -cne [string]$Target.source.source_tree -or
        [string]$laneTargets[0].predecessor_archive_sha256 -cne [string]$Target.predecessor.archive_sha256) {
      throw '[mir4-local-playtest-shadow] The target is not exactly bound by the private lane authorization.'
    }
    $laneBinding = [pscustomobject][ordered]@{
      path = $laneRelativePath
      kind = [string]$laneAuthority.kind
      authority_family = [string]$laneAuthority.authority_family
      record_sha256 = [string]$laneAuthority.record_sha256
    }
    $targetDescriptor.local_lane_authority = $laneBinding
  }
  $manifest = [pscustomobject][ordered]@{
    schema = 2
    kind = 'MIR4BootstrapCapsuleManifestV2'
    status = 'local-unpublished-closed-construction-input'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    lane = $Lane
    target = [pscustomobject]$targetDescriptor
    package_membership_authority = 'tools/lib/validation/PackageIdentity.ps1#Get-MIRPackageSourceRoots'
    member_count = [int]$members.Count
    members = $members
    payload_root_sha256 = $payloadRoot
    authority_closure_root_sha256 = $authorityClosureRoot
    git_source_proof_record_sha256 = [string]$gitProof.record_sha256
    toolchain_lock_record_sha256 = [string]$toolchainLock.record_sha256
    canonical_builder_sha256 = [string]$builderIdentity.sha256
    reconstruction_runner_sha256 = [string]$runnerIdentity.sha256
    record_sha256 = ''
  }
  $manifestPath = Join-Path $capsuleRoot $manifestRelative
  $null = Write-MIR4BootstrapRecord -Record $manifest -Path $manifestPath
  $capsuleContentRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-content.v1' -Fields ([ordered]@{
    payload_root_sha256 = $payloadRoot
    internal_manifest_record_sha256 = [string]$manifest.record_sha256
  })

  $capsulePath = Join-Path $targetRoot 'source-capsule.zip'
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $capsuleRoot -EntryRoot 'mir4-source-capsule' -OutputPath $capsulePath -ContainmentRoot $output
  $inventory = Get-MIR4ArchiveInventory -Path $capsulePath
  if ([string]$inventory.root -cne 'mir4-source-capsule') {
    throw "MIR 4 source capsules require the exact archive root 'mir4-source-capsule'; got '$($inventory.root)'."
  }
  $runnerSidecarPath = Join-Path $targetRoot 'Invoke-MIR4BootstrapCapsule.ps1'
  Copy-Item -LiteralPath (Join-Path $capsuleRoot 'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1') -Destination $runnerSidecarPath
  $recordFields = [ordered]@{
    schema = 2
    kind = 'MIR4BootstrapSourceCapsuleV2'
    status = 'local-unpublished-input'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    public_output_authorized = $false
    lane = $Lane
    target_key = [string]$Target.target_key
    factorio_line = [string]$Target.factorio_line
    distribution_version = [string]$Target.distribution_version
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
    closure = [pscustomobject][ordered]@{
      internal_manifest_record_sha256 = [string]$manifest.record_sha256
      payload_root_sha256 = $payloadRoot
      capsule_content_root_sha256 = $capsuleContentRoot
      authority_closure_root_sha256 = $authorityClosureRoot
      git_source_proof_record_sha256 = [string]$gitProof.record_sha256
      toolchain_lock_record_sha256 = [string]$toolchainLock.record_sha256
      canonical_builder_sha256 = [string]$builderIdentity.sha256
      reconstruction_runner_sha256 = [string]$runnerIdentity.sha256
    }
    bootstrap_runner = [pscustomobject][ordered]@{
      capsule_path = 'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1'
      detached_path = 'Invoke-MIR4BootstrapCapsule.ps1'
      sha256 = [string]$runnerIdentity.sha256
      bytes = [long]$runnerIdentity.bytes
    }
    capsule = [pscustomobject][ordered]@{
      path = 'source-capsule.zip'
      archive_sha256 = $inventory.archive_sha256
      content_sha256 = $inventory.content_sha256
      bytes = $inventory.bytes
      entry_count = $inventory.entry_count
    }
  }
  if ($null -ne $correctionBinding) { $recordFields.correction_authority = $correctionBinding }
  if ($null -ne $laneBinding) { $recordFields.local_lane_authority = $laneBinding }
  $recordFields.record_sha256 = ''
  $record = [pscustomobject]$recordFields
  $recordPath = Join-Path $targetRoot 'source-capsule.json'
  $null = Write-MIR4BootstrapRecord -Record $record -Path $recordPath
  if (Get-Command Test-Json -ErrorAction SilentlyContinue) {
    $schemaPath = Join-Path $repo 'spec/schemas/mir4-bootstrap-source-capsule.schema.json'
    if (-not ((Get-Content -Raw -LiteralPath $recordPath) | Test-Json -SchemaFile $schemaPath)) {
      throw "Generated MIR 4 source capsule record failed schema validation for $($Target.target_key)/$CapsuleId."
    }
  }
  Remove-MIR4BuildTree -OutputRoot $output -Path $workRoot
  return [pscustomobject][ordered]@{
    archive_path = $capsulePath
    record_path = $recordPath
    runner_path = $runnerSidecarPath
    record = $record
  }
}
