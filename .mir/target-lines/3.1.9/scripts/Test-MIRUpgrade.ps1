param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$FromZip,
  [Parameter(Mandatory)][string]$ToZip,
  [string]$FromVersion = "3.0.5",
  [string]$ToVersion = "3.1.0",
  [string]$FixtureName = "assert-upgrade-3-0-5-to-3-1-0",
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
  @(
    Get-Content -LiteralPath $Source |
      ForEach-Object { $_.TrimEnd() }
  ) | Set-Content -LiteralPath $Destination -Encoding UTF8
}

$factorio = Resolve-MIRUpgradePath -Path $FactorioBin
$from = Resolve-MIRUpgradePath -Path $FromZip
$to = Resolve-MIRUpgradePath -Path $ToZip
$fixture = Resolve-MIRUpgradePath -Path (Join-Path $RepoRoot "fixtures\$FixtureName")
$fixtureInfo = Get-Content -Raw -LiteralPath (Join-Path $fixture "info.json") | ConvertFrom-Json
$fixtureModName = [string]$fixtureInfo.name
$proofSuffix = if ($FixtureName -like "*-automatic-compiler") { " automatic compiler" } else { "" }
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = ".mir\evidence\$ToVersion-upgrade-proof.json"
}
$output = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent)) { New-Item -ItemType Directory -Force -Path $outputParent | Out-Null }

$upgradeSlug = (($FromVersion + "-to-" + $ToVersion) -replace '[^0-9A-Za-z.-]', '-')
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

$modList = [ordered]@{ mods = @(
  @{ name = "base"; enabled = $true },
  @{ name = "elevated-rails"; enabled = $true },
  @{ name = "quality"; enabled = $true },
  @{ name = "recycler"; enabled = $true },
  @{ name = "space-age"; enabled = $true },
  @{ name = "more-infinite-research"; enabled = $true },
  @{ name = $fixtureModName; enabled = $true }
) }
$modList | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $mods "mod-list.json") -Encoding UTF8
Copy-Item -LiteralPath $from -Destination (Join-Path $mods (Split-Path -Leaf $from))
Copy-Item -LiteralPath $fixture -Destination (Join-Path $mods $fixtureModName) -Recurse

$save = Join-Path $root "mir-$FromVersion-save.zip"
$log = Join-Path $userdata "factorio-current.log"
$createArgs = @("--config", $config, "--no-log-rotation", "--disable-audio", "--mod-directory", $mods, "--create", $save)
$createExitCode = Invoke-FactorioProcess -FilePath $factorio -Arguments $createArgs
if ($createExitCode -ne 0 -or -not (Test-Path -LiteralPath $save)) {
  throw "MIR $FromVersion upgrade source save creation failed with exit code $createExitCode."
}
$createText = Get-Content -Raw -LiteralPath $log
if (-not $createText.Contains("[mir-fixture] $FromVersion$proofSuffix upgrade source proof complete")) {
  throw "MIR $FromVersion upgrade source proof marker is missing."
}
$createEvidence = Join-Path $outputParent "$ToVersion-upgrade-from-$FromVersion-create.txt"
Copy-MIRUpgradeLogEvidence -Source $log -Destination $createEvidence

Get-ChildItem -LiteralPath $mods -File -Filter "more-infinite-research_*.zip" | Remove-Item -Force
Copy-Item -LiteralPath $to -Destination (Join-Path $mods (Split-Path -Leaf $to))
$loadArgs = @(
  "--config", $config, "--no-log-rotation", "--disable-audio", "--mod-directory", $mods,
  "--benchmark", $save, "--benchmark-ticks", "1", "--benchmark-runs", "1", "--benchmark-sanitize"
)
$loadExitCode = Invoke-FactorioProcess -FilePath $factorio -Arguments $loadArgs
if ($loadExitCode -ne 0) { throw "MIR $ToVersion upgrade load failed with exit code $loadExitCode." }
$loadText = Get-Content -Raw -LiteralPath $log
if (-not $loadText.Contains("[mir-fixture] $FromVersion to $ToVersion$proofSuffix upgrade proof complete")) {
  throw "MIR $ToVersion upgrade proof marker is missing."
}
$loadEvidence = Join-Path $outputParent "$ToVersion-upgrade-from-$FromVersion-load.txt"
Copy-MIRUpgradeLogEvidence -Source $log -Destination $loadEvidence

$assertions = if ($FixtureName -eq "assert-upgrade-3-1-5-to-3-1-9") {
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
  schema = 1
  status = "passed"
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  git_commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  factorio_binary_version = (Get-Item -LiteralPath $factorio).VersionInfo.FileVersion
  from = [ordered]@{ version = $FromVersion; path = $FromZip; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $from).Hash }
  to = [ordered]@{ version = $ToVersion; path = $ToZip; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $to).Hash }
  assertions = $assertions
  create_log = (Split-Path -Leaf $createEvidence)
  load_log = (Split-Path -Leaf $loadEvidence)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $output -Encoding UTF8

Write-Host "[ok] MIR $FromVersion to $ToVersion upgrade proof: $output"
