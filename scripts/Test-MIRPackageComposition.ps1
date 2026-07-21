param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $repo "build\package-composition-test"))
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repo "build")) + [System.IO.Path]::DirectorySeparatorChar
if (-not $testRoot.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Package composition test directory escaped build/: $testRoot"
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-TestArchive {
  param([string]$Path, [hashtable]$Entries)

  $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
  $zip = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
  try {
    foreach ($relative in @($Entries.Keys | Sort-Object)) {
      $entry = $zip.CreateEntry("more-infinite-research_3.2.0/$relative", [System.IO.Compression.CompressionLevel]::Optimal)
      $writer = [System.IO.StreamWriter]::new($entry.Open(), [System.Text.UTF8Encoding]::new($false))
      try {
        $writer.Write([string]$Entries[$relative])
      } finally {
        $writer.Dispose()
      }
    }
  } finally {
    $zip.Dispose()
    $stream.Dispose()
  }
}

if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
  $baselinePath = Join-Path $testRoot "baseline.zip"
  $candidatePath = Join-Path $testRoot "candidate.zip"
  $reportPath = Join-Path $testRoot "report.json"
  New-TestArchive -Path $baselinePath -Entries @{
    "README.md" = "baseline"
    "locale/en/mir.cfg" = "[mod-name]`nmir=More Infinite Research"
    "prototypes/mir/pipeline/commands.lua" = "return {}"
  }
  New-TestArchive -Path $candidatePath -Entries @{
    "README.md" = "candidate"
    "locale/en/mir.cfg" = "[mod-name]`nmir=More Infinite Research"
    "locale/fr/mir.cfg" = "[mod-name]`nmir=Recherche infinie"
    "prototypes/mir/pipeline/commands.lua" = "return {changed=true}"
  }

  $report = & (Join-Path $repo "scripts\Measure-MIRPackageComposition.ps1") `
    -RepoRoot $repo `
    -ArchivePath $candidatePath `
    -BaselinePath $baselinePath `
    -OutputPath $reportPath `
    -GrowthReviewPercent 0 `
    -RootGrowthReviewPercent 0 `
    -Explanation "Synthetic growth is expected by this unit test." `
    -RequireReviewedExplanation

  if ($report.schema -ne 1 -or $report.archive.entry_count -ne 4) {
    throw "Package composition report did not preserve its schema or entry count."
  }
  if (@($report.roots | Where-Object { $_.root -eq "locale" }).Count -ne 1) {
    throw "Package composition report did not classify locale entries."
  }
  if (-not (@($report.delta.added) -contains "locale/fr/mir.cfg")) {
    throw "Package composition report did not record the added locale."
  }
  if (@($report.delta.changed | Where-Object { $_.path -eq "README.md" }).Count -ne 1) {
    throw "Package composition report did not record a changed entry."
  }
  if (-not $report.review.reviewed -or $report.review.required) {
    throw "Package composition explanation did not satisfy review."
  }

  $unreviewedPath = Join-Path $testRoot "unreviewed.json"
  $rejected = $false
  try {
    & (Join-Path $repo "scripts\Measure-MIRPackageComposition.ps1") `
      -RepoRoot $repo `
      -ArchivePath $candidatePath `
      -BaselinePath $baselinePath `
      -OutputPath $unreviewedPath `
      -GrowthReviewPercent 0 `
      -RootGrowthReviewPercent 0 `
      -RequireReviewedExplanation | Out-Null
  } catch {
    $rejected = $true
  }
  if (-not $rejected) {
    throw "Package composition report accepted unexplained reviewed growth."
  }
} finally {
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host "[ok] package composition reporting"
