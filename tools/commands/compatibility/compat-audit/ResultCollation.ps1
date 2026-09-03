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

  $runtimeCampaign = New-MIRCompatRuntimeCampaignRoot -RequestedRoot $RuntimeRoot
  $runtimeRunRoot = $runtimeCampaign.path
  $retainedRunRoot = New-MIRDirectory -Path (Join-Path $resolvedOutputDir "runs")
  $loadResultsPath = Join-Path $resolvedOutputDir "load-results.json"
  $manualResultsPath = Join-Path $resolvedOutputDir "manual-results.json"
  $scenarioList = @($selectedScenarios)
  try {
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
  } finally {
    Remove-MIRCompatRuntimeCampaignRootIfEmpty -Campaign $runtimeCampaign
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
