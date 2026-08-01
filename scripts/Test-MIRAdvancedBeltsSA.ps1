[CmdletBinding()]
param(
  [string]$Candidate = "dist\more-infinite-research_2.5.0.zip",
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$LocalModZipDir = "C:\Projects\Factorio\testmods_2.0",
  [string]$ExpectedSourceCommit = "",
  [string]$OutputPath = "artifacts\assurance\2.5.0-advanced-belts-sa.json",
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\FactorioProcess.ps1")
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")

function Resolve-MIRLocalPath {
  param([Parameter(Mandatory)][string]$Path)
  $candidatePath = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  return [IO.Path]::GetFullPath($candidatePath)
}

function Assert-MIRExactSha256 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Expected,
    [Parameter(Mandatory)][string]$Label
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if ($actual -ne $Expected) { throw "$Label SHA-256 mismatch: $actual" }
  return $actual
}

$candidatePath = Resolve-MIRLocalPath -Path $Candidate
$factorioPath = Resolve-MIRLocalPath -Path $FactorioBin
$modLibraryPath = Resolve-MIRLocalPath -Path $LocalModZipDir
$outputFile = Resolve-MIRLocalPath -Path $OutputPath
$authority = (Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\releases.json") | ConvertFrom-Json).development."factorio-2.0"
if ([string]$authority.candidate_id -ne "2.5-P10") { throw "AdvancedBeltsSA qualification requires active candidate 2.5-P10." }

$candidateHash = Assert-MIRExactSha256 -Path $candidatePath -Expected ([string]$authority.archive_sha256) -Label "P10 candidate"
$candidateContentHash = Get-MIRZipContentFingerprint -Path $candidatePath
if ($candidateContentHash -ne [string]$authority.package_content_sha256) {
  throw "P10 candidate content fingerprint mismatch: $candidateContentHash"
}

$qualificationCommit = (& git -C $repo rev-parse HEAD).Trim()
if ($ExpectedSourceCommit -and $qualificationCommit -ne $ExpectedSourceCommit) {
  throw "Qualification source commit mismatch: $qualificationCommit"
}
$packageSourceCommit = [string]$authority.package_source_commit
& git -C $repo merge-base --is-ancestor $packageSourceCommit $qualificationCommit
if ($LASTEXITCODE -ne 0) { throw "P10 package source is not an ancestor of the qualification source." }
$packageRoots = @(Get-MIRPackageSourceRoots)
& git -C $repo diff --quiet $packageSourceCommit $qualificationCommit -- @packageRoots
if ($LASTEXITCODE -ne 0) { throw "Package-visible source changed after the P10 package source." }

if (-not (Test-Path -LiteralPath $factorioPath -PathType Leaf)) { throw "Factorio binary is missing: $factorioPath" }
$factorioVersion = Get-MIRFactorioBinaryVersion -Path $factorioPath
if (-not $factorioVersion.StartsWith("2.0.77", [StringComparison]::Ordinal)) {
  throw "AdvancedBeltsSA qualification requires Factorio 2.0.77; found $factorioVersion"
}
$factorioHash = (Get-FileHash -LiteralPath $factorioPath -Algorithm SHA256).Hash

$advancedBeltsPath = Join-Path $modLibraryPath "AdvancedBeltsSA_2.3.3.zip"
$advancedBeltsHash = Assert-MIRExactSha256 -Path $advancedBeltsPath -Expected "A5D62D3EB189442574209625369E60EBFB04956921D7704A354823A80AAF241A" -Label "AdvancedBeltsSA 2.3.3"
$assertionFixture = Join-Path $repo "fixtures\assert-advanced-belts-sa-productivity"
if (-not (Test-Path -LiteralPath $assertionFixture -PathType Container)) {
  throw "AdvancedBeltsSA assertion fixture is missing."
}

$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $repo "artifacts"))
$runRoot = [IO.Path]::GetFullPath((Join-Path $artifactsRoot "advanced-belts-sa\p10"))
if (-not $runRoot.StartsWith($artifactsRoot.TrimEnd("\") + "\", [StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to use an AdvancedBeltsSA run root outside artifacts."
}
if (Test-Path -LiteralPath $runRoot) { Remove-Item -LiteralPath $runRoot -Recurse -Force }
$modsDir = Join-Path $runRoot "mods"
New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
Copy-MIRFileWithHardlinkFallback -Source $candidatePath -Destination (Join-Path $modsDir (Split-Path -Leaf $candidatePath))
Copy-MIRFileWithHardlinkFallback -Source $advancedBeltsPath -Destination (Join-Path $modsDir (Split-Path -Leaf $advancedBeltsPath))
Copy-MIRModDirectory -Source $assertionFixture -Name "mir-fixture-assert-advanced-belts-sa-productivity" -ModsDir $modsDir

$modList = [ordered]@{
  mods = @(
    [ordered]@{name="base"; enabled=$true},
    [ordered]@{name="elevated-rails"; enabled=$true},
    [ordered]@{name="quality"; enabled=$true},
    [ordered]@{name="recycler"; enabled=$true},
    [ordered]@{name="space-age"; enabled=$true},
    [ordered]@{name="more-infinite-research"; enabled=$true},
    [ordered]@{name="AdvancedBeltsSA"; enabled=$true},
    [ordered]@{name="mir-fixture-assert-advanced-belts-sa-productivity"; enabled=$true}
  )
}
$modList | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $modsDir "mod-list.json") -Encoding UTF8

$factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $factorioPath))
$readData = Join-Path $factorioRoot "data"
if (-not (Test-Path -LiteralPath $readData -PathType Container)) {
  throw "Factorio read-data directory is missing: $readData"
}
$configPath = Join-Path $runRoot "config.ini"
$configText = @"
; Generated by MIR AdvancedBeltsSA qualification.
[path]
read-data=$readData
write-data=$runRoot

[general]
locale=auto

[other]
enable-steam-networking=false
disable-blueprint-storage=true
"@
Set-Content -LiteralPath $configPath -Value $configText -Encoding UTF8

$savePath = Join-Path $runRoot "advanced-belts-sa-p10.zip"
$arguments = @(
  "--config", $configPath,
  "--no-log-rotation",
  "--disable-audio",
  "--mod-directory", $modsDir,
  "--create", $savePath
)
$exitCode = Invoke-FactorioProcess -FilePath $factorioPath -Arguments $arguments -TimeoutMs ($TimeoutSeconds * 1000)
$logPath = Join-Path $runRoot "factorio-current.log"
if ($exitCode -ne 0) { throw "AdvancedBeltsSA Factorio run exited with code $exitCode. Log: $logPath" }
if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw "AdvancedBeltsSA run did not create a save." }
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "AdvancedBeltsSA run did not create a Factorio log." }
$logText = Get-Content -Raw -LiteralPath $logPath
if ($logText.Contains("------------- Error -------------") -or $logText.Contains("Error Util.cpp")) {
  throw "AdvancedBeltsSA Factorio log contains a fatal marker."
}
$successMarker = "[mir-fixture-assert-advanced-belts-sa-productivity] passed: 12 structural belt recipes and 4 cryogenic return contracts"
if (-not $logText.Contains($successMarker)) {
  throw "AdvancedBeltsSA assertion success marker is absent."
}

$evidence = [ordered]@{
  schema = 1
  kind = "mir-advanced-belts-sa-native-qualification"
  status = "passed"
  release = "2.5.0"
  candidate_id = "2.5-P10"
  candidate = [ordered]@{
    path = [IO.Path]::GetRelativePath($repo, $candidatePath).Replace("\", "/")
    archive_sha256 = $candidateHash
    content_sha256 = $candidateContentHash
    package_source_commit = $packageSourceCommit
    qualification_source_commit = $qualificationCommit
  }
  factorio = [ordered]@{
    version = $factorioVersion
    binary_sha256 = $factorioHash
  }
  external_mod = [ordered]@{
    name = "AdvancedBeltsSA"
    version = "2.3.3"
    archive_sha256 = $advancedBeltsHash
  }
  assertions = [ordered]@{
    expected_belt_recipe_effects = 12
    cryogenic_ignored_returns = 4
    exact_success_marker = $successMarker
  }
  artifacts = [ordered]@{
    log = [IO.Path]::GetRelativePath($repo, $logPath).Replace("\", "/")
    save = [IO.Path]::GetRelativePath($repo, $savePath).Replace("\", "/")
  }
  completed_at = (Get-Date).ToUniversalTime().ToString("o")
}
$outputParent = Split-Path -Parent $outputFile
New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputFile -Encoding UTF8
Write-Host "[ok] Exact P10 AdvancedBeltsSA 2.3.3 native Factorio 2.0.77 qualification passed."
Write-Host "[ok] Evidence: $outputFile"
