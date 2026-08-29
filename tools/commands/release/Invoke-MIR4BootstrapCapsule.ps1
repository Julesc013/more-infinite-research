param(
  [Parameter(Mandatory)][string]$CapsulePath,
  [Parameter(Mandatory)][string]$EnvelopePath,
  [Parameter(Mandatory)][string]$PredecessorPath,
  [Parameter(Mandatory)][string]$ToolchainRoot,
  [Parameter(Mandatory)][string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$invariantCulture = [Globalization.CultureInfo]::InvariantCulture
[Threading.Thread]::CurrentThread.CurrentCulture = $invariantCulture
[Threading.Thread]::CurrentThread.CurrentUICulture = $invariantCulture

function Get-RawSha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-BytesSha256([byte[]]$Bytes) {
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '') }
  finally { $algorithm.Dispose() }
}

function ConvertTo-CanonicalValue($Value) {
  if ($Value -is [string]) {
    if ($Value -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') {
      return [DateTime]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    }
    if ($Value -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?[+-]\d{2}:\d{2}$') {
      return [DateTimeOffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    }
    return $Value
  }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in $Value.Keys) { $result[$key] = ConvertTo-CanonicalValue $Value[$key] }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) { $result[$property.Name] = ConvertTo-CanonicalValue $property.Value }
    return [pscustomobject]$result
  }
  if ($Value -is [Collections.IEnumerable]) {
    $items = [Collections.Generic.List[object]]::new()
    foreach ($item in $Value) { $items.Add((ConvertTo-CanonicalValue $item)) }
    return ,$items.ToArray()
  }
  return $Value
}

function ConvertTo-CanonicalJson($Value) {
  $canonicalValue = ConvertTo-CanonicalValue $Value
  return (($canonicalValue | ConvertTo-Json -Depth 100 -Compress) -replace "`r`n", "`n" -replace "`r", "`n")
}

function Get-RecordSha256($Record) {
  $unsigned = [ordered]@{}
  foreach ($property in $Record.PSObject.Properties) {
    if ($property.Name -ne 'record_sha256') { $unsigned[$property.Name] = $property.Value }
  }
  return Get-BytesSha256 -Bytes ([Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-CanonicalJson ([pscustomobject]$unsigned))))
}

function Assert-Record($Record, [string]$Kind) {
  if ([string]$Record.kind -cne $Kind -or [string]$Record.record_sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$Record.record_sha256 -cne (Get-RecordSha256 $Record)) {
    throw "Invalid or stale $Kind record."
  }
}

function Assert-Exact([object]$Actual, [object]$Expected, [string]$Context) {
  if ([string]$Actual -cne [string]$Expected) { throw "$Context mismatch." }
}

function Assert-SafeRelativePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z0-9._/-]+$' -or
      $Path.StartsWith('/') -or $Path.Contains('\') -or $Path.Contains(':') -or $Path.Contains('//') -or
      $Path -match '(^|/)\.{1,2}(/|$)') {
    throw "Unsafe capsule-relative path: $Path"
  }
  foreach ($segment in @($Path -split '/')) {
    if ([string]::IsNullOrEmpty($segment) -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) {
      throw "Capsule paths cannot contain empty or trailing-dot/space segments: $Path"
    }
    if ($segment -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)') {
      throw "Capsule paths cannot contain a DOS device alias: $Path"
    }
  }
}

function Add-SafeCapsulePath([Collections.Generic.Dictionary[string, string]]$PathMap, [string]$Path) {
  Assert-SafeRelativePath $Path
  $key = $Path.ToLowerInvariant()
  if ($PathMap.ContainsKey($key)) { throw "Duplicate or ordinal-case-colliding capsule members: $($PathMap[$key]) and $Path" }
  $segments = @($key -split '/')
  for ($index = 1; $index -lt $segments.Count; $index++) {
    $ancestorKey = @($segments[0..($index - 1)]) -join '/'
    if ($PathMap.ContainsKey($ancestorKey)) { throw "Capsule file/prefix collision: $($PathMap[$ancestorKey]) and $Path" }
  }
  foreach ($existingKey in $PathMap.Keys) {
    if ($existingKey.StartsWith("$key/", [StringComparison]::Ordinal)) { throw "Capsule file/prefix collision: $Path and $($PathMap[$existingKey])" }
  }
  $PathMap.Add($key, $Path)
}

function Assert-Descendant([string]$Root, [string]$Path) {
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  $pathFull = [IO.Path]::GetFullPath($Path)
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if (-not $pathFull.StartsWith($rootFull, $comparison)) { throw "Capsule output escapes its construction root: $pathFull" }
  return $pathFull
}

function Assert-NoReparseAncestors([string]$Root, [string]$Path) {
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
  $pathFull = Assert-Descendant $rootFull $Path
  $cursor = $rootFull
  foreach ($segment in @([IO.Path]::GetRelativePath($rootFull, $pathFull) -split '[\\/]')) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.') { continue }
    $cursor = Join-Path $cursor $segment
    if (Test-Path -LiteralPath $cursor) {
      $item = Get-Item -LiteralPath $cursor -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Capsule output traverses a reparse point: $cursor"
      }
    }
  }
}

function Assert-NoReparsePathChain([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  $pathRoot = [IO.Path]::GetPathRoot($full)
  $cursor = $pathRoot
  $relative = [IO.Path]::GetRelativePath($pathRoot, $full)
  foreach ($segment in @($relative -split '[\\/]')) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.') { continue }
    $cursor = Join-Path $cursor $segment
    if (-not (Test-Path -LiteralPath $cursor)) { continue }
    $item = Get-Item -LiteralPath $cursor -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Capsule output path traverses a reparse point: $cursor"
    }
  }
}

function Get-EntryBytes([IO.Compression.ZipArchiveEntry]$Entry, [long]$MaximumBytes = 268435456) {
  if ([long]$Entry.Length -lt 0 -or [long]$Entry.Length -gt $MaximumBytes) {
    throw "Capsule member exceeds its bounded expanded size: $($Entry.FullName)"
  }
  $stream = $Entry.Open()
  $memory = [IO.MemoryStream]::new()
  $buffer = [byte[]]::new(65536)
  [long]$total = 0
  try {
    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
      $total += $read
      if ($total -gt $MaximumBytes -or $total -gt [long]$Entry.Length) {
        throw "Capsule member expanded beyond its declared or bounded size: $($Entry.FullName)"
      }
      $memory.Write($buffer, 0, $read)
    }
    if ($total -ne [long]$Entry.Length) { throw "Capsule member expanded length differs from its central-directory identity: $($Entry.FullName)" }
    return ,([byte[]]$memory.ToArray())
  } finally {
    $memory.Dispose()
    $stream.Dispose()
  }
}

function Copy-EntryBounded([IO.Compression.ZipArchiveEntry]$Entry, [IO.Stream]$Target, [long]$MaximumBytes = 268435456) {
  if ([long]$Entry.Length -lt 0 -or [long]$Entry.Length -gt $MaximumBytes) {
    throw "Capsule member exceeds its bounded expanded size: $($Entry.FullName)"
  }
  $input = $Entry.Open()
  $buffer = [byte[]]::new(65536)
  [long]$total = 0
  try {
    while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
      $total += $read
      if ($total -gt $MaximumBytes -or $total -gt [long]$Entry.Length) {
        throw "Capsule member expanded beyond its declared or bounded size: $($Entry.FullName)"
      }
      $Target.Write($buffer, 0, $read)
    }
    if ($total -ne [long]$Entry.Length) { throw "Capsule member expanded length differs from its central-directory identity: $($Entry.FullName)" }
  } finally {
    $input.Dispose()
  }
}

$capsule = (Resolve-Path -LiteralPath $CapsulePath).Path
$envelopeFile = (Resolve-Path -LiteralPath $EnvelopePath).Path
$predecessor = (Resolve-Path -LiteralPath $PredecessorPath).Path
$toolchain = (Resolve-Path -LiteralPath $ToolchainRoot).Path
$output = [IO.Path]::GetFullPath($OutputRoot)
if ([IO.Path]::GetPathRoot($output).TrimEnd('\', '/') -eq $output.TrimEnd('\', '/')) { throw 'A filesystem root is not a valid capsule output.' }
Assert-NoReparsePathChain $output
if (Test-Path -LiteralPath $output) {
  $existing = @(Get-ChildItem -LiteralPath $output -Force)
  if ($existing.Count -ne 0) { throw 'The capsule reconstruction output root must be new or empty.' }
} else {
  New-Item -ItemType Directory -Path $output | Out-Null
}
Assert-NoReparsePathChain $output
if (((Get-Item -LiteralPath $output -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
  throw 'The capsule reconstruction output root cannot be a reparse point.'
}

$envelopeText = [IO.File]::ReadAllText($envelopeFile, [Text.UTF8Encoding]::new($false, $true))
$envelope = $envelopeText | ConvertFrom-Json -Depth 100 -DateKind String
Assert-Record $envelope 'MIR4BootstrapSourceCapsuleV2'
$lane = [string]$envelope.lane
$validTarget = if ($lane -ceq 'emergency') {
  [string]$envelope.target_key -ceq 'f210'
} elseif ($lane -ceq 'local-playtest-shadow') {
  [string]$envelope.target_key -cin @('f200', 'f110', 'f100')
} else { $false }
if ([int]$envelope.schema -ne 2 -or [string]$envelope.status -cne 'local-unpublished-input' -or
    [bool]$envelope.public_output_authorized -ne $false -or -not $validTarget) {
  throw 'The capsule runner received an envelope outside the two bounded unpublished construction lanes.'
}
if ($lane -ceq 'emergency' -and $null -eq $envelope.PSObject.Properties['correction_authority']) {
  throw 'The f210 capsule envelope must bind the approved MIR3-TERM-0033 correction.'
}
if ($lane -ceq 'local-playtest-shadow' -and $null -ne $envelope.PSObject.Properties['correction_authority']) {
  throw 'A lower-target local-playtest capsule cannot inherit the f210 correction authority.'
}
if ($lane -ceq 'local-playtest-shadow' -and $null -eq $envelope.PSObject.Properties['local_lane_authority']) {
  throw 'A lower-target local-playtest capsule must bind the private lane authority.'
}
if ($lane -ceq 'emergency' -and $null -ne $envelope.PSObject.Properties['local_lane_authority']) {
  throw 'The f210 emergency capsule cannot inherit the lower-target private lane authority.'
}
Assert-Exact (Get-RawSha256 $capsule) $envelope.capsule.archive_sha256 'Capsule archive hash'
Assert-Exact (Get-Item -LiteralPath $capsule).Length $envelope.capsule.bytes 'Capsule byte count'
if ([long](Get-Item -LiteralPath $capsule).Length -gt 536870912) { throw 'The capsule archive exceeds its bounded compressed size.' }
Assert-Exact (Get-RawSha256 $predecessor) $envelope.predecessor.archive_sha256 'Predecessor archive hash'
Assert-Exact (Get-Item -LiteralPath $predecessor).Length $envelope.predecessor.bytes 'Predecessor byte count'
Assert-Exact (Get-RawSha256 $PSCommandPath) $envelope.bootstrap_runner.sha256 'Detached runner hash'
Assert-Exact (Get-Item -LiteralPath $PSCommandPath).Length $envelope.bootstrap_runner.bytes 'Detached runner byte count'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($capsule)
$entryMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$portablePathMap = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
try {
  if ($zip.Entries.Count -eq 0) { throw 'The capsule archive is empty.' }
  if ($zip.Entries.Count -gt 4096) { throw 'The capsule archive exceeds the bounded entry count.' }
  [long]$expandedBytes = 0
  foreach ($entry in $zip.Entries) {
    if ([long]$entry.Length -gt 268435456) { throw "A capsule member exceeds the bounded expanded size: $($entry.FullName)" }
    $expandedBytes += [long]$entry.Length
    if ($expandedBytes -gt 1073741824) { throw 'The capsule archive exceeds the bounded total expanded size.' }
    $name = [string]$entry.FullName
    Assert-SafeRelativePath $name
    if ([string]::IsNullOrEmpty($entry.Name)) { throw "Directory entries are forbidden in a capsule: $name" }
    if ([int64]$entry.ExternalAttributes -ne 0) { throw "Non-regular ZIP attributes are forbidden in a capsule: $name" }
    if (-not $name.StartsWith('mir4-source-capsule/', [StringComparison]::Ordinal)) { throw "Unexpected capsule root: $name" }
    $relative = $name.Substring('mir4-source-capsule/'.Length)
    Add-SafeCapsulePath $portablePathMap $relative
    $entryMap.Add($relative, $entry)
  }

  $manifestRelative = '.mir/capsule/manifest.json'
  if (-not $entryMap.ContainsKey($manifestRelative)) { throw 'The capsule-internal manifest is absent.' }
  $manifestBytes = Get-EntryBytes -Entry $entryMap[$manifestRelative] -MaximumBytes 8388608
  $manifestText = [Text.UTF8Encoding]::new($false, $true).GetString($manifestBytes)
  $manifest = $manifestText | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-Record $manifest 'MIR4BootstrapCapsuleManifestV2'
  if ([int]$manifest.schema -ne 2 -or [string]$manifest.lane -cne $lane -or [string]$manifest.target.target_key -cne [string]$envelope.target_key) { throw 'Unexpected capsule-internal manifest authority.' }
  Assert-Exact $manifest.record_sha256 $envelope.closure.internal_manifest_record_sha256 'Internal manifest binding'
  Assert-Exact $manifest.target.target_key $envelope.target_key 'Internal manifest target'
  Assert-Exact $manifest.target.factorio_line $envelope.factorio_line 'Internal manifest Factorio line'
  Assert-Exact $manifest.target.distribution_version $envelope.distribution_version 'Internal manifest distribution version'
  Assert-Exact (ConvertTo-CanonicalJson $manifest.target.source) (ConvertTo-CanonicalJson $envelope.source) 'Internal manifest source authority'
  Assert-Exact (ConvertTo-CanonicalJson $manifest.target.predecessor) (ConvertTo-CanonicalJson $envelope.predecessor) 'Internal manifest predecessor authority'
  if ($lane -ceq 'emergency') {
    Assert-Exact (ConvertTo-CanonicalJson $manifest.target.correction_authority) (ConvertTo-CanonicalJson $envelope.correction_authority) 'Internal manifest correction authority'
  } elseif ($null -ne $manifest.target.PSObject.Properties['correction_authority']) {
    throw 'The lower-target internal manifest inherited an f210 correction binding.'
  }
  if ($lane -ceq 'local-playtest-shadow') {
    Assert-Exact (ConvertTo-CanonicalJson $manifest.target.local_lane_authority) (ConvertTo-CanonicalJson $envelope.local_lane_authority) 'Internal manifest local lane authority'
  } elseif ($null -ne $manifest.target.PSObject.Properties['local_lane_authority']) {
    throw 'The f210 internal manifest inherited a lower-target lane binding.'
  }

  $expectedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $null = $expectedPaths.Add($manifestRelative)
  $lastPath = ''
  foreach ($member in @($manifest.members)) {
    $relative = [string]$member.path
    Assert-SafeRelativePath $relative
    if ($relative -ceq $manifestRelative -or (-not [string]::IsNullOrEmpty($lastPath) -and [StringComparer]::Ordinal.Compare($lastPath, $relative) -ge 0)) {
      throw 'Capsule member manifest paths are duplicated, recursive, or not ordinally ordered.'
    }
    $lastPath = $relative
    if (-not $expectedPaths.Add($relative) -or -not $entryMap.ContainsKey($relative)) { throw "Capsule member is absent or duplicated: $relative" }
    $bytes = Get-EntryBytes $entryMap[$relative]
    Assert-Exact $bytes.Length $member.bytes "Capsule member bytes $relative"
    Assert-Exact (Get-BytesSha256 $bytes) $member.sha256 "Capsule member hash $relative"
  }
  if ($expectedPaths.Count -ne $entryMap.Count) { throw 'The capsule contains a member outside its signed internal manifest.' }
  foreach ($relative in $entryMap.Keys) {
    if (-not $expectedPaths.Contains($relative)) { throw "Unmanifested capsule member: $relative" }
  }

  $workspace = Join-Path $output 'workspace'
  New-Item -ItemType Directory -Path $workspace | Out-Null
  foreach ($relative in @($entryMap.Keys | Sort-Object -CaseSensitive)) {
    $destination = Assert-Descendant $workspace (Join-Path $workspace $relative)
    Assert-NoReparseAncestors $workspace $destination
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Assert-NoReparseAncestors $workspace $destination
    $target = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { Copy-EntryBounded -Entry $entryMap[$relative] -Target $target } finally { $target.Dispose() }
  }
} finally {
  $zip.Dispose()
}

$workspace = Join-Path $output 'workspace'
. (Join-Path $workspace 'tools/lib/mir4/BootstrapMaterialization.ps1')
if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) { throw 'The bound PowerShell toolchain does not provide Test-Json.' }
$schemaRoot = Join-Path $workspace 'spec/schemas'
foreach ($schemaProbe in @(
  [pscustomobject]@{ text = $envelopeText; schema = 'mir4-bootstrap-source-capsule.schema.json'; label = 'detached envelope' },
  [pscustomobject]@{ text = $manifestText; schema = 'mir4-bootstrap-capsule-manifest.schema.json'; label = 'internal manifest' }
)) {
  if (-not ($schemaProbe.text | Test-Json -SchemaFile (Join-Path $schemaRoot $schemaProbe.schema))) {
    throw "Capsule $($schemaProbe.label) schema validation failed."
  }
}
if (-not (Test-MIR4BootstrapRecordHash -Record $envelope)) {
  throw 'The detached envelope differs under the capsule-owned canonicalization authority.'
}

$correction = $null
if ($lane -ceq 'emergency') {
  $correctionRelativePath = [string]$envelope.correction_authority.path
  Assert-SafeRelativePath $correctionRelativePath
  $correctionPath = Assert-Descendant $workspace (Join-Path $workspace $correctionRelativePath)
  if (-not (Test-Path -LiteralPath $correctionPath -PathType Leaf)) {
    throw 'The capsule omits its bound approved correction authority.'
  }
  $correctionText = Get-Content -Raw -LiteralPath $correctionPath
  if (-not ($correctionText | Test-Json -SchemaFile (Join-Path $schemaRoot 'mir4-approved-bootstrap-correction-delta-v2.schema.json'))) {
    throw 'The capsule approved correction authority fails its exact schema.'
  }
  $correction = $correctionText | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-Record $correction 'MIR4ApprovedBootstrapCorrectionDeltaV2'
  Assert-Exact (@($correction.findings | Sort-Object) -join '+') 'MIR3-TERM-0032+MIR3-TERM-0033' 'Approved correction findings'
  Assert-Exact $correction.target_key $envelope.target_key 'Approved correction target'
  Assert-Exact $correction.record_sha256 $envelope.correction_authority.record_sha256 'Approved correction record binding'
  Assert-Exact $correction.kind $envelope.correction_authority.kind 'Approved correction kind binding'
  Assert-Exact (@($correction.findings | Sort-Object) -join '+') $envelope.correction_authority.finding 'Approved correction finding binding'
}
$laneAuthority = $null
if ($lane -ceq 'local-playtest-shadow') {
  $laneRelativePath = [string]$envelope.local_lane_authority.path
  Assert-SafeRelativePath $laneRelativePath
  $lanePath = Assert-Descendant $workspace (Join-Path $workspace $laneRelativePath)
  $laneText = Get-Content -Raw -LiteralPath $lanePath
  if (-not ($laneText | Test-Json -SchemaFile (Join-Path $schemaRoot 'mir4-private-lane-authorization-v2.schema.json'))) {
    throw 'The private local-playtest lane authority fails its exact schema.'
  }
  $laneAuthority = $laneText | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-Record $laneAuthority 'MIR4PrivateLaneAuthorizationV2'
  Assert-Exact $laneAuthority.authority_family 'MIRLocalArtifactLaneAuthorizationV1' 'Local lane authority family'
  Assert-Exact $laneAuthority.record_sha256 $envelope.local_lane_authority.record_sha256 'Local lane record binding'
  Assert-Exact $laneAuthority.kind $envelope.local_lane_authority.kind 'Local lane kind binding'
  Assert-Exact $laneAuthority.authority_family $envelope.local_lane_authority.authority_family 'Local lane family binding'
  $laneTargets = @($laneAuthority.authorized_targets | Where-Object { [string]$_.target_key -ceq [string]$envelope.target_key })
  if ($laneTargets.Count -ne 1) { throw 'The private lane does not uniquely authorize this target.' }
  Assert-Exact $laneTargets[0].source_commit $envelope.source.candidate_commit 'Local lane source commit'
  Assert-Exact $laneTargets[0].source_tree $envelope.source.source_tree 'Local lane source tree'
  Assert-Exact $laneTargets[0].predecessor_archive_sha256 $envelope.predecessor.archive_sha256 'Local lane predecessor archive'
  foreach ($import in @($laneAuthority.imports.PSObject.Properties.Value)) {
    $importPath = Assert-Descendant $workspace (Join-Path $workspace ([string]$import.path))
    Assert-Exact (Get-RawSha256 $importPath) $import.file_sha256 "Local lane import $($import.path)"
    if ($null -ne $import.PSObject.Properties['record_sha256']) {
      $importRecord = Get-Content -Raw -LiteralPath $importPath | ConvertFrom-Json -Depth 100 -DateKind String
      Assert-Exact $importRecord.record_sha256 $import.record_sha256 "Local lane record import $($import.path)"
    }
  }
}

$capsuleInventory = Get-MIR4ArchiveInventory -Path $capsule
Assert-Exact $capsuleInventory.root 'mir4-source-capsule' 'Capsule archive root'
Assert-Exact $capsuleInventory.content_sha256 $envelope.capsule.content_sha256 'Capsule canonical content hash'
Assert-Exact $capsuleInventory.entry_count $envelope.capsule.entry_count 'Capsule entry count'
$internalRunnerPath = Join-Path $workspace 'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1'
Assert-Exact (Get-RawSha256 $internalRunnerPath) $envelope.closure.reconstruction_runner_sha256 'Capsule-internal runner hash'

$manifestPath = Join-Path $workspace '.mir/capsule/manifest.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100 -DateKind String
if (-not (Test-MIR4BootstrapRecordHash -Record $manifest)) { throw 'Capsule-internal manifest self-hash mismatch after extraction.' }
if ([int]$manifest.member_count -ne @($manifest.members).Count) { throw 'Capsule-internal manifest member count is inconsistent.' }
$memberFields = [ordered]@{}
$authorityFields = [ordered]@{}
foreach ($member in @($manifest.members)) {
  $memberFields[[string]$member.path] = "$([string]$member.role)|$([long]$member.bytes)|$([string]$member.sha256)"
  if ([string]$member.role -ceq 'authority') { $authorityFields[[string]$member.path] = [string]$member.sha256 }
}
$payloadRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-payload.v1' -Fields $memberFields
$authorityRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-authority.v1' -Fields $authorityFields
Assert-Exact $payloadRoot $manifest.payload_root_sha256 'Capsule payload root'
Assert-Exact $payloadRoot $envelope.closure.payload_root_sha256 'Envelope payload root'
Assert-Exact $authorityRoot $manifest.authority_closure_root_sha256 'Capsule authority closure root'
Assert-Exact $authorityRoot $envelope.closure.authority_closure_root_sha256 'Envelope authority closure root'
Assert-Exact $manifest.git_source_proof_record_sha256 $envelope.closure.git_source_proof_record_sha256 'Manifest Git proof closure'
Assert-Exact $manifest.toolchain_lock_record_sha256 $envelope.closure.toolchain_lock_record_sha256 'Manifest toolchain closure'
Assert-Exact $manifest.canonical_builder_sha256 $envelope.closure.canonical_builder_sha256 'Manifest canonical builder closure'
Assert-Exact $manifest.reconstruction_runner_sha256 $envelope.closure.reconstruction_runner_sha256 'Manifest reconstruction runner closure'
$capsuleContentRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-content.v1' -Fields ([ordered]@{
  payload_root_sha256 = $payloadRoot
  internal_manifest_record_sha256 = [string]$manifest.record_sha256
})
Assert-Exact $capsuleContentRoot $envelope.closure.capsule_content_root_sha256 'Capsule content root'

$toolchainLockPath = Join-Path $workspace '.mir/capsule/toolchain-lock.json'
$toolchainLock = Get-Content -Raw -LiteralPath $toolchainLockPath | ConvertFrom-Json -Depth 100 -DateKind String
$toolchainLockText = Get-Content -Raw -LiteralPath $toolchainLockPath
if (-not ($toolchainLockText | Test-Json -SchemaFile (Join-Path $schemaRoot 'mir4-bootstrap-toolchain-lock.schema.json')) -or
    [string]$toolchainLock.kind -cne 'MIR4BootstrapToolchainLockV1' -or -not (Test-MIR4BootstrapRecordHash -Record $toolchainLock)) {
  throw 'Capsule toolchain lock is invalid.'
}
Assert-Exact $toolchainLock.record_sha256 $manifest.toolchain_lock_record_sha256 'Manifest toolchain lock'
Assert-Exact $toolchainLock.record_sha256 $envelope.closure.toolchain_lock_record_sha256 'Envelope toolchain lock'
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if (-not [string]::Equals($toolchain, (Resolve-Path -LiteralPath $PSHOME).Path, $comparison)) { throw 'The supplied toolchain root is not the executing PowerShell home.' }
Assert-Exact $PSVersionTable.PSVersion $toolchainLock.powershell_version 'PowerShell version'
Assert-Exact ([Environment]::Version) $toolchainLock.dotnet_runtime_version '.NET runtime version'
Assert-Exact ([Environment]::OSVersion.Platform) $toolchainLock.os_platform 'OS platform'
Assert-Exact ([Environment]::OSVersion.Version) $toolchainLock.os_version 'OS version'
Assert-Exact ([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture) $toolchainLock.process_architecture 'Process architecture'
$executingPwshName = [IO.Path]::GetFileName((Get-Process -Id $PID).Path)
if (-not [string]::Equals($executingPwshName, [string]$toolchainLock.executable, $comparison)) {
  throw 'PowerShell executable mismatch.'
}
Assert-Exact $toolchainLock.execution_culture 'InvariantCulture' 'Reconstruction execution culture authority'
Assert-Exact ([Threading.Thread]::CurrentThread.CurrentCulture.Name) '' 'Reconstruction current culture'
Assert-Exact ([Threading.Thread]::CurrentThread.CurrentUICulture.Name) '' 'Reconstruction current UI culture'
$actualToolchain = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$actualCaseKeys = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
if (((Get-Item -LiteralPath $toolchain -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
  throw 'The executing toolchain root cannot be a reparse point.'
}
foreach ($item in @(Get-ChildItem -LiteralPath $toolchain -Recurse -Force)) {
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "The executing toolchain contains a reparse point: $($item.FullName)" }
  if ($item.PSIsContainer) { continue }
  $relative = [IO.Path]::GetRelativePath($toolchain, $item.FullName).Replace('\', '/')
  Assert-SafeRelativePath $relative
  $caseKey = $relative.ToLowerInvariant()
  if ($actualCaseKeys.ContainsKey($caseKey)) { throw "Case-colliding executing toolchain paths: $($actualCaseKeys[$caseKey]) and $relative" }
  $actualCaseKeys.Add($caseKey, $relative)
  $actualToolchain.Add($relative, $item)
}
Assert-Exact $actualToolchain.Count $toolchainLock.file_count 'Bound toolchain file count'
Assert-Exact @($toolchainLock.files).Count $toolchainLock.file_count 'Toolchain lock row count'
$expectedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$toolchainFields = [ordered]@{}
[long]$toolchainBytes = 0
$lastToolchainPath = ''
foreach ($row in @($toolchainLock.files)) {
  $relative = [string]$row.path
  Assert-SafeRelativePath $relative
  if (-not [string]::IsNullOrEmpty($lastToolchainPath) -and [StringComparer]::Ordinal.Compare($lastToolchainPath, $relative) -ge 0) {
    throw 'Bound toolchain paths are duplicated or not ordinally ordered.'
  }
  $lastToolchainPath = $relative
  if (-not $expectedPaths.Add($relative) -or -not $actualToolchain.ContainsKey($relative)) { throw "Bound toolchain file is absent or duplicated: $relative" }
  $path = $actualToolchain[$relative].FullName
  $rawBytes = [long]$actualToolchain[$relative].Length
  $rawHash = Get-RawSha256 $path
  Assert-Exact $rawHash $row.sha256 "Bound toolchain hash $relative"
  Assert-Exact $rawBytes $row.bytes "Bound toolchain bytes $relative"
  $toolchainFields[$relative] = "$rawBytes|$rawHash"
  $toolchainBytes += $rawBytes
}
foreach ($relative in $actualToolchain.Keys) {
  if (-not $expectedPaths.Contains($relative)) { throw "Executing toolchain contains an unbound file: $relative" }
}
$toolchainContentRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.toolchain-content.v1' -Fields $toolchainFields
Assert-Exact $toolchainBytes $toolchainLock.total_bytes 'Bound toolchain total bytes'
Assert-Exact $toolchainContentRoot $toolchainLock.content_root_sha256 'Bound toolchain content root'

$gitProofPath = Join-Path $workspace '.mir/capsule/git/source-identity.json'
$gitProofText = Get-Content -Raw -LiteralPath $gitProofPath
if (-not ($gitProofText | Test-Json -SchemaFile (Join-Path $schemaRoot 'mir4-bootstrap-git-source-proof.schema.json'))) {
  throw 'Capsule Git source proof schema validation failed.'
}
$gitProof = $gitProofText | ConvertFrom-Json -Depth 100 -DateKind String
$null = Assert-MIR4GitSourceProof -CapsuleRoot $workspace -Proof $gitProof
$null = Assert-MIR4BootstrapCapsuleManifestClosure -Manifest $manifest -GitProof $gitProof -Lane $lane
Assert-Exact $gitProof.record_sha256 $manifest.git_source_proof_record_sha256 'Manifest Git source proof'
Assert-Exact $gitProof.record_sha256 $envelope.closure.git_source_proof_record_sha256 'Envelope Git source proof'
Assert-Exact $gitProof.candidate_commit $envelope.source.candidate_commit 'Envelope source commit'
Assert-Exact $gitProof.source_tree $envelope.source.source_tree 'Envelope source tree'

$packageIdentityPath = Join-Path $workspace 'tools/lib/validation/PackageIdentity.ps1'
$capsuleAuthorityPath = Join-Path $workspace 'tools/lib/mir4/BootstrapMaterialization.ps1'
Assert-Exact (Get-RawSha256 $packageIdentityPath) $envelope.package_membership.authority_sha256 'Package-membership authority member hash'
Assert-Exact (Get-RawSha256 $capsuleAuthorityPath) $envelope.package_membership.capsule_tool_sha256 'Capsule authority member hash'

$infoPath = Join-Path $workspace 'info.json'
$info = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json -DateKind String
Assert-Exact $info.version $envelope.predecessor.release 'Capsule predecessor version'
Assert-Exact $info.factorio_version $envelope.factorio_line 'Capsule Factorio line'
$predecessorInventory = Get-MIR4ArchiveInventory -Path $predecessor
foreach ($field in @('archive_sha256', 'content_sha256', 'bytes', 'entry_count')) {
  Assert-Exact $predecessorInventory.$field $envelope.predecessor.$field "Predecessor $field"
}

Set-MIR4InfoVersion -InfoPath $infoPath -Version ([string]$envelope.distribution_version)
$builderPath = Join-Path $workspace 'tools/commands/package/Build-MIRPackage.ps1'
Assert-Exact (Get-RawSha256 $builderPath) $envelope.closure.canonical_builder_sha256 'Canonical builder hash'
& $builderPath -OutputDir 'build/capsule-output' *> $null
$packageName = "more-infinite-research_$($envelope.distribution_version)"
$builtPath = Join-Path $workspace "build/capsule-output/$packageName.zip"
if (-not (Test-Path -LiteralPath $builtPath -PathType Leaf)) { throw 'The canonical package builder did not emit the expected candidate.' }
$candidateInventory = Get-MIR4ArchiveInventory -Path $builtPath
$equivalenceArguments = @{
  CandidatePath = $builtPath
  PredecessorPath = $predecessor
  ExpectedCandidateVersion = [string]$envelope.distribution_version
  ExpectedPredecessorVersion = [string]$envelope.predecessor.release
  ExpectedCandidateRoot = $packageName
  ExpectedPredecessorRoot = "more-infinite-research_$($envelope.predecessor.release)"
  ThrowOnDifference = $true
}
$equivalence = if ($null -ne $correction) {
  Compare-MIR4BootstrapCorrectedCandidate @equivalenceArguments -Correction $correction
} else {
  Compare-MIR4BootstrapCandidate @equivalenceArguments
}

$candidatePath = Join-Path $output 'candidate.zip'
Copy-Item -LiteralPath $builtPath -Destination $candidatePath
$packageRows = @($candidateInventory.entries | ForEach-Object { "$($_.path)|$($_.bytes)|$($_.raw_sha256)" })
$packageManifestSha256 = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.package-manifest.v1' -Fields ([ordered]@{ entries = $packageRows })
$equivalenceSha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $equivalence)
$inputFields = [ordered]@{
  capsule_content_root_sha256 = [string]$envelope.closure.capsule_content_root_sha256
  envelope_record_sha256 = [string]$envelope.record_sha256
  predecessor_archive_sha256 = [string]$predecessorInventory.archive_sha256
  toolchain_lock_record_sha256 = [string]$toolchainLock.record_sha256
}
if ($null -ne $correction) { $inputFields.correction_record_sha256 = [string]$correction.record_sha256 }
if ($null -ne $laneAuthority) { $inputFields.local_lane_authority_record_sha256 = [string]$laneAuthority.record_sha256 }
$inputRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.reconstruction-input.v1' -Fields $inputFields
$resultRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.reconstruction-result.v1' -Fields ([ordered]@{
  candidate_archive_sha256 = [string]$candidateInventory.archive_sha256
  candidate_content_sha256 = [string]$candidateInventory.content_sha256
  package_manifest_sha256 = $packageManifestSha256
  equivalence_sha256 = $equivalenceSha256
})
$receipt = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4BootstrapCapsuleReconstructionReceiptV1'
  status = 'passed'
  canonicalization = 'MIR4BootstrapCanonicalJsonV1'
  lane = $lane
  target_key = [string]$envelope.target_key
  factorio_line = [string]$envelope.factorio_line
  distribution_version = [string]$envelope.distribution_version
  mode = 'capsule-local-fresh-process'
  capsule_only = $true
  checkout_argument_supplied = $false
  source_capsule_record_sha256 = [string]$envelope.record_sha256
  source_capsule_archive_sha256 = [string]$capsuleInventory.archive_sha256
  capsule_content_root_sha256 = [string]$envelope.closure.capsule_content_root_sha256
  toolchain_lock_record_sha256 = [string]$toolchainLock.record_sha256
  predecessor = [pscustomobject][ordered]@{
    archive_sha256 = [string]$predecessorInventory.archive_sha256
    content_sha256 = [string]$predecessorInventory.content_sha256
    bytes = [long]$predecessorInventory.bytes
    entry_count = [int]$predecessorInventory.entry_count
  }
  candidate = [pscustomobject][ordered]@{
    archive_sha256 = [string]$candidateInventory.archive_sha256
    content_sha256 = [string]$candidateInventory.content_sha256
    bytes = [long]$candidateInventory.bytes
    entry_count = [int]$candidateInventory.entry_count
  }
  package_manifest_sha256 = $packageManifestSha256
  equivalence_sha256 = $equivalenceSha256
  equivalence = $equivalence
  input_root_sha256 = $inputRoot
  result_root_sha256 = $resultRoot
  record_sha256 = ''
}
if ($null -ne $correction) {
  $receipt | Add-Member -NotePropertyName correction_authority -NotePropertyValue ([pscustomobject][ordered]@{
    path = [string]$envelope.correction_authority.path
    kind = [string]$correction.kind
    finding = (@($correction.findings | Sort-Object) -join '+')
    record_sha256 = [string]$correction.record_sha256
  })
}
if ($null -ne $laneAuthority) {
  $receipt | Add-Member -NotePropertyName local_lane_authority -NotePropertyValue ([pscustomobject][ordered]@{
    path = [string]$envelope.local_lane_authority.path
    kind = [string]$laneAuthority.kind
    authority_family = [string]$laneAuthority.authority_family
    record_sha256 = [string]$laneAuthority.record_sha256
  })
}
$receiptPath = Join-Path $output 'reconstruction.json'
$null = Write-MIR4BootstrapRecord -Record $receipt -Path $receiptPath
if (-not ((Get-Content -Raw -LiteralPath $receiptPath) | Test-Json -SchemaFile (Join-Path $schemaRoot 'mir4-bootstrap-reconstruction-receipt.schema.json'))) {
  throw 'Generated capsule reconstruction receipt failed schema validation.'
}

[pscustomobject][ordered]@{
  status = 'passed'
  candidate_path = 'candidate.zip'
  receipt_path = 'reconstruction.json'
  candidate_archive_sha256 = [string]$candidateInventory.archive_sha256
  receipt_record_sha256 = [string]$receipt.record_sha256
} | ConvertTo-Json -Compress
