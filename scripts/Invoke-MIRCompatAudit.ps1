param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [ValidateSet("2.0", "2.1")]
  [string]$FactorioLine = "",
  [string]$ModPortalUsername = $env:FACTORIO_USERNAME,
  [string]$ModPortalToken = $env:FACTORIO_TOKEN,
  [int]$MinDownloads = 10000,
  [string[]]$FactorioVersions = @("2.0", "2.1"),
  [switch]$IncludeSpaceAge,
  [switch]$UseCachedDownloads,
  [string]$ModCacheDir = (Join-Path $PSScriptRoot "..\build\compat-mod-cache"),
  [string]$OutputDir = (Join-Path $PSScriptRoot "..\artifacts\compat-audit"),
  [int]$MaxCandidates = 50,
  [int]$CatalogPages = 0,
  [string]$FromLockfile,
  [int]$StartIndex = 0,
  [int]$Count = 0,
  [string[]]$CandidateNames = @(),
  [string[]]$LocalModZipDirs = @(),
  [string[]]$LocalModZips = @(),
  [string[]]$LocalModLibraryDirs = @(),
  [string[]]$LocalModLibraryZips = @(),
  [string[]]$LocalModNames = @(),
  [string]$ModUnderTestZip = "",
  [string]$ModUnderTestSourceCommit = "",
  [switch]$DownloadMods,
  [switch]$RunLoadTests,
  [switch]$RunManualScenarios,
  [switch]$RunLocalModZips,
  [switch]$RunGeneratedLocalScenarios,
  [switch]$GenerateLocalMegaScenario,
  [switch]$GenerateLocalClusterScenarios,
  [switch]$GenerateLocalPairwiseScenarios,
  [int]$GeneratedLocalPairwiseLimit = 40,
  [switch]$IncludeRecommendedDependencies,
  [ValidateSet("Copy", "Hardlink", "Symlink")]
  [string]$LinkMode = "Copy",
  [switch]$Offline,
  [string[]]$ScenarioNames = @(),
  [int]$ScenarioTimeoutSeconds = 900,
  [switch]$ContinueOnDependencyFailure,
  [switch]$FailFast,
  [Alias("ManualScenarios")]
  [string]$ManualScenariosPath = (Join-Path $PSScriptRoot "..\fixtures\compat-matrix\manual-scenarios.json"),
  [string]$SanitationBudgetPath = (Join-Path $PSScriptRoot "..\.mir\sanitation-budgets.json"),
  [string]$KnownExclusions = (Join-Path $PSScriptRoot "..\fixtures\compat-matrix\known-exclusions.json")
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$moduleRoot = Join-Path $PSScriptRoot "MIRCompatAudit"
. (Join-Path $moduleRoot "ModPortal.ps1")
. (Join-Path $moduleRoot "DependencyResolver.ps1")
. (Join-Path $moduleRoot "DiagnosticsParser.ps1")
. (Join-Path $moduleRoot "FactorioRunner.ps1")
. (Join-Path $PSScriptRoot "validation\SettingsOverrides.ps1")

$resolvedSanitationBudgetPath = (Resolve-Path -LiteralPath $SanitationBudgetPath).Path
$sanitationPolicy = Get-Content -Raw -LiteralPath $resolvedSanitationBudgetPath | ConvertFrom-Json
if ([int]$sanitationPolicy.schema -ne 1 -or [string]$sanitationPolicy.policy -ne "mir-ecosystem-sanitation-budget-v1") {
  throw "Compatibility audit requires mir-ecosystem-sanitation-budget-v1 schema 1."
}

$resolvedModUnderTestZip = ""
if (-not [string]::IsNullOrWhiteSpace($ModUnderTestZip)) {
  $resolvedModUnderTestZip = (Resolve-Path -LiteralPath $ModUnderTestZip).Path
}
if (-not [string]::IsNullOrWhiteSpace($ModUnderTestSourceCommit) -and $ModUnderTestSourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
  throw "ModUnderTestSourceCommit must be a full 40-character git commit."
}

if ([string]::IsNullOrWhiteSpace($FactorioLine)) {
  $lineCandidates = @($FactorioVersions | Where-Object { $_ -in @("2.0", "2.1") } | Select-Object -Unique)
  if ($lineCandidates.Count -eq 1) {
    $FactorioLine = [string]$lineCandidates[0]
  } else {
    $FactorioLine = "2.1"
  }
}

function New-MIRDirectory {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Read-MIRJsonFile {
  param([string]$Path, $Fallback)
  if (-not (Test-Path -LiteralPath $Path)) { return $Fallback }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-MIRObjectProperty {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Select-MIRWindow {
  param([object[]]$Items)

  $out = @($Items)
  if ($StartIndex -gt 0) {
    $out = @($out | Select-Object -Skip $StartIndex)
  }
  if ($Count -gt 0) {
    $out = @($out | Select-Object -First $Count)
  }
  return $out
}

function Test-MIRInterestingCategory {
  param($Mod)

  $category = [string]$Mod.category
  if ($category -in @("content", "overhaul", "mod-packs", "tweaks")) { return $true }

  foreach ($tag in @($Mod.tags)) {
    if ([string]$tag -in @("manufacturing", "mining", "fluids", "planets", "transportation", "power", "logistics")) {
      return $true
    }
  }

  return $false
}

function Test-MIRKnownExcluded {
  param($Mod, $Exclusions)

  $name = [string]$Mod.name
  $category = [string]$Mod.category
  foreach ($excludedName in @($Exclusions.mod_names)) {
    if ($name -eq [string]$excludedName) { return $true }
  }
  foreach ($excludedCategory in @($Exclusions.categories)) {
    if ($category -eq [string]$excludedCategory) { return $true }
  }
  return $false
}

function ConvertTo-MIRLockEntry {
  param(
    [Parameter(Mandatory)]$FullMod,
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)]$Dependencies
  )

  [pscustomobject][ordered]@{
    name = [string]$FullMod.name
    title = [string]$FullMod.title
    version = [string]$Release.version
    factorio_version = [string]$Release.info_json.factorio_version
    downloads_count = [int]$FullMod.downloads_count
    category = [string]$FullMod.category
    owner = [string]$FullMod.owner
    file_name = [string]$Release.file_name
    sha1 = [string]$Release.sha1
    sha256 = [string](Get-MIRObjectProperty -Object $Release -Name "sha256" -Default "")
    download_url = [string]$Release.download_url
    source = ""
    source_path = ""
    dependencies = @($Dependencies | ForEach-Object {
      [ordered]@{
        name = $_.name
        kind = $_.kind
        required = $_.required
        raw = $_.raw
      }
    })
  }
}

function ConvertTo-MIRLocalFullMod {
  param([Parameter(Mandatory)][string]$ZipPath)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolvedZip = (Resolve-Path -LiteralPath $ZipPath).Path
  $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedZip)
  try {
    $entry = $zip.Entries | Where-Object { $_.FullName -match "^[^/]+/info\.json$" } | Select-Object -First 1
    if (-not $entry) {
      throw "Local mod zip does not contain a top-level info.json: $resolvedZip"
    }

    $reader = [System.IO.StreamReader]::new($entry.Open())
    try {
      $infoJson = $reader.ReadToEnd()
      try {
        $info = $infoJson | ConvertFrom-Json -ErrorAction Stop
      } catch {
        $infoTable = $infoJson | ConvertFrom-Json -AsHashTable -ErrorAction Stop
        $info = [pscustomobject]@{
          name = [string]$infoTable["name"]
          title = [string]$infoTable["title"]
          version = [string]$infoTable["version"]
          factorio_version = [string]$infoTable["factorio_version"]
          dependencies = @($infoTable["dependencies"])
        }
      }
    } finally {
      $reader.Dispose()
    }
  } finally {
    $zip.Dispose()
  }

  $dependencies = @($info.dependencies | ForEach-Object {
    if (-not [string]::IsNullOrWhiteSpace([string]$_)) { [string]$_ }
  })
  $file = Get-Item -LiteralPath $resolvedZip
  $sha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $resolvedZip).Hash.ToLowerInvariant()
  $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedZip).Hash.ToLowerInvariant()

  [pscustomobject]@{
    name = [string]$info.name
    title = if ([string]::IsNullOrWhiteSpace([string]$info.title)) { [string]$info.name } else { [string]$info.title }
    owner = "local"
    downloads_count = 0
    category = "local"
    releases = @(
      [pscustomobject]@{
        version = [string]$info.version
        file_name = $file.Name
        sha1 = $sha1
        sha256 = $sha256
        download_url = ""
        source_path = $resolvedZip
        source = "local_zip"
        info_json = [pscustomobject]@{
          factorio_version = [string]$info.factorio_version
          dependencies = $dependencies
        }
      }
    )
  }
}

function ConvertTo-MIRLocalLockEntry {
  param(
    [Parameter(Mandatory)]$FullMod,
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)]$Dependencies
  )

  $entry = ConvertTo-MIRLockEntry -FullMod $FullMod -Release $Release -Dependencies $Dependencies
  $entry.source = "local_zip"
  $entry.source_path = [string]$Release.source_path
  return $entry
}

function ConvertTo-MIRScenarioLockEntry {
  param(
    [Parameter(Mandatory)]$FullMod,
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)]$Dependencies
  )

  if ($Release.PSObject.Properties["source_path"] -and -not [string]::IsNullOrWhiteSpace([string]$Release.source_path)) {
    return ConvertTo-MIRLocalLockEntry -FullMod $FullMod -Release $Release -Dependencies $Dependencies
  }

  return ConvertTo-MIRLockEntry -FullMod $FullMod -Release $Release -Dependencies $Dependencies
}

function New-MIRScenario {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Type,
    [string[]]$RequestedMods = @(),
    [string[]]$RootMods = @(),
    [string[]]$ResolvedMods = @(),
    [string[]]$OfficialMods = @(),
    [object[]]$LockEntries = @(),
    [object[]]$Failures = @(),
    [string]$ClaimLevel = "loads",
    [int]$TimeoutSeconds = $ScenarioTimeoutSeconds,
    $Settings = $null,
    $ExpectedPlan = $null,
    [string]$SourceManifest = "",
    [string]$Notes = ""
  )

  [pscustomobject]@{
    name = $Name
    type = $Type
    requested_mods = @($RequestedMods | Sort-Object -Unique)
    root_mods = @($RootMods | Sort-Object -Unique)
    resolved_mods = @($ResolvedMods | Sort-Object -Unique)
    official_mods = @($OfficialMods | Sort-Object -Unique)
    lock_entries = @($LockEntries | Sort-Object name, version -Unique)
    dependency_failures = @($Failures)
    claim_level = $ClaimLevel
    timeout_seconds = $TimeoutSeconds
    settings = if ($null -eq $Settings) { [pscustomobject]@{} } else { $Settings }
    expected_plan = if ($null -eq $ExpectedPlan) { [pscustomobject]@{} } else { $ExpectedPlan }
    source_manifest = $SourceManifest
    notes = $Notes
  }
}

function Get-MIRLockEntriesByName {
  param([object[]]$LockEntries)

  $out = @{}
  foreach ($entry in @($LockEntries)) {
    $out[[string]$entry.name] = $entry
  }
  return $out
}

$resolvedOutputDir = New-MIRDirectory -Path $OutputDir
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
$knownOfficialBuiltinMods = @("space-age", "quality", "elevated-rails", "recycler")
function Get-MIROfficialBuiltinFullMods {
  param(
    [string]$FactorioBinary,
    [string[]]$Candidates
  )

  $index = @{}
  if (-not [string]::IsNullOrWhiteSpace($FactorioBinary) -and (Test-Path -LiteralPath $FactorioBinary)) {
    $factorioExe = (Resolve-Path -LiteralPath $FactorioBinary).Path
    $factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $factorioExe))
    $dataRoot = Join-Path $factorioRoot "data"
    if (Test-Path -LiteralPath $dataRoot) {
      foreach ($candidate in @($Candidates)) {
        $infoPath = Join-Path $dataRoot ("{0}\info.json" -f $candidate)
        if (-not (Test-Path -LiteralPath $infoPath)) { continue }
        $info = Read-MIRJsonFile -Path $infoPath
        $index[[string]$candidate] = [pscustomobject]@{
          name = [string]$candidate
          title = if ([string]::IsNullOrWhiteSpace([string]$info.title)) { [string]$candidate } else { [string]$info.title }
          releases = @([pscustomobject]@{
            version = [string]$info.version
            info_json = $info
          })
        }
      }
      return $index
    }
  }

  foreach ($candidate in @($Candidates)) {
    $index[[string]$candidate] = [pscustomobject]@{
      name = [string]$candidate
      title = [string]$candidate
      releases = @([pscustomobject]@{
        version = ""
        info_json = [pscustomobject]@{
          name = [string]$candidate
          version = ""
          dependencies = @()
        }
      })
    }
  }
  return $index
}

$officialBuiltinFullModsByName = Get-MIROfficialBuiltinFullMods -FactorioBinary $FactorioBin -Candidates $knownOfficialBuiltinMods
$officialBuiltinMods = @($officialBuiltinFullModsByName.Keys | Sort-Object)
$specialLocalMods = @("base", "more-infinite-research")
$officialBuiltinLookup = @{}
foreach ($officialMod in $knownOfficialBuiltinMods) {
  $officialBuiltinLookup[$officialMod] = $true
}
$availableOfficialBuiltinLookup = @{}
foreach ($officialMod in $officialBuiltinMods) {
  $availableOfficialBuiltinLookup[$officialMod] = $true
}
$localModLookup = @{}
foreach ($name in @($knownOfficialBuiltinMods + $specialLocalMods)) {
  $localModLookup[$name] = $true
}

function Add-MIROfficialBuiltinDependencyClosure {
  param(
    [Parameter(Mandatory)][hashtable]$Enabled,
    [switch]$IncludeRecommendedDependencies
  )

  $queue = [System.Collections.Generic.Queue[string]]::new()
  foreach ($name in @($Enabled.Keys)) { $queue.Enqueue([string]$name) }

  while ($queue.Count -gt 0) {
    $name = $queue.Dequeue()
    if (-not $officialBuiltinFullModsByName.ContainsKey($name)) { continue }
    $full = $officialBuiltinFullModsByName[$name]
    $release = @($full.releases)[0]
    foreach ($dep in @(Get-MIRReleaseDependencies -Release $release)) {
      $includeDependency = $dep.required -or ($IncludeRecommendedDependencies -and $dep.kind -eq "recommended")
      if (-not $includeDependency -or -not $officialBuiltinLookup.ContainsKey([string]$dep.name)) { continue }
      if (-not $Enabled.ContainsKey([string]$dep.name)) {
        $Enabled[[string]$dep.name] = $true
        $queue.Enqueue([string]$dep.name)
      }
    }
  }
}

function Get-MIRPortalRootModNames {
  param([string[]]$ModNames)
  @($ModNames | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and -not $localModLookup.ContainsKey([string]$_)
  } | Sort-Object -Unique)
}

function Get-MIRExplicitOfficialMods {
  param([string[]]$ModNames)
  @($ModNames | Where-Object { $officialBuiltinLookup.ContainsKey([string]$_) } | Sort-Object -Unique)
}

function Get-MIREnabledOfficialModsFromEntries {
  param(
    [object[]]$LockEntries,
    [bool]$EnableSpaceAgeBundle,
    [string[]]$ExplicitOfficialMods = @(),
    [switch]$IncludeRecommendedDependencies
  )

  $enabled = @{}
  if ($EnableSpaceAgeBundle) {
    foreach ($name in $officialBuiltinMods) { $enabled[$name] = $true }
  }
  foreach ($name in @($ExplicitOfficialMods)) {
    if ($officialBuiltinLookup.ContainsKey([string]$name)) { $enabled[[string]$name] = $true }
  }

  foreach ($entry in @($LockEntries)) {
    foreach ($dep in @($entry.dependencies)) {
      $includeDependency = $dep.required -or ($IncludeRecommendedDependencies -and $dep.kind -eq "recommended")
      if ($includeDependency -and $officialBuiltinLookup.ContainsKey([string]$dep.name)) {
        $enabled[[string]$dep.name] = $true
      }
    }
  }

  if ($enabled.ContainsKey("space-age")) {
    foreach ($name in $officialBuiltinMods) { $enabled[$name] = $true }
  }
  Add-MIROfficialBuiltinDependencyClosure -Enabled $enabled -IncludeRecommendedDependencies:$IncludeRecommendedDependencies

  return @($enabled.Keys | Sort-Object)
}

function Get-MIRUnavailableOfficialMods {
  param(
    [object[]]$LockEntries,
    [bool]$EnableSpaceAgeBundle,
    [string[]]$ExplicitOfficialMods = @(),
    [switch]$IncludeRecommendedDependencies
  )

  $required = @{}
  if ($EnableSpaceAgeBundle) {
    $required["space-age"] = $true
  }
  foreach ($name in @($ExplicitOfficialMods)) {
    if ($officialBuiltinLookup.ContainsKey([string]$name)) { $required[[string]$name] = $true }
  }
  foreach ($entry in @($LockEntries)) {
    foreach ($dep in @($entry.dependencies)) {
      $includeDependency = $dep.required -or ($IncludeRecommendedDependencies -and $dep.kind -eq "recommended")
      if ($includeDependency -and $officialBuiltinLookup.ContainsKey([string]$dep.name)) {
        $required[[string]$dep.name] = $true
      }
    }
  }
  Add-MIROfficialBuiltinDependencyClosure -Enabled $required -IncludeRecommendedDependencies:$IncludeRecommendedDependencies
  @($required.Keys | Where-Object { -not $availableOfficialBuiltinLookup.ContainsKey([string]$_) } | Sort-Object)
}

function Resolve-MIRLockDependencyNames {
  param(
    [Parameter(Mandatory)][string[]]$RootModNames,
    [Parameter(Mandatory)]$LockEntriesByName,
    [switch]$IncludeRecommendedDependencies
  )

  $queue = [System.Collections.Generic.Queue[string]]::new()
  foreach ($name in @($RootModNames | Sort-Object -Unique)) {
    if (-not $localModLookup.ContainsKey([string]$name)) { $queue.Enqueue([string]$name) }
  }

  $resolved = @{}
  $failures = @()
  while ($queue.Count -gt 0) {
    $name = $queue.Dequeue()
    if ($localModLookup.ContainsKey($name) -or $resolved.ContainsKey($name)) { continue }
    if (-not $LockEntriesByName.ContainsKey($name)) {
      $failures += [pscustomobject]@{
        name = $name
        error = "Dependency '$name' is not present in the lockfile."
      }
      continue
    }

    $entry = $LockEntriesByName[$name]
    $resolved[$name] = $true
    foreach ($dep in @($entry.dependencies)) {
      $includeDependency = $dep.required -or ($IncludeRecommendedDependencies -and $dep.kind -eq "recommended")
      if ($includeDependency -and -not $localModLookup.ContainsKey([string]$dep.name) -and -not $resolved.ContainsKey([string]$dep.name)) {
        $queue.Enqueue([string]$dep.name)
      }
    }
  }

  [pscustomobject]@{
    names = @($resolved.Keys | Sort-Object)
    failures = $failures
  }
}

function Get-MIRDependencyNamesFromFullMod {
  param($FullMod)

  $names = @()
  foreach ($release in @($FullMod.releases)) {
    foreach ($dependency in @($release.info_json.dependencies)) {
      if ([string]::IsNullOrWhiteSpace([string]$dependency)) { continue }
      $parsed = ConvertFrom-MIRDependencyString -Dependency ([string]$dependency)
      $names += [string]$parsed.name
    }
  }
  @($names | Sort-Object -Unique)
}

function Test-MIRLocalModHasCompatibleRelease {
  param([Parameter(Mandatory)]$FullMod)

  $release = Select-MIRCompatibleRelease -FullMod $FullMod -FactorioVersions $FactorioVersions
  return $null -ne $release
}

function Get-MIRCompatibleLocalModNames {
  param([Parameter(Mandatory)]$FullModsByName)

  @(
    foreach ($name in @($FullModsByName.Keys | Sort-Object)) {
      if (Test-MIRLocalModHasCompatibleRelease -FullMod $FullModsByName[$name]) {
        [string]$name
      }
    }
  )
}

function Test-MIRLocalNameMatches {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$FullMod,
    [Parameter(Mandatory)][string]$Pattern
  )

  $title = [string]$FullMod.title
  $deps = (Get-MIRDependencyNamesFromFullMod -FullMod $FullMod) -join " "
  return (($Name + " " + $title + " " + $deps) -match $Pattern)
}

function New-MIRGeneratedLocalScenarioDefinition {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string[]]$Mods = @(),
    [bool]$IncludeSpaceAge,
    [Parameter(Mandatory)][string]$Notes
  )

  $modList = @($Mods | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
  if ($modList.Count -eq 0) { return $null }
  [pscustomobject]@{
    name = $Name
    include_space_age = $IncludeSpaceAge
    mods = $modList
    notes = $Notes
  }
}

function New-MIRGeneratedLocalScenarioDefinitions {
  param([Parameter(Mandatory)]$FullModsByName)

  $compatibleNames = @(Get-MIRCompatibleLocalModNames -FullModsByName $FullModsByName)
  $definitions = @()
  $scenarioLineSlug = $FactorioLine.Replace(".", "-")

  if ($GenerateLocalMegaScenario -or (-not $GenerateLocalClusterScenarios -and -not $GenerateLocalPairwiseScenarios)) {
    $definitions += New-MIRGeneratedLocalScenarioDefinition `
      -Name "generated-local-$scenarioLineSlug-mega-all" `
      -Mods $compatibleNames `
      -IncludeSpaceAge $true `
      -Notes "Generated stress scenario: all locally available compatible mods enabled together with the official Space Age bundle."
  }

  if ($GenerateLocalClusterScenarios) {
    $clusterPatterns = @(
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-planets"
        include_space_age = $true
        pattern = "(?i)(planet|moon|space-age|Cerys|Fulgora|corrundum|cubium|lignumis|Moshine|muluna|rubia|secretas|panglia|Paracelsin|rabbasca|vesta|aquilo|gleba|Muria|carna|linox|foliax|nauv|Small-Space-Age|warptorio)"
        notes = "Generated cluster scenario for locally available planet and Space Age content mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-bz-resources"
        include_space_age = $true
        pattern = "(?i)^(bz|bzt|bzz)|resource|ore|carbon|lead|silicon|tin|titanium|zirconium"
        notes = "Generated cluster scenario for locally available BZ/resource-chain mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-bob"
        include_space_age = $false
        pattern = "(?i)^bob"
        notes = "Generated cluster scenario for locally available Bob mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-krastorio"
        include_space_age = $true
        pattern = "(?i)Krastorio|k2so|K2"
        notes = "Generated cluster scenario for locally available Krastorio and K2SO mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-production-fluids"
        include_space_age = $true
        pattern = "(?i)refin|chem|fluid|casting|foundry|molten|metal|ore|plutonium|carbon|mineral|hot-metals|more-casting"
        notes = "Generated cluster scenario for locally available production, fluid, casting, and resource-flow mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-logistics-transport"
        include_space_age = $true
        pattern = "(?i)train|cargo|ship|loader|inserter|belt|logistic|transport|rail|space-platform"
        notes = "Generated cluster scenario for locally available logistics, transport, rail, cargo, and inserter mods."
      }
    )

    foreach ($cluster in $clusterPatterns) {
      $mods = @(
        foreach ($name in $compatibleNames) {
          if (Test-MIRLocalNameMatches -Name $name -FullMod $FullModsByName[$name] -Pattern $cluster.pattern) {
            [string]$name
          }
        }
      )
      $definition = New-MIRGeneratedLocalScenarioDefinition -Name $cluster.name -Mods $mods -IncludeSpaceAge ([bool]$cluster.include_space_age) -Notes ([string]$cluster.notes)
      if ($null -ne $definition) { $definitions += $definition }
    }
  }

  if ($GenerateLocalPairwiseScenarios) {
    $pairPool = @(
      foreach ($name in $compatibleNames) {
        if (Test-MIRLocalNameMatches -Name $name -FullMod $FullModsByName[$name] -Pattern "(?i)planet|moon|space-age|bz|bob|Krastorio|refin|chem|casting|ore|resource|train|cargo|ship|logistic|inserter") {
          [string]$name
        }
      }
    ) | Sort-Object -Unique

    $pairCount = 0
    for ($i = 0; $i -lt $pairPool.Count; $i++) {
      for ($j = $i + 1; $j -lt $pairPool.Count; $j++) {
        if ($pairCount -ge $GeneratedLocalPairwiseLimit) { break }
        $pairCount++
        $definitions += New-MIRGeneratedLocalScenarioDefinition `
          -Name ("generated-local-$scenarioLineSlug-pair-{0:D3}" -f $pairCount) `
          -Mods @($pairPool[$i], $pairPool[$j]) `
          -IncludeSpaceAge $true `
          -Notes ("Generated capped pairwise local-library scenario: {0} + {1}." -f $pairPool[$i], $pairPool[$j])
      }
      if ($pairCount -ge $GeneratedLocalPairwiseLimit) { break }
    }
  }

  @($definitions | Where-Object { $null -ne $_ })
}

$exclusions = Read-MIRJsonFile -Path $KnownExclusions -Fallback ([pscustomobject]@{
  mod_names = @()
  categories = @("localizations", "internal")
})
$manualScenarioPaths = @($ManualScenariosPath)
if (-not $PSBoundParameters.ContainsKey("ManualScenariosPath")) {
  $lineManifest = if ($FactorioLine -eq "2.0") {
    Join-Path $PSScriptRoot "..\fixtures\compat-matrix\local-library-scenarios-2.0.json"
  } else {
    Join-Path $PSScriptRoot "..\fixtures\compat-matrix\local-library-scenarios.json"
  }
  $manualScenarioPaths += $lineManifest
}

$manualScenarios = @()
foreach ($scenarioManifestPath in @($manualScenarioPaths | Select-Object -Unique)) {
  $manifest = Read-MIRJsonFile -Path $scenarioManifestPath -Fallback ([pscustomobject]@{ schema = 0; scenarios = @() })
  if ([int](Get-MIRObjectProperty -Object $manifest -Name "schema" -Default 0) -ne 2) {
    throw "Scenario manifest must use schema 2: $scenarioManifestPath"
  }
  foreach ($scenario in @($manifest.scenarios)) {
    $targets = @((Get-MIRObjectProperty -Object $scenario -Name "targets" -Default @()) | ForEach-Object { [string]$_ })
    if ($targets.Count -gt 0 -and $FactorioLine -notin $targets) { continue }
    $scenario | Add-Member -NotePropertyName "_source_manifest" -NotePropertyValue $scenarioManifestPath -Force
    $manualScenarios += $scenario
  }
}
$manual = [pscustomobject]@{ scenarios = @($manualScenarios) }

$fullCache = @{}
function Get-FullCached {
  param([Parameter(Mandatory)][string]$Name)
  if ($localFullModsByName.ContainsKey($Name)) {
    return $localFullModsByName[$Name]
  }
  if ($Offline) {
    throw "Offline mode is enabled and mod '$Name' is not present in local mod zip roots or libraries."
  }
  if (-not $fullCache.ContainsKey($Name)) {
    $fullCache[$Name] = Get-MIRModPortalFullMod -Name $Name
  }
  return $fullCache[$Name]
}

function Resolve-MIRPortalScenario {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Type,
    [string[]]$RequestedMods = @(),
    [bool]$EnableSpaceAgeBundle,
    [string]$ClaimLevel = "loads",
    [int]$TimeoutSeconds = $ScenarioTimeoutSeconds,
    $Settings = $null,
    $ExpectedPlan = $null,
    [string]$SourceManifest = "",
    [string]$Notes = ""
  )

  $rootModNames = @(Get-MIRPortalRootModNames -ModNames $RequestedMods)
  $explicitOfficialMods = @(Get-MIRExplicitOfficialMods -ModNames $RequestedMods)
  $scenarioFailures = @()
  $scenarioLockEntries = @()

  foreach ($rootName in $rootModNames) {
    try {
      $full = Get-FullCached -Name $rootName
      $release = Select-MIRCompatibleRelease -FullMod $full -FactorioVersions $FactorioVersions
      if (-not $release) {
        $scenarioFailures += [pscustomobject]@{
          name = $rootName
          phase = "release-selection"
          error = "No compatible release for Factorio versions: $($FactorioVersions -join ',')"
        }
        continue
      }

      $deps = @(Get-MIRReleaseDependencies -Release $release)
      $scenarioLockEntries += ConvertTo-MIRScenarioLockEntry -FullMod $full -Release $release -Dependencies $deps

      $closure = Resolve-MIRRequiredDependencyClosure `
        -RootModNames @($rootName) `
        -GetFullMod { param($name) Get-FullCached -Name $name } `
        -SelectRelease { param($fullMod) Select-MIRCompatibleRelease -FullMod $fullMod -FactorioVersions $FactorioVersions } `
        -IncludeRecommendedDependencies:$IncludeRecommendedDependencies `
        -FailFast:$FailFast

      foreach ($dep in @($closure.resolved)) {
        if ($dep.name -eq $rootName) { continue }
        $scenarioLockEntries += ConvertTo-MIRScenarioLockEntry -FullMod $dep.full -Release $dep.release -Dependencies $dep.dependencies
      }
      $scenarioFailures += @($closure.failures | ForEach-Object {
        [pscustomobject]@{
          name = $_.name
          phase = "dependency-resolution"
          error = $_.error
        }
      })
    } catch {
      $scenarioFailures += [pscustomobject]@{
        name = $rootName
        phase = "metadata"
        error = $_.Exception.Message
      }
      if ($FailFast) { throw }
    }
  }

  $scenarioLockEntries = @($scenarioLockEntries | Sort-Object name, version -Unique)
  $resolvedNames = @($scenarioLockEntries | ForEach-Object { $_.name } | Sort-Object -Unique)
  $officialMods = @(Get-MIREnabledOfficialModsFromEntries `
    -LockEntries $scenarioLockEntries `
    -EnableSpaceAgeBundle $EnableSpaceAgeBundle `
    -ExplicitOfficialMods $explicitOfficialMods `
    -IncludeRecommendedDependencies:$IncludeRecommendedDependencies)
  foreach ($missingOfficial in @(Get-MIRUnavailableOfficialMods `
      -LockEntries $scenarioLockEntries `
      -EnableSpaceAgeBundle $EnableSpaceAgeBundle `
      -ExplicitOfficialMods $explicitOfficialMods `
      -IncludeRecommendedDependencies:$IncludeRecommendedDependencies)) {
    $scenarioFailures += [pscustomobject]@{
      name = $missingOfficial
      phase = "official-mod"
      error = "Official built-in mod '$missingOfficial' is not present for Factorio line $FactorioLine at the selected Factorio binary."
    }
  }

  New-MIRScenario `
    -Name $Name `
    -Type $Type `
    -RequestedMods $RequestedMods `
    -RootMods $rootModNames `
    -ResolvedMods $resolvedNames `
    -OfficialMods $officialMods `
    -LockEntries $scenarioLockEntries `
    -Failures $scenarioFailures `
    -ClaimLevel $ClaimLevel `
    -TimeoutSeconds $TimeoutSeconds `
    -Settings $Settings `
    -ExpectedPlan $ExpectedPlan `
    -SourceManifest $SourceManifest `
    -Notes $Notes
}

function Resolve-MIRLockScenario {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$LockEntriesByName,
    [string[]]$RequestedMods = @(),
    [bool]$EnableSpaceAgeBundle
  )

  $rootModNames = @(Get-MIRPortalRootModNames -ModNames $RequestedMods)
  $closure = Resolve-MIRLockDependencyNames `
    -RootModNames $rootModNames `
    -LockEntriesByName $LockEntriesByName `
    -IncludeRecommendedDependencies:$IncludeRecommendedDependencies
  $resolvedNames = @($closure.names)
  $scenarioLockEntries = @(
    foreach ($name in $resolvedNames) {
      if ($LockEntriesByName.ContainsKey([string]$name)) { $LockEntriesByName[[string]$name] }
    }
  )
  $officialMods = @(Get-MIREnabledOfficialModsFromEntries `
    -LockEntries $scenarioLockEntries `
    -EnableSpaceAgeBundle $EnableSpaceAgeBundle `
    -ExplicitOfficialMods (Get-MIRExplicitOfficialMods -ModNames $RequestedMods) `
    -IncludeRecommendedDependencies:$IncludeRecommendedDependencies)
  $scenarioFailures = @($closure.failures)
  foreach ($missingOfficial in @(Get-MIRUnavailableOfficialMods `
      -LockEntries $scenarioLockEntries `
      -EnableSpaceAgeBundle $EnableSpaceAgeBundle `
      -ExplicitOfficialMods (Get-MIRExplicitOfficialMods -ModNames $RequestedMods) `
      -IncludeRecommendedDependencies:$IncludeRecommendedDependencies)) {
    $scenarioFailures += [pscustomobject]@{
      name = $missingOfficial
      phase = "official-mod"
      error = "Official built-in mod '$missingOfficial' is not present for Factorio line $FactorioLine at the selected Factorio binary."
    }
  }

  New-MIRScenario `
    -Name $Name `
    -Type "catalog" `
    -RequestedMods $RequestedMods `
    -RootMods $rootModNames `
    -ResolvedMods $resolvedNames `
    -OfficialMods $officialMods `
    -LockEntries $scenarioLockEntries `
    -Failures $scenarioFailures
}

function Invoke-MIRScenarioLoad {
  param([Parameter(Mandatory)]$Scenario)

  $dependencyFailures = @($Scenario.dependency_failures)
  if ($dependencyFailures.Count -gt 0 -and -not $ContinueOnDependencyFailure) {
    [pscustomobject]@{
      scenario = $Scenario.name
      type = $Scenario.type
      requested_mods = @($Scenario.requested_mods)
      root_mods = @($Scenario.root_mods)
      resolved_mods = @($Scenario.resolved_mods)
      official_mods = @($Scenario.official_mods)
      dependency_failures = $dependencyFailures
      exit_code = $null
      timed_out = $false
      timeout_seconds = [int](Get-MIRObjectProperty -Object $Scenario -Name "timeout_seconds" -Default $ScenarioTimeoutSeconds)
      duration_seconds = 0.0
      skipped = $true
      skip_reason = "dependency_resolution_failure"
      process_passed = $false
      passed = $false
      save = ""
      stdout = ""
      stderr = ""
      audit_rows = @()
      sanitation_rows = @()
    }
    return
  }

  $userData = New-MIRCompatUserDataDir -Root $runRoot
  $modsDir = Join-Path $userData "mods"
  $null = Copy-MIRModUnderTest -RepoRoot $repo.Path -ModsDir $modsDir -ZipPath $resolvedModUnderTestZip
  Initialize-MIRSettingsOverrideMod -ModsDir $modsDir -FactorioVersion $FactorioLine
  Enable-CopiedDiagnostics -ModsDir $modsDir

  Copy-MIRCachedModZips -CacheDir $resolvedCacheDir -ModsDir $modsDir -LockEntries $Scenario.lock_entries -LinkMode $LinkMode

  $enabledMods = @("more-infinite-research", "mir-validation-settings-overrides") + @($Scenario.resolved_mods) + @($Scenario.official_mods)
  Write-MIRModList -ModsDir $modsDir -EnabledMods $enabledMods -OfficialBuiltinMods $officialBuiltinMods

  $scenarioTimeout = [int](Get-MIRObjectProperty -Object $Scenario -Name "timeout_seconds" -Default $ScenarioTimeoutSeconds)
  $result = Invoke-MIRFactorioLoadCheck -FactorioBin $FactorioBin -UserDataDir $userData -ScenarioName $Scenario.name -ScenarioTimeoutSeconds $scenarioTimeout
  $expectedPlan = Get-MIRObjectProperty -Object $Scenario -Name "expected_plan" -Default ([pscustomobject]@{})
  $requiredStreamScience = Get-MIRObjectProperty -Object $expectedPlan -Name "required_stream_science" -Default ([pscustomobject]@{})
  $scienceAssertions = @(
    foreach ($requiredStream in @($requiredStreamScience.PSObject.Properties)) {
      $streamName = [string]$requiredStream.Name
      $requiredPacks = @($requiredStream.Value | ForEach-Object { [string]$_ })
      $streamRows = @($result.audit_rows | Where-Object {
        [string]$_.kind -eq "stream" -and
        [string]$_.key -eq $streamName -and
        [string]$_.status -eq "generated"
      })
      $observedPacks = @(
        $streamRows |
          ForEach-Object { @([string]$_.science -split ",") } |
          Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
          Sort-Object -Unique
      )
      $missingPacks = @($requiredPacks | Where-Object { $_ -notin $observedPacks })
      [pscustomobject]@{
        stream = $streamName
        required_packs = $requiredPacks
        observed_packs = $observedPacks
        matching_generated_rows = $streamRows.Count
        missing_packs = $missingPacks
        passed = ($streamRows.Count -gt 0 -and $missingPacks.Count -eq 0)
      }
    }
  )
  $scienceContractPassed = @($scienceAssertions | Where-Object { $_.passed -ne $true }).Count -eq 0
  [pscustomobject]@{
    scenario = $Scenario.name
    type = $Scenario.type
    requested_mods = @($Scenario.requested_mods)
    root_mods = @($Scenario.root_mods)
    resolved_mods = @($Scenario.resolved_mods)
    official_mods = @($Scenario.official_mods)
    dependency_failures = $dependencyFailures
    exit_code = $result.exit_code
    timed_out = $result.timed_out
    timeout_seconds = $result.timeout_seconds
    duration_seconds = [double]$result.duration_seconds
    skipped = $false
    skip_reason = ""
    process_passed = [bool]$result.passed
    passed = ($result.passed -and $scienceContractPassed)
    save = $result.save
    stdout = $result.stdout
    stderr = $result.stderr
    audit_rows = @($result.audit_rows)
    sanitation_rows = @($result.sanitation_rows)
    science_contract_passed = $scienceContractPassed
    science_assertions = $scienceAssertions
  }
}

$selectedScenarios = @()
$failures = @()
$lockEntries = @()
$lock = $null

if (-not [string]::IsNullOrWhiteSpace($FromLockfile)) {
  $resolvedLockfile = (Resolve-Path -LiteralPath $FromLockfile).Path
  $lock = Read-MIRJsonFile -Path $resolvedLockfile -Fallback $null
  if (-not $lock) { throw "Could not read lockfile: $FromLockfile" }
  $lockEntries = @($lock.mods)
  $lockEntriesByName = Get-MIRLockEntriesByName -LockEntries $lockEntries

  $rootNames = @($lock.candidates_selected)
  if ($CandidateNames.Count -gt 0) {
    $candidateLookup = @{}
    foreach ($name in $CandidateNames) { $candidateLookup[[string]$name] = $true }
    $rootNames = @($rootNames | Where-Object { $candidateLookup.ContainsKey([string]$_) })
  }
  $rootNames = @(Select-MIRWindow -Items $rootNames)

  foreach ($rootName in $rootNames) {
    $selectedScenarios += Resolve-MIRLockScenario `
      -Name ([string]$rootName) `
      -LockEntriesByName $lockEntriesByName `
      -RequestedMods @([string]$rootName) `
      -EnableSpaceAgeBundle ([bool]$IncludeSpaceAge -or [bool]$lock.include_space_age)
  }
} else {
  $nonCatalogModeRequested = [bool]($RunManualScenarios -or $RunLocalModZips -or $RunGeneratedLocalScenarios)
  if ($Offline -and ($CandidateNames.Count -gt 0 -or ($MaxCandidates -gt 0 -and -not $nonCatalogModeRequested))) {
    throw "Offline mode cannot resolve catalog or named catalog candidates. Use -RunLocalModZips, -RunManualScenarios with local libraries, or -FromLockfile with cached/local archives."
  }

  $catalogCandidates = @()
  if ($CandidateNames.Count -gt 0) {
    $catalogCandidates = @($CandidateNames | ForEach-Object {
      [pscustomobject]@{ name = [string]$_; downloads_count = 0; category = ""; tags = @() }
    })
  } elseif ($MaxCandidates -gt 0 -and -not ($Offline -and $nonCatalogModeRequested)) {
    Write-Host "[compat-audit] querying mod portal catalog"
    $catalog = @(Get-MIRModPortalCatalog -MaxPages $CatalogPages)
    $catalogCandidates = @(
      $catalog |
        Where-Object { [int]$_.downloads_count -ge $MinDownloads } |
        Where-Object { Test-MIRInterestingCategory -Mod $_ } |
        Where-Object { -not (Test-MIRKnownExcluded -Mod $_ -Exclusions $exclusions) } |
        Sort-Object downloads_count -Descending |
        Select-Object -First $MaxCandidates
    )
  }

  $catalogCandidates = @(Select-MIRWindow -Items $catalogCandidates)

  foreach ($candidate in $catalogCandidates) {
    Write-Host "[compat-audit] inspecting $($candidate.name)"
    $selectedScenarios += Resolve-MIRPortalScenario `
      -Name ([string]$candidate.name) `
      -Type "catalog" `
      -RequestedMods @([string]$candidate.name) `
      -EnableSpaceAgeBundle ([bool]$IncludeSpaceAge)
  }
}

if ($RunManualScenarios) {
  $scenarioDefinitions = @($manual.scenarios)
  if ($ScenarioNames.Count -gt 0) {
    $scenarioLookup = @{}
    foreach ($name in $ScenarioNames) { $scenarioLookup[[string]$name] = $true }
    $scenarioDefinitions = @($scenarioDefinitions | Where-Object {
      $scenarioLookup.ContainsKey([string](Get-MIRObjectProperty -Object $_ -Name "name" -Default ""))
    })
  }

  foreach ($scenario in $scenarioDefinitions) {
    $scenarioName = [string](Get-MIRObjectProperty -Object $scenario -Name "name" -Default "")
    if ([string]::IsNullOrWhiteSpace($scenarioName)) {
      throw "Manual scenario is missing a non-empty name in $ManualScenariosPath."
    }
    Write-Host "[compat-audit] inspecting manual scenario $scenarioName"
    $scenarioMods = @((Get-MIRObjectProperty -Object $scenario -Name "roots" -Default @()) | ForEach-Object { [string]$_ })
    $setup = Get-MIRObjectProperty -Object $scenario -Name "setup" -Default ([pscustomobject]@{})
    $includeBundle = [bool](Get-MIRObjectProperty -Object $setup -Name "include_space_age" -Default $false)
    if ($scenarioMods -contains "space-age") { $includeBundle = $true }
    $selectedScenarios += Resolve-MIRPortalScenario `
      -Name $scenarioName `
      -Type "manual" `
      -RequestedMods $scenarioMods `
      -EnableSpaceAgeBundle $includeBundle `
      -ClaimLevel ([string](Get-MIRObjectProperty -Object $scenario -Name "claim_level" -Default "loads")) `
      -TimeoutSeconds ([int](Get-MIRObjectProperty -Object $scenario -Name "timeout_seconds" -Default $ScenarioTimeoutSeconds)) `
      -Settings (Get-MIRObjectProperty -Object $scenario -Name "settings" -Default ([pscustomobject]@{})) `
      -ExpectedPlan (Get-MIRObjectProperty -Object $scenario -Name "expected_plan" -Default ([pscustomobject]@{})) `
      -SourceManifest ([string](Get-MIRObjectProperty -Object $scenario -Name "_source_manifest" -Default "")) `
      -Notes ([string](Get-MIRObjectProperty -Object $scenario -Name "notes" -Default ""))
  }
}

if ($RunGeneratedLocalScenarios) {
  if ($localRootFullModsByName.Count -eq 0) {
    throw "RunGeneratedLocalScenarios requires -LocalModZipDirs or -LocalModZips for generated scenario roots."
  }

  $generatedDefinitions = @(New-MIRGeneratedLocalScenarioDefinitions -FullModsByName $localRootFullModsByName)
  if ($ScenarioNames.Count -gt 0) {
    $scenarioLookup = @{}
    foreach ($name in $ScenarioNames) { $scenarioLookup[[string]$name] = $true }
    $generatedDefinitions = @($generatedDefinitions | Where-Object { $scenarioLookup.ContainsKey([string]$_.name) })
  }

  foreach ($scenario in $generatedDefinitions) {
    Write-Host "[compat-audit] inspecting generated local scenario $($scenario.name)"
    $selectedScenarios += Resolve-MIRPortalScenario `
      -Name ([string]$scenario.name) `
      -Type "generated_local" `
      -RequestedMods @($scenario.mods | ForEach-Object { [string]$_ }) `
      -EnableSpaceAgeBundle ([bool]$scenario.include_space_age) `
      -Notes ([string]$scenario.notes)
  }
}

if ($RunLocalModZips) {
  if ($localRootFullModsByName.Count -eq 0) {
    throw "RunLocalModZips requires -LocalModZipDirs or -LocalModZips."
  }

  $localNames = @($localRootFullModsByName.Keys | Sort-Object)
  if ($LocalModNames.Count -gt 0) {
    $localLookup = @{}
    foreach ($name in $LocalModNames) { $localLookup[[string]$name] = $true }
    foreach ($name in $LocalModNames) {
      if (-not $localRootFullModsByName.ContainsKey([string]$name)) {
        throw "Requested local mod '$name' was not found in local zip inputs."
      }
    }
    $localNames = @($localNames | Where-Object { $localLookup.ContainsKey([string]$_) })
  }

  $localNames = @(Select-MIRWindow -Items $localNames)

  foreach ($localName in $localNames) {
    Write-Host "[compat-audit] inspecting local zip scenario $localName"
    $selectedScenarios += Resolve-MIRPortalScenario `
      -Name $localName `
      -Type "local_zip" `
      -RequestedMods @([string]$localName) `
      -EnableSpaceAgeBundle $false `
      -Notes "Local mod zip supplied to the compatibility audit."
  }
}

$failures = @(
  foreach ($scenario in $selectedScenarios) {
    foreach ($failure in @($scenario.dependency_failures)) {
      [pscustomobject]@{
        scenario = $scenario.name
        name = $failure.name
        phase = $failure.phase
        error = $failure.error
      }
    }
  }
)

$lockEntries = @(
  foreach ($scenario in $selectedScenarios) {
    foreach ($entry in @($scenario.lock_entries)) { $entry }
  }
) | Sort-Object name, version -Unique
$lockEntries = @($lockEntries)
$lockEntriesByName = Get-MIRLockEntriesByName -LockEntries $lockEntries

$lock = [ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  min_downloads = $MinDownloads
  factorio_line = $FactorioLine
  factorio_versions = $FactorioVersions
  include_space_age = [bool]$IncludeSpaceAge
  scenario_timeout_seconds = $ScenarioTimeoutSeconds
  continue_on_dependency_failure = [bool]$ContinueOnDependencyFailure
  include_recommended_dependencies = [bool]$IncludeRecommendedDependencies
  max_candidates = $MaxCandidates
  catalog_pages = $CatalogPages
  from_lockfile = $FromLockfile
  start_index = $StartIndex
  count = $Count
  offline = [bool]$Offline
  local_mod_zip_dirs = @($LocalModZipDirs)
  local_mod_zips = @($LocalModZips)
  local_mod_library_dirs = @($LocalModLibraryDirs)
  local_mod_library_zips = @($LocalModLibraryZips)
  mod_under_test_zip = $resolvedModUnderTestZip
  mod_under_test_sha256 = if ($resolvedModUnderTestZip) { (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedModUnderTestZip).Hash.ToUpperInvariant() } else { "" }
  mod_under_test_source_commit = $ModUnderTestSourceCommit
  link_mode = $LinkMode
  local_root_zip_count = $localRootZipPaths.Count
  local_library_zip_count = $localLibraryZipPaths.Count
  candidates_selected = @($selectedScenarios | Where-Object { $_.type -eq "catalog" } | ForEach-Object { $_.name })
  manual_scenarios_selected = @($selectedScenarios | Where-Object { $_.type -eq "manual" } | ForEach-Object { $_.name })
  generated_local_scenarios_selected = @($selectedScenarios | Where-Object { $_.type -eq "generated_local" } | ForEach-Object { $_.name })
  local_zip_scenarios_selected = @($selectedScenarios | Where-Object { $_.type -eq "local_zip" } | ForEach-Object { $_.name })
  mods = $lockEntries
}

$lockPath = Join-Path $resolvedOutputDir "compat-candidates.lock.json"
$reportPath = Join-Path $resolvedOutputDir "compat-report.md"
$failureCsvPath = Join-Path $resolvedOutputDir "failures.csv"
$jsonReportPath = Join-Path $resolvedOutputDir "compat-report.json"

$lock | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $lockPath -Encoding UTF8

$scenarioSummaries = @($selectedScenarios | ForEach-Object {
  [ordered]@{
    name = $_.name
    type = $_.type
    requested_mods = @($_.requested_mods)
    root_mods = @($_.root_mods)
    resolved_mods = @($_.resolved_mods)
    official_mods = @($_.official_mods)
    dependency_failures = @($_.dependency_failures)
    claim_level = [string](Get-MIRObjectProperty -Object $_ -Name "claim_level" -Default "loads")
    timeout_seconds = [int](Get-MIRObjectProperty -Object $_ -Name "timeout_seconds" -Default $ScenarioTimeoutSeconds)
    settings = Get-MIRObjectProperty -Object $_ -Name "settings" -Default ([pscustomobject]@{})
    expected_plan = Get-MIRObjectProperty -Object $_ -Name "expected_plan" -Default ([pscustomobject]@{})
    source_manifest = [string](Get-MIRObjectProperty -Object $_ -Name "source_manifest" -Default "")
    notes = $_.notes
  }
})

[ordered]@{
  schema = 1
  lockfile = $lockPath
  factorio_line = $FactorioLine
  selected_count = @($selectedScenarios | Where-Object { $_.type -eq "catalog" }).Count
  manual_selected_count = @($selectedScenarios | Where-Object { $_.type -eq "manual" }).Count
  generated_local_selected_count = @($selectedScenarios | Where-Object { $_.type -eq "generated_local" }).Count
  local_zip_selected_count = @($selectedScenarios | Where-Object { $_.type -eq "local_zip" }).Count
  offline = [bool]$Offline
  local_root_zip_count = $localRootZipPaths.Count
  local_library_zip_count = $localLibraryZipPaths.Count
  mod_count = $lockEntries.Count
  failure_count = $failures.Count
  failures = $failures
  scenarios = $scenarioSummaries
  manual_scenarios = @($manual.scenarios)
} | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $jsonReportPath -Encoding UTF8

if ($failures.Count -gt 0) {
  $failures | Export-Csv -NoTypeInformation -LiteralPath $failureCsvPath
} else {
  "scenario,name,phase,error" | Set-Content -LiteralPath $failureCsvPath -Encoding UTF8
}

$report = @()
$report += "# MIR Compatibility Audit"
$report += ""
$report += "- Generated: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss K"))"
$report += "- Factorio line: $FactorioLine"
$report += "- Minimum downloads: $MinDownloads"
$report += "- Factorio versions: $($FactorioVersions -join ', ')"
$report += "- Scenario timeout seconds: $ScenarioTimeoutSeconds"
$report += "- Continue on dependency failure: $([bool]$ContinueOnDependencyFailure)"
$report += "- Include recommended dependencies: $([bool]$IncludeRecommendedDependencies)"
$report += "- Offline: $([bool]$Offline)"
$report += "- Local root zip inputs: $($localRootZipPaths.Count)"
$report += "- Local library zip inputs: $($localLibraryZipPaths.Count)"
$report += "- Local zip inputs total: $($localZipPaths.Count)"
$report += "- Catalog scenarios: $(@($selectedScenarios | Where-Object { $_.type -eq "catalog" }).Count)"
$report += "- Manual scenarios: $(@($selectedScenarios | Where-Object { $_.type -eq "manual" }).Count)"
$report += "- Generated local scenarios: $(@($selectedScenarios | Where-Object { $_.type -eq "generated_local" }).Count)"
$report += "- Local zip scenarios: $(@($selectedScenarios | Where-Object { $_.type -eq "local_zip" }).Count)"
$report += "- Locked mods including dependencies: $($lockEntries.Count)"
$report += "- Failures: $($failures.Count)"
$report += ""
$report += "## Scenarios"
$report += ""
$report += "| Scenario | Type | Requested | Resolved third-party mods | Official mods |"
$report += "| --- | --- | --- | --- | --- |"
foreach ($scenario in $selectedScenarios | Sort-Object type, name) {
  $report += "| $($scenario.name) | $($scenario.type) | $(@($scenario.requested_mods) -join ', ') | $(@($scenario.resolved_mods) -join ', ') | $(@($scenario.official_mods) -join ', ') |"
}
$report += ""
$report += "## Locked Mods"
$report += ""
$report += "| Mod | Version | Downloads | Category | Dependencies |"
$report += "| --- | --- | ---: | --- | ---: |"
foreach ($entry in $lockEntries | Sort-Object downloads_count -Descending) {
  $report += "| $($entry.name) | $($entry.version) | $($entry.downloads_count) | $($entry.category) | $(@($entry.dependencies).Count) |"
}
$report += ""
$report += "## Failures"
$report += ""
if ($failures.Count -eq 0) {
  $report += "No metadata or dependency failures."
} else {
  foreach ($failure in $failures) {
    $report += ('- `{0}` / `{1}` [{2}]: {3}' -f $failure.scenario, $failure.name, $failure.phase, $failure.error)
  }
}
$report -join "`n" | Set-Content -LiteralPath $reportPath -Encoding UTF8

$downloadEntries = @($lockEntries | Where-Object {
  -not [string]::IsNullOrWhiteSpace([string]$_.file_name) -and
  -not [string]::IsNullOrWhiteSpace([string]$_.download_url)
})
if (($DownloadMods -or ($RunLoadTests -and -not $UseCachedDownloads)) -and $downloadEntries.Count -gt 0) {
  if ($Offline) {
    throw "Offline mode cannot download $($downloadEntries.Count) Mod Portal archive(s). Add those zips to local roots/libraries or rerun without -Offline."
  }
  if ([string]::IsNullOrWhiteSpace($ModPortalUsername) -or [string]::IsNullOrWhiteSpace($ModPortalToken)) {
    throw "Mod downloads require -ModPortalUsername and -ModPortalToken or FACTORIO_USERNAME/FACTORIO_TOKEN."
  }

  foreach ($entry in $downloadEntries) {
    $null = Save-MIRModPortalDownload -Release $entry -Username $ModPortalUsername -Token $ModPortalToken -CacheDir $resolvedCacheDir
  }
}

$results = @()
if ($RunLoadTests) {
  if ([string]::IsNullOrWhiteSpace($FactorioBin)) {
    throw "Load tests require -FactorioBin or FACTORIO_BIN."
  }

  $runRoot = New-MIRDirectory -Path (Join-Path $resolvedOutputDir "runs")
  $loadResultsPath = Join-Path $resolvedOutputDir "load-results.json"
  $manualResultsPath = Join-Path $resolvedOutputDir "manual-results.json"
  $scenarioList = @($selectedScenarios)
  for ($scenarioIndex = 0; $scenarioIndex -lt $scenarioList.Count; $scenarioIndex++) {
    $scenario = $scenarioList[$scenarioIndex]
    $displayIndex = $scenarioIndex + 1
    $rootMods = @($scenario.root_mods) -join ","
    $resolvedCount = @($scenario.resolved_mods).Count
    $officialMods = @($scenario.official_mods) -join ","
    $dependencyFailureCount = @($scenario.dependency_failures).Count
    Write-Host ("[compat-audit] load {0}/{1} starting scenario={2} type={3} roots={4} resolved={5} official={6} dependency_failures={7}" -f $displayIndex, $scenarioList.Count, $scenario.name, $scenario.type, $rootMods, $resolvedCount, $officialMods, $dependencyFailureCount)
    $scenarioStarted = Get-Date
    $result = Invoke-MIRScenarioLoad -Scenario $scenario
    $results += $result
    $results | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $loadResultsPath -Encoding UTF8
    $manualResults = @($results | Where-Object { $_.type -in @("manual", "generated_local") })
    if ($manualResults.Count -gt 0) {
      $manualResults | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manualResultsPath -Encoding UTF8
    }
    $scenarioSeconds = [math]::Round(((Get-Date) - $scenarioStarted).TotalSeconds, 2)
    Write-Host ("[compat-audit] load {0}/{1} result scenario={2} passed={3} skipped={4} timed_out={5} exit_code={6} audit_rows={7} seconds={8}" -f $displayIndex, $scenarioList.Count, $scenario.name, $result.passed, $result.skipped, $result.timed_out, $result.exit_code, @($result.audit_rows).Count, $scenarioSeconds)
    if ($FailFast -and $result.passed -ne $true) { throw "Load test failed for $($scenario.name)." }
  }
  $results | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $loadResultsPath -Encoding UTF8
  $manualResults = @($results | Where-Object { $_.type -in @("manual", "generated_local") })
  if ($manualResults.Count -gt 0) {
    $manualResults | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manualResultsPath -Encoding UTF8
  }

  $lockSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $lockPath).Hash.ToUpperInvariant()
  $resultByScenario = @{}
  foreach ($result in $results) { $resultByScenario[[string]$result.scenario] = $result }
  $campaignScenarios = @(
    foreach ($scenario in $selectedScenarios) {
      $result = $resultByScenario[[string]$scenario.name]
      $dependencyFailureCount = @($scenario.dependency_failures).Count
      $expectedPlan = Get-MIRObjectProperty -Object $scenario -Name "expected_plan" -Default ([pscustomobject]@{})
      $maximumDependencyFailures = [int](Get-MIRObjectProperty -Object $expectedPlan -Name "maximum_dependency_failures" -Default 0)
      $budgetScope = if ([string]$scenario.type -eq "local_zip") { "local_mod_zips" } else { "campaigns" }
      $budgetKey = if ($budgetScope -eq "local_mod_zips") {
        "local-$FactorioLine-$($scenario.name)"
      } else {
        [string]$scenario.name
      }
      $budgetScopeProperty = $sanitationPolicy.PSObject.Properties[$budgetScope]
      if ($null -eq $budgetScopeProperty) {
        throw "Sanitation policy has no '$budgetScope' budget scope for scenario $($scenario.name)."
      }
      $budgetProperty = $budgetScopeProperty.Value.PSObject.Properties[$budgetKey]
      if ($null -eq $budgetProperty) {
        throw "Scenario $($scenario.name) has no governed sanitation budget '$budgetKey' in scope '$budgetScope'."
      }
      $sanitationBudget = $budgetProperty.Value
      $expectedPrunes = @($sanitationBudget.expected_external_prunes)
      $maximumUnreviewedPrunes = [int]$sanitationBudget.maximum_unreviewed_external_prunes
      $observedPrunes = @($result.sanitation_rows | Where-Object { [string]$_.owner -eq "external" })
      $expectedIdentities = @($expectedPrunes | ForEach-Object { "$($_.technology)|$($_.effect_type)|$($_.target)" } | Sort-Object -Unique)
      $observedIdentities = @($observedPrunes | ForEach-Object { "$($_.technology)|$($_.effect_type)|$($_.target)" } | Sort-Object -Unique)
      $missingExpectedPrunes = @(Compare-Object $expectedIdentities $observedIdentities | Where-Object SideIndicator -eq '<=' | ForEach-Object InputObject)
      $unreviewedPrunes = @(Compare-Object $expectedIdentities $observedIdentities | Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject)
      $processResult = if ($result.process_passed -eq $true) { "passed" } elseif ($result.skipped -eq $true) { "skipped" } else { "failed" }
      $sanitationResult = if ($processResult -eq "skipped") {
        "skipped"
      } elseif ($missingExpectedPrunes.Count -eq 0 -and $unreviewedPrunes.Count -le $maximumUnreviewedPrunes) {
        "passed"
      } else {
        "REVIEW_REQUIRED"
      }
      $claimGateResult = if ($processResult -eq "passed" -and $result.passed -eq $true -and
          $dependencyFailureCount -le $maximumDependencyFailures -and
          $sanitationResult -eq "passed") {
        "passed"
      } elseif ($processResult -eq "skipped") {
        "skipped"
      } else {
        "failed"
      }
      $closure = @(
        foreach ($entry in @($scenario.lock_entries | Sort-Object name, version -Unique)) {
          if ([string]::IsNullOrWhiteSpace([string]$entry.sha256)) {
            throw "Campaign evidence requires SHA-256 for resolved mod $($entry.name) $($entry.version)."
          }
          [ordered]@{
            name = [string]$entry.name
            version = [string]$entry.version
            sha256 = [string]$entry.sha256
            source = [string]$entry.source
          }
        }
      )
      [ordered]@{
        scenario_id = [string]$scenario.name
        requested_roots = @($scenario.requested_mods)
        actual_executed_roots = @($scenario.root_mods)
        resolved_mods = @($scenario.resolved_mods)
        official_mods = @($scenario.official_mods)
        dependency_closure = $closure
        dependency_failure_count = $dependencyFailureCount
        process_result = $processResult
        result = $claimGateResult
        exit_code = $result.exit_code
        timed_out = [bool]$result.timed_out
        timeout_seconds = [int](Get-MIRObjectProperty -Object $scenario -Name "timeout_seconds" -Default $ScenarioTimeoutSeconds)
        duration_seconds = [double]$result.duration_seconds
        settings = Get-MIRObjectProperty -Object $scenario -Name "settings" -Default ([pscustomobject]@{})
        expected_plan = $expectedPlan
        sanitation_budget = [ordered]@{
          scope = $budgetScope
          key = $budgetKey
          expected_external_prunes = $expectedPrunes
          maximum_unreviewed_external_prunes = $maximumUnreviewedPrunes
        }
        observed_external_prunes = $observedPrunes
        missing_expected_prunes = $missingExpectedPrunes
        unreviewed_external_prunes = $unreviewedPrunes
        sanitation_result = $sanitationResult
        source_manifest = [string](Get-MIRObjectProperty -Object $scenario -Name "source_manifest" -Default "")
        claim_level = [string](Get-MIRObjectProperty -Object $scenario -Name "claim_level" -Default "loads")
      }
    }
  )
  $campaignEvidence = [ordered]@{
    schema = 1
    kind = "mir-modpack-campaign-evidence"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    factorio_line = $FactorioLine
    factorio_binary = [ordered]@{
      name = Split-Path -Leaf (Resolve-Path -LiteralPath $FactorioBin).Path
      version = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $FactorioBin).Path).VersionInfo.FileVersion
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Resolve-Path -LiteralPath $FactorioBin).Path).Hash
    }
    mir_archive = [ordered]@{
      path = if ([string]::IsNullOrWhiteSpace($resolvedModUnderTestZip)) { "working-tree" } else { Split-Path -Leaf $resolvedModUnderTestZip }
      sha256 = $lock.mod_under_test_sha256
      source_commit = $ModUnderTestSourceCommit
      source_commit_binding = if ([string]::IsNullOrWhiteSpace($ModUnderTestSourceCommit)) { "unbound" } else { "declared" }
    }
    dependency_lock = [ordered]@{
      path = Split-Path -Leaf $lockPath
      sha256 = $lockSha256
    }
    sanitation_budget = [ordered]@{
      policy = [string]$sanitationPolicy.policy
      path = ".mir/sanitation-budgets.json"
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedSanitationBudgetPath).Hash
    }
    scenarios = $campaignScenarios
  }
  $campaignEvidencePath = Join-Path $resolvedOutputDir "campaign-evidence.json"
  $campaignEvidence | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $campaignEvidencePath -Encoding UTF8
}

Write-Host "[compat-audit] wrote $lockPath"
Write-Host "[compat-audit] wrote $reportPath"
Write-Host "[compat-audit] wrote $jsonReportPath"
Write-Host "[compat-audit] wrote $failureCsvPath"
if ($RunLoadTests) { Write-Host "[compat-audit] wrote $campaignEvidencePath" }
