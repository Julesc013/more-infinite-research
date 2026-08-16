param(
  [string]$RepoRoot = "",
  [switch]$Check
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot "tools\lib\validation\PackageIdentity.ps1")
Add-Type -AssemblyName System.IO.Compression.FileSystem

$release = "3.2.10"
$baselineDirectory = Join-Path $RepoRoot ".mir\releases\terminal\baselines\$release"
$compositionPath = Join-Path $baselineDirectory "package-composition.json"
$snapshotPath = Join-Path $baselineDirectory "normalized-snapshot.json"
$manifestPath = Join-Path $baselineDirectory "baseline-manifest.json"
$closurePath = Join-Path $RepoRoot ".mir\releases\terminal\closures\$release.json"

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

function Write-Or-CheckJson([string]$Path, $Value) {
  $bytes = ConvertTo-CanonicalJsonBytes $Value
  if ($Check) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Tracked generated authority is absent: $(Get-RelativePath $Path)" }
    $actual = [IO.File]::ReadAllBytes($Path)
    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$actual, [byte[]]$bytes)) {
      throw "Tracked generated authority is stale: $(Get-RelativePath $Path)"
    }
    return
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  [IO.File]::WriteAllBytes($Path, $bytes)
}

function Get-FileBinding([string]$RelativePath, [string]$Role) {
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Continuation input is absent: $RelativePath" }
  return [ordered]@{
    logical_path = "authority/$($RelativePath.Replace('\','/'))"
    source_path = $RelativePath.Replace("\", "/")
    sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    bytes = [long](Get-Item -LiteralPath $path).Length
    role = $Role
  }
}

function Get-ZipComposition([string]$Path) {
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $roots = @($zip.Entries | ForEach-Object { ($_.FullName -split '/')[0] } | Sort-Object -Unique)
    if ($roots.Count -ne 1) { throw "Expected one package root in $(Get-RelativePath $Path)." }
    $files = foreach ($entry in @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object FullName)) {
      $stream = $entry.Open()
      try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace("-", "") } finally { $sha.Dispose() }
      } finally { $stream.Dispose() }
      [ordered]@{
        path = $entry.FullName.Substring($roots[0].Length + 1)
        sha256 = $hash
        bytes = [long]$entry.Length
        compressed_bytes = [long]$entry.CompressedLength
      }
    }
    return [ordered]@{root=$roots[0];files=@($files);entries=@($files).Count}
  } finally { $zip.Dispose() }
}

$releaseRecordPath = ".mir/releases/records/3.2.10.json"
$publicationPath = ".mir/evidence/terminal-publication/2026-08-16/github/3.2.10.json"
$qualificationPath = ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixLocalQualificationV1.json"
$sourceFreezePath = ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixSourceFreezeV1.json"
$reconstructionPath = ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixCandidateReconstructionV1.json"
$overridePath = ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixMaintainerReleaseOverrideV1.json"
$findingPath = ".mir/releases/emergency/findings/MIR3-TERM-0033.json"
$foundationManifestPath = ".mir/releases/terminal/baselines/3.2.9/baseline-manifest.json"
$foundationSnapshotPath = ".mir/releases/terminal/baselines/3.2.9/normalized-snapshot.json"

$releaseRecord = Read-Json $releaseRecordPath
$publication = Read-Json $publicationPath
$qualification = Read-Json $qualificationPath
$foundationManifest = Read-Json $foundationManifestPath
$foundationSnapshot = Read-Json $foundationSnapshotPath
$finding = Read-Json $findingPath
$distRelativePath = "dist/more-infinite-research_3.2.10.zip"
$distPath = Join-Path $RepoRoot $distRelativePath
if (-not (Test-Path -LiteralPath $distPath -PathType Leaf)) { throw "Published 3.2.10 distribution is absent." }

$archiveSha = (Get-FileHash -LiteralPath $distPath -Algorithm SHA256).Hash.ToUpperInvariant()
$contentSha = Get-MIRZipContentFingerprint -Path $distPath
$archiveBytes = [long](Get-Item -LiteralPath $distPath).Length
$composition = Get-ZipComposition $distPath
if ([string]$releaseRecord.state -cne "publicly-verified" -or [string]$publication.status -cne "published-and-verified" -or
    $archiveSha -cne [string]$releaseRecord.package.archive_sha256 -or $archiveSha -cne [string]$publication.download_sha256 -or
    $contentSha -cne [string]$releaseRecord.package.content_sha256 -or $archiveBytes -ne [long]$releaseRecord.package.bytes -or
    [int]$composition.entries -ne [int]$releaseRecord.package.entries) {
  throw "Published 3.2.10 identity does not match its append-only release record."
}

$compositionRecord = Add-RecordSha256 ([ordered]@{
  schema = 1
  kind = "MIR3PostTerminalHotfixPackageCompositionV1"
  release = $release
  root_directory = [string]$composition.root
  archive_sha256 = $archiveSha
  content_sha256 = $contentSha
  bytes = $archiveBytes
  entries = [int]$composition.entries
  forbidden_package_surfaces_absent = $true
  files = @($composition.files)
})
Write-Or-CheckJson $compositionPath $compositionRecord

$closureRecord = Add-RecordSha256 ([ordered]@{
  schema = 1
  kind = "Mir3TerminalReleaseClosureV1"
  release = $release
  status = "github-closed-mod-portal-pending"
  package_visible = $false
  frozen_manifest = [ordered]@{path=$sourceFreezePath;sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot $sourceFreezePath) -Algorithm SHA256).Hash.ToUpperInvariant()}
  review = [ordered]@{path=$overridePath;sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot $overridePath) -Algorithm SHA256).Hash.ToUpperInvariant();decision="maintainer-accepted-release-specific-override"}
  seal = [ordered]@{path=$reconstructionPath;sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot $reconstructionPath) -Algorithm SHA256).Hash.ToUpperInvariant();status="deterministically-reconstructed"}
  tag = [ordered]@{name=[string]$publication.tag.name;object_sha=[string]$publication.tag.object_sha;peeled_commit=[string]$publication.tag.peeled_commit;immutable=[bool]$publication.tag.immutable}
  github = [ordered]@{receipt=$publicationPath;status=[string]$publication.status;release_url=[string]$publication.github_release.url;download_sha256=[string]$publication.download_sha256}
  mod_portal = [ordered]@{state="maintainer-upload-not-independently-custody-verified";authenticated_redownload="pending"}
  final_channel_state = "github-published-and-verified-mod-portal-custody-pending"
})
Write-Or-CheckJson $closurePath $closureRecord

$snapshotRecord = Add-RecordSha256 ([ordered]@{
  schema = 1
  kind = "MIR4TerminalNormalizedSnapshotV1"
  status = "importable-pre-eol-public-custody-pending"
  semantic_authority = $false
  release = $release
  target = "2.1"
  successor_target = "MIR4-R0/2.1"
  source_identity = [ordered]@{
    candidate_id = [string]$releaseRecord.candidate_id
    candidate_commit = [string]$releaseRecord.package.source_commit
    source_tree = [string]$releaseRecord.package.source_tree
    common_source_commit = [string]$foundationSnapshot.source_identity.common_source_commit
  }
  distribution = [ordered]@{path=$distRelativePath;archive_sha256=$archiveSha;content_sha256=$contentSha;bytes=$archiveBytes;entries=[int]$composition.entries;tag=[string]$publication.tag.name}
  engine = [ordered]@{version=[string]$qualification.factorio_version;executable_sha256=[string]$qualification.engine_binary_sha256;qualification=$qualificationPath;status="maintainer-accepted-release-specific-exact-engine-lock"}
  predecessors = @(
    [ordered]@{release="3.2.9";role="immutable-terminal-predecessor";upgrade_id="3.2.9-to-3.2.10"},
    [ordered]@{release="3.2.5";role="older-governed-predecessor";upgrade_id="3.2.5-to-3.2.10"}
  )
  foundation = [ordered]@{release="3.2.9";manifest=$foundationManifestPath;root_sha256=[string]$foundationManifest.input_root_sha256}
  inventories = [ordered]@{
    features = [ordered]@{foundation_snapshot=$foundationSnapshotPath;package_composition=(Get-RelativePath $compositionPath);disposition="3.2.9-plus-approved-emergency-delta"}
    technologies = [ordered]@{foundation_snapshot=$foundationSnapshotPath;emergency_delta=".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixChangeSetV1.json";open_follow_up=$findingPath;stable_ids_preserved=$true}
    settings = [ordered]@{foundation_snapshot=$foundationSnapshotPath;emergency_delta=".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixChangeSetV1.json";released_id_or_type_changes=0;codec="MIRSET1"}
    owners_aliases_tombstones = [ordered]@{foundation_snapshot=$foundationSnapshotPath;emergency_delta=".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixChangeSetV1.json";required_mir4_follow_up="MIR3-TERM-0033"}
    migrations = [ordered]@{foundation_snapshot=$foundationSnapshotPath;watermark=[ordered]@{from=@("3.2.9","3.2.5","3.2.3");stable_ids=$true;to="3.2.10"}}
    locales = [ordered]@{foundation_snapshot=$foundationSnapshotPath;package_composition=(Get-RelativePath $compositionPath)}
    runtime_profiles = [ordered]@{foundation_snapshot=$foundationSnapshotPath;qualification=$qualificationPath;target_backend="storage"}
    upgrades = [ordered]@{qualification=$qualificationPath;required=@("3.2.9-to-3.2.10","3.2.5-to-3.2.10","3.2.3-to-3.2.10")}
  }
  capability_omissions = @($foundationSnapshot.capability_omissions)
  compatibility_import = [ordered]@{authority=[string]$foundationSnapshot.compatibility_import.authority;level_counts=$foundationSnapshot.compatibility_import.level_counts;public_claims_allowed=[int]$foundationSnapshot.compatibility_import.public_claims_allowed;promoted_claims=0;rule="preserve-3.2.9-claim-envelope-and-add-no-hotfix-claims"}
})
Write-Or-CheckJson $snapshotPath $snapshotRecord

$authorityInputs = @(
  $releaseRecordPath,
  $publicationPath,
  $qualificationPath,
  $sourceFreezePath,
  $reconstructionPath,
  $overridePath,
  $findingPath,
  ".mir/evidence/terminal-publication/2026-08-16/runtime/3.2.10-base-competitor-rollback.json",
  ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixAuthorizationV1.json",
  ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixProgrammeV1.json",
  ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixChangeSetV1.json",
  ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixTargetMatrixV1.json",
  ".mir/releases/emergency/findings/MIR3-TERM-0032.json",
  ".mir/releases/deltas/3.2.9-to-3.2.10.json",
  ".mir/releases/transitions/3.2.10-c34-manually-accepted.json",
  ".mir/releases/transitions/3.2.10-c34-tagged.json",
  ".mir/releases/transitions/3.2.10-c34-published.json",
  ".mir/releases/transitions/3.2.10-c34-publicly-verified.json",
  "docs/releases/notes/release-notes-3.2.10.md",
  $foundationManifestPath,
  $foundationSnapshotPath,
  ".mir/releases/terminal/baselines/3.2.9/package-composition.json",
  "tools/commands/release/New-MIR3PostTerminalHotfixBaselineContinuation.ps1",
  "spec/schemas/mir3-post-terminal-hotfix-baseline-continuation.schema.json",
  (Get-RelativePath $compositionPath),
  (Get-RelativePath $snapshotPath),
  (Get-RelativePath $closurePath)
)
$files = foreach ($path in @($authorityInputs | Sort-Object -Unique)) {
  $role = if ($path -eq (Get-RelativePath $snapshotPath)) { "normalized-import-snapshot" } elseif ($path -eq (Get-RelativePath $compositionPath)) { "hotfix-package-composition" } elseif ($path -eq (Get-RelativePath $closurePath)) { "release-closure" } elseif ($path -eq $foundationManifestPath) { "immutable-3.2.9-foundation" } else { "post-terminal-hotfix-authority" }
  Get-FileBinding $path $role
}
$inputMaterial = (@($files) | ForEach-Object { "$($_.logical_path)`0$($_.sha256)`0$($_.bytes)" }) -join "`n"
$manifestRecord = Add-RecordSha256 ([ordered]@{
  schema = 1
  kind = "MIR3PostTerminalHotfixBaselineContinuationV1"
  release = $release
  target = "2.1"
  status = "captured-public-custody-pending-open-mir4-follow-up"
  package_visible = $false
  capture_tool = [ordered]@{path="tools/commands/release/New-MIR3PostTerminalHotfixBaselineContinuation.ps1";version="1";sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot "tools/commands/release/New-MIR3PostTerminalHotfixBaselineContinuation.ps1") -Algorithm SHA256).Hash.ToUpperInvariant()}
  foundation = [ordered]@{release="3.2.9";manifest=$foundationManifestPath;root_sha256=[string]$foundationManifest.input_root_sha256;retained_as_immutable_historical_snapshot=$true}
  distribution = $snapshotRecord.distribution
  input_root_sha256 = Get-MIRStringSha256 -Value $inputMaterial
  files = @($files)
  normalized_snapshot = @($files | Where-Object source_path -eq (Get-RelativePath $snapshotPath))[0]
  public_custody = [ordered]@{github="published-and-verified";mod_portal="maintainer-upload-not-independently-custody-verified";authenticated_redownload="pending"}
  continuation = [ordered]@{supersedes_for_factorio_2_1_predecessor="3.2.9";preserves_historical_baseline=$true;required_mir4_follow_up="MIR3-TERM-0033";factorio_2_0_predecessor="2.5.9"}
  completion = [ordered]@{state="captured-for-mir4-predecessor-refresh";required_files_present=$true;exact_engine_lock_bound=$true;open_findings=@("MIR3-TERM-0033");mir4_behavioral_proof_required=$true}
})
Write-Or-CheckJson $manifestPath $manifestRecord

$schemaPath = Join-Path $RepoRoot "spec\schemas\mir3-post-terminal-hotfix-baseline-continuation.schema.json"
if (-not ((Get-Content -Raw -LiteralPath $manifestPath) | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
  throw "Generated 3.2.10 continuation manifest failed schema validation."
}
Write-Host "[ok] MIR 3.2.10 terminal baseline continuation: $($manifestRecord.record_sha256)"
