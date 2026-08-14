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

function Get-CanonicalTextFileBytes([string]$Path) {
  $text = [IO.File]::ReadAllText($Path)
  $text = $text -replace "`r`n", "`n"
  $text = $text -replace "`r", "`n"
  return [Text.UTF8Encoding]::new($false).GetBytes($text)
}

function Get-CanonicalTextFileSha256([string]$Path) {
  return Get-Sha256Bytes (Get-CanonicalTextFileBytes $Path)
}

function Get-RelativeFileMap([string]$Root) {
  $map = @{}
  foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File)) {
    $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
    $map[$relative] = Get-CanonicalTextFileSha256 $file.FullName
  }
  return $map
}

$expected = [ordered]@{
  "3.2.5" = [ordered]@{
    root = "692E071E6057854D090880C6921F17607C3B1BA13587F1846359DC7CED09AB53"
    bundle = "DF65F461EFBA68AE3CD2641689E6D9EA0C43405C081E23FF75C2779884394F89"
    realized_technologies = 65; realized_effects = 165; realized_settings = 66; realized_compatibility = 14
    technologies_minimum = 70
    settings_minimum = 30
    locales_minimum = 400
    compatibility_minimum = 10
  }
  "2.5.5" = [ordered]@{
    root = "6B74589F413C010AA4BF7F8B178C07054315169802EC1A12AA19FAECD3316FF6"
    bundle = "6818955C53B4C4655ABD241EA039C3C78FEC477B64801C38C6FEA007CDFE926B"
    realized_technologies = 63; realized_effects = 161; realized_settings = 66; realized_compatibility = 0
    technologies_minimum = 70
    settings_minimum = 30
    locales_minimum = 400
    compatibility_minimum = 0
  }
  "1.9.5" = [ordered]@{
    root = "BF412FF6CA673F039D43B19D4835152D0CC392C6FDEF65D6E898A1FBB2C9F4B6"
    bundle = "2348FC37C212F3E955053D6DD4FC710DB36EC740C7D9952EDB7F3C820C0C9A59"
    realized_technologies = 11; realized_effects = 15; realized_settings = 48; realized_compatibility = 0
    technologies_minimum = 70
    settings_minimum = 30
    locales_minimum = 400
    compatibility_minimum = 0
  }
  "1.8.5" = [ordered]@{
    root = "2193441BFC20C491234EA0A57EDEA64DFDD483EA97471E209DC3578529DCBB2A"
    bundle = "D44C1C4055951A7E67D104B7BB4F52940B452863CAD0C520AC7C191F795818E3"
    realized_technologies = 11; realized_effects = 15; realized_settings = 48; realized_compatibility = 0
    technologies_minimum = 70
    settings_minimum = 30
    locales_minimum = 400
    compatibility_minimum = 0
  }
  "1.7.5" = [ordered]@{
    root = "5966912C8A801EC5CD858E688CFC47E12023C411101F54CAD2BC90F8474CD672"
    bundle = "EC176AB42590BCE033F3743C3D95B9636136586DF065C5A949086BA83645A58E"
    realized_technologies = 11; realized_effects = 15; realized_settings = 43; realized_compatibility = 0
    technologies_minimum = 60
    settings_minimum = 20
    locales_minimum = 250
    compatibility_minimum = 0
  }
  "1.6.5" = [ordered]@{
    root = "2176FE3DD74488153D42A87CDE6FD9C2D248ACFA9D5094E04378020C6AC6E0F5"
    bundle = "3EF77A3AECED932AD297BC164D3FEDF51859DE7CF4B2DBF179389D40551712F1"
    realized_technologies = 10; realized_effects = 14; realized_settings = 43; realized_compatibility = 0
    technologies_minimum = 60
    settings_minimum = 20
    locales_minimum = 250
    compatibility_minimum = 0
  }
  "1.5.5" = [ordered]@{
    root = "81671E6577CBA23348AA0FDECAD653ED3675182175BF1B3B1413F3E9BF417E5D"
    bundle = "8940651109715E1F891274FC41D67C5775B5F5302B1FF08893C64F25E6E7F3A7"
    realized_technologies = 3; realized_effects = 3; realized_settings = 43; realized_compatibility = 0
    technologies_minimum = 60
    settings_minimum = 20
    locales_minimum = 250
    compatibility_minimum = 0
  }
  "1.4.5" = [ordered]@{
    root = "C0B7E4A9DE2968D778BB180AF3C93AF43D2ADCBEDF43315738897DACD795A672"
    bundle = "2976715689F22C07820DB4E98F383507B0F118B4DD196DFC382956756EDE369A"
    realized_technologies = 2; realized_effects = 2; realized_settings = 0; realized_compatibility = 0
    technologies_minimum = 60
    settings_minimum = 20
    locales_minimum = 250
    compatibility_minimum = 0
  }
  "1.3.5" = [ordered]@{
    root = "07B8C5AD6525B8AB19F2ACE430FB7C2FC465910957FD5CD5FAF6C3D2EB3FD43A"
    bundle = "98330B778142921CD7F15E9BE07509F47EE9C618E3436F4B43FF584534478917"
    realized_technologies = 2; realized_effects = 2; realized_settings = 0; realized_compatibility = 0
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
$null = New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "build")
$resolvedBuildRoot = (Resolve-Path -LiteralPath (Join-Path $RepoRoot "build")).Path.TrimEnd('\') + '\'

if (Test-Path -LiteralPath $testRoot) {
  $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
  if (-not $resolvedTestRoot.StartsWith($resolvedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace terminal baseline test output outside build/."
  }
  Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}

try {
  $probeSource = Join-Path $baselineRoot "3.2.5\declared\compatibility-claims.json"
  $probePath = Join-Path $testRoot "line-ending-probe.json"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $probePath) | Out-Null
  $probeText = [IO.File]::ReadAllText($probeSource) -replace "`r`n", "`n" -replace "`r", "`n"
  [IO.File]::WriteAllText($probePath, ($probeText -replace "`n", "`r`n"), [Text.UTF8Encoding]::new($false))
  if ((Get-CanonicalTextFileSha256 $probePath) -ne (Get-CanonicalTextFileSha256 $probeSource) -or
      (Get-CanonicalTextFileBytes $probePath).Length -ne (Get-CanonicalTextFileBytes $probeSource).Length) {
    throw "Canonical text identity is not invariant across LF and CRLF checkouts."
  }
  if ((Get-FileHash -LiteralPath $probePath -Algorithm SHA256).Hash -eq (Get-CanonicalTextFileSha256 $probePath)) {
    throw "Line-ending regression probe did not exercise distinct CRLF physical bytes."
  }

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
        [string]$manifest.capture_tool.version -ne "2" -or
        [string]$manifest.completion.state -ne "complete" -or
        -not [bool]$manifest.completion.public_identities_reconciled -or
        -not [bool]$manifest.completion.required_files_present -or
        -not [bool]$manifest.completion.exact_engine_observation_passed -or
        -not [bool]$manifest.completion.inventories_complete_or_capability_omitted -or
        -not [bool]$manifest.completion.contradictions_classified) {
      throw "$release realized baseline is not completely reconciled."
    }
    if ([string]$manifest.baseline_root_sha256 -ne [string]$expected[$release].root -or @($manifest.files).Count -ne 26) {
      throw "$release baseline root or manifest file count drifted."
    }

    foreach ($row in @($manifest.files)) {
      $path = Join-Path $trackedRoot ([string]$row.path)
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
          (Get-CanonicalTextFileSha256 $path) -ne [string]$row.sha256 -or
          (Get-CanonicalTextFileBytes $path).Length -ne [long]$row.bytes) {
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

    $realizedTechnology = Get-Content -Raw -LiteralPath (Join-Path $trackedRoot "realized\technologies.json") | ConvertFrom-Json -Depth 100
    $realizedEffects = Get-Content -Raw -LiteralPath (Join-Path $trackedRoot "realized\effects-and-owners.json") | ConvertFrom-Json -Depth 100
    $realizedSettings = Get-Content -Raw -LiteralPath (Join-Path $trackedRoot "realized\settings.json") | ConvertFrom-Json -Depth 100
    $realizedCompatibility = Get-Content -Raw -LiteralPath (Join-Path $trackedRoot "realized\compatibility-observations.json") | ConvertFrom-Json -Depth 100
    if (@($realizedTechnology.items).Count -ne [int]$expected[$release].realized_technologies -or
        @($realizedEffects.items).Count -ne [int]$expected[$release].realized_effects -or
        @($realizedSettings.items).Count -ne [int]$expected[$release].realized_settings -or
        @($realizedCompatibility.items).Count -ne [int]$expected[$release].realized_compatibility) {
      throw "$release exact-engine realized inventory count drifted."
    }
    if ($release -in @("1.4.5", "1.3.5") -and @($realizedSettings.explicit_omissions).Count -eq 0) {
      throw "$release must retain the independently established settings-stage capability omission."
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
      [string]$matrix.status -ne "complete" -or
      (@($matrix.release_order) -join "|") -ne ($releaseOrder -join "|") -or
      @($matrix.releases).Count -ne 9 -or
      -not [bool]$matrix.completion.all_nine_static_inventories_present -or
      -not [bool]$matrix.completion.all_nine_realized_engine_inventories_complete -or
      -not [bool]$matrix.completion.contradictions_classified -or
      -not [bool]$matrix.completion.queue_completion_permitted) {
    throw "Terminal .5 semantic matrix is incomplete, out of order, or lacks realized reconciliation."
  }
  if ([string]$matrix.generated_by.sha256 -ne (Get-CanonicalTextFileSha256 (Join-Path $RepoRoot ([string]$matrix.generated_by.path)))) {
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
        [string]$rows[0].completion_state -ne "complete") {
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
  if (@($matrix.unresolved_findings).Count -ne 0) { throw "Terminal .5 semantic matrix must contain no unresolved baseline realization findings." }

  $generatedMatrix = Join-Path $testRoot "MIR3-Dot5-Semantic-MatrixV1.json"
  & (Join-Path $RepoRoot "scripts\Export-MIRTerminalBaselineMatrix.ps1") -RepoRoot $RepoRoot -OutputPath $generatedMatrix | Out-Host
  if ((Get-CanonicalTextFileSha256 $generatedMatrix) -ne (Get-CanonicalTextFileSha256 $matrixPath)) {
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

Write-Host "[ok] terminal baseline capture is exact, deterministic, realized, and reconciled"
