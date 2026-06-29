param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$UserDataDir = $env:FACTORIO_USERDATA,
  [switch]$StaticOnly
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")

function Invoke-RepoCheck {
  param([string]$Description, [scriptblock]$Script)
  Write-Host "[check] $Description"
  & $Script
}

Invoke-RepoCheck "info.json parses" {
  $null = Get-Content -Raw (Join-Path $repo "info.json") | ConvertFrom-Json
}

Invoke-RepoCheck "release metadata avoids compatibility mod dependencies" {
  $info = Get-Content -Raw (Join-Path $repo "info.json") | ConvertFrom-Json
  $deps = @($info.dependencies)
  $compatDependencyModIds = @(
    "? Advanced-Electric-Revamped-v16",
    "? Better_Robots_Extended",
    "? OCs_ammo_casting",
    "? OCs_stone_casting",
    "? fluid-quality-imprinting",
    "? plates-n-circuit-productivity"
  )
  $present = @($compatDependencyModIds | Where-Object { $_ -in $deps })
  if ($present.Count -gt 0) {
    throw "Unexpected compatibility mod dependencies in info.json: $($present -join ', ')"
  }
}

Invoke-RepoCheck "docs match opportunistic compatibility policy" {
  $forbiddenPhrases = @(
    "declared as optional dependencies so More Infinite Research",
    "optional load-order dependencies",
    "optional dependencies for Space Age and known compatibility targets",
    "add optional or hidden optional dependencies"
  )
  $files = @(
    (Join-Path $repo "changelog.txt"),
    (Join-Path $repo "docs\compatibility.md"),
    (Join-Path $repo "docs\roadmap.md")
  )
  foreach ($file in $files) {
    $text = Get-Content -Raw -LiteralPath $file
    foreach ($phrase in $forbiddenPhrases) {
      if ($text.Contains($phrase)) {
        throw "Forbidden optional dependency policy phrase found in $file`: $phrase"
      }
    }
  }
}

Invoke-RepoCheck "no old tool-based science pack authority remains" {
  $matches = & rg --line-number "data.raw.tool|tool_exists|has_tool|PACKS_ALL" (Join-Path $repo "prototypes")
  if ($LASTEXITCODE -eq 0) {
    $matches | Write-Host
    throw "Old science-pack authority references remain."
  }
  if ($LASTEXITCODE -ne 1) { throw "rg failed while scanning science-pack authority." }
}

Invoke-RepoCheck "generated icons do not use icon_mipmaps" {
  $matches = & rg --line-number "icon_mipmaps" (Join-Path $repo "prototypes")
  if ($LASTEXITCODE -eq 0) {
    $matches | Write-Host
    throw "icon_mipmaps references remain in prototypes."
  }
  if ($LASTEXITCODE -ne 1) { throw "rg failed while scanning icon_mipmaps." }
}

Invoke-RepoCheck "locale files match English fallback" {
  & (Join-Path $repo "scripts\Test-MIRLocales.ps1") -AllowMissingSupportedLanguages
}

Invoke-RepoCheck "git whitespace check" {
  git -C $repo diff --check
}

if ($StaticOnly -or [string]::IsNullOrWhiteSpace($FactorioBin)) {
  Write-Host "[skip] Factorio runtime validation skipped. Set FACTORIO_BIN or pass -FactorioBin to run load tests."
  exit 0
}

if (-not (Test-Path -LiteralPath $FactorioBin)) {
  throw "Factorio binary not found: $FactorioBin"
}

if ([string]::IsNullOrWhiteSpace($UserDataDir)) {
  $UserDataDir = Join-Path ([System.IO.Path]::GetTempPath()) "mir-factorio-userdata"
}

$modsDir = Join-Path $UserDataDir "mods"
New-Item -ItemType Directory -Force -Path $modsDir | Out-Null

function Copy-ModDirectory {
  param([string]$Source, [string]$Name)
  $target = Join-Path $modsDir $Name
  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
  Copy-Item -LiteralPath $Source -Destination $target -Recurse
}

Copy-ModDirectory -Source $repo -Name "more-infinite-research"
$fixtureRoot = Join-Path $repo "fixtures"
if (-not (Test-Path -LiteralPath $fixtureRoot)) {
  throw "Fixture directory not found: $fixtureRoot"
}

$fixtureNames = @()
foreach ($fixture in Get-ChildItem -LiteralPath $fixtureRoot -Directory) {
  $info = Get-Content -Raw (Join-Path $fixture.FullName "info.json") | ConvertFrom-Json
  $fixtureNames += $info.name
  Copy-ModDirectory -Source $fixture.FullName -Name $info.name
}

$copiedInfoPath = Join-Path $modsDir "more-infinite-research\info.json"
$copiedInfo = Get-Content -Raw -LiteralPath $copiedInfoPath | ConvertFrom-Json
$dependencies = @($copiedInfo.dependencies)
foreach ($fixtureName in $fixtureNames) {
  $dependency = "? $fixtureName"
  if ($dependencies -notcontains $dependency) {
    $dependencies += $dependency
  }
}
$copiedInfo.dependencies = $dependencies
$copiedInfo | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $copiedInfoPath -Encoding UTF8

$modList = @{
  mods = @(
    @{ name = "base"; enabled = $true },
    @{ name = "more-infinite-research"; enabled = $true },
    @{ name = "mir-fixture-item-science-pack"; enabled = $true },
    @{ name = "mir-fixture-custom-lab"; enabled = $true },
    @{ name = "mir-fixture-late-recipe"; enabled = $true }
  )
} | ConvertTo-Json -Depth 5

Set-Content -LiteralPath (Join-Path $modsDir "mod-list.json") -Value $modList -Encoding UTF8

$savePath = Join-Path $UserDataDir "mir-validation.zip"
if (Test-Path -LiteralPath $savePath) {
  Remove-Item -LiteralPath $savePath -Force
}

Write-Host "[run] Factorio load check with fixture mods"
$factorioArgs = @(
  "--mod-directory",
  "`"$modsDir`"",
  "--create",
  "`"$savePath`""
)
$factorioProcess = Start-Process -FilePath $FactorioBin -ArgumentList $factorioArgs -Wait -PassThru -WindowStyle Hidden
$factorioExitCode = $factorioProcess.ExitCode
if ($factorioExitCode -ne 0) {
  throw "Factorio runtime validation exited with code $factorioExitCode"
}
if (-not (Test-Path -LiteralPath $savePath)) {
  throw "Factorio runtime validation did not create the expected save: $savePath. Factorio exit code: $factorioExitCode"
}

$factorioLog = Join-Path $env:APPDATA "Factorio\factorio-current.log"
if (Test-Path -LiteralPath $factorioLog) {
  $fatalMarkers = Select-String -LiteralPath $factorioLog -Pattern "------------- Error -------------", "Error Util.cpp" -SimpleMatch
  if ($fatalMarkers) {
    $fatalMarkers | Select-Object -First 10 | ForEach-Object { Write-Host $_.Line }
    throw "Factorio runtime validation log contains fatal error markers."
  }
}

Write-Host "[ok] Validation completed."
$global:LASTEXITCODE = 0
