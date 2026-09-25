# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [Parameter(Mandatory)][string]$CandidateManifestPath,
  [Parameter(Mandatory)][string]$TechnicalSealPath,
  [Parameter(Mandatory)][string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')

function Get-MIR42RestoreFile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  $full = [IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[$Code-missing]" }
  return $full
}
function Get-MIR42RestoreHash {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Resolve-MIR42RestoreCandidateFile {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Relative,[Parameter(Mandatory)][string]$Code)
  if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])[.][.]([\\/]|$)') { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
  if (-not $full.StartsWith($Root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw "[$Code-containment]"
  }
  return Get-MIR42RestoreFile -Path $full -Code $Code
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$manifestPath = Get-MIR42RestoreFile -Path $CandidateManifestPath -Code 'mir42-restore-manifest'
$sealPath = Get-MIR42RestoreFile -Path $TechnicalSealPath -Code 'mir42-restore-seal'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100 -DateKind String
$seal = Get-Content -Raw -LiteralPath $sealPath | ConvertFrom-Json -Depth 100 -DateKind String
$manifestSchema = Join-Path $repo 'spec/schemas/mir42-four-target-deterministic-candidate-manifest-v1.schema.json'
if (-not (Test-Path -LiteralPath $manifestSchema -PathType Leaf) -or
    -not ((Get-Content -Raw -LiteralPath $manifestPath) | Test-Json -SchemaFile $manifestSchema -ErrorAction SilentlyContinue) -or
    -not (Test-MIR4BootstrapRecordHash -Record $manifest) -or
    [string]$manifest.kind -cne 'MIR42FourTargetDeterministicCandidateManifestV1' -or
    [string]$manifest.status -cne 'private-deterministic-four-target-candidate-built-unqualified' -or
    -not [bool]$manifest.build_complete) { throw '[mir42-restore-candidate-invalid]' }
if (-not (Test-MIR4BootstrapRecordHash -Record $seal) -or
    [string]$seal.kind -cne 'MIR42FourTargetTechnicalSealV1' -or
    [string]$seal.status -cne 'MIR-4.2-FOUR-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR' -or
    [bool]$seal.publication_authorized -or
    [string]$seal.candidate_manifest.sha256 -cne (Get-MIR42RestoreHash -Path $manifestPath) -or
    [string]$seal.candidate_manifest.record_sha256 -cne [string]$manifest.record_sha256) {
  throw '[mir42-restore-seal-binding]'
}
$head = (& git -C $repo rev-parse HEAD).Trim()
$tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$dirty = @(& git -C $repo status --porcelain --untracked-files=no)
$packageSourceSha = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0 -or
    $head -cne [string]$manifest.source.commit -or $tree -cne [string]$manifest.source.tree -or
    $head -cne [string]$seal.source.commit -or $tree -cne [string]$seal.source.tree -or
    $packageSourceSha -cne [string]$manifest.package_source_sha256 -or
    $packageSourceSha -cne [string]$seal.source.package_source_sha256) {
  throw '[mir42-restore-source-binding]'
}

$targets = @('f210','f200','f110','f100')
if ((@($manifest.targets | ForEach-Object { [string]$_.target }) -join '|') -cne ($targets -join '|') -or
    (@($seal.targets | ForEach-Object { [string]$_.target }) -join '|') -cne ($targets -join '|')) {
  throw '[mir42-restore-target-set]'
}
$candidateRoot = [IO.Path]::GetFullPath((Split-Path -Parent $manifestPath))
$inputs = [Collections.Generic.List[object]]::new()
$inputs.Add([pscustomobject]@{source=$manifestPath;relative='candidate-manifest.json';sha256=(Get-MIR42RestoreHash -Path $manifestPath)})
$inputs.Add([pscustomobject]@{source=$sealPath;relative='technical-seal.json';sha256=(Get-MIR42RestoreHash -Path $sealPath)})
foreach ($target in $targets) {
  $candidate = @($manifest.targets | Where-Object { [string]$_.target -ceq $target })[0]
  $sealed = @($seal.targets | Where-Object { [string]$_.target -ceq $target })[0]
  if ([string]$candidate.asset.sha256 -cne [string]$sealed.archive_sha256 -or
      [string]$candidate.content_sha256 -cne [string]$sealed.content_sha256 -or
      [int]$candidate.entry_count -ne [int]$sealed.entry_count) {
    throw "[mir42-restore-$target-sealed-target-binding]"
  }
  $assetPath = Resolve-MIR42RestoreCandidateFile -Root $candidateRoot -Relative ([string]$candidate.asset.path) -Code "mir42-restore-$target-asset"
  $rowPath = Resolve-MIR42RestoreCandidateFile -Root $candidateRoot -Relative ([string]$candidate.target_row_path) -Code "mir42-restore-$target-row"
  if ((Get-MIR42RestoreHash -Path $assetPath) -cne [string]$candidate.asset.sha256) { throw "[mir42-restore-$target-asset-hash]" }
  $row = Get-Content -Raw -LiteralPath $rowPath | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $row) -or
      [string]$row.target -cne $target -or [string]$row.asset.sha256 -cne [string]$candidate.asset.sha256) {
    throw "[mir42-restore-$target-row-binding]"
  }
  $inputs.Add([pscustomobject]@{source=$rowPath;relative="target-rows/$target.json";sha256=(Get-MIR42RestoreHash -Path $rowPath)})
  $inputs.Add([pscustomobject]@{source=$assetPath;relative="assets/$([IO.Path]::GetFileName($assetPath))";sha256=(Get-MIR42RestoreHash -Path $assetPath)})
}

$out = [IO.Path]::GetFullPath($OutputRoot)
$build = [IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
if (-not $out.StartsWith($build,[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $out -PathType Leaf) -or
    ((Test-Path -LiteralPath $out -PathType Container) -and @(Get-ChildItem -LiteralPath $out -Force).Count -ne 0)) {
  throw '[mir42-restore-clean-output-required]'
}
$null = Assert-MIR4NoReparseAncestors -Root $repo -Path $out
New-Item -ItemType Directory -Force -Path $out | Out-Null
$capsulePath = Join-Path $out 'four-target-capsule.zip'
$restored = Join-Path $out 'restored'
$zip = [IO.Compression.ZipFile]::Open($capsulePath,[IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($file in $inputs) {
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,[string]$file.source,[string]$file.relative,[IO.Compression.CompressionLevel]::Optimal)
  }
} finally { $zip.Dispose() }
New-Item -ItemType Directory -Force -Path $restored | Out-Null
[IO.Compression.ZipFile]::ExtractToDirectory($capsulePath,$restored)
$restoredFiles = @(Get-ChildItem -LiteralPath $restored -Recurse -File -Force)
if ($restoredFiles.Count -ne $inputs.Count) { throw '[mir42-restore-inventory-count]' }
foreach ($file in $inputs) {
  $copy = Resolve-MIR42RestoreCandidateFile -Root $restored -Relative ([string]$file.relative) -Code 'mir42-restore-object'
  if ((Get-MIR42RestoreHash -Path $copy) -cne [string]$file.sha256) { throw "[mir42-restore-object-hash] $($file.relative)" }
}
$rows = @(
  foreach ($target in $targets) {
    $candidate = @($manifest.targets | Where-Object { [string]$_.target -ceq $target })[0]
    $relative = "assets/$([IO.Path]::GetFileName([string]$candidate.asset.path))"
    $copy = Resolve-MIR42RestoreCandidateFile -Root $restored -Relative $relative -Code "mir42-restore-$target-final"
    $inventory = Get-MIR4ArchiveInventory -Path $copy
    if ([string]$inventory.archive_sha256 -cne [string]$candidate.asset.sha256 -or
        [string]$inventory.content_sha256 -cne [string]$candidate.content_sha256 -or
        [int]$inventory.entry_count -ne [int]$candidate.entry_count) { throw "[mir42-restore-$target-archive-inventory]" }
    [pscustomobject][ordered]@{
      target=$target
      archive=[pscustomobject][ordered]@{sha256=[string]$candidate.asset.sha256;content_sha256=[string]$candidate.content_sha256;entry_count=[int]$candidate.entry_count}
      restored_archive=[pscustomobject][ordered]@{path=$copy;sha256=[string]$inventory.archive_sha256;content_sha256=[string]$inventory.content_sha256;entry_count=[int]$inventory.entry_count}
    }
  }
)
$receipt = [ordered]@{
  schema=1;kind='MIR42FourTargetOfflineRestoreDrillV1';status='MIR-4.2-FOUR-TARGET-OFFLINE-RESTORE-DRILL-PASSED-PRIVATE-UNSEALED'
  source=[ordered]@{commit=$head;tree=$tree;package_source_sha256=$packageSourceSha}
  candidate_manifest=[ordered]@{path=(Join-Path $restored 'candidate-manifest.json');sha256=(Get-MIR42RestoreHash -Path $manifestPath);record_sha256=[string]$manifest.record_sha256}
  technical_seal=[ordered]@{path=(Join-Path $restored 'technical-seal.json');sha256=(Get-MIR42RestoreHash -Path $sealPath);record_sha256=[string]$seal.record_sha256}
  capsule=[ordered]@{path=$capsulePath;sha256=(Get-MIR42RestoreHash -Path $capsulePath)}
  restored_inventory=@($inputs | ForEach-Object { [ordered]@{path=(Join-Path $restored ([string]$_.relative));sha256=([string]$_.sha256)} })
  targets=$rows
  clean_untracked_root=$true
  publication_authorized=$false
}
$receiptPath = Join-Path $out 'restore-drill.json'
$null = Write-MIR4BootstrapRecord -Record $receipt -Path $receiptPath
Write-Host "[ok] four-target offline capsule restore: $receiptPath"
