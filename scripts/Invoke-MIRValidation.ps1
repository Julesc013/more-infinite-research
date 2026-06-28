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
foreach ($fixture in Get-ChildItem -LiteralPath (Join-Path $repo "dev-fixtures") -Directory) {
  $info = Get-Content -Raw (Join-Path $fixture.FullName "info.json") | ConvertFrom-Json
  Copy-ModDirectory -Source $fixture.FullName -Name $info.name
}

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

Write-Host "[run] Factorio load check with fixture mods"
& $FactorioBin --mod-directory $modsDir --create (Join-Path $UserDataDir "mir-validation.zip")
if ($LASTEXITCODE -ne 0) {
  throw "Factorio runtime validation failed with exit code $LASTEXITCODE."
}

Write-Host "[ok] Validation completed."
