param(
  [string]$RepoRoot = "",
  [string]$OutputRoot = "",
  [string]$BuildRoot = "",
  [string[]]$Release = @(),
  [switch]$Check,
  [switch]$BuildBundles
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $RepoRoot ".mir\releases\terminal\baselines"
} elseif (-not [IO.Path]::IsPathRooted($OutputRoot)) {
  $OutputRoot = Join-Path $RepoRoot $OutputRoot
}
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
  $BuildRoot = Join-Path $RepoRoot "build\terminal\dot9-baselines"
} elseif (-not [IO.Path]::IsPathRooted($BuildRoot)) {
  $BuildRoot = Join-Path $RepoRoot $BuildRoot
}

. (Join-Path $RepoRoot "tools\lib\validation\PackageIdentity.ps1")
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-RelativePath([string]$Path) {
  return [IO.Path]::GetRelativePath($RepoRoot, $Path).Replace("\", "/")
}

function Read-Json([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required authority is missing: $RelativePath" }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
}

function Get-Sha256Bytes([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "") } finally { $sha.Dispose() }
}

function ConvertTo-CanonicalJsonBytes($Value) {
  $json = ($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
  return [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
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

function Get-FileBinding([string]$LogicalPath, [string]$SourcePath, [string]$Role) {
  $absolute = Join-Path $RepoRoot $SourcePath
  if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Bundle input is absent: $SourcePath" }
  return [ordered]@{
    logical_path = $LogicalPath.Replace("\", "/")
    source_path = $SourcePath.Replace("\", "/")
    sha256 = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToUpperInvariant()
    bytes = [long](Get-Item -LiteralPath $absolute).Length
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
    return [ordered]@{ root = $roots[0]; files = @($files); entries = @($files).Count }
  } finally { $zip.Dispose() }
}

function New-DeterministicBundle([string]$Path, [array]$Files, [string]$ManifestPath) {
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false, [Text.UTF8Encoding]::new($false))
    try {
      $entries = @($Files | ForEach-Object { [pscustomobject]@{logical_path=[string]$_["logical_path"]; source_path=[string]$_["source_path"]} })
      $entries += [pscustomobject]@{logical_path="baseline-manifest.json"; source_path=$ManifestPath}
      foreach ($row in @($entries | Sort-Object logical_path)) {
        $source = if ([IO.Path]::IsPathRooted([string]$row.source_path)) { [string]$row.source_path } else { Join-Path $RepoRoot ([string]$row.source_path) }
        $entry = $archive.CreateEntry(([string]$row.logical_path).Replace("\", "/"), [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $input = [IO.File]::OpenRead($source)
        $output = $entry.Open()
        try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
      }
    } finally { $archive.Dispose() }
  } finally { $stream.Dispose() }
}

$familyPath = ".mir/releases/terminal/MIR3TerminalFamilyReadinessV1.json"
$profilePath = ".mir/releases/terminal/MIR3-Terminal-Shadow-ProjectionProfilesV1.json"
$targetPath = ".mir/targets.json"
$custodyPath = ".mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-CustodyObservationV1.json"
$family = Read-Json $familyPath
$profiles = Read-Json $profilePath
$targetProfiles = Read-Json $targetPath
$custody = Read-Json $custodyPath
$claims = Read-Json ".mir/releases/terminal/MIR3-Compatibility-ClaimsV1.json"

$expectedFamily = @("3.2.9", "2.5.9", "1.9.9", "1.8.9", "1.7.9", "1.6.9", "1.5.9", "1.4.9", "1.3.9")
if ((@($family.releases) -join "|") -ne ($expectedFamily -join "|")) { throw "Terminal family identity changed." }
$selected = if ($Release.Count -gt 0) { @($Release) } else { $expectedFamily }
foreach ($item in $selected) { if ($item -notin $expectedFamily) { throw "Unsupported terminal .9 release: $item" } }

$commonInputs = @(
  ".mir/releases/terminal/MIR3-Terminal-ProgrammeV1.json",
  ".mir/releases/terminal/MIR3-Terminal-EOL-PolicyV1.json",
  ".mir/releases/terminal/MIR3TerminalSuccessorBootstrapPolicyV1.json",
  ".mir/releases/terminal/MIR3-Terminal-Candidate-AllocationV1.json",
  ".mir/releases/terminal/MIR3TerminalSourceFreezeV1.json",
  ".mir/releases/terminal/MIR3TerminalFixedPointReceiptV1.json",
  ".mir/releases/terminal/MIR3TerminalCandidateReconstructionReceiptV1.json",
  ".mir/releases/terminal/MIR3TerminalCandidateSettingsQualificationV1.json",
  ".mir/releases/terminal/MIR3TerminalFamilyReadinessV1.json",
  ".mir/releases/terminal/MIR3TerminalMaintainerAcceptanceV1.json",
  ".mir/releases/terminal/MIR3-Settings-Scope-AuditV1.json",
  ".mir/releases/terminal/MIR3-Compatibility-ClaimsV1.json",
  ".mir/releases/terminal/MIR3-ModPortal-Compatibility-CensusV1.json",
  ".mir/releases/terminal/MIR3-Mod-Interaction-MatrixV1.json",
  ".mir/releases/terminal/MIR3-FINAL-DEFECT-INDEX.json",
  ".mir/releases/terminal/MIR3TerminalProductImplementationReconciliationV1.json",
  ".mir/releases/terminal/MIR3TerminalProductAdmissionBundleV1.json",
  ".mir/releases/terminal/MIR3-Terminal-Target-MatrixV1.json",
  $profilePath,
  ".mir/releases/terminal/MIR3-Terminal-PublicationPolicyV1.json",
  ".mir/evidence/terminal-publication/2026-08-15/MIR3-GitHub-Family-PublicationV1.json",
  $custodyPath
)

$catalogRows = @()
foreach ($version in $selected) {
  $packageManifestPath = ".mir/releases/terminal/manifests/$version-package.json"
  $releaseManifestPath = ".mir/releases/terminal/manifests/$version-release.json"
  $qualificationPath = ".mir/releases/terminal/qualifications/$version.json"
  $reviewPath = ".mir/releases/terminal/reviews/$version.json"
  $sealPath = ".mir/releases/terminal/seals/$version.json"
  $githubPath = ".mir/evidence/terminal-publication/2026-08-15/github/$version.json"
  $freezePath = ".mir/releases/terminal/freezes/$version.json"
  $releaseBodyPath = ".mir/releases/terminal/release-bodies/$version.md"
  $portalDescriptionPath = ".mir/releases/terminal/mod-portal-descriptions/$version.md"
  $closurePath = ".mir/releases/terminal/closures/$version.json"
  $baselineDirectory = Join-Path $OutputRoot $version
  $compositionPath = Get-RelativePath (Join-Path $baselineDirectory "package-composition.json")
  $snapshotPath = Get-RelativePath (Join-Path $baselineDirectory "normalized-snapshot.json")
  $manifestPath = Get-RelativePath (Join-Path $baselineDirectory "baseline-manifest.json")

  $packageManifest = Read-Json $packageManifestPath
  $releaseManifest = Read-Json $releaseManifestPath
  $qualification = Read-Json $qualificationPath
  $review = Read-Json $reviewPath
  $seal = Read-Json $sealPath
  $github = Read-Json $githubPath
  $profileRows = @($profiles.targets | Where-Object release -eq $version)
  $custodyRows = @($custody.observations | Where-Object release -eq $version)
  if ($profileRows.Count -ne 1 -or $custodyRows.Count -ne 1) { throw "Target profile or custody row is ambiguous for $version." }
  $profile = $profileRows[0]
  $custodyRow = $custodyRows[0]
  $targetProfileProperty = $targetProfiles.profiles.PSObject.Properties[[string]$profile.factorio_line]
  $targetProfileMissing = $null -eq $targetProfileProperty
  if ($targetProfileMissing) {
    $targetProfile = [pscustomobject]@{
      features = [pscustomobject]@{}
      prototype_shapes = [pscustomobject]@{}
      runtime_state_backend = "explicit-capability-omission"
    }
  } else {
    $targetProfile = $targetProfileProperty.Value
  }

  $distPath = Join-Path $RepoRoot "dist\more-infinite-research_$version.zip"
  if (-not (Test-Path -LiteralPath $distPath -PathType Leaf)) { throw "Sealed distribution is absent: $version" }
  $archiveSha = (Get-FileHash -LiteralPath $distPath -Algorithm SHA256).Hash.ToUpperInvariant()
  $contentSha = Get-MIRZipContentFingerprint -Path $distPath
  $distBytes = [long](Get-Item -LiteralPath $distPath).Length
  $compositionData = Get-ZipComposition $distPath
  if ($archiveSha -ne [string]$seal.archive_sha256 -or $contentSha -ne [string]$seal.content_sha256 -or
      $distBytes -ne [long]$seal.bytes -or [int]$compositionData.entries -ne [int]$seal.entries) {
    throw "Sealed distribution identity mismatch for $version."
  }
  if ([string]$github.status -ne "published-and-verified" -or [string]$github.download_sha256 -ne $archiveSha -or
      [string]$github.tag.peeled_commit -ne [string]$seal.candidate_commit) {
    throw "GitHub publication identity mismatch for $version."
  }

  $compositionMaterial = [ordered]@{
    schema = 1
    kind = "Mir3Dot9TerminalPackageCompositionV1"
    release = $version
    root_directory = [string]$compositionData.root
    archive_sha256 = $archiveSha
    content_sha256 = $contentSha
    bytes = $distBytes
    entries = [int]$compositionData.entries
    forbidden_package_surfaces_absent = $true
    files = @($compositionData.files)
  }
  $compositionRecord = Add-RecordSha256 $compositionMaterial
  Write-Or-CheckJson (Join-Path $RepoRoot $compositionPath) $compositionRecord

  $closureMaterial = [ordered]@{
    schema = 1
    kind = "Mir3TerminalReleaseClosureV1"
    release = $version
    status = "github-closed-mod-portal-pending"
    package_visible = $false
    frozen_manifest = [ordered]@{ path=$releaseManifestPath; sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot $releaseManifestPath) -Algorithm SHA256).Hash.ToUpperInvariant() }
    review = [ordered]@{ path=$reviewPath; sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot $reviewPath) -Algorithm SHA256).Hash.ToUpperInvariant(); decision=[string]$review.status }
    seal = [ordered]@{ path=$sealPath; sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot $sealPath) -Algorithm SHA256).Hash.ToUpperInvariant(); status=[string]$seal.status }
    tag = [ordered]@{ name=[string]$github.tag.name; object_sha=[string]$github.tag.object_sha; peeled_commit=[string]$github.tag.peeled_commit; immutable=[bool]$github.tag.immutable }
    github = [ordered]@{ receipt=$githubPath; status=[string]$github.status; release_url=[string]$github.github_release.url; download_sha256=[string]$github.download_sha256 }
    mod_portal = [ordered]@{ observation=$custodyPath; state=[string]$custodyRow.portal_state; sha1=$custodyRow.portal_sha1; authenticated_redownload=[string]$custodyRow.authenticated_redownload }
    final_channel_state = "github-published-and-verified-mod-portal-custody-pending"
  }
  $closureRecord = Add-RecordSha256 $closureMaterial
  Write-Or-CheckJson (Join-Path $RepoRoot $closurePath) $closureRecord

  $foundationManifestPath = [string]$seal.baseline_bundle.path
  $foundationManifest = Read-Json $foundationManifestPath
  $featureOmissions = @()
  if ($targetProfileMissing) {
    $featureOmissions += [ordered]@{ field="canonical-target-profile"; reason="terminal-finite-target-is-represented-by-the-sealed-shadow-profile-rather-than-.mir/targets.json"; disposition="explicit-capability-omission" }
  }
  foreach ($feature in @($targetProfile.features.PSObject.Properties | Sort-Object Name)) {
    if (-not [bool]$feature.Value) {
      $featureOmissions += [ordered]@{ field="feature:$($feature.Name)"; reason="unsupported-by-terminal-target-profile"; disposition="explicit-omission" }
    }
  }
  foreach ($field in @($targetProfile.prototype_shapes.PSObject.Properties | Sort-Object Name)) {
    if ($null -eq $field.Value -or $field.Value -eq $false) {
      $featureOmissions += [ordered]@{ field="prototype-shape:$($field.Name)"; reason="unsupported-by-terminal-target-profile"; disposition="explicit-omission" }
    }
  }
  $claimCounts = [ordered]@{}
  foreach ($group in @($claims.claims | Group-Object level | Sort-Object Name)) { $claimCounts[$group.Name] = [int]$group.Count }

  $snapshotMaterial = [ordered]@{
    schema = 1
    kind = "MIR4TerminalNormalizedSnapshotV1"
    status = "importable-pre-eol-public-custody-pending"
    semantic_authority = $false
    release = $version
    target = [string]$packageManifest.target
    successor_target = [string]$packageManifest.mir4_successor_target
    source_identity = [ordered]@{ candidate_id=[string]$seal.candidate_id; candidate_commit=[string]$seal.candidate_commit; source_tree=[string]$seal.source_tree; common_source_commit=[string]$packageManifest.source.common_source_commit }
    distribution = [ordered]@{ path="dist/more-infinite-research_$version.zip"; archive_sha256=$archiveSha; content_sha256=$contentSha; bytes=$distBytes; entries=[int]$compositionData.entries; tag=[string]$github.tag.name }
    engine = [ordered]@{ version=[string]$seal.engine.version; executable_sha256=[string]$seal.engine.binary_sha256; qualification=$qualificationPath; status="exact-engine-qualified" }
    predecessors = @(
      [ordered]@{ release=[string]$profile.baseline.release; role="immutable-dot5"; upgrade_id=[string]$profile.upgrade_rows[0] },
      [ordered]@{ release=[string]$profile.pre_dot5.release; role="pre-dot5"; upgrade_id=[string]$profile.upgrade_rows[1] }
    )
    foundation = [ordered]@{ release=[string]$foundationManifest.release; manifest=$foundationManifestPath; root_sha256=[string]$foundationManifest.baseline_root_sha256 }
    inventories = [ordered]@{
      features = [ordered]@{ package_manifest=$packageManifestPath; package_composition=$compositionPath; disposition="foundation-plus-sealed-terminal-delta" }
      technologies = [ordered]@{ foundation="$([IO.Path]::GetDirectoryName($foundationManifestPath).Replace('\','/'))/declared/technologies.json"; terminal_delta=".mir/releases/terminal/MIR3TerminalProductImplementationReconciliationV1.json"; stable_ids_preserved=[bool]$packageManifest.migration_watermark.stable_ids }
      settings = [ordered]@{ foundation="$([IO.Path]::GetDirectoryName($foundationManifestPath).Replace('\','/'))/declared/settings.json"; terminal_audit=".mir/releases/terminal/MIR3-Settings-Scope-AuditV1.json"; released_id_or_type_changes=0; codec="MIRSET1" }
      owners_aliases_tombstones = [ordered]@{ foundation="$([IO.Path]::GetDirectoryName($foundationManifestPath).Replace('\','/'))/declared/owners-aliases-tombstones.json"; terminal_delta=".mir/releases/terminal/MIR3TerminalProductImplementationReconciliationV1.json" }
      migrations = [ordered]@{ foundation="$([IO.Path]::GetDirectoryName($foundationManifestPath).Replace('\','/'))/declared/migrations.json"; watermark=$packageManifest.migration_watermark }
      locales = [ordered]@{ foundation="$([IO.Path]::GetDirectoryName($foundationManifestPath).Replace('\','/'))/declared/locales.json"; package_composition=$compositionPath }
      runtime_profiles = [ordered]@{ foundation="$([IO.Path]::GetDirectoryName($foundationManifestPath).Replace('\','/'))/declared/runtime-profile-schemas.json"; target_backend=[string]$targetProfile.runtime_state_backend }
      upgrades = [ordered]@{ fixed_point=".mir/releases/terminal/MIR3TerminalFixedPointReceiptV1.json"; qualification=$qualificationPath; required=@($profile.upgrade_rows) }
    }
    capability_omissions = @($featureOmissions)
    compatibility_import = [ordered]@{ authority=".mir/releases/terminal/MIR3-Compatibility-ClaimsV1.json"; level_counts=$claimCounts; public_claims_allowed=@($claims.claims | Where-Object public_claim_allowed).Count; promoted_claims=0; rule="preserve-level-envelope-dimensions-and-public-permission" }
  }
  $snapshotRecord = Add-RecordSha256 $snapshotMaterial
  Write-Or-CheckJson (Join-Path $RepoRoot $snapshotPath) $snapshotRecord

  $sourceInputs = @($commonInputs + @($packageManifestPath, $releaseManifestPath, $qualificationPath, $reviewPath, $sealPath, $githubPath, $freezePath, $releaseBodyPath, $portalDescriptionPath, $closurePath, $compositionPath, $snapshotPath, $foundationManifestPath))
  $files = [Collections.Generic.List[object]]::new()
  foreach ($source in @($sourceInputs | Sort-Object -Unique)) {
    $role = if ($source -eq $snapshotPath) { "normalized-import-snapshot" } elseif ($source -eq $compositionPath) { "terminal-package-composition" } elseif ($source -eq $closurePath) { "release-closure" } else { "terminal-authority" }
    $files.Add((Get-FileBinding "authority/$source" $source $role))
  }
  $foundationDirectory = [IO.Path]::GetDirectoryName($foundationManifestPath).Replace("\", "/")
  foreach ($foundationFile in @($foundationManifest.files)) {
    $source = "$foundationDirectory/$([string]$foundationFile.path)"
    $files.Add((Get-FileBinding "foundation/$([string]$foundationFile.path)" $source "immutable-dot5-foundation"))
  }
  $fileRows = @($files.ToArray() | Sort-Object { [string]$_["logical_path"] })
  $inputMaterial = ($fileRows | ForEach-Object { "$($_["logical_path"])`0$($_["sha256"])`0$($_["bytes"])" }) -join "`n"
  $snapshotBinding = @($fileRows | Where-Object { [string]$_["source_path"] -eq $snapshotPath })
  if ($snapshotBinding.Count -ne 1 -or $fileRows.Count -lt 25) {
    throw "Baseline logical view is incomplete for $version (files=$($fileRows.Count), snapshots=$($snapshotBinding.Count), expected=$snapshotPath)."
  }
  $manifestMaterial = [ordered]@{
    schema = 1
    kind = "Mir3Dot9TerminalBaselineBundleManifestV1"
    release = $version
    target = [string]$packageManifest.target
    status = "capture-ready-mod-portal-pending"
    package_visible = $false
    capture_tool = [ordered]@{ path="tools/commands/release/New-MIR3Dot9TerminalBaselines.ps1"; version="1"; sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToUpperInvariant() }
    foundation = [ordered]@{ release=[string]$foundationManifest.release; manifest=$foundationManifestPath; root_sha256=[string]$foundationManifest.baseline_root_sha256 }
    distribution = [ordered]@{ path="dist/more-infinite-research_$version.zip"; archive_sha256=$archiveSha; content_sha256=$contentSha; bytes=$distBytes; entries=[int]$compositionData.entries }
    input_root_sha256 = Get-MIRStringSha256 -Value $inputMaterial
    files = $fileRows
    normalized_snapshot = $snapshotBinding[0]
    deterministic_bundle = [ordered]@{ algorithm="sorted-logical-path-fixed-time-deflate"; builds_required=2; build_location="build/terminal/dot9-baselines/$version"; self_contained_logical_view=$true }
    public_custody = [ordered]@{ github="published-and-verified"; mod_portal=[string]$custodyRow.portal_state; authenticated_redownload=[string]$custodyRow.authenticated_redownload }
    completion = [ordered]@{ state="capture-ready-public-custody-pending"; required_files_present=$true; inventories_complete_or_capability_omitted=$true; exact_engine_qualification_bound=$true; contradictions_classified=$true; mod_portal_custody_complete=$false }
  }
  $manifestRecord = Add-RecordSha256 $manifestMaterial
  $manifestAbsolute = Join-Path $RepoRoot $manifestPath
  Write-Or-CheckJson $manifestAbsolute $manifestRecord

  $bundleIdentity = $null
  if ($BuildBundles) {
    if ($Check) { throw "-BuildBundles cannot be combined with -Check." }
    $releaseBuild = Join-Path $BuildRoot $version
    $bundleA = Join-Path $releaseBuild "MIR3-Dot9-Terminal-Baseline-$version-a.zip"
    $bundleB = Join-Path $releaseBuild "MIR3-Dot9-Terminal-Baseline-$version-b.zip"
    New-DeterministicBundle $bundleA $fileRows $manifestAbsolute
    New-DeterministicBundle $bundleB $fileRows $manifestAbsolute
    $shaA = (Get-FileHash -LiteralPath $bundleA -Algorithm SHA256).Hash.ToUpperInvariant()
    $shaB = (Get-FileHash -LiteralPath $bundleB -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($shaA -ne $shaB) { throw "Terminal .9 baseline bundle is not byte deterministic for $version." }
    $bundleIdentity = [ordered]@{ sha256=$shaA; bytes=[long](Get-Item -LiteralPath $bundleA).Length; builds=2; deterministic=$true }
    $receipt = Add-RecordSha256 ([ordered]@{ schema=1; kind="Mir3Dot9TerminalBaselineBuildReceiptV1"; release=$version; manifest_record_sha256=[string]$manifestRecord.record_sha256; bundle=$bundleIdentity })
    Write-Or-CheckJson (Join-Path $releaseBuild "build-receipt.json") $receipt
  }

  $catalogRows += [ordered]@{
    release = $version
    target = [string]$packageManifest.target
    manifest = $manifestPath
    manifest_record_sha256 = [string]$manifestRecord.record_sha256
    normalized_snapshot = $snapshotPath
    normalized_snapshot_record_sha256 = [string]$snapshotRecord.record_sha256
    status = [string]$manifestRecord.status
    deterministic_build = $null
  }
  Write-Host "[ok] MIR 3 $version final baseline capture ready; files=$($fileRows.Count) manifest=$($manifestRecord.record_sha256)"
}

if ($Release.Count -eq 0) {
  $catalogMaterial = [ordered]@{
    schema = 1
    kind = "Mir3Dot9TerminalBaselineFamilyCatalogV1"
    status = "all-nine-capture-ready-mod-portal-pending"
    package_visible = $false
    family = $expectedFamily
    releases = @($catalogRows)
    public_custody = [ordered]@{ github=9; mod_portal_api_visible=[int]$custody.summary.api_visible; mod_portal_not_uploaded=[int]$custody.summary.not_uploaded; authenticated_redownloads_complete=[int]$custody.summary.authenticated_redownloads_complete }
  }
  $catalog = Add-RecordSha256 $catalogMaterial
  Write-Or-CheckJson (Join-Path $OutputRoot "dot9-family-catalog.json") $catalog
  Write-Host "[ok] all-nine terminal .9 baseline catalog: $($catalog.record_sha256)"
}
