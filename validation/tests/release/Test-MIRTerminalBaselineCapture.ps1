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
  "2.5.5" = [ordered]@{
    root = "7ACE30AB13C5C532863A942A74C3959FED8980A8BA588C381E0591286E8BBE1B"
    bundle = "31E0AD38897CAAE26B80870C36F3548EBC38F74564DDB91FC5F67609319D18DB"
    technologies_minimum = 70
    settings_minimum = 30
    locales_minimum = 400
    compatibility_minimum = 0
  }
  "1.9.5" = [ordered]@{
    root = "34BA4397E569A52E40317FC2E75E5CF173B1476706546ED70718D08A7D7F7377"
    bundle = "6EA05D14B8E93232A275B7D79547F20A54F4B56BAA8FD6B9F1958762AD79CAA5"
    technologies_minimum = 70
    settings_minimum = 30
    locales_minimum = 400
    compatibility_minimum = 0
  }
  "1.8.5" = [ordered]@{
    root = "5B85A4FB23EB06AD63AC97132CC0C78205E2473304291081FDD554D6B4F576D3"
    bundle = "2D410ACBDFC736C5E77DC607FC0B526E3A15790D329D82A6268CC4EB4B62E8BE"
    technologies_minimum = 70
    settings_minimum = 30
    locales_minimum = 400
    compatibility_minimum = 0
  }
  "1.7.5" = [ordered]@{
    root = "59497401C8CF701B08F6927DE428C7C25F8B900F5C0F73D9DD46ADBE572F034F"
    bundle = "70FCF025F71D8D683D1AA2728C6FA20D6EF61FABF5310BCF2B2BF24958E4DA2E"
    technologies_minimum = 60
    settings_minimum = 20
    locales_minimum = 250
    compatibility_minimum = 0
  }
  "1.6.5" = [ordered]@{
    root = "3EE468E58F7A507316877E79D9F71C2F6A6FE7213AC375243B4ABD5D4E20B5C6"
    bundle = "AE612D533E3586FED0B20F83914F8A3828A546DEA053BAD68CB5B146FC760E01"
    technologies_minimum = 60
    settings_minimum = 20
    locales_minimum = 250
    compatibility_minimum = 0
  }
  "1.5.5" = [ordered]@{
    root = "25E83329D5C9BE664DA0A97D1BDA51C42F358B6B9217D66725AEBD8A81351697"
    bundle = "DECF3E910360D8AF93B64222D4BC64E4A1AA168F67FD09DD014F04BF61B1C738"
    technologies_minimum = 60
    settings_minimum = 20
    locales_minimum = 250
    compatibility_minimum = 0
  }
  "1.4.5" = [ordered]@{
    root = "724FD0A4B54AD9D3BBF79C254AAA1499DE2342E263B2C2C1D900E95182958E91"
    bundle = "EF93D401C794E7F862E5EF4DC57A2C77A8F650FBC489CC25E21118562B1FF709"
    technologies_minimum = 60
    settings_minimum = 20
    locales_minimum = 250
    compatibility_minimum = 0
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
    if ($release -ne "3.2.5" -and (@($compatibility.fields_unavailable).Count -eq 0 -or @($compatibility.items).Count -ne 0)) {
      throw "$release must record the historical claim-authority omission without projecting modern claims backward."
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

  $matrixPath = Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Dot5-Semantic-MatrixV1.json"
  $matrix = Get-Content -Raw -LiteralPath $matrixPath | ConvertFrom-Json -Depth 100
  $releaseOrder = @($expected.Keys)
  if ([string]$matrix.kind -ne "MIR3Dot5SemanticMatrixV1" -or
      [string]$matrix.status -ne "calibration-incomplete-realized-probes-pending" -or
      (@($matrix.release_order) -join "|") -ne ($releaseOrder -join "|") -or
      @($matrix.releases).Count -ne 9 -or
      -not [bool]$matrix.completion.all_nine_static_inventories_present -or
      [bool]$matrix.completion.all_nine_realized_engine_inventories_complete -or
      [bool]$matrix.completion.contradictions_classified -or
      [bool]$matrix.completion.queue_completion_permitted) {
    throw "Terminal .5 semantic matrix is incomplete, out of order, or overclaims realized completion."
  }
  if ([string]$matrix.generated_by.sha256 -ne (Get-FileHash -LiteralPath (Join-Path $RepoRoot ([string]$matrix.generated_by.path)) -Algorithm SHA256).Hash) {
    throw "Terminal .5 semantic matrix does not bind its exact generator."
  }
  $matrixRecordMaterial = [ordered]@{}
  foreach ($property in $matrix.PSObject.Properties) {
    if ($property.Name -ne "record_sha256") { $matrixRecordMaterial[$property.Name] = $property.Value }
  }
  if ((Get-Sha256Bytes (ConvertTo-CanonicalJsonBytes $matrixRecordMaterial)) -ne [string]$matrix.record_sha256) {
    throw "Terminal .5 semantic matrix record digest is not canonical."
  }
  foreach ($release in $releaseOrder) {
    $rows = @($matrix.releases | Where-Object release -eq $release)
    if ($rows.Count -ne 1 -or [string]$rows[0].baseline_root_sha256 -ne [string]$expected[$release].root -or
        [string]$rows[0].completion_state -ne "calibration-incomplete") {
      throw "Terminal .5 semantic matrix release binding failed: $release"
    }
  }
  $expectedMatrixCounts = [ordered]@{ features=6; technologies=76; settings=39; migrations=2; compatibility_claims=14 }
  foreach ($definition in $expectedMatrixCounts.GetEnumerator()) {
    $rows = @($matrix.matrices.($definition.Key))
    if ($rows.Count -ne [int]$definition.Value) { throw "Terminal semantic matrix row count drifted: $($definition.Key)" }
    foreach ($row in $rows) {
      if (@($row.cells).Count -ne 9 -or (@($row.cells.release) -join "|") -ne ($releaseOrder -join "|")) {
        throw "Terminal semantic matrix cell coverage is incomplete: $($definition.Key)/$($row.stable_id)"
      }
    }
  }
  if (@($matrix.unresolved_findings).Count -ne 27) { throw "Terminal .5 semantic matrix must carry all 27 calibrated realization findings." }

  $generatedMatrix = Join-Path $testRoot "MIR3-Dot5-Semantic-MatrixV1.json"
  & (Join-Path $RepoRoot "scripts\Export-MIRTerminalBaselineMatrix.ps1") -RepoRoot $RepoRoot -OutputPath $generatedMatrix | Out-Host
  if ((Get-FileHash -LiteralPath $generatedMatrix -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $matrixPath -Algorithm SHA256).Hash) {
    throw "Terminal .5 semantic matrix regeneration differs from the tracked authority."
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
