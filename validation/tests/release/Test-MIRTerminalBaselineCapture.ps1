param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path }

. (Join-Path $RepoRoot "tools\lib\validation\PackageIdentity.ps1")
Add-Type -AssemblyName System.IO.Compression.FileSystem

function ConvertTo-CanonicalJsonBytes($Value) {
  $json = ($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
  return [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
}

function Get-Sha256Bytes([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "") } finally { $sha.Dispose() }
}

function Get-RelativeFileMap([string]$Root) {
  $map = @{}
  foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File)) {
    $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
    $map[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
  }
  return $map
}

$expected = [ordered]@{
  "3.2.5" = [ordered]@{
    root = "2C6F1E61D359B8680B6FEA3C4EF8CD9F775E851EFAA7A13D1231036530C17596"
    bundle = "E3165E789E05385D3F037CE73709BE481AC6F89C1BCFD01AB36EF80196E9CCA6"
    technologies_minimum = 70
    settings_minimum = 30
    locales_minimum = 400
    compatibility_minimum = 10
  }
  "1.3.5" = [ordered]@{
    root = "369B54B23FA58E3F814113E6830F01372E91856B31A567C58C923CA365F21761"
    bundle = "FB6EA09DEB429E4ED2A60CF2F4FD613850C79CCF0BB7CF1BA622A56759814282"
    technologies_minimum = 60
    settings_minimum = 20
    locales_minimum = 250
    compatibility_minimum = 0
  }
}

$wave = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-WAVE-INDEX.json") | ConvertFrom-Json -Depth 100
$baselineRoot = Join-Path $RepoRoot ".mir\releases\terminal\baselines"
$exporter = Join-Path $RepoRoot "scripts\Export-MIRTerminalBaseline.ps1"
$testRoot = Join-Path $RepoRoot "build\results\terminal-baseline-capture-test"
$resolvedBuildRoot = (Resolve-Path -LiteralPath (Join-Path $RepoRoot "build")).Path.TrimEnd('\') + '\'

if (Test-Path -LiteralPath $testRoot) {
  $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
  if (-not $resolvedTestRoot.StartsWith($resolvedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace terminal baseline test output outside build/."
  }
  Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}

try {
  foreach ($release in $expected.Keys) {
    $trackedRoot = Join-Path $baselineRoot $release
    $files = @(Get-ChildItem -LiteralPath $trackedRoot -Recurse -File)
    if ($files.Count -ne 27) { throw "$release baseline must contain exactly 27 files; found $($files.Count)." }

    $identity = Get-Content -Raw -LiteralPath (Join-Path $trackedRoot "identity.json") | ConvertFrom-Json -Depth 100
    $waveRows = @($wave.releases | Where-Object version -eq $release)
    if ($waveRows.Count -ne 1) { throw "$release is not unique in the immutable .5 wave index." }
    $waveRow = $waveRows[0]
    $archive = Join-Path $RepoRoot ([string]$waveRow.dist)
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try { $entryCount = $zip.Entries.Count } finally { $zip.Dispose() }
    if ([string]$identity.archive_sha256 -ne [string]$waveRow.archive_sha256 -or
        [string]$identity.content_sha256 -ne [string]$waveRow.content_sha256 -or
        [long]$identity.bytes -ne [long]$waveRow.bytes -or
        [int]$identity.entries -ne [int]$waveRow.entries -or
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne [string]$identity.archive_sha256 -or
        (Get-MIRZipContentFingerprint -Path $archive) -ne [string]$identity.content_sha256 -or
        (Get-Item -LiteralPath $archive).Length -ne [long]$identity.bytes -or
        $entryCount -ne [int]$identity.entries) {
      throw "$release terminal baseline does not bind the exact frozen public ZIP."
    }

    $manifestPath = Join-Path $trackedRoot "baseline-manifest.json"
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
    if ([string]$manifest.kind -ne "Mir3TerminalBaselineBundleManifestV1" -or
        [string]$manifest.completion.state -ne "calibration-incomplete" -or
        -not [bool]$manifest.completion.public_identities_reconciled -or
        -not [bool]$manifest.completion.required_files_present -or
        -not [bool]$manifest.completion.exact_engine_observation_passed -or
        [bool]$manifest.completion.inventories_complete_or_capability_omitted -or
        [bool]$manifest.completion.contradictions_classified) {
      throw "$release calibration overclaims completion or omits proven identity/load state."
    }
    if ([string]$manifest.baseline_root_sha256 -ne [string]$expected[$release].root -or @($manifest.files).Count -ne 26) {
      throw "$release baseline root or manifest file count drifted."
    }

    foreach ($row in @($manifest.files)) {
      $path = Join-Path $trackedRoot ([string]$row.path)
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
          (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne [string]$row.sha256 -or
          (Get-Item -LiteralPath $path).Length -ne [long]$row.bytes) {
        throw "$release baseline manifest file binding failed: $($row.path)"
      }
    }
    $rootMaterial = (@($manifest.files) | ForEach-Object { "$($_.path)`0$($_.sha256)`0$($_.bytes)" }) -join "`n"
    if ((Get-Sha256Bytes ([Text.UTF8Encoding]::new($false).GetBytes($rootMaterial))) -ne [string]$manifest.baseline_root_sha256) {
      throw "$release baseline root is not the canonical digest of its manifest rows."
    }
    $recordMaterial = [ordered]@{}
    foreach ($property in $manifest.PSObject.Properties) {
      if ($property.Name -ne "record_sha256") { $recordMaterial[$property.Name] = $property.Value }
    }
    if ((Get-Sha256Bytes (ConvertTo-CanonicalJsonBytes $recordMaterial)) -ne [string]$manifest.record_sha256) {
      throw "$release baseline manifest record digest is not canonical."
    }

    $technology = Get-Content -Raw -LiteralPath (Join-Path $trackedRoot "declared\technologies.json") | ConvertFrom-Json -Depth 100
    $settings = Get-Content -Raw -LiteralPath (Join-Path $trackedRoot "declared\settings.json") | ConvertFrom-Json -Depth 100
    $locales = Get-Content -Raw -LiteralPath (Join-Path $trackedRoot "declared\locales.json") | ConvertFrom-Json -Depth 100
    $compatibility = Get-Content -Raw -LiteralPath (Join-Path $trackedRoot "declared\compatibility-claims.json") | ConvertFrom-Json -Depth 100
    if (@($technology.items).Count -lt [int]$expected[$release].technologies_minimum -or
        @($settings.items).Count -lt [int]$expected[$release].settings_minimum -or
        @($locales.items).Count -lt [int]$expected[$release].locales_minimum -or
        @($compatibility.items).Count -lt [int]$expected[$release].compatibility_minimum) {
      throw "$release declared semantic inventory fell below its calibrated floor."
    }
    if ($release -eq "1.3.5" -and (@($compatibility.fields_unavailable).Count -eq 0 -or @($compatibility.items).Count -ne 0)) {
      throw "1.3.5 must record the historical claim-authority omission without projecting modern claims backward."
    }

    $generatedOutput = Join-Path $testRoot "output"
    $generatedBuild = Join-Path $testRoot "build"
    & $exporter -Release $release -RepoRoot $RepoRoot -OutputRoot $generatedOutput -BuildRoot $generatedBuild | Out-Host
    $generatedRoot = Join-Path $generatedOutput $release
    $trackedMap = Get-RelativeFileMap $trackedRoot
    $generatedMap = Get-RelativeFileMap $generatedRoot
    if ($trackedMap.Count -ne $generatedMap.Count) { throw "$release regenerated baseline file count differs from tracked calibration." }
    foreach ($relative in $trackedMap.Keys) {
      if (-not $generatedMap.ContainsKey($relative) -or $generatedMap[$relative] -ne $trackedMap[$relative]) {
        throw "$release regenerated baseline differs from tracked calibration: $relative"
      }
    }
    $receipt = Get-Content -Raw -LiteralPath (Join-Path $generatedBuild "$release\build-receipt.json") | ConvertFrom-Json -Depth 100
    if (-not [bool]$receipt.deterministic -or [int]$receipt.builds -ne 2 -or
        [string]$receipt.baseline_root_sha256 -ne [string]$expected[$release].root -or
        [string]$receipt.bundle_sha256 -ne [string]$expected[$release].bundle -or
        [string]$receipt.tracked_manifest_record_sha256 -ne [string]$manifest.record_sha256) {
      throw "$release double-build receipt does not bind the calibrated deterministic bundle."
    }
  }
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
    if ($resolvedTestRoot.StartsWith($resolvedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
  }
}

Write-Host "[ok] terminal baseline capture calibration is exact, deterministic, and truthfully incomplete"
