param(
  [string]$OutputDir = "dist",
  [ValidateSet("Fastest", "NoCompression", "Optimal")]
  [string]$CompressionLevel = "Optimal"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$packageName = "$($info.name)_$($info.version)"
$buildRoot = Join-Path $repo "build\package"
$packageRoot = Join-Path $buildRoot $packageName
$outputRoot = Join-Path $repo $OutputDir
$zipPath = Join-Path $outputRoot "$packageName.zip"
$tempZipPath = Join-Path $buildRoot "$packageName.new.zip"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-MIRPackageFiles {
  $roots = @(
    "changelog.txt", "control.lua", "data-final-fixes.lua", "data-updates.lua",
    "data.lua", "info.json", "LICENSE", "README.md", "settings.lua", "thumbnail.png",
    "locale", "migrations", "prototypes"
  )
  $files = foreach ($relative in $roots) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $relative.Replace("\", "/")
    } elseif (Test-Path -LiteralPath $path -PathType Container) {
      Get-ChildItem -LiteralPath $path -Recurse -File | ForEach-Object {
        [System.IO.Path]::GetRelativePath($repo, $_.FullName).Replace("\", "/")
      }
    }
  }
  return @($files | Sort-Object -Unique)
}

function Test-MIRTextPackageFile([string]$RelativePath) {
  $extension = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
  return $extension -in @(".cfg", ".json", ".lua", ".md", ".txt") -or
    [System.IO.Path]::GetFileName($RelativePath) -eq "LICENSE"
}

if (Test-Path -LiteralPath $packageRoot) { Remove-Item -LiteralPath $packageRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $packageRoot, $outputRoot | Out-Null

$packageFiles = @(Get-MIRPackageFiles)
foreach ($relative in $packageFiles) {
  $source = Join-Path $repo $relative
  $destination = Join-Path $packageRoot $relative
  $parent = Split-Path -Parent $destination
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  Copy-Item -LiteralPath $source -Destination $destination
}

if (Test-Path -LiteralPath $tempZipPath) { Remove-Item -LiteralPath $tempZipPath -Force }
$fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
$compression = [System.IO.Compression.CompressionLevel]::$CompressionLevel
$fileStream = [System.IO.File]::Open($tempZipPath, [System.IO.FileMode]::CreateNew)
$archive = [System.IO.Compression.ZipArchive]::new($fileStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
try {
  foreach ($relative in $packageFiles) {
    $entry = $archive.CreateEntry("$packageName/$relative", $compression)
    $entry.LastWriteTime = $fixedTimestamp
    $entry.ExternalAttributes = 0
    $output = $entry.Open()
    try {
      $source = Join-Path $repo $relative
      if (Test-MIRTextPackageFile $relative) {
        $text = [System.IO.File]::ReadAllText($source).Replace("`r`n", "`n").Replace("`r", "`n")
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
        $output.Write($bytes, 0, $bytes.Length)
      } else {
        $input = [System.IO.File]::OpenRead($source)
        try { $input.CopyTo($output) } finally { $input.Dispose() }
      }
    } finally { $output.Dispose() }
  }
} finally {
  $archive.Dispose()
  $fileStream.Dispose()
}

$newHash = (Get-FileHash -LiteralPath $tempZipPath -Algorithm SHA256).Hash
if ((Test-Path -LiteralPath $zipPath) -and
  (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -eq $newHash) {
  Remove-Item -LiteralPath $tempZipPath -Force
  Write-Host "Built $zipPath (unchanged, SHA-256 $newHash)"
  return
}
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Move-Item -LiteralPath $tempZipPath -Destination $zipPath
Write-Host "Built $zipPath (SHA-256 $newHash)"
