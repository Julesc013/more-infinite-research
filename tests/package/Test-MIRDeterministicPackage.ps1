# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1")

$relativeRoots = @("build\packages\deterministic-package-a", "build\packages\deterministic-package-b")
$absoluteRoots = @($relativeRoots | ForEach-Object { Join-Path $repo $_ })

foreach ($path in $absoluteRoots) {
  $full = [System.IO.Path]::GetFullPath($path)
  $buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repo "build\packages")) + [System.IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Deterministic package output escaped build/packages: $full"
  }
  if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
}

$results = @()
for ($index = 0; $index -lt $relativeRoots.Count; $index++) {
  $results += & (Join-Path $repo "tools\commands\package\Build-MIRPackage.ps1") -Target f210 -CandidateId "MIR4-DETERMINISM-$index" -OutputDir $relativeRoots[$index] -CompressionLevel Optimal
}

$left = [string]$results[0].archive_path
$right = [string]$results[1].archive_path
$leftHash = Get-MIRFileSha256 -Path $left
$rightHash = Get-MIRFileSha256 -Path $right
if ($leftHash -ne $rightHash) {
  throw "MIR package builds are not byte-identical: $leftHash != $rightHash"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($left)
try {
  $names = @($zip.Entries | ForEach-Object { $_.FullName })
  $sortedNames = @($names)
  [Array]::Sort($sortedNames, [StringComparer]::Ordinal)
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
& (Join-Path $repo "tests\package\Test-MIRPackageComposition.ps1") -RepoRoot $repo
