param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
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
  [string[]]$LocalModNames = @(),
  [switch]$DownloadMods,
  [switch]$RunLoadTests,
  [switch]$RunManualScenarios,
  [switch]$RunLocalModZips,
  [switch]$IncludeRecommendedDependencies,
  [string[]]$ScenarioNames = @(),
  [int]$ScenarioTimeoutSeconds = 900,
  [switch]$ContinueOnDependencyFailure,
  [switch]$FailFast,
  [Alias("ManualScenarios")]
  [string]$ManualScenariosPath = (Join-Path $PSScriptRoot "..\fixtures\compat-matrix\manual-scenarios.json"),
  [string]$KnownExclusions = (Join-Path $PSScriptRoot "..\fixtures\compat-matrix\known-exclusions.json")
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$moduleRoot = Join-Path $PSScriptRoot "MIRCompatAudit"
. (Join-Path $moduleRoot "ModPortal.ps1")
. (Join-Path $moduleRoot "DependencyResolver.ps1")
. (Join-Path $moduleRoot "DiagnosticsParser.ps1")
. (Join-Path $moduleRoot "FactorioRunner.ps1")

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

  [ordered]@{
    name = [string]$FullMod.name
    title = [string]$FullMod.title
    version = [string]$Release.version
    factorio_version = [string]$Release.info_json.factorio_version
    downloads_count = [int]$FullMod.downloads_count
    category = [string]$FullMod.category
    owner = [string]$FullMod.owner
    file_name = [string]$Release.file_name
    sha1 = [string]$Release.sha1
    download_url = [string]$Release.download_url
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
      $info = $reader.ReadToEnd() | ConvertFrom-Json
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
$localZipPaths = @()
foreach ($dir in @($LocalModZipDirs)) {
  if ([string]::IsNullOrWhiteSpace([string]$dir)) { continue }
  if (-not (Test-Path -LiteralPath $dir)) {
    throw "Local mod zip directory does not exist: $dir"
  }
  $localZipPaths += @(Get-ChildItem -LiteralPath $dir -Filter *.zip -File | ForEach-Object { $_.FullName })
}
foreach ($zipPath in @($LocalModZips)) {
  if ([string]::IsNullOrWhiteSpace([string]$zipPath)) { continue }
  if (-not (Test-Path -LiteralPath $zipPath)) {
    throw "Local mod zip does not exist: $zipPath"
  }
  $localZipPaths += (Resolve-Path -LiteralPath $zipPath).Path
}
$localZipPaths = @($localZipPaths | Sort-Object -Unique)
$localFullModsByName = @{}
foreach ($zipPath in $localZipPaths) {
  $localFull = ConvertTo-MIRLocalFullMod -ZipPath $zipPath
  if ([string]::IsNullOrWhiteSpace([string]$localFull.name)) {
    throw "Local mod zip has no mod name: $zipPath"
  }
  $localFullModsByName[[string]$localFull.name] = $localFull
}
$officialBuiltinMods = @("space-age", "quality", "elevated-rails", "recycler")
$specialLocalMods = @("base", "more-infinite-research")
$officialBuiltinLookup = @{}
foreach ($officialMod in $officialBuiltinMods) {
  $officialBuiltinLookup[$officialMod] = $true
}
$localModLookup = @{}
foreach ($name in @($officialBuiltinMods + $specialLocalMods)) {
  $localModLookup[$name] = $true
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

  return @($enabled.Keys | Sort-Object)
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

$exclusions = Read-MIRJsonFile -Path $KnownExclusions -Fallback ([pscustomobject]@{
  mod_names = @()
  categories = @("localizations", "internal")
})
$manual = Read-MIRJsonFile -Path $ManualScenariosPath -Fallback ([pscustomobject]@{
  scenarios = @()
})

$fullCache = @{}
function Get-FullCached {
  param([Parameter(Mandatory)][string]$Name)
  if ($localFullModsByName.ContainsKey($Name)) {
    return $localFullModsByName[$Name]
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
    [Parameter(Mandatory)][string[]]$RequestedMods,
    [bool]$EnableSpaceAgeBundle,
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

  New-MIRScenario `
    -Name $Name `
    -Type $Type `
    -RequestedMods $RequestedMods `
    -RootMods $rootModNames `
    -ResolvedMods $resolvedNames `
    -OfficialMods $officialMods `
    -LockEntries $scenarioLockEntries `
    -Failures $scenarioFailures `
    -Notes $Notes
}

function Resolve-MIRLockScenario {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$LockEntriesByName,
    [Parameter(Mandatory)][string[]]$RequestedMods,
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

  New-MIRScenario `
    -Name $Name `
    -Type "catalog" `
    -RequestedMods $RequestedMods `
    -RootMods $rootModNames `
    -ResolvedMods $resolvedNames `
    -OfficialMods $officialMods `
    -LockEntries $scenarioLockEntries `
    -Failures $closure.failures
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
      timeout_seconds = $ScenarioTimeoutSeconds
      skipped = $true
      skip_reason = "dependency_resolution_failure"
      passed = $false
      save = ""
      stdout = ""
      stderr = ""
      audit_rows = @()
    }
    return
  }

  $userData = New-MIRCompatUserDataDir -Root $runRoot
  $modsDir = Join-Path $userData "mods"
  $null = Copy-MIRModUnderTest -RepoRoot $repo.Path -ModsDir $modsDir
  Enable-MIRCopiedGenerationReport -ModsDir $modsDir

  Copy-MIRCachedModZips -CacheDir $resolvedCacheDir -ModsDir $modsDir -LockEntries $Scenario.lock_entries

  $enabledMods = @("more-infinite-research") + @($Scenario.resolved_mods) + @($Scenario.official_mods)
  Write-MIRModList -ModsDir $modsDir -EnabledMods $enabledMods

  $result = Invoke-MIRFactorioLoadCheck -FactorioBin $FactorioBin -UserDataDir $userData -ScenarioName $Scenario.name -ScenarioTimeoutSeconds $ScenarioTimeoutSeconds
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
    skipped = $false
    skip_reason = ""
    passed = $result.passed
    save = $result.save
    stdout = $result.stdout
    stderr = $result.stderr
    audit_rows = @($result.audit_rows)
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
  $catalogCandidates = @()
  if ($CandidateNames.Count -gt 0) {
    $catalogCandidates = @($CandidateNames | ForEach-Object {
      [pscustomobject]@{ name = [string]$_; downloads_count = 0; category = ""; tags = @() }
    })
  } elseif ($MaxCandidates -gt 0) {
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
    $scenarioMods = @((Get-MIRObjectProperty -Object $scenario -Name "mods" -Default @()) | ForEach-Object { [string]$_ })
    $includeBundle = [bool](Get-MIRObjectProperty -Object $scenario -Name "include_space_age" -Default $false)
    if ($scenarioMods -contains "space-age") { $includeBundle = $true }
    $selectedScenarios += Resolve-MIRPortalScenario `
      -Name $scenarioName `
      -Type "manual" `
      -RequestedMods $scenarioMods `
      -EnableSpaceAgeBundle $includeBundle `
      -Notes ([string](Get-MIRObjectProperty -Object $scenario -Name "notes" -Default ""))
  }
}

if ($RunLocalModZips) {
  if ($localFullModsByName.Count -eq 0) {
    throw "RunLocalModZips requires -LocalModZipDirs or -LocalModZips."
  }

  $localNames = @($localFullModsByName.Keys | Sort-Object)
  if ($LocalModNames.Count -gt 0) {
    $localLookup = @{}
    foreach ($name in $LocalModNames) { $localLookup[[string]$name] = $true }
    foreach ($name in $LocalModNames) {
      if (-not $localFullModsByName.ContainsKey([string]$name)) {
        throw "Requested local mod '$name' was not found in local zip inputs."
      }
    }
    $localNames = @($localNames | Where-Object { $localLookup.ContainsKey([string]$_) })
  }

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
  local_mod_zip_dirs = @($LocalModZipDirs)
  local_mod_zips = @($LocalModZips)
  candidates_selected = @($selectedScenarios | Where-Object { $_.type -eq "catalog" } | ForEach-Object { $_.name })
  manual_scenarios_selected = @($selectedScenarios | Where-Object { $_.type -eq "manual" } | ForEach-Object { $_.name })
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
    notes = $_.notes
  }
})

[ordered]@{
  schema = 1
  lockfile = $lockPath
  selected_count = @($selectedScenarios | Where-Object { $_.type -eq "catalog" }).Count
  manual_selected_count = @($selectedScenarios | Where-Object { $_.type -eq "manual" }).Count
  local_zip_selected_count = @($selectedScenarios | Where-Object { $_.type -eq "local_zip" }).Count
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
$report += "- Minimum downloads: $MinDownloads"
$report += "- Factorio versions: $($FactorioVersions -join ', ')"
$report += "- Scenario timeout seconds: $ScenarioTimeoutSeconds"
$report += "- Continue on dependency failure: $([bool]$ContinueOnDependencyFailure)"
$report += "- Include recommended dependencies: $([bool]$IncludeRecommendedDependencies)"
$report += "- Local zip inputs: $($localZipPaths.Count)"
$report += "- Catalog scenarios: $(@($selectedScenarios | Where-Object { $_.type -eq "catalog" }).Count)"
$report += "- Manual scenarios: $(@($selectedScenarios | Where-Object { $_.type -eq "manual" }).Count)"
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
  if ([string]::IsNullOrWhiteSpace($ModPortalUsername) -or [string]::IsNullOrWhiteSpace($ModPortalToken)) {
    throw "Mod downloads require -ModPortalUsername and -ModPortalToken or FACTORIO_USERNAME/FACTORIO_TOKEN."
  }

  foreach ($entry in $downloadEntries) {
    $null = Save-MIRModPortalDownload -Release $entry -Username $ModPortalUsername -Token $ModPortalToken -CacheDir $resolvedCacheDir
  }
}

if ($RunLoadTests) {
  if ([string]::IsNullOrWhiteSpace($FactorioBin)) {
    throw "Load tests require -FactorioBin or FACTORIO_BIN."
  }

  $runRoot = New-MIRDirectory -Path (Join-Path $resolvedOutputDir "runs")
  $results = @()
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
    $scenarioSeconds = [math]::Round(((Get-Date) - $scenarioStarted).TotalSeconds, 2)
    Write-Host ("[compat-audit] load {0}/{1} result scenario={2} passed={3} skipped={4} timed_out={5} exit_code={6} audit_rows={7} seconds={8}" -f $displayIndex, $scenarioList.Count, $scenario.name, $result.passed, $result.skipped, $result.timed_out, $result.exit_code, @($result.audit_rows).Count, $scenarioSeconds)
    if ($FailFast -and $result.passed -ne $true) { throw "Load test failed for $($scenario.name)." }
  }
  $results | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $resolvedOutputDir "load-results.json") -Encoding UTF8
  $manualResults = @($results | Where-Object { $_.type -eq "manual" })
  if ($manualResults.Count -gt 0) {
    $manualResults | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $resolvedOutputDir "manual-results.json") -Encoding UTF8
  }
}

Write-Host "[compat-audit] wrote $lockPath"
Write-Host "[compat-audit] wrote $reportPath"
Write-Host "[compat-audit] wrote $jsonReportPath"
Write-Host "[compat-audit] wrote $failureCsvPath"
