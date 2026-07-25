param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")

$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$archiveName = "$($info.name)_$($info.version).zip"
$relativeRoots = @("build\deterministic-package-a", "build\deterministic-package-b")
$absoluteRoots = @($relativeRoots | ForEach-Object { Join-Path $repo $_ })

foreach ($path in $absoluteRoots) {
  $full = [System.IO.Path]::GetFullPath($path)
  $buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repo "build")) + [System.IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Deterministic package output escaped the repository build directory: $full"
  }
  if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
}

foreach ($relativeRoot in $relativeRoots) {
  & (Join-Path $repo "scripts\Build-MIRPackage.ps1") -OutputDir $relativeRoot -CompressionLevel Optimal | Out-Host
}

$left = Join-Path $absoluteRoots[0] $archiveName
$right = Join-Path $absoluteRoots[1] $archiveName
$leftHash = Get-MIRFileSha256 -Path $left
$rightHash = Get-MIRFileSha256 -Path $right
if ($leftHash -ne $rightHash) {
  throw "MIR package builds are not byte-identical: $leftHash != $rightHash"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($left)
try {
  $names = @($zip.Entries | ForEach-Object { $_.FullName })
  $sortedNames = @($names | Sort-Object)
  if (($names -join "`n") -ne ($sortedNames -join "`n")) {
    throw "MIR deterministic package entries are not in canonical path order."
  }
  $unexpectedTimestamp = @($zip.Entries | Where-Object {
    $_.LastWriteTime.DateTime -ne [DateTime]::new(1980, 1, 1, 0, 0, 0)
  })
  if ($unexpectedTimestamp.Count -gt 0) {
    throw "MIR deterministic package contains non-canonical entry timestamps."
  }
} finally {
  $zip.Dispose()
}

Write-Host "[ok] MIR deterministic package SHA-256 $leftHash"
& (Join-Path $repo "scripts\Test-MIRPackageComposition.ps1") -RepoRoot $repo
