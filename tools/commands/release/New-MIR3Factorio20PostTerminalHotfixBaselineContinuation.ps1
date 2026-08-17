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

. (Join-Path $RepoRoot "tools/lib/validation/PackageIdentity.ps1")
Add-Type -AssemblyName System.IO.Compression.FileSystem

$release = "2.5.10"
$foundationRelease = "2.5.9"
$baselineDirectory = Join-Path $RepoRoot ".mir/releases/terminal/baselines/$release"
$compositionPath = Join-Path $baselineDirectory "package-composition.json"
$snapshotPath = Join-Path $baselineDirectory "normalized-snapshot.json"
$manifestPath = Join-Path $baselineDirectory "baseline-manifest.json"
$closurePath = Join-Path $RepoRoot ".mir/releases/terminal/closures/$release.json"

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
  $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  return [ordered]@{
    logical_path = "authority/$($RelativePath.Replace('\','/'))"
    source_path = $RelativePath.Replace("\", "/")
    sha256 = Get-Sha256Bytes $bytes
    bytes = [long]$bytes.Length
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
      [ordered]@{path=$entry.FullName.Substring($roots[0].Length + 1);sha256=$hash;bytes=[long]$entry.Length;compressed_bytes=[long]$entry.CompressedLength}
    }
    return [ordered]@{root=$roots[0];files=@($files);entries=@($files).Count}
  } finally { $zip.Dispose() }
}

$releaseRecordPath = ".mir/releases/records/2.5.10.json"
$publicationPath = ".mir/evidence/terminal-publication/2026-08-17/github/2.5.10.json"
$authorizationPath = ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixAuthorizationV1.json"
$programmePath = ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixProgrammeV1.json"
$targetMatrixPath = ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixTargetMatrixV1.json"
$foundationManifestPath = ".mir/releases/terminal/baselines/$foundationRelease/baseline-manifest.json"
$foundationSnapshotPath = ".mir/releases/terminal/baselines/$foundationRelease/normalized-snapshot.json"
$releaseNotesPath = "docs/releases/notes/release-notes-2.5.10.md"
$captureToolPath = "tools/commands/release/New-MIR3Factorio20PostTerminalHotfixBaselineContinuation.ps1"
$schemaRelativePath = "spec/schemas/mir3-factorio-2-0-post-terminal-hotfix-baseline-continuation.schema.json"

$releaseRecord = Read-Json $releaseRecordPath
$publication = Read-Json $publicationPath
$foundationManifest = Read-Json $foundationManifestPath
$foundationSnapshot = Read-Json $foundationSnapshotPath
$distRelativePath = "dist/more-infinite-research_2.5.10.zip"
$distPath = Join-Path $RepoRoot $distRelativePath
if (-not (Test-Path -LiteralPath $distPath -PathType Leaf)) { throw "Published 2.5.10 distribution is absent." }

$archiveSha = (Get-FileHash -LiteralPath $distPath -Algorithm SHA256).Hash.ToUpperInvariant()
$contentSha = Get-MIRZipContentFingerprint -Path $distPath
$archiveBytes = [long](Get-Item -LiteralPath $distPath).Length
$composition = Get-ZipComposition $distPath
if ([string]$releaseRecord.state -cne "publicly-verified" -or [string]$publication.status -cne "published-and-verified" -or
    $archiveSha -cne [string]$releaseRecord.package.archive_sha256 -or $archiveSha -cne [string]$publication.download_sha256 -or
    $contentSha -cne [string]$releaseRecord.package.content_sha256 -or $archiveBytes -ne [long]$releaseRecord.package.bytes -or
    [int]$composition.entries -ne [int]$releaseRecord.package.entries) {
  throw "Published 2.5.10 identity does not match its append-only release record."
}

$compositionRecord = Add-RecordSha256 ([ordered]@{
  schema=1;kind="MIR3PostTerminalHotfixPackageCompositionV1";release=$release;root_directory=[string]$composition.root
  archive_sha256=$archiveSha;content_sha256=$contentSha;bytes=$archiveBytes;entries=[int]$composition.entries
  forbidden_package_surfaces_absent=$true;files=@($composition.files)
})
Write-Or-CheckJson $compositionPath $compositionRecord

$releaseRecordSha = (Get-FileHash -LiteralPath (Join-Path $RepoRoot $releaseRecordPath) -Algorithm SHA256).Hash.ToUpperInvariant()
$authorizationSha = (Get-FileHash -LiteralPath (Join-Path $RepoRoot $authorizationPath) -Algorithm SHA256).Hash.ToUpperInvariant()
$closureRecord = Add-RecordSha256 ([ordered]@{
  schema=1;kind="Mir3TerminalReleaseClosureV1";release=$release;status="github-closed-mod-portal-pending";package_visible=$false
  frozen_manifest=[ordered]@{path=$releaseRecordPath;sha256=$releaseRecordSha}
  review=[ordered]@{path=$authorizationPath;sha256=$authorizationSha;decision="explicit-emergency-backport-authorization"}
  seal=[ordered]@{path=$releaseRecordPath;sha256=$releaseRecordSha;status="deterministically-reconstructed-and-publicly-verified"}
  tag=[ordered]@{name=[string]$publication.tag.name;object_sha=[string]$publication.tag.object_sha;peeled_commit=[string]$publication.tag.peeled_commit;immutable=[bool]$publication.tag.immutable}
  github=[ordered]@{receipt=$publicationPath;status=[string]$publication.status;release_url=[string]$publication.github_release.url;download_sha256=[string]$publication.download_sha256}
  mod_portal=[ordered]@{state="maintainer-upload-not-independently-custody-verified";authenticated_redownload="pending"}
  final_channel_state="github-published-and-verified-mod-portal-custody-pending"
})
Write-Or-CheckJson $closurePath $closureRecord

$snapshotRecord = Add-RecordSha256 ([ordered]@{
  schema=1;kind="MIR4TerminalNormalizedSnapshotV1";status="importable-pre-eol-public-custody-pending";semantic_authority=$false
  release=$release;target="2.0";successor_target="MIR4-R0/2.0"
  source_identity=[ordered]@{candidate_id=[string]$releaseRecord.candidate_id;candidate_commit=[string]$releaseRecord.package.source_commit;source_tree=[string]$releaseRecord.package.source_tree;common_source_commit=[string]$foundationSnapshot.source_identity.common_source_commit}
  distribution=[ordered]@{path=$distRelativePath;archive_sha256=$archiveSha;content_sha256=$contentSha;bytes=$archiveBytes;entries=[int]$composition.entries;tag=[string]$publication.tag.name}
  engine=[ordered]@{version=[string]$publication.engine_acceptance.version;executable_sha256=[string]$publication.engine_acceptance.binary_sha256;qualification=$publicationPath;status="passed-exact-engine-qualification"}
  predecessors=@(
    [ordered]@{release="2.5.9";role="immutable-terminal-predecessor";upgrade_id="2.5.9-to-2.5.10"},
    [ordered]@{release="2.5.5";role="older-governed-predecessor";upgrade_id="2.5.5-to-2.5.10"}
  )
  foundation=[ordered]@{release=$foundationRelease;manifest=$foundationManifestPath;root_sha256=[string]$foundationManifest.input_root_sha256}
  inventories=[ordered]@{
    features=[ordered]@{foundation_snapshot=$foundationSnapshotPath;package_composition=(Get-RelativePath $compositionPath);disposition="2.5.9-plus-factorio-2.0-runtime-settings-transport"}
    technologies=[ordered]@{foundation_snapshot=$foundationSnapshotPath;stable_ids_preserved=$true;affected_family="five-generated-productivity-streams"}
    settings=[ordered]@{foundation_snapshot=$foundationSnapshotPath;released_id_or_type_changes=0;codec="MIRSET1";runtime_transport_added=$true}
    owners_aliases_tombstones=[ordered]@{foundation_snapshot=$foundationSnapshotPath;native_owner_adoption=$false;generated_stream_runtime_caps=$true}
    migrations=[ordered]@{foundation_snapshot=$foundationSnapshotPath;watermark=[ordered]@{from=@("2.5.9","2.5.5","2.5.0");stable_ids=$true;to="2.5.10"}}
    locales=[ordered]@{foundation_snapshot=$foundationSnapshotPath;package_composition=(Get-RelativePath $compositionPath)}
    runtime_profiles=[ordered]@{foundation_snapshot=$foundationSnapshotPath;qualification=$publicationPath;target_backend="global"}
    upgrades=[ordered]@{qualification=$publicationPath;required=@("2.5.9-to-2.5.10","2.5.5-to-2.5.10","2.5.0-to-2.5.10")}
  }
  capability_omissions=@($foundationSnapshot.capability_omissions)
  compatibility_import=[ordered]@{authority=[string]$foundationSnapshot.compatibility_import.authority;level_counts=$foundationSnapshot.compatibility_import.level_counts;public_claims_allowed=[int]$foundationSnapshot.compatibility_import.public_claims_allowed;promoted_claims=0;rule="preserve-2.5.9-claim-envelope-and-add-no-hotfix-claims"}
})
Write-Or-CheckJson $snapshotPath $snapshotRecord

$authorityInputs = @(
  $releaseRecordPath,$publicationPath,$authorizationPath,$programmePath,$targetMatrixPath,$releaseNotesPath,
  $foundationManifestPath,$foundationSnapshotPath,$captureToolPath,$schemaRelativePath,
  (Get-RelativePath $compositionPath),(Get-RelativePath $snapshotPath),(Get-RelativePath $closurePath)
)
$files = foreach ($path in @($authorityInputs | Sort-Object -Unique)) {
  $role = if ($path -eq (Get-RelativePath $snapshotPath)) { "normalized-import-snapshot" } elseif ($path -eq (Get-RelativePath $compositionPath)) { "hotfix-package-composition" } elseif ($path -eq (Get-RelativePath $closurePath)) { "release-closure" } elseif ($path -eq $foundationManifestPath) { "immutable-2.5.9-foundation" } else { "post-terminal-hotfix-authority" }
  Get-FileBinding $path $role
}
$inputMaterial = (@($files) | ForEach-Object { "$($_.logical_path)`0$($_.sha256)`0$($_.bytes)" }) -join "`n"
$manifestRecord = Add-RecordSha256 ([ordered]@{
  schema=1;kind="MIR3PostTerminalHotfixBaselineContinuationV1";release=$release;target="2.0"
  status="captured-public-custody-pending-open-mir4-follow-up";package_visible=$false
  capture_tool=[ordered]@{path=$captureToolPath;version="1";sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot $captureToolPath) -Algorithm SHA256).Hash.ToUpperInvariant()}
  foundation=[ordered]@{release=$foundationRelease;manifest=$foundationManifestPath;root_sha256=[string]$foundationManifest.input_root_sha256;retained_as_immutable_historical_snapshot=$true}
  distribution=$snapshotRecord.distribution;input_root_sha256=Get-MIRStringSha256 -Value $inputMaterial;files=@($files)
  normalized_snapshot=@($files | Where-Object source_path -eq (Get-RelativePath $snapshotPath))[0]
  public_custody=[ordered]@{github="published-and-verified";mod_portal="maintainer-upload-not-independently-custody-verified";authenticated_redownload="pending"}
  continuation=[ordered]@{supersedes_for_factorio_2_0_predecessor=$foundationRelease;preserves_historical_baseline=$true;runtime_settings_transport="required-on-targets-without-mod-data";factorio_2_1_predecessor="3.2.10"}
  completion=[ordered]@{state="captured-for-mir4-predecessor-refresh-v2";required_files_present=$true;exact_engine_lock_bound=$true;open_findings=@();mir4_behavioral_proof_required=$true}
})
Write-Or-CheckJson $manifestPath $manifestRecord

$schemaPath = Join-Path $RepoRoot $schemaRelativePath
if (-not ((Get-Content -Raw -LiteralPath $manifestPath) | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
  throw "Generated 2.5.10 continuation manifest failed schema validation."
}
Write-Host "[ok] MIR 2.5.10 terminal baseline continuation: $($manifestRecord.record_sha256)"
