param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")),
  [string]$F210SourceCandidate = "build/deterministic-package-a/more-infinite-research_3.2.11.zip",
  [string]$F200Predecessor = "dist/more-infinite-research_2.5.11.zip",
  [string]$F200Characterization = "build/results/mir4-sol/sol06/f200-candidate-v2/more-infinite-research_4.0.20000.zip",
  [string]$OutputRoot = "build/results/mir4-sol/sol08/target-candidates"
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$expectedInputs = [ordered]@{
  f210_source = 'A51BBDC0360AFAAA43BF08A213F289CBE141D4B58A00C23C0AEB68627A9D87E6'
  f200_predecessor = '4AE3DA83C4F8CB7D084891065387B78032BB25B8E4ED3948058D9B773070847C'
  f200_characterization = '911FC3CC36A6BEA8444F866E417805101ED51D6691F19B655474A8FC13322441'
}

function Resolve-MIR4InputPath {
  param([Parameter(Mandatory)][string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) { return (Resolve-Path -LiteralPath $Path).Path }
  return (Resolve-Path -LiteralPath (Join-Path $repo $Path)).Path
}

function Get-MIR4ArchiveEntries {
  param([Parameter(Mandatory)][string]$Path)
  $entries = [ordered]@{}
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    foreach ($entry in @($zip.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } | Sort-Object FullName)) {
      $slash = $entry.FullName.IndexOf('/')
      if ($slash -lt 0) { throw "Archive entry lacks a package root: $($entry.FullName)" }
      $relative = $entry.FullName.Substring($slash + 1)
      if ([string]::IsNullOrWhiteSpace($relative) -or $entries.Contains($relative)) {
        throw "Archive has an empty or duplicate normalized path: $relative"
      }
      $stream = $entry.Open()
      try {
        $memory = [IO.MemoryStream]::new()
        try {
          $stream.CopyTo($memory)
          $entries[$relative] = $memory.ToArray()
        } finally {
          $memory.Dispose()
        }
      } finally {
        $stream.Dispose()
      }
    }
  } finally {
    $zip.Dispose()
  }
  return $entries
}

function Get-MIR4NormalizedFileBytes {
  param([Parameter(Mandatory)][string]$Path)
  $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
  return [Text.UTF8Encoding]::new($false).GetBytes($text)
}

function Set-MIR4InfoProjection {
  param(
    [Parameter(Mandatory)]$Entries,
    [Parameter(Mandatory)][string]$Version,
    [string[]]$Dependencies = @()
  )
  $info = [Text.UTF8Encoding]::new($false).GetString([byte[]]$Entries['info.json']) | ConvertFrom-Json
  $info.version = $Version
  if ($Dependencies.Count -gt 0) { $info.dependencies = @($Dependencies) }
  $json = ($info | ConvertTo-Json -Depth 20) + "`n"
  $Entries['info.json'] = [Text.UTF8Encoding]::new($false).GetBytes($json)
}

function Write-MIR4DeterministicArchive {
  param(
    [Parameter(Mandatory)]$Entries,
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][string]$Path
  )
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
  $fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
  $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
  $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
  try {
    foreach ($relative in @($Entries.Keys | Sort-Object)) {
      $entry = $archive.CreateEntry("$PackageRoot/$relative", [IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime = $fixedTimestamp
      $entry.ExternalAttributes = 0
      $output = $entry.Open()
      try {
        $bytes = [byte[]]$Entries[$relative]
        $output.Write($bytes, 0, $bytes.Length)
      } finally {
        $output.Dispose()
      }
    }
  } finally {
    $archive.Dispose()
    $stream.Dispose()
  }
}

function New-MIR4RepeatedTarget {
  param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)]$Entries,
    [Parameter(Mandatory)][string[]]$OverlayPaths,
    [Parameter(Mandatory)][string]$Construction
  )
  $name = "more-infinite-research_$Version.zip"
  $paths = @()
  foreach ($repetition in @('A', 'B')) {
    $path = Join-Path $output "$Target/$repetition/$name"
    Write-MIR4DeterministicArchive -Entries $Entries -PackageRoot "more-infinite-research_$Version" -Path $path
    $paths += $path
  }
  $hashA = Get-MIRFileSha256 -Path $paths[0]
  $hashB = Get-MIRFileSha256 -Path $paths[1]
  if ($hashA -ne $hashB) { throw "$Target A/B package construction is not byte-identical." }
  $distribution = Join-Path $output "distributions/$name"
  $distributionParent = Split-Path -Parent $distribution
  if (-not (Test-Path -LiteralPath $distributionParent)) { New-Item -ItemType Directory -Force -Path $distributionParent | Out-Null }
  Copy-Item -LiteralPath $paths[0] -Destination $distribution -Force
  if ((Get-MIRFileSha256 -Path $distribution) -ne $hashA) { throw "$Target distribution copy changed bytes." }
  return [ordered]@{
    target_key = $Target
    factorio_line = if ($Target -eq 'f210') { '2.1' } else { '2.0' }
    version = $Version
    construction = $Construction
    overlays = @($OverlayPaths)
    archive = [IO.Path]::GetRelativePath($repo, $distribution).Replace('\', '/')
    archive_sha256 = $hashA
    content_sha256 = Get-MIRZipContentFingerprint -Path $distribution
    bytes = (Get-Item -LiteralPath $distribution).Length
    entry_count = (Get-MIR4ArchiveEntries -Path $distribution).Count
    repetitions = @(
      [ordered]@{ id = 'A'; path = [IO.Path]::GetRelativePath($repo, $paths[0]).Replace('\', '/'); sha256 = $hashA },
      [ordered]@{ id = 'B'; path = [IO.Path]::GetRelativePath($repo, $paths[1]).Replace('\', '/'); sha256 = $hashB }
    )
  }
}

$f210Source = Resolve-MIR4InputPath -Path $F210SourceCandidate
$f200Predecessor = Resolve-MIR4InputPath -Path $F200Predecessor
$f200Characterization = Resolve-MIR4InputPath -Path $F200Characterization
if ((Get-MIRFileSha256 -Path $f210Source) -ne $expectedInputs.f210_source -or
    (Get-MIRFileSha256 -Path $f200Predecessor) -ne $expectedInputs.f200_predecessor -or
    (Get-MIRFileSha256 -Path $f200Characterization) -ne $expectedInputs.f200_characterization) {
  throw 'Affected target materialization input identity changed.'
}

$output = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
$repoPrefix = $repo.TrimEnd('\') + '\'
if (-not ($output.TrimEnd('\') + '\').StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Affected target output must remain inside the repository: $output"
}
if (-not (Test-Path -LiteralPath $output)) { New-Item -ItemType Directory -Force -Path $output | Out-Null }

$f210Entries = Get-MIR4ArchiveEntries -Path $f210Source
Set-MIR4InfoProjection -Entries $f210Entries -Version '4.0.21000'
$f210 = New-MIR4RepeatedTarget -Target 'f210' -Version '4.0.21000' -Entries $f210Entries `
  -OverlayPaths @('info.json#/version') -Construction 'exact-current-candidate-version-projection'

$characterizationEntries = Get-MIR4ArchiveEntries -Path $f200Characterization
$f200Entries = Get-MIR4ArchiveEntries -Path $f200Predecessor
$characterizationOverlayPaths = @(
  'prototypes/mir/capabilities/science_integration/science_packs.lua',
  'prototypes/mir/compatibility/policies/k2_science_phase.lua',
  'prototypes/mir/planner/base_continuations.lua',
  'prototypes/mir/planner/science.lua'
)
foreach ($relative in $characterizationOverlayPaths) {
  if (-not $characterizationEntries.Contains($relative)) { throw "Missing f200 characterization overlay: $relative" }
  $f200Entries[$relative] = [byte[]]$characterizationEntries[$relative]
}
$routeOverlayPaths = @(
  'prototypes/mir/capabilities/science_integration/pack_production_reachability.lua',
  'prototypes/mir/capabilities/science_integration/production_route_policy.lua'
)
foreach ($relative in $routeOverlayPaths) {
  $source = Join-Path $repo $relative
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing f200 route overlay: $relative" }
  $f200Entries[$relative] = Get-MIR4NormalizedFileBytes -Path $source
}
$f200Dependencies = @(
  'base >= 2.0.77',
  '(?) elevated-rails',
  '? recycler >= 2.0.77',
  '(?) quality',
  '(?) recycler-progression',
  '(?) Krastorio2-spaced-out',
  '(?) pypostprocessing',
  '(?) space-exploration',
  '? space-age >= 2.0.77'
)
Set-MIR4InfoProjection -Entries $f200Entries -Version '4.0.20000' -Dependencies $f200Dependencies
$f200OverlayPaths = @('info.json#/version-and-target-load-order') + $characterizationOverlayPaths + $routeOverlayPaths
$f200 = New-MIR4RepeatedTarget -Target 'f200' -Version '4.0.20000' -Entries $f200Entries `
  -OverlayPaths $f200OverlayPaths -Construction 'exact-2.5.11-plus-bounded-k2-and-production-route-overlays'

$f200FixtureRelative = 'fixtures/assert-recycler-progression-routes-f200'
$f200FixtureRoot = Join-Path $repo $f200FixtureRelative
$f200FixtureEntries = [ordered]@{}
foreach ($name in @('data-final-fixes.lua', 'info.json')) {
  $path = Join-Path $f200FixtureRoot $name
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing f200 fixture source: $path" }
  $f200FixtureEntries[$name] = Get-MIR4NormalizedFileBytes -Path $path
}
$f200FixtureZip = Join-Path $output 'fixtures/mir-fixture-assert-recycler-progression-routes-f200_0.1.0.zip'
Write-MIR4DeterministicArchive -Entries $f200FixtureEntries `
  -PackageRoot 'mir-fixture-assert-recycler-progression-routes-f200_0.1.0' -Path $f200FixtureZip
$f200Fixture = [ordered]@{
  id = 'recycler-progression-routes-f200'
  source = $f200FixtureRelative
  archive = [IO.Path]::GetRelativePath($repo, $f200FixtureZip).Replace('\', '/')
  archive_sha256 = Get-MIRFileSha256 -Path $f200FixtureZip
  content_sha256 = Get-MIRZipContentFingerprint -Path $f200FixtureZip
}

$authorityPaths = @($routeOverlayPaths | ForEach-Object {
  [ordered]@{ path = $_; sha256 = Get-MIRFileSha256 -Path (Join-Path $repo $_) }
})
$manifest = [ordered]@{
  schema = 1
  kind = 'MIR4AffectedTargetCandidateSetSOL08V1'
  status = 'built-unqualified-local-development-candidates'
  source_commit = (& git -C $repo rev-parse HEAD).Trim()
  source_dirty = @(& git -C $repo status --porcelain).Count -gt 0
  public_output_authorized = $false
  publication_authorized = $false
  inputs = [ordered]@{
    f210_source = [ordered]@{ path = [IO.Path]::GetRelativePath($repo, $f210Source).Replace('\', '/'); sha256 = $expectedInputs.f210_source }
    f200_predecessor = [ordered]@{ path = [IO.Path]::GetRelativePath($repo, $f200Predecessor).Replace('\', '/'); sha256 = $expectedInputs.f200_predecessor }
    f200_characterization = [ordered]@{ path = [IO.Path]::GetRelativePath($repo, $f200Characterization).Replace('\', '/'); sha256 = $expectedInputs.f200_characterization }
  }
  route_overlay_authorities = $authorityPaths
  targets = @($f210, $f200)
  auxiliary_fixtures = @($f200Fixture)
  hard_boundary = 'These artifacts are exact affected-proof development candidates. They supersede prior private M4C01 bytes for corrected-package testing only and grant no source freeze, release, signing, sealing, upload, or publication authority.'
}
$manifestPath = Join-Path $output 'MIR4_AFFECTED_TARGET_CANDIDATES.json'
$manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Host "[ok] MIR 4 SOL-08 affected target candidates: $manifestPath"
