param(
  [string]$OutputDir = "dist",
  [ValidateSet("Fastest", "NoCompression", "Optimal")]
  [string]$CompressionLevel = "Optimal"
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$infoPath = Join-Path $repo "info.json"
$info = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json

$packageName = "$($info.name)_$($info.version)"
$buildRoot = Join-Path $repo "build\package"
$packageRoot = Join-Path $buildRoot $packageName
$outputRoot = Join-Path $repo $OutputDir
$zipPath = Join-Path $outputRoot "$packageName.zip"

if (Test-Path -LiteralPath $packageRoot) {
  Remove-Item -LiteralPath $packageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$files = @(
  "changelog.txt",
  "data-final-fixes.lua",
  "data-updates.lua",
  "data.lua",
  "defaults.lua",
  "info.json",
  "LICENSE",
  "README.md",
  "settings.lua",
  "thumbnail.png"
)

$directories = @(
  "docs",
  "locale",
  "prototypes"
)

foreach ($file in $files) {
  $source = Join-Path $repo $file
  if (Test-Path -LiteralPath $source) {
    Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot $file)
  }
}

foreach ($directory in $directories) {
  $source = Join-Path $repo $directory
  if (Test-Path -LiteralPath $source) {
    Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot $directory) -Recurse
  }
}

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -CompressionLevel $CompressionLevel

Write-Host "Built $zipPath"
