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
$tempZipPath = Join-Path $buildRoot "$packageName.new.zip"

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-MIRZipContentManifest {
  param([Parameter(Mandatory)][string]$Path)

  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
  try {
    return @(
      $zip.Entries |
        Where-Object { -not [string]::IsNullOrEmpty($_.Name) } |
        Sort-Object FullName |
        ForEach-Object {
          $stream = $_.Open()
          try {
            $hashBytes = $sha256.ComputeHash($stream)
            $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
          } finally {
            $stream.Dispose()
          }

          "{0}`t{1}`t{2}" -f $_.FullName, $_.Length, $hash
        }
    )
  } finally {
    $zip.Dispose()
    $sha256.Dispose()
  }
}

function Test-MIRZipContentEqual {
  param(
    [Parameter(Mandatory)][string]$Left,
    [Parameter(Mandatory)][string]$Right
  )

  if (-not (Test-Path -LiteralPath $Left) -or -not (Test-Path -LiteralPath $Right)) {
    return $false
  }

  $leftManifest = @(Get-MIRZipContentManifest -Path $Left)
  $rightManifest = @(Get-MIRZipContentManifest -Path $Right)
  if ($leftManifest.Count -ne $rightManifest.Count) { return $false }

  for ($i = 0; $i -lt $leftManifest.Count; $i++) {
    if ($leftManifest[$i] -ne $rightManifest[$i]) { return $false }
  }

  return $true
}

if (Test-Path -LiteralPath $packageRoot) {
  Remove-Item -LiteralPath $packageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$files = @(
  "changelog.txt",
  "CONTRIBUTING.md",
  "control.lua",
  "data-final-fixes.lua",
  "data-updates.lua",
  "data.lua",
  "defaults.lua",
  "info.json",
  "LICENSE",
  "README.md",
  "settings.lua",
  "thumbnail.png",
  "todo.md"
)

$directories = @(
  "docs",
  "control",
  "locale",
  "migrations",
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

if (Test-Path -LiteralPath $tempZipPath) {
  Remove-Item -LiteralPath $tempZipPath -Force
}

Compress-Archive -LiteralPath $packageRoot -DestinationPath $tempZipPath -CompressionLevel $CompressionLevel

if ((Test-Path -LiteralPath $zipPath) -and (Test-MIRZipContentEqual -Left $zipPath -Right $tempZipPath)) {
  Remove-Item -LiteralPath $tempZipPath -Force
  Write-Host "Built $zipPath (unchanged)"
  return
}

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Move-Item -LiteralPath $tempZipPath -Destination $zipPath

Write-Host "Built $zipPath"
