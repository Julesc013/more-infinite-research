$resolvedOutputDir = [IO.Path]::GetFullPath($OutputDir)
$resolvedCacheDir = New-MIRDirectory -Path $ModCacheDir

function Resolve-MIRZipInputPaths {
  param(
    [string[]]$Dirs = @(),
    [string[]]$Zips = @(),
    [Parameter(Mandatory)][string]$Kind
  )

  $paths = @()
  foreach ($dir in @($Dirs)) {
    if ([string]::IsNullOrWhiteSpace([string]$dir)) { continue }
    if (-not (Test-Path -LiteralPath $dir)) {
      throw "$Kind directory does not exist: $dir"
    }
    $paths += @(Get-ChildItem -LiteralPath $dir -Filter *.zip -File | ForEach-Object { $_.FullName })
  }

  foreach ($zipPath in @($Zips)) {
    if ([string]::IsNullOrWhiteSpace([string]$zipPath)) { continue }
    if (-not (Test-Path -LiteralPath $zipPath)) {
      throw "$Kind zip does not exist: $zipPath"
    }
    $paths += (Resolve-Path -LiteralPath $zipPath).Path
  }

  return @($paths | Sort-Object -Unique)
}

function Add-MIRLocalFullModToIndex {
  param(
    [Parameter(Mandatory)]$Index,
    [Parameter(Mandatory)]$FullMod
  )

  $name = [string]$FullMod.name
  if ($Index.ContainsKey($name)) {
    $existing = $Index[$name]
    $existing.releases = @($existing.releases) + @($FullMod.releases)
  } else {
    $Index[$name] = $FullMod
  }
}

$localRootZipPaths = @(Resolve-MIRZipInputPaths -Dirs $LocalModZipDirs -Zips $LocalModZips -Kind "Local mod root")
$localLibraryZipPaths = @(Resolve-MIRZipInputPaths -Dirs $LocalModLibraryDirs -Zips $LocalModLibraryZips -Kind "Local mod library")
$localZipPaths = @((@($localRootZipPaths) + @($localLibraryZipPaths)) | Sort-Object -Unique)
$localRootZipLookup = @{}
foreach ($path in $localRootZipPaths) { $localRootZipLookup[$path] = $true }
$localFullModsByName = @{}
$localRootFullModsByName = @{}
foreach ($zipPath in $localZipPaths) {
  $localFull = ConvertTo-MIRLocalFullMod -ZipPath $zipPath
  if ([string]::IsNullOrWhiteSpace([string]$localFull.name)) {
    throw "Local mod zip has no mod name: $zipPath"
  }
  Add-MIRLocalFullModToIndex -Index $localFullModsByName -FullMod $localFull
  if ($localRootZipLookup.ContainsKey($zipPath)) {
    Add-MIRLocalFullModToIndex -Index $localRootFullModsByName -FullMod $localFull
  }
}
