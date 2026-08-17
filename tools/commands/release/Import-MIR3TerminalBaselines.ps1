param(
  [string]$RepoRoot = "",
  [string]$OutputPath = "",
  [switch]$Check
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot ".mir\releases\waves\mir4-r0\terminal-baseline-import.json"
} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot $OutputPath
}

. (Join-Path $RepoRoot "tools\lib\validation\PackageIdentity.ps1")
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-RelativePath([string]$Path) {
  return [IO.Path]::GetRelativePath($RepoRoot, $Path).Replace("\", "/")
}

function Read-Json([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required authority is missing: $RelativePath" }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
}

function ConvertTo-CanonicalJsonBytes($Value) {
  $json = ($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
  return [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
}

function Get-Sha256Bytes([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "") } finally { $sha.Dispose() }
}

function Add-RecordSha256($Material) {
  $record = [ordered]@{}
  foreach ($property in $Material.Keys) { $record[$property] = $Material[$property] }
  $record.record_sha256 = Get-Sha256Bytes (ConvertTo-CanonicalJsonBytes $Material)
  return $record
}

function Assert-RecordSha256($Record, [string]$Context) {
  $material = [ordered]@{}
  foreach ($property in $Record.PSObject.Properties) {
    if ($property.Name -ne "record_sha256") { $material[$property.Name] = $property.Value }
  }
  $expected = Get-Sha256Bytes (ConvertTo-CanonicalJsonBytes $material)
  if ($expected -ne [string]$Record.record_sha256) { throw "$Context self-hash mismatch." }
}

function Get-AuthorityIdentity([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required authority is missing: $RelativePath" }
  return [pscustomobject][ordered]@{
    path = $RelativePath.Replace("\", "/")
    sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
  }
}

function Get-ZipEntryCount([string]$Path) {
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  try { return @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count } finally { $zip.Dispose() }
}

$authorityDirectory = ".mir/releases/waves/mir4-r0"
$requiredKinds = @(
  "MIR4-ProgrammeV1",
  "MIR4-Entry-GateV1",
  "MIR4-Versioning-and-Distribution-Identity-ADRv1",
  "MIR4-Repository-Layout-TransitionV1",
  "MIR4-Target-RegistryV1",
  "MIR4-Terminal-Import-ContractV1",
  "MIR4-Terminal-Import-ContractV2",
  "MIR4-Equivalence-PolicyV1",
  "MIR4-Emergency-LaneV1",
  "MIR4-Offline-Release-AuthorityV1",
  "MIR3-to-MIR4-Governance-ReconciliationV1",
  "MIR4-Terminal-Predecessor-RefreshV1",
  "MIR4-Terminal-Predecessor-RefreshV2"
)
$authorityFiles = @($requiredKinds | ForEach-Object { "$authorityDirectory/$_.json" })
foreach ($path in $authorityFiles) {
  $authority = Read-Json $path
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -ne [IO.Path]::GetFileNameWithoutExtension($path) -or [bool]$authority.package_visible) {
    throw "Invalid MIR 4 R0 authority: $path"
  }
}

$reconciliation = Read-Json "$authorityDirectory/MIR3-to-MIR4-Governance-ReconciliationV1.json"
$entryGate = Read-Json "$authorityDirectory/MIR4-Entry-GateV1.json"
if ([bool]$reconciliation.payload.public_4x_before_eol -or [bool]$entryGate.payload.public_version_4_before_eol -or
    [string]$reconciliation.payload.conflict.eol_policy_clause -ne "publish-valid-4x-distribution") {
  throw "The circular MIR 3 EOL / MIR 4 publication gate is not safely reconciled."
}

$catalogPath = ".mir/releases/terminal/baselines/dot9-family-catalog.json"
$catalog = Read-Json $catalogPath
Assert-RecordSha256 $catalog "Terminal .9 baseline catalog"
if ([string]$catalog.status -ne "all-nine-capture-ready-mod-portal-pending" -or @($catalog.releases).Count -ne 9) {
  throw "Terminal .9 baseline catalog is not import-ready."
}

$allInputs = [Collections.Generic.List[object]]::new()
foreach ($path in @($authorityFiles + @(
  $catalogPath,
  "tools/commands/release/New-MIR3Dot9TerminalBaselines.ps1",
  "tools/commands/release/New-MIR3PostTerminalHotfixBaselineContinuation.ps1",
  "tools/commands/release/New-MIR3Factorio20PostTerminalHotfixBaselineContinuation.ps1",
  "tools/commands/release/Import-MIR3TerminalBaselines.ps1",
  "spec/schemas/mir3-dot9-terminal-baseline-bundle-manifest.schema.json",
  "spec/schemas/mir3-post-terminal-hotfix-baseline-continuation.schema.json",
  "spec/schemas/mir3-factorio-2-0-post-terminal-hotfix-baseline-continuation.schema.json",
  "spec/schemas/mir4-terminal-normalized-snapshot.schema.json",
  "spec/schemas/mir4-terminal-baseline-import.schema.json",
  "spec/schemas/mir4-r0-authority.schema.json",
  ".mir/releases/waves/mir4-r0/MIR4-Target-RegistryV3.json",
  "spec/schemas/mir4-target-registry-v3.schema.json"
))) { $allInputs.Add((Get-AuthorityIdentity $path)) }

$rows = @()
foreach ($catalogRow in @($catalog.releases)) {
  $version = [string]$catalogRow.release
  $manifestPath = [string]$catalogRow.manifest
  $snapshotPath = [string]$catalogRow.normalized_snapshot
  $closurePath = ".mir/releases/terminal/closures/$version.json"
  $manifest = Read-Json $manifestPath
  $snapshot = Read-Json $snapshotPath
  $closure = Read-Json $closurePath
  Assert-RecordSha256 $manifest "$version baseline manifest"
  Assert-RecordSha256 $snapshot "$version normalized snapshot"
  Assert-RecordSha256 $closure "$version release closure"
  if ([string]$manifest.record_sha256 -ne [string]$catalogRow.manifest_record_sha256 -or
      [string]$snapshot.record_sha256 -ne [string]$catalogRow.normalized_snapshot_record_sha256) {
    throw "Catalog binding mismatch for $version."
  }
  if ([bool]$snapshot.semantic_authority -or [string]$snapshot.status -ne "importable-pre-eol-public-custody-pending" -or
      [string]$closure.status -ne "github-closed-mod-portal-pending") {
    throw "Pre-EOL import boundary was weakened for $version."
  }
  foreach ($file in @($manifest.files)) {
    $path = Join-Path $RepoRoot ([string]$file.source_path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() -ne [string]$file.sha256 -or
        [long](Get-Item -LiteralPath $path).Length -ne [long]$file.bytes) {
      throw "Logical bundle input drift for ${version}: $($file.source_path)"
    }
    $allInputs.Add((Get-AuthorityIdentity ([string]$file.source_path)))
  }

  $distPath = Join-Path $RepoRoot ([string]$manifest.distribution.path)
  $archiveSha = (Get-FileHash -LiteralPath $distPath -Algorithm SHA256).Hash.ToUpperInvariant()
  $contentSha = Get-MIRZipContentFingerprint -Path $distPath
  if ($archiveSha -ne [string]$manifest.distribution.archive_sha256 -or
      $contentSha -ne [string]$manifest.distribution.content_sha256 -or
      [long](Get-Item -LiteralPath $distPath).Length -ne [long]$manifest.distribution.bytes -or
      (Get-ZipEntryCount $distPath) -ne [int]$manifest.distribution.entries) {
    throw "Sealed distribution drift for $version."
  }

  foreach ($path in @($manifestPath, $snapshotPath, $closurePath)) { $allInputs.Add((Get-AuthorityIdentity $path)) }
  $rows += [ordered]@{
    release = $version
    target = [string]$snapshot.target
    successor_target = [string]$snapshot.successor_target
    baseline_manifest = [ordered]@{ path=$manifestPath; record_sha256=[string]$manifest.record_sha256; input_root_sha256=[string]$manifest.input_root_sha256; status=[string]$manifest.status }
    normalized_snapshot = [ordered]@{ path=$snapshotPath; record_sha256=[string]$snapshot.record_sha256; semantic_authority=[bool]$snapshot.semantic_authority }
    release_closure = [ordered]@{ path=$closurePath; record_sha256=[string]$closure.record_sha256; status=[string]$closure.status }
    distribution = $snapshot.distribution
    import_disposition = "normalized-shadow-input-no-semantic-authority-before-eol"
    snapshot = $snapshot
  }
}

# The immutable .9 family remains fully captured above. For the current Factorio
# 2.1 predecessor only, replace the executable import row with the append-only
# 3.2.10 emergency continuation. The historical 3.2.9 files remain bound inputs.
$continuationVersion = "3.2.10"
$continuationManifestPath = ".mir/releases/terminal/baselines/$continuationVersion/baseline-manifest.json"
$continuationSnapshotPath = ".mir/releases/terminal/baselines/$continuationVersion/normalized-snapshot.json"
$continuationClosurePath = ".mir/releases/terminal/closures/$continuationVersion.json"
$continuationManifest = Read-Json $continuationManifestPath
$continuationSnapshot = Read-Json $continuationSnapshotPath
$continuationClosure = Read-Json $continuationClosurePath
Assert-RecordSha256 $continuationManifest "$continuationVersion continuation manifest"
Assert-RecordSha256 $continuationSnapshot "$continuationVersion normalized snapshot"
Assert-RecordSha256 $continuationClosure "$continuationVersion release closure"
if ([string]$continuationManifest.kind -cne "MIR3PostTerminalHotfixBaselineContinuationV1" -or
    [string]$continuationManifest.status -cne "captured-public-custody-pending-open-mir4-follow-up" -or
    [bool]$continuationSnapshot.semantic_authority -or
    [string]$continuationSnapshot.status -cne "importable-pre-eol-public-custody-pending" -or
    [string]$continuationClosure.status -cne "github-closed-mod-portal-pending") {
  throw "The 3.2.10 continuation is not import-ready."
}
foreach ($file in @($continuationManifest.files)) {
  $path = Join-Path $RepoRoot ([string]$file.source_path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
      (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$file.sha256 -or
      [long](Get-Item -LiteralPath $path).Length -ne [long]$file.bytes) {
    throw "Logical continuation input drift for ${continuationVersion}: $($file.source_path)"
  }
  $allInputs.Add((Get-AuthorityIdentity ([string]$file.source_path)))
}
$continuationDistPath = Join-Path $RepoRoot ([string]$continuationManifest.distribution.path)
if ((Get-FileHash -LiteralPath $continuationDistPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$continuationManifest.distribution.archive_sha256 -or
    (Get-MIRZipContentFingerprint -Path $continuationDistPath) -cne [string]$continuationManifest.distribution.content_sha256 -or
    [long](Get-Item -LiteralPath $continuationDistPath).Length -ne [long]$continuationManifest.distribution.bytes -or
    (Get-ZipEntryCount $continuationDistPath) -ne [int]$continuationManifest.distribution.entries) {
  throw "Published distribution drift for $continuationVersion."
}
foreach ($path in @($continuationManifestPath, $continuationSnapshotPath, $continuationClosurePath)) {
  $allInputs.Add((Get-AuthorityIdentity $path))
}
$continuationRow = [ordered]@{
  release = $continuationVersion
  target = [string]$continuationSnapshot.target
  successor_target = [string]$continuationSnapshot.successor_target
  baseline_manifest = [ordered]@{path=$continuationManifestPath;record_sha256=[string]$continuationManifest.record_sha256;input_root_sha256=[string]$continuationManifest.input_root_sha256;status=[string]$continuationManifest.status}
  normalized_snapshot = [ordered]@{path=$continuationSnapshotPath;record_sha256=[string]$continuationSnapshot.record_sha256;semantic_authority=[bool]$continuationSnapshot.semantic_authority}
  release_closure = [ordered]@{path=$continuationClosurePath;record_sha256=[string]$continuationClosure.record_sha256;status=[string]$continuationClosure.status}
  distribution = $continuationSnapshot.distribution
  import_disposition = "normalized-shadow-input-no-semantic-authority-before-eol"
  snapshot = $continuationSnapshot
}
$rows = @($continuationRow) + @($rows | Where-Object { [string]$_.release -cne "3.2.9" })

# The Factorio 2.0 predecessor advanced independently after exact applicability,
# deterministic reconstruction, and public-byte verification. Replace only the
# executable f200 import row; retain the immutable 2.5.9 bundle as a bound input.
$f200ContinuationVersion = "2.5.10"
$f200ContinuationManifestPath = ".mir/releases/terminal/baselines/$f200ContinuationVersion/baseline-manifest.json"
$f200ContinuationSnapshotPath = ".mir/releases/terminal/baselines/$f200ContinuationVersion/normalized-snapshot.json"
$f200ContinuationClosurePath = ".mir/releases/terminal/closures/$f200ContinuationVersion.json"
$f200ContinuationManifest = Read-Json $f200ContinuationManifestPath
$f200ContinuationSnapshot = Read-Json $f200ContinuationSnapshotPath
$f200ContinuationClosure = Read-Json $f200ContinuationClosurePath
Assert-RecordSha256 $f200ContinuationManifest "$f200ContinuationVersion continuation manifest"
Assert-RecordSha256 $f200ContinuationSnapshot "$f200ContinuationVersion normalized snapshot"
Assert-RecordSha256 $f200ContinuationClosure "$f200ContinuationVersion release closure"
if ([string]$f200ContinuationManifest.kind -cne "MIR3PostTerminalHotfixBaselineContinuationV1" -or
    [string]$f200ContinuationManifest.status -cne "captured-public-custody-pending-open-mir4-follow-up" -or
    [bool]$f200ContinuationSnapshot.semantic_authority -or
    [string]$f200ContinuationSnapshot.target -cne "2.0" -or
    [string]$f200ContinuationSnapshot.status -cne "importable-pre-eol-public-custody-pending" -or
    [string]$f200ContinuationClosure.status -cne "github-closed-mod-portal-pending") {
  throw "The 2.5.10 continuation is not import-ready."
}
foreach ($file in @($f200ContinuationManifest.files)) {
  $path = Join-Path $RepoRoot ([string]$file.source_path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
      (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$file.sha256 -or
      [long](Get-Item -LiteralPath $path).Length -ne [long]$file.bytes) {
    throw "Logical continuation input drift for ${f200ContinuationVersion}: $($file.source_path)"
  }
  $allInputs.Add((Get-AuthorityIdentity ([string]$file.source_path)))
}
$f200ContinuationDistPath = Join-Path $RepoRoot ([string]$f200ContinuationManifest.distribution.path)
if ((Get-FileHash -LiteralPath $f200ContinuationDistPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$f200ContinuationManifest.distribution.archive_sha256 -or
    (Get-MIRZipContentFingerprint -Path $f200ContinuationDistPath) -cne [string]$f200ContinuationManifest.distribution.content_sha256 -or
    [long](Get-Item -LiteralPath $f200ContinuationDistPath).Length -ne [long]$f200ContinuationManifest.distribution.bytes -or
    (Get-ZipEntryCount $f200ContinuationDistPath) -ne [int]$f200ContinuationManifest.distribution.entries) {
  throw "Published distribution drift for $f200ContinuationVersion."
}
foreach ($path in @($f200ContinuationManifestPath, $f200ContinuationSnapshotPath, $f200ContinuationClosurePath)) {
  $allInputs.Add((Get-AuthorityIdentity $path))
}
$f200ContinuationRow = [ordered]@{
  release = $f200ContinuationVersion
  target = [string]$f200ContinuationSnapshot.target
  successor_target = [string]$f200ContinuationSnapshot.successor_target
  baseline_manifest = [ordered]@{path=$f200ContinuationManifestPath;record_sha256=[string]$f200ContinuationManifest.record_sha256;input_root_sha256=[string]$f200ContinuationManifest.input_root_sha256;status=[string]$f200ContinuationManifest.status}
  normalized_snapshot = [ordered]@{path=$f200ContinuationSnapshotPath;record_sha256=[string]$f200ContinuationSnapshot.record_sha256;semantic_authority=[bool]$f200ContinuationSnapshot.semantic_authority}
  release_closure = [ordered]@{path=$f200ContinuationClosurePath;record_sha256=[string]$f200ContinuationClosure.record_sha256;status=[string]$f200ContinuationClosure.status}
  distribution = $f200ContinuationSnapshot.distribution
  import_disposition = "normalized-shadow-input-no-semantic-authority-before-eol"
  snapshot = $f200ContinuationSnapshot
}
$rows = @($rows | Where-Object { [string]$_.release -ceq "3.2.10" }) + @($f200ContinuationRow) +
  @($rows | Where-Object { [string]$_.release -cnotin @("3.2.10", "2.5.9") })

$inputRows = @($allInputs.ToArray() | Sort-Object path -Unique)
$inputMaterial = ($inputRows | ForEach-Object { "$($_.path)`0$($_.sha256)" }) -join "`n"
$material = [ordered]@{
  schema = 1
  kind = "MIR4TerminalBaselineImportV1"
  status = "ready-for-r0-implementation-public-custody-pending"
  package_visible = $false
  semantic_authority = $false
  source_generation = "MIR4-R0-pre-release"
  distribution_generation = $null
  mir3_eol_status = "pending"
  input_root_sha256 = Get-MIRStringSha256 -Value $inputMaterial
  inputs = $inputRows
  releases = @($rows)
  guarantees = @(
    "all-nine-historical-dot9-distributions-remain-exact-and-bound",
    "factorio-2.1-predecessor-continues-at-exact-public-3.2.10",
    "factorio-2.0-predecessor-continues-at-exact-public-2.5.10",
    "factorio-1.x-and-older-predecessors-remain-dot9",
    "all-nine-current-import-views-self-contained",
    "terminal-claim-maturity-not-promoted",
    "unsupported-target-fields-explicitly-omitted",
    "mir3-remains-semantic-authority-until-eol",
    "no-version-4-package-tag-or-publication-created"
  )
  next_executable_task = "M4-003-local-offline-emergency-lane"
}
$record = Add-RecordSha256 $material
$bytes = ConvertTo-CanonicalJsonBytes $record
if ($Check) {
  if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw "Tracked MIR 4 terminal import is absent: $(Get-RelativePath $OutputPath)" }
  $actual = [IO.File]::ReadAllBytes($OutputPath)
  if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$actual, [byte[]]$bytes)) {
    throw "Tracked MIR 4 terminal import is stale: $(Get-RelativePath $OutputPath)"
  }
  Write-Host "[ok] MIR 4 terminal baseline import is current: $($record.record_sha256)"
  exit 0
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
[IO.File]::WriteAllBytes($OutputPath, $bytes)
Write-Host "[ok] wrote $(Get-RelativePath $OutputPath): $($record.record_sha256)"
