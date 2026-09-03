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

$resolvedOutputDir = New-MIRDirectory -Path $resolvedOutputDir
$lockPath = Join-Path $resolvedOutputDir "compat-candidates.lock.json"
$reportPath = Join-Path $resolvedOutputDir "compat-report.md"
$failureCsvPath = Join-Path $resolvedOutputDir "failures.csv"
$jsonReportPath = Join-Path $resolvedOutputDir "compat-report.json"

$lock | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $lockPath -Encoding UTF8
