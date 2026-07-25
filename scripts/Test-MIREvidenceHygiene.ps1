param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$Release = "3.2.0",
  [int64]$MaximumTrackedTextBytes = 524288
)

$ErrorActionPreference = "Stop"
$evidenceRoot = Join-Path $RepoRoot ".mir\evidence"
$tracked = @(& git -C $RepoRoot ls-files ".mir/evidence/$Release-*" ".mir/evidence/$Release-*/**")
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate tracked release evidence." }

$textExtensions = @(".json", ".log", ".txt", ".md", ".csv", ".yml", ".yaml")
$absolutePathPattern = '(?i)([A-Z]:[\\/](?:Users|Program Files|Projects|Programs)[\\/]|/(?:Users|home|tmp)/)'
foreach ($relative in $tracked) {
  $path = Join-Path $RepoRoot $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
  $item = Get-Item -LiteralPath $path
  $extension = [IO.Path]::GetExtension($item.Name).ToLowerInvariant()
  if ($extension -in $textExtensions) {
    if ($item.Length -gt $MaximumTrackedTextBytes) {
      throw "Tracked release evidence is too large for the portable summary ledger: $relative ($($item.Length) bytes)."
    }
    $text = Get-Content -Raw -LiteralPath $path
    if ($text -match $absolutePathPattern) {
      throw "Tracked release evidence contains a machine-specific absolute path: $relative"
    }
  }
  if ($item.Name -like "*.crop-cache.dat") {
    throw "Raw crop-cache evidence must remain in immutable external artifacts, not the active release ledger: $relative"
  }
}

$rawBundle = Join-Path $evidenceRoot "$Release-assurance-qualification.json"
if (Test-Path -LiteralPath $rawBundle -PathType Leaf) {
  throw "The complete qualification bundle must be stored as a workflow artifact; track only its portable summary and digests."
}

Write-Host "[ok] $Release tracked evidence is portable, bounded, and summary-oriented."
