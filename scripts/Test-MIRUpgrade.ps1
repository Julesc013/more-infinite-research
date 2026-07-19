param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$FromZip,
  [Parameter(Mandatory)][string]$ToZip,
  [string]$FromVersion = "3.0.5",
  [string]$ToVersion = "3.1.0",
  [string]$FixtureName = "assert-upgrade-3-0-5-to-3-1-0",
  [ValidateSet("", "base-default", "space-age-native-owner", "automatic-family-creation", "base-continuations", "mod-set-configuration-change")]
  [string]$Archetype = "",
  [string[]]$SourceOnlyFixtureNames = @(),
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $RepoRoot "scripts\validation\FactorioProcess.ps1")

function Resolve-MIRUpgradePath {
  param([Parameter(Mandatory)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return (Resolve-Path -LiteralPath $Path).Path }
  return (Resolve-Path -LiteralPath (Join-Path $RepoRoot $Path)).Path
}

function Copy-MIRUpgradeLogEvidence {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination
  )
  $normalized = @(
    Get-Content -LiteralPath $Source |
      Where-Object { $_ -notmatch 'System info:|Memory info:|\s\[[0-9]+\]:\s' } |
      ForEach-Object {
        $_.TrimEnd() `
          -replace '(?i)[A-Z]:\\Program Files\\Steam\\steamapps\\common\\Factorio', '<factorio-install>' `
          -replace '(?i)[A-Z]:/Program Files/Steam/steamapps/common/Factorio', '<factorio-install>' `
          -replace '(?i)[A-Z]:\\Users\\[^\\]+\\AppData\\Local\\Temp\\mir-upgrade-[^\\\s"]+', '<temp-upgrade-root>' `
          -replace '(?i)[A-Z]:/Users/[^/]+/AppData/Local/Temp/mir-upgrade-[^/\s"]+', '<temp-upgrade-root>'
      }
  )
  $normalized | Set-Content -LiteralPath $Destination -Encoding UTF8
}

function Write-MIRUpgradeModList {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$FixtureModName,
    [Parameter(Mandatory)][bool]$EnableDlc,
    [string[]]$AdditionalModNames = @()
  )
  $rows = @(
    @{ name = "base"; enabled = $true }
    @{ name = "elevated-rails"; enabled = $EnableDlc }
    @{ name = "quality"; enabled = $EnableDlc }
    @{ name = "recycler"; enabled = $EnableDlc }
    @{ name = "space-age"; enabled = $EnableDlc }
    @{ name = "more-infinite-research"; enabled = $true }
    @{ name = $FixtureModName; enabled = $true }
  )
  foreach ($name in $AdditionalModNames) { $rows += @{ name = $name; enabled = $true } }
  [ordered]@{ mods = $rows } | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $Path -Encoding UTF8
}

$factorio = Resolve-MIRUpgradePath -Path $FactorioBin
$from = Resolve-MIRUpgradePath -Path $FromZip
$to = Resolve-MIRUpgradePath -Path $ToZip
$factorioVersionInfo = (Get-Item -LiteralPath $factorio).VersionInfo
$isLegacyFactorio = [int]$factorioVersionInfo.FileMajorPart -lt 2
$fixture = Resolve-MIRUpgradePath -Path (Join-Path $RepoRoot "fixtures\$FixtureName")
$fixtureInfo = Get-Content -Raw -LiteralPath (Join-Path $fixture "info.json") | ConvertFrom-Json
$fixtureModName = [string]$fixtureInfo.name
$proofSuffix = if ($FixtureName -like "*-automatic-compiler") { " automatic compiler" } else { "" }
$archetypeSuffix = if ($Archetype) { " archetype=$Archetype" } else { "" }
$artifactSlug = if ($Archetype) { $Archetype } else { "default" }
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = ".mir\evidence\$ToVersion-upgrade-$artifactSlug-proof.json"
}
$output = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent)) { New-Item -ItemType Directory -Force -Path $outputParent | Out-Null }

$upgradeSlug = (($FromVersion + "-to-" + $ToVersion + "-" + $artifactSlug) -replace '[^0-9A-Za-z.-]', '-')
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("mir-upgrade-$upgradeSlug-" + [guid]::NewGuid().ToString("N"))
$mods = Join-Path $root "mods"
$userdata = Join-Path $root "userdata"
New-Item -ItemType Directory -Force -Path $mods, $userdata | Out-Null
$config = Join-Path $root "config.ini"
@(
  "[path]",
  "read-data=__PATH__executable__/../../data",
  "write-data=$($userdata.Replace('\', '/'))",
  "[other]",
  "check-updates=false"
) | Set-Content -LiteralPath $config -Encoding UTF8

$enableDlc = -not $isLegacyFactorio
if ($Archetype) { $enableDlc = $Archetype -eq "space-age-native-owner" }
$sourceOnlyModNames = @()
foreach ($sourceFixtureName in $SourceOnlyFixtureNames) {
  $sourceFixture = Resolve-MIRUpgradePath -Path (Join-Path $RepoRoot "fixtures\$sourceFixtureName")
  $sourceInfo = Get-Content -Raw -LiteralPath (Join-Path $sourceFixture "info.json") | ConvertFrom-Json
  $sourceModName = [string]$sourceInfo.name
  if ([string]::IsNullOrWhiteSpace($sourceModName)) { throw "Source-only fixture $sourceFixtureName has no mod name." }
  Copy-Item -LiteralPath $sourceFixture -Destination (Join-Path $mods $sourceModName) -Recurse
  $sourceOnlyModNames += $sourceModName
}

$modListPath = Join-Path $mods "mod-list.json"
Write-MIRUpgradeModList -Path $modListPath -FixtureModName $fixtureModName -EnableDlc $enableDlc -AdditionalModNames $sourceOnlyModNames
Copy-Item -LiteralPath $from -Destination (Join-Path $mods (Split-Path -Leaf $from))
$stagedFixture = Join-Path $mods $fixtureModName
Copy-Item -LiteralPath $fixture -Destination $stagedFixture -Recurse
if ($Archetype) {
  $settingsPath = Join-Path $stagedFixture "settings.lua"
  if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw "Upgrade archetype selection requires fixture settings.lua: $settingsPath"
  }
  $settingsText = Get-Content -Raw -LiteralPath $settingsPath
  $updatedSettingsText = $settingsText -replace 'default_value\s*=\s*"[^"]+"', ('default_value = "' + $Archetype + '"')
  if ($updatedSettingsText -eq $settingsText -and $settingsText -notmatch ('default_value\s*=\s*"' + [regex]::Escape($Archetype) + '"')) {
    throw "Could not select upgrade archetype $Archetype in $settingsPath"
  }
  Set-Content -LiteralPath $settingsPath -Value $updatedSettingsText -Encoding UTF8
}

$save = Join-Path $root "mir-$FromVersion-$artifactSlug-save.zip"
$log = Join-Path $userdata "factorio-current.log"
$createArgs = @("--config", $config, "--no-log-rotation", "--disable-audio", "--mod-directory", $mods, "--create", $save)
$createExitCode = Invoke-FactorioProcess -FilePath $factorio -Arguments $createArgs
if (-not (Test-Path -LiteralPath $save) -or ($createExitCode -ne 0 -and -not $isLegacyFactorio)) {
  throw "MIR $FromVersion upgrade source save creation failed with exit code $createExitCode. Temporary root: $root"
}
$createText = Get-Content -Raw -LiteralPath $log
if ($isLegacyFactorio -and -not $createText.Contains("[mir-fixture] $FromVersion$proofSuffix upgrade source proof complete$archetypeSuffix")) {
  $sourceInitArgs = @(
    "--config", $config, "--no-log-rotation", "--disable-audio", "--mod-directory", $mods,
    "--start-server", $save, "--until-tick", "1"
  )
  $sourceInitExitCode = Invoke-FactorioProcess -FilePath $factorio -Arguments $sourceInitArgs
  if ($sourceInitExitCode -ne 0) {
    throw "MIR $FromVersion legacy source-save initialization failed with exit code $sourceInitExitCode. Temporary root: $root"
  }
  $createText = Get-Content -Raw -LiteralPath $log
}
$sourceMarker = "[mir-fixture] $FromVersion$proofSuffix upgrade source proof complete$archetypeSuffix"
if (-not $createText.Contains($sourceMarker)) {
  throw "MIR $FromVersion upgrade source proof marker is missing: $sourceMarker. Temporary root: $root"
}
$createEvidence = Join-Path $outputParent "$ToVersion-upgrade-$artifactSlug-from-$FromVersion-create.txt"
Copy-MIRUpgradeLogEvidence -Source $log -Destination $createEvidence

Get-ChildItem -LiteralPath $mods -File -Filter "more-infinite-research_*.zip" | Remove-Item -Force
Copy-Item -LiteralPath $to -Destination (Join-Path $mods (Split-Path -Leaf $to))
foreach ($sourceModName in $sourceOnlyModNames) {
  $sourcePath = Join-Path $mods $sourceModName
  $resolvedSourcePath = (Resolve-Path -LiteralPath $sourcePath).Path
  if (-not $resolvedSourcePath.StartsWith($mods, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove source-only fixture outside temporary mod directory: $resolvedSourcePath"
  }
  Remove-Item -LiteralPath $resolvedSourcePath -Recurse -Force
}
Write-MIRUpgradeModList -Path $modListPath -FixtureModName $fixtureModName -EnableDlc $enableDlc

$loadArgs = @(
  "--config", $config, "--no-log-rotation", "--disable-audio", "--mod-directory", $mods,
  "--benchmark", $save, "--benchmark-ticks", "1", "--benchmark-runs", "1", "--benchmark-sanitize"
)
$loadExitCode = Invoke-FactorioProcess -FilePath $factorio -Arguments $loadArgs
if ($loadExitCode -ne 0) { throw "MIR $ToVersion upgrade load failed with exit code $loadExitCode. Temporary root: $root" }
$loadText = Get-Content -Raw -LiteralPath $log
$loadMarker = "[mir-fixture] $FromVersion to $ToVersion$proofSuffix upgrade proof complete$archetypeSuffix"
if (-not $loadText.Contains($loadMarker)) {
  throw "MIR $ToVersion upgrade proof marker is missing: $loadMarker. Temporary root: $root"
}
$loadEvidence = Join-Path $outputParent "$ToVersion-upgrade-$artifactSlug-from-$FromVersion-load.txt"
Copy-MIRUpgradeLogEvidence -Source $log -Destination $loadEvidence

$assertions = if ($Archetype) {
  $common = @(
    "startup-profile-retained",
    "technology-level-retained",
    "current-research-retained",
    "fractional-research-progress-retained",
    "fixture-storage-retained",
    "exact-candidate-normal-mod-directory-load"
  )
  switch ($Archetype) {
    "base-default" { $common + @("base-only-mod-set-retained") }
    "space-age-native-owner" { $common + @("space-age-native-owner-retained") }
    "automatic-family-creation" { $common + @("automatic-generated-family-retained", "automatic-recipe-target-retained") }
    "base-continuations" { $common + @("base-continuation-retained") }
    "mod-set-configuration-change" { $common + @("source-only-mod-removed", "removed-recipe-target-sanitized") }
  }
} elseif ($isLegacyFactorio) {
  @(
    "startup-setting-retained",
    "generated-technology-level-retained",
    "current-research-retained",
    "fractional-research-progress-retained",
    "global-runtime-state-retained",
    "exact-candidate-normal-mod-directory-load"
  )
} elseif ($FixtureName -in @("assert-upgrade-3-1-5-to-3-1-9", "assert-upgrade-3-1-9-to-3-2-0")) {
  @(
    "startup-settings-retained",
    "native-owner-technology-level-retained",
    "native-owner-current-research-retained",
    "native-owner-fractional-progress-retained",
    "fixture-storage-retained",
    "exact-candidate-normal-mod-directory-load"
  )
} else {
  @(
    "startup-setting-retained",
    "effect-setting-retained",
    "technology-level-retained",
    "fixture-storage-retained",
    "scripted-runtime-effect-retained",
    "exact-candidate-normal-mod-directory-load"
  )
}

[ordered]@{
  schema = 2
  status = "passed"
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  git_commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  archetype = if ($Archetype) { $Archetype } else { "default" }
  factorio_binary_version = $factorioVersionInfo.FileVersion
  factorio_binary_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $factorio).Hash
  from = [ordered]@{ version = $FromVersion; path = $FromZip; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $from).Hash }
  to = [ordered]@{ version = $ToVersion; path = $ToZip; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $to).Hash }
  source_only_fixtures = @($SourceOnlyFixtureNames)
  assertions = $assertions
  create_log = (Split-Path -Leaf $createEvidence)
  create_log_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $createEvidence).Hash
  load_log = (Split-Path -Leaf $loadEvidence)
  load_log_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $loadEvidence).Hash
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $output -Encoding UTF8

Write-Host "[ok] MIR $FromVersion to $ToVersion upgrade proof ($artifactSlug): $output"
