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

  if ([string]$Correction.kind -cne 'MIR4ApprovedBootstrapCorrectionDeltaV2' -or
      (@($Correction.findings | Sort-Object) -join '+') -cne 'MIR3-TERM-0032+MIR3-TERM-0033' -or
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
  $findingIdentity = @($Correction.findings | Sort-Object) -join '+'
  $result = [pscustomobject][ordered]@{
    equivalent = $equivalent
    policy = 'MIR4BootstrapApprovedCorrectionEquivalenceV1'
    correction_kind = [string]$Correction.kind
    correction_record_sha256 = [string]$Correction.record_sha256
    finding = $findingIdentity
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
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateRange(1, 100000)][int]$MaxEntries = 4096,
    [ValidateRange(1, 2147483647)][long]$MaxEntryBytes = 268435456,
    [ValidateRange(1, 9223372036854775807)][long]$MaxExpandedBytes = 1073741824
  )

  $inventory = Get-MIR4ArchiveInventory -Path $ArchivePath -MaxEntries $MaxEntries -MaxEntryBytes $MaxEntryBytes -MaxExpandedBytes $MaxExpandedBytes
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
