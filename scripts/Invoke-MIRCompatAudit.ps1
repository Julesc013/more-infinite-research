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
  [switch]$DownloadMods,
  [switch]$RunLoadTests,
  [switch]$FailFast,
  [string]$ManualScenarios = (Join-Path $PSScriptRoot "..\fixtures\compat-matrix\manual-scenarios.json"),
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

$resolvedOutputDir = New-MIRDirectory -Path $OutputDir
$resolvedCacheDir = New-MIRDirectory -Path $ModCacheDir
$exclusions = Read-MIRJsonFile -Path $KnownExclusions -Fallback ([pscustomobject]@{
  mod_names = @()
  categories = @("localizations", "internal")
})
$manual = Read-MIRJsonFile -Path $ManualScenarios -Fallback ([pscustomobject]@{
  scenarios = @()
})

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

$fullCache = @{}
function Get-FullCached {
  param([Parameter(Mandatory)][string]$Name)
  if (-not $fullCache.ContainsKey($Name)) {
    $fullCache[$Name] = Get-MIRModPortalFullMod -Name $Name
  }
  return $fullCache[$Name]
}

$selected = @()
$failures = @()
foreach ($candidate in $catalogCandidates) {
  Write-Host "[compat-audit] inspecting $($candidate.name)"
  try {
    $full = Get-FullCached -Name $candidate.name
    $release = Select-MIRCompatibleRelease -FullMod $full -FactorioVersions $FactorioVersions
    if (-not $release) {
      $failures += [pscustomobject]@{
        name = $candidate.name
        phase = "release-selection"
        error = "No compatible release for Factorio versions: $($FactorioVersions -join ',')"
      }
      continue
    }

    $deps = @(Get-MIRReleaseDependencies -Release $release)
    $closure = Resolve-MIRRequiredDependencyClosure `
      -RootModNames @($candidate.name) `
      -GetFullMod { param($name) Get-FullCached -Name $name } `
      -SelectRelease { param($fullMod) Select-MIRCompatibleRelease -FullMod $fullMod -FactorioVersions $FactorioVersions } `
      -FailFast:$FailFast

    $selected += [pscustomobject]@{
      full = $full
      release = $release
      dependencies = $deps
      dependency_closure = $closure.resolved
      dependency_failures = $closure.failures
    }
    $failures += @($closure.failures | ForEach-Object {
      [pscustomobject]@{
        name = $_.name
        phase = "dependency-resolution"
        error = $_.error
      }
    })
  } catch {
    $failures += [pscustomobject]@{
      name = $candidate.name
      phase = "metadata"
      error = $_.Exception.Message
    }
    if ($FailFast) { throw }
  }
}

$lockEntries = @()
foreach ($entry in $selected) {
  $lockEntries += ConvertTo-MIRLockEntry -FullMod $entry.full -Release $entry.release -Dependencies $entry.dependencies
  foreach ($dep in @($entry.dependency_closure)) {
    if ($dep.name -eq $entry.full.name) { continue }
    $lockEntries += ConvertTo-MIRLockEntry -FullMod $dep.full -Release $dep.release -Dependencies $dep.dependencies
  }
}
$lockEntries = @($lockEntries | Sort-Object name, version -Unique)

$lock = [ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  min_downloads = $MinDownloads
  factorio_versions = $FactorioVersions
  include_space_age = [bool]$IncludeSpaceAge
  max_candidates = $MaxCandidates
  candidates_selected = @($selected | ForEach-Object { $_.full.name })
  mods = $lockEntries
}

$lockPath = Join-Path $resolvedOutputDir "compat-candidates.lock.json"
$reportPath = Join-Path $resolvedOutputDir "compat-report.md"
$failureCsvPath = Join-Path $resolvedOutputDir "failures.csv"
$jsonReportPath = Join-Path $resolvedOutputDir "compat-report.json"

$lock | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $lockPath -Encoding UTF8
[ordered]@{
  schema = 1
  lockfile = $lockPath
  selected_count = $selected.Count
  mod_count = $lockEntries.Count
  failure_count = $failures.Count
  failures = $failures
  manual_scenarios = @($manual.scenarios)
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonReportPath -Encoding UTF8

if ($failures.Count -gt 0) {
  $failures | Export-Csv -NoTypeInformation -LiteralPath $failureCsvPath
} else {
  "name,phase,error" | Set-Content -LiteralPath $failureCsvPath -Encoding UTF8
}

$report = @()
$report += "# MIR Compatibility Audit"
$report += ""
$report += "- Generated: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss K"))"
$report += "- Minimum downloads: $MinDownloads"
$report += "- Factorio versions: $($FactorioVersions -join ', ')"
$report += "- Selected candidates: $($selected.Count)"
$report += "- Locked mods including dependencies: $($lockEntries.Count)"
$report += "- Failures: $($failures.Count)"
$report += ""
$report += "## Selected Candidates"
$report += ""
$report += "| Mod | Version | Downloads | Category | Dependencies |"
$report += "| --- | --- | ---: | --- | ---: |"
foreach ($entry in $lockEntries | Sort-Object downloads_count -Descending) {
  $report += "| $($entry.name) | $($entry.version) | $($entry.downloads_count) | $($entry.category) | $(@($entry.dependencies).Count) |"
}
$report += ""
$report += "## Manual Scenarios"
$report += ""
foreach ($scenario in @($manual.scenarios)) {
  $report += ('- `{0}`: {1}' -f $scenario.name, (@($scenario.mods) -join ", "))
}
$report += ""
$report += "## Failures"
$report += ""
if ($failures.Count -eq 0) {
  $report += "No metadata or dependency failures."
} else {
  foreach ($failure in $failures) {
    $report += ('- `{0}` [{1}]: {2}' -f $failure.name, $failure.phase, $failure.error)
  }
}
$report -join "`n" | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($DownloadMods -or $RunLoadTests) {
  if ([string]::IsNullOrWhiteSpace($ModPortalUsername) -or [string]::IsNullOrWhiteSpace($ModPortalToken)) {
    throw "Mod downloads require -ModPortalUsername and -ModPortalToken or FACTORIO_USERNAME/FACTORIO_TOKEN."
  }

  foreach ($entry in $selected) {
    $null = Save-MIRModPortalDownload -Release $entry.release -Username $ModPortalUsername -Token $ModPortalToken -CacheDir $resolvedCacheDir
    foreach ($dep in @($entry.dependency_closure)) {
      $null = Save-MIRModPortalDownload -Release $dep.release -Username $ModPortalUsername -Token $ModPortalToken -CacheDir $resolvedCacheDir
    }
  }
}

if ($RunLoadTests) {
  if ([string]::IsNullOrWhiteSpace($FactorioBin)) {
    throw "Load tests require -FactorioBin or FACTORIO_BIN."
  }

  $runRoot = New-MIRDirectory -Path (Join-Path $resolvedOutputDir "runs")
  $results = @()
  foreach ($entry in $selected) {
    $userData = New-MIRCompatUserDataDir -Root $runRoot
    $modsDir = Join-Path $userData "mods"
    $null = Copy-MIRModUnderTest -RepoRoot $repo.Path -ModsDir $modsDir
    Copy-MIRCachedModZips -CacheDir $resolvedCacheDir -ModsDir $modsDir -LockEntries $lockEntries
    Write-MIRModList -ModsDir $modsDir -EnabledMods @("more-infinite-research", $entry.full.name)
    $results += Invoke-MIRFactorioLoadCheck -FactorioBin $FactorioBin -UserDataDir $userData -ScenarioName $entry.full.name
    if ($FailFast -and $results[-1].passed -ne $true) { throw "Load test failed for $($entry.full.name)." }
  }
  $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $resolvedOutputDir "load-results.json") -Encoding UTF8
}

Write-Host "[compat-audit] wrote $lockPath"
Write-Host "[compat-audit] wrote $reportPath"
Write-Host "[compat-audit] wrote $jsonReportPath"
Write-Host "[compat-audit] wrote $failureCsvPath"
