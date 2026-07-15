param(
  [Parameter(Mandatory)]
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6")]
  [string]$FactorioVersion,
  [string]$OutputDir = "dist",
  [string]$MaterializeRoot = ""
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Import-Module (Join-Path $PSScriptRoot "Museum\MuseumCompiler.psm1") -Force
$catalog = Get-MIRMuseumCatalog -Path (Join-Path $repo ".mir\museum-targets.json")
$target = Get-MIRMuseumTarget -Catalog $catalog -FactorioVersion $FactorioVersion
$validation = Test-MIRMuseumTarget -Catalog $catalog -Target $target
if (-not $validation.passed) { throw ($validation.errors -join "`n") }
foreach ($warning in @($validation.warnings)) { Write-Warning $warning }

$result = New-MIRMuseumPackage -Catalog $catalog -Target $target -RepoRoot $repo -OutputDir $OutputDir
if (-not [string]::IsNullOrWhiteSpace($MaterializeRoot)) {
  $resolvedMaterializeRoot = if ([IO.Path]::IsPathRooted($MaterializeRoot)) { $MaterializeRoot } else { Join-Path $repo $MaterializeRoot }
  $sourceRoot = Join-Path $repo ("build\museum\$FactorioVersion\runtime")
  foreach ($relative in @("config.lua", "data.lua", "info.json", "locale\en\more-infinite-research.cfg")) {
    $destination = Join-Path $resolvedMaterializeRoot $relative
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination -Force
  }
  $metadataRoot = Join-Path $resolvedMaterializeRoot ".mir\museum"
  if (-not (Test-Path -LiteralPath $metadataRoot)) { New-Item -ItemType Directory -Force -Path $metadataRoot | Out-Null }
  Copy-Item -LiteralPath (Join-Path $repo "build\museum\$FactorioVersion\stream-manifest.json") -Destination (Join-Path $metadataRoot "stream-manifest.json") -Force
  Copy-Item -LiteralPath (Join-Path $repo "build\museum\$FactorioVersion\balance.json") -Destination (Join-Path $metadataRoot "balance.json") -Force
}

$result | ConvertTo-Json -Depth 10

