param(
  [string]$OutputDir = "dist",
  [ValidateSet("Fastest", "NoCompression", "Optimal")]
  [string]$CompressionLevel = "Optimal"
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
$infoPath = Join-Path $repo "info.json"
$info = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json

$packageName = "$($info.name)_$($info.version)"
$buildRoot = Join-Path $repo "build\package"
$packageRoot = Join-Path $buildRoot $packageName
$outputRoot = Join-Path $repo $OutputDir
$zipPath = Join-Path $outputRoot "$packageName.zip"
$tempZipPath = Join-Path $buildRoot "$packageName.new.zip"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
$compression = [System.IO.Compression.CompressionLevel]::$CompressionLevel

if (Test-Path -LiteralPath $packageRoot) {
  Remove-Item -LiteralPath $packageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

foreach ($relative in Get-MIRPackageSourceFiles -RepoRoot $repo) {
  $source = Join-Path $repo $relative
  $destination = Join-Path $packageRoot $relative
  $parent = Split-Path -Parent $destination
  if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  Copy-Item -LiteralPath $source -Destination $destination
}

if (Test-Path -LiteralPath $tempZipPath) {
  Remove-Item -LiteralPath $tempZipPath -Force
}

$fileStream = [System.IO.File]::Open($tempZipPath, [System.IO.FileMode]::CreateNew)
$archive = [System.IO.Compression.ZipArchive]::new(
  $fileStream,
  [System.IO.Compression.ZipArchiveMode]::Create,
  $false
)
try {
  foreach ($relative in @(Get-MIRPackageSourceFiles -RepoRoot $repo | Sort-Object)) {
    $entryName = ($packageName + "/" + $relative.Replace("\", "/"))
    $entry = $archive.CreateEntry($entryName, $compression)
    $entry.LastWriteTime = $fixedTimestamp
    $entry.ExternalAttributes = 0
    $input = [System.IO.File]::OpenRead((Join-Path $repo $relative))
    $output = $entry.Open()
    try {
      $input.CopyTo($output)
    } finally {
      $output.Dispose()
      $input.Dispose()
    }
  }
} finally {
  $archive.Dispose()
  $fileStream.Dispose()
}

if ((Test-Path -LiteralPath $zipPath) -and
  (Get-MIRFileSha256 -Path $zipPath) -eq (Get-MIRFileSha256 -Path $tempZipPath)) {
  Remove-Item -LiteralPath $tempZipPath -Force
  Write-Host "Built $zipPath (unchanged)"
  return
}

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Move-Item -LiteralPath $tempZipPath -Destination $zipPath

Write-Host "Built $zipPath"
