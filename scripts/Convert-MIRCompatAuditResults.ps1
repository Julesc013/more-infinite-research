param(
  [Parameter(Mandatory)][string]$AuditDir,
  [string]$OutputDir = $AuditDir,
  [string]$ExpectedFailures = (Join-Path $PSScriptRoot "..\fixtures\compat-matrix\expected-failures.json")
)

$ErrorActionPreference = "Stop"

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

function ConvertTo-MIRArray {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [array]) { return @($Value) }
  return @($Value)
}

function Get-MIRObjectProperty {
  param($Object, [string]$Name, $Default = "")
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Read-MIRTextIfExists {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  return Get-Content -Raw -LiteralPath $Path
}

function Get-MIRFactorioErrorText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

  $marker = "------------- Error -------------"
  $markerIndex = $Text.LastIndexOf($marker, [System.StringComparison]::Ordinal)
  if ($markerIndex -ge 0) {
    return $Text.Substring($markerIndex)
  }

  $lines = @($Text -split "`r?`n")
  $errorLines = @($lines | Where-Object {
    $_ -match "Error Util\.cpp|Failed to load mod|Error while loading|Exception"
  })
  if ($errorLines.Count -gt 0) {
    return ($errorLines -join "`n")
  }

  return (($lines | Select-Object -Last 80) -join "`n")
}

function New-MIRFailureGroup {
  param(
    [Parameter(Mandatory)][string]$Kind,
    [string]$Scenario = "",
    [string]$Mod = "",
    [string]$Stream = "",
    [string]$Recipe = "",
    [string]$Reason = "",
    [string]$Evidence = "",
    [string]$LikelyRemediation = "",
    [bool]$Expected = $false,
    [string]$Expectation = ""
  )

  [ordered]@{
    id = ""
    kind = $Kind
    scenario = $Scenario
    mod = $Mod
    stream = $Stream
    recipe = $Recipe
    reason = $Reason
    evidence = $Evidence
    likely_remediation = $LikelyRemediation
    expected = $Expected
    expectation = $Expectation
  }
}

function Test-MIRExpectedPattern {
  param([string]$Value, [string]$Pattern)
  if ([string]::IsNullOrWhiteSpace($Pattern)) { return $true }
  return $Value -match $Pattern
}

function Find-MIRExpectedFailure {
  param($Group, [object[]]$ExpectedFailureRules)

  foreach ($rule in @($ExpectedFailureRules)) {
    $scenarioPattern = [string](Get-MIRObjectProperty -Object $rule -Name "scenario_pattern" -Default (Get-MIRObjectProperty -Object $rule -Name "scenario" -Default ""))
    $modPattern = [string](Get-MIRObjectProperty -Object $rule -Name "mod_pattern" -Default (Get-MIRObjectProperty -Object $rule -Name "mod" -Default ""))
    $kindPattern = [string](Get-MIRObjectProperty -Object $rule -Name "kind_pattern" -Default (Get-MIRObjectProperty -Object $rule -Name "kind" -Default ""))
    $reasonPattern = [string](Get-MIRObjectProperty -Object $rule -Name "reason_pattern" -Default "")

    if (-not (Test-MIRExpectedPattern -Value ([string]$Group.scenario) -Pattern $scenarioPattern)) { continue }
    if (-not (Test-MIRExpectedPattern -Value ([string]$Group.mod) -Pattern $modPattern)) { continue }
    if (-not (Test-MIRExpectedPattern -Value ([string]$Group.kind) -Pattern $kindPattern)) { continue }
    if (-not (Test-MIRExpectedPattern -Value ([string]$Group.reason) -Pattern $reasonPattern)) { continue }

    return $rule
  }

  return $null
}

$resolvedAuditDir = (Resolve-Path -LiteralPath $AuditDir).Path
$resolvedOutputDir = New-MIRDirectory -Path $OutputDir

$compatReport = Read-MIRJsonFile -Path (Join-Path $resolvedAuditDir "compat-report.json") -Fallback ([pscustomobject]@{})
$loadResults = ConvertTo-MIRArray (Read-MIRJsonFile -Path (Join-Path $resolvedAuditDir "load-results.json") -Fallback @())
$manualResults = ConvertTo-MIRArray (Read-MIRJsonFile -Path (Join-Path $resolvedAuditDir "manual-results.json") -Fallback @())
$reportFailures = ConvertTo-MIRArray (Get-MIRObjectProperty -Object $compatReport -Name "failures" -Default @())
$expectedFailureData = Read-MIRJsonFile -Path $ExpectedFailures -Fallback ([pscustomobject]@{ expected_failures = @() })
$expectedFailureRules = ConvertTo-MIRArray (Get-MIRObjectProperty -Object $expectedFailureData -Name "expected_failures" -Default @())

$groups = @()
$observationRows = @()

foreach ($failure in $reportFailures) {
  $phase = [string](Get-MIRObjectProperty -Object $failure -Name "phase")
  $kind = "dependency_resolution_failure"
  if ($phase -eq "release-selection") { $kind = "dependency_resolution_failure" }
  if ($phase -eq "metadata") { $kind = "dependency_resolution_failure" }
  $groups += New-MIRFailureGroup `
    -Kind $kind `
    -Scenario ([string](Get-MIRObjectProperty -Object $failure -Name "scenario")) `
    -Mod ([string](Get-MIRObjectProperty -Object $failure -Name "name")) `
    -Reason $phase `
    -Evidence ([string](Get-MIRObjectProperty -Object $failure -Name "error")) `
    -LikelyRemediation "Check dependency compatibility, selected Factorio version, and Mod Portal metadata before treating this as a MIR bug."
}

foreach ($result in $loadResults) {
  $scenario = [string](Get-MIRObjectProperty -Object $result -Name "scenario")
  $rootMods = @(ConvertTo-MIRArray (Get-MIRObjectProperty -Object $result -Name "root_mods" -Default @()))
  $primaryMod = if ($rootMods.Count -gt 0) { [string]$rootMods[0] } else { $scenario }
  $stdoutPath = [string](Get-MIRObjectProperty -Object $result -Name "stdout")
  $stderrPath = [string](Get-MIRObjectProperty -Object $result -Name "stderr")
  $logText = (Read-MIRTextIfExists -Path $stdoutPath) + "`n" + (Read-MIRTextIfExists -Path $stderrPath)
  $errorText = Get-MIRFactorioErrorText -Text $logText
  $passed = [bool](Get-MIRObjectProperty -Object $result -Name "passed" -Default $false)
  $skipped = [bool](Get-MIRObjectProperty -Object $result -Name "skipped" -Default $false)
  $skipReason = [string](Get-MIRObjectProperty -Object $result -Name "skip_reason")
  $timedOut = [bool](Get-MIRObjectProperty -Object $result -Name "timed_out" -Default $false)
  $auditRows = ConvertTo-MIRArray (Get-MIRObjectProperty -Object $result -Name "audit_rows" -Default @())

  if ($skipped) {
    $groups += New-MIRFailureGroup `
      -Kind $skipReason `
      -Scenario $scenario `
      -Mod $primaryMod `
      -Reason "load_skipped" `
      -Evidence "Scenario load test skipped before Factorio startup." `
      -LikelyRemediation "Resolve required dependencies, or rerun with -ContinueOnDependencyFailure when partial modsets are useful for diagnostics."
    continue
  }

  if (-not $passed) {
    $kind = "load_failure"
    if ($timedOut) {
      $kind = "timeout"
    } elseif ($errorText -match "multiple infinite productivity owners|multiple infinite recipe-productivity owners") {
      $kind = "duplicate_exact_owner"
    } elseif ($errorText -match "missing prerequisite|Unknown technology|Technology prerequisite") {
      $kind = "missing_prerequisite"
    } elseif ($errorText -match "No lab|science pack|ingredients") {
      $kind = "invalid_science_pack"
    }

    $groups += New-MIRFailureGroup `
      -Kind $kind `
      -Scenario $scenario `
      -Mod $primaryMod `
      -Reason ("exit_code=" + [string](Get-MIRObjectProperty -Object $result -Name "exit_code")) `
      -Evidence $stdoutPath `
      -LikelyRemediation $(if ($timedOut) { "Increase ScenarioTimeoutSeconds only after checking whether Factorio is genuinely hung on this modset." } else { "Inspect the Factorio log for the prototype-stage error, then decide whether MIR policy or the tested modset caused the failure." })
  }

  if ($passed -and $auditRows.Count -eq 0) {
    $groups += New-MIRFailureGroup `
      -Kind "no_audit_rows" `
      -Scenario $scenario `
      -Mod $primaryMod `
      -Reason "audit_rows_empty" `
      -Evidence $stdoutPath `
      -LikelyRemediation "Confirm the copied MIR diagnostics patch was applied and the Factorio log was captured."
  }

  foreach ($row in $auditRows) {
    $kind = [string](Get-MIRObjectProperty -Object $row -Name "kind")
    $stream = [string](Get-MIRObjectProperty -Object $row -Name "key")
    $status = [string](Get-MIRObjectProperty -Object $row -Name "status")
    $reason = [string](Get-MIRObjectProperty -Object $row -Name "reason")
    $recipe = [string](Get-MIRObjectProperty -Object $row -Name "recipe")
    $ownerKinds = [string](Get-MIRObjectProperty -Object $row -Name "owner_kinds")
    $owners = [string](Get-MIRObjectProperty -Object $row -Name "owners")
    $warningClass = [string](Get-MIRObjectProperty -Object $row -Name "warning_class")
    $capState = [string](Get-MIRObjectProperty -Object $row -Name "cap_state")

    if ($kind -in @("compatibility_role", "compatibility_plan", "recipe_cap")) {
      $observationRows += [pscustomobject]@{
        scenario = $scenario
        mod = $primaryMod
        kind = $kind
        key = $stream
        status = $status
        reason = $reason
        role = [string](Get-MIRObjectProperty -Object $row -Name "role")
        action = [string](Get-MIRObjectProperty -Object $row -Name "action")
        signal = [string](Get-MIRObjectProperty -Object $row -Name "signal")
        recipe = $recipe
        warning_class = $warningClass
        cap_state = $capState
        maximum_productivity = [string](Get-MIRObjectProperty -Object $row -Name "maximum_productivity")
        per_level = [string](Get-MIRObjectProperty -Object $row -Name "per_level")
        levels_to_cap = [string](Get-MIRObjectProperty -Object $row -Name "levels_to_cap")
        total = [string](Get-MIRObjectProperty -Object $row -Name "total")
        warnings = [string](Get-MIRObjectProperty -Object $row -Name "warnings")
      }
    }

    if ($kind -eq "recipe_owner" -and $ownerKinds -match "unknown_external") {
      $groups += New-MIRFailureGroup `
        -Kind "unknown_external_owner" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Recipe $recipe `
        -Reason $reason `
        -Evidence $owners `
        -LikelyRemediation "Keep MIR suppressed unless repeated audit evidence supports a declarative compatibility profile." `
        -Expected $true `
        -Expectation "Conservative suppression under an unknown external productivity owner is an expected audit observation."
    } elseif ($kind -eq "recipe_owner" -and $ownerKinds -match "known_competitor") {
      $groups += New-MIRFailureGroup `
        -Kind "known_competitor_not_replaced" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Recipe $recipe `
        -Reason $reason `
        -Evidence $owners `
        -LikelyRemediation "Check whether coverage, change value, lab science, or another owner prevented replacement."
    } elseif ($kind -eq "stream" -and $status -eq "skipped" -and $reason -match "^existing technology effect ") {
      continue
    } elseif ($kind -eq "stream" -and $reason -match "no_lab|lab-compatible|lab_compatible") {
      $groups += New-MIRFailureGroup `
        -Kind "invalid_science_pack" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Reason $reason `
        -Evidence ([string](Get-MIRObjectProperty -Object $row -Name "science")) `
        -LikelyRemediation "Review science-pack selection and lab compatibility for this modset."
    } elseif ($kind -eq "stream" -and $status -eq "skipped" -and $reason -match "^missing required ") {
      continue
    } elseif ($kind -eq "stream" -and $reason -match "missing|required") {
      $groups += New-MIRFailureGroup `
        -Kind "missing_prerequisite" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Reason $reason `
        -Evidence ([string](Get-MIRObjectProperty -Object $row -Name "prerequisites")) `
        -LikelyRemediation "Check required prototype gates and prerequisite resolution for this stream."
    } elseif ($reason -match "recipe_productivity_not_allowed|productivity_not_allowed") {
      $groups += New-MIRFailureGroup `
        -Kind "recipe_productivity_disallowed" `
        -Scenario $scenario `
        -Mod $primaryMod `
        -Stream $stream `
        -Recipe $recipe `
        -Reason $reason `
        -Evidence $owners `
        -LikelyRemediation "Do not force productivity onto recipes whose prototypes disallow it." `
        -Expected $true `
        -Expectation "MIR correctly rejected a recipe whose prototype disallows productivity."
    }
  }
}

$dedup = @{}
$deduped = @()
foreach ($group in $groups) {
  $key = @(
    $group.kind,
    $group.scenario,
    $group.mod,
    $group.stream,
    $group.recipe,
    $group.reason,
    $group.evidence
  ) -join "`u{1f}"
  if ($dedup.ContainsKey($key)) { continue }
  $dedup[$key] = $true
  $deduped += $group
}

$index = 1
foreach ($group in $deduped) {
  $group.id = "FG{0:D4}" -f $index
  $expectedRule = Find-MIRExpectedFailure -Group $group -ExpectedFailureRules $expectedFailureRules
  if ($null -ne $expectedRule) {
    $group.expected = $true
    $group.expectation = [string](Get-MIRObjectProperty -Object $expectedRule -Name "notes" -Default "expected failure")
  }
  $index++
}

$unexpected = @($deduped | Where-Object { $_.expected -ne $true })
$expected = @($deduped | Where-Object { $_.expected -eq $true })

$profileCandidates = @(
  $deduped |
    Where-Object { $_.kind -in @("known_competitor_not_replaced", "unknown_external_owner", "duplicate_exact_owner", "split_productivity_family") } |
    ForEach-Object {
      [ordered]@{
        group_id = $_.id
        kind = $_.kind
        mod = $_.mod
        scenario = $_.scenario
        stream = $_.stream
        recipe = $_.recipe
        evidence = $_.evidence
        review_required = $true
      }
    }
)

$missingDependencyRows = @(
  $reportFailures |
    Where-Object {
      $phase = [string](Get-MIRObjectProperty -Object $_ -Name "phase")
      $phase -in @("dependency-resolution", "metadata", "release-selection")
    } |
    ForEach-Object {
      [pscustomobject]@{
        scenario = [string](Get-MIRObjectProperty -Object $_ -Name "scenario")
        mod = [string](Get-MIRObjectProperty -Object $_ -Name "name")
        phase = [string](Get-MIRObjectProperty -Object $_ -Name "phase")
        error = [string](Get-MIRObjectProperty -Object $_ -Name "error")
      }
    }
)

$missingDependencySummary = @(
  $missingDependencyRows |
    Group-Object mod |
    Sort-Object -Property @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name"; Descending = $false } |
    ForEach-Object {
      $rows = @($_.Group)
      [ordered]@{
        mod = [string]$_.Name
        count = [int]$_.Count
        phases = @($rows | ForEach-Object { $_.phase } | Sort-Object -Unique)
        scenarios = @($rows | ForEach-Object { $_.scenario } | Sort-Object -Unique)
        sample_error = [string]$rows[0].error
      }
    }
)

$groupedPath = Join-Path $resolvedOutputDir "compat-failures.grouped.json"
$summaryPath = Join-Path $resolvedOutputDir "compat-summary.md"
$profilePath = Join-Path $resolvedOutputDir "profile-candidates.json"
$observationsJsonPath = Join-Path $resolvedOutputDir "compat-observations.json"
$observationsCsvPath = Join-Path $resolvedOutputDir "compat-observations.csv"
$observationsMdPath = Join-Path $resolvedOutputDir "compat-observations.md"
$missingJsonPath = Join-Path $resolvedOutputDir "missing-dependencies.json"
$missingCsvPath = Join-Path $resolvedOutputDir "missing-dependencies.csv"
$missingMdPath = Join-Path $resolvedOutputDir "missing-dependencies.md"

[ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  audit_dir = $resolvedAuditDir
  group_count = $deduped.Count
  unexpected_count = $unexpected.Count
  expected_count = $expected.Count
  groups = $deduped
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $groupedPath -Encoding UTF8

[ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  candidates = $profileCandidates
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $profilePath -Encoding UTF8

$observationSummary = @(
  $observationRows |
    Group-Object kind |
    Sort-Object Name |
    ForEach-Object {
      [ordered]@{
        kind = [string]$_.Name
        count = [int]$_.Count
      }
    }
)

[ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  audit_dir = $resolvedAuditDir
  observation_count = $observationRows.Count
  summary = $observationSummary
  observations = @($observationRows)
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $observationsJsonPath -Encoding UTF8

if ($observationRows.Count -gt 0) {
  $observationRows | Export-Csv -NoTypeInformation -LiteralPath $observationsCsvPath
} else {
  "scenario,mod,kind,key,status,reason,role,action,signal,recipe,warning_class,cap_state,maximum_productivity,per_level,levels_to_cap,total,warnings" | Set-Content -LiteralPath $observationsCsvPath -Encoding UTF8
}

$observationsMd = @()
$observationsMd += "# MIR Compatibility Observations"
$observationsMd += ""
$observationsMd += ('- Audit dir: `{0}`' -f $resolvedAuditDir)
$observationsMd += "- Observation rows: $($observationRows.Count)"
$observationsMd += ""
$observationsMd += "These rows are diagnostics, not failure groups. They describe MIR roles, planner summaries, and recipe-cap warnings."
$observationsMd += ""
$observationsMd += "## Rows By Kind"
$observationsMd += ""
if ($observationSummary.Count -eq 0) {
  $observationsMd += "No compatibility observation rows detected."
} else {
  $observationsMd += "| Kind | Count |"
  $observationsMd += "| --- | ---: |"
  foreach ($entry in $observationSummary) {
    $observationsMd += "| $($entry.kind) | $($entry.count) |"
  }
}

$recipeCapWarnings = @($observationRows | Where-Object { $_.kind -eq "recipe_cap" })
if ($recipeCapWarnings.Count -gt 0) {
  $observationsMd += ""
  $observationsMd += "## Recipe Cap Warnings"
  $observationsMd += ""
  $observationsMd += "| Scenario | Stream | Recipe | Warning | Cap state | Maximum | Per level | Levels to cap |"
  $observationsMd += "| --- | --- | --- | --- | --- | ---: | ---: | ---: |"
  foreach ($entry in $recipeCapWarnings | Select-Object -First 100) {
    $observationsMd += "| $($entry.scenario) | $($entry.key) | $($entry.recipe) | $($entry.warning_class) | $($entry.cap_state) | $($entry.maximum_productivity) | $($entry.per_level) | $($entry.levels_to_cap) |"
  }
}
$observationsMd -join "`n" | Set-Content -LiteralPath $observationsMdPath -Encoding UTF8

[ordered]@{
  schema = 1
  generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
  audit_dir = $resolvedAuditDir
  missing_dependency_count = $missingDependencySummary.Count
  total_missing_dependency_rows = $missingDependencyRows.Count
  missing_dependencies = $missingDependencySummary
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $missingJsonPath -Encoding UTF8

if ($missingDependencyRows.Count -gt 0) {
  $missingDependencyRows | Export-Csv -NoTypeInformation -LiteralPath $missingCsvPath
} else {
  "scenario,mod,phase,error" | Set-Content -LiteralPath $missingCsvPath -Encoding UTF8
}

$missingMd = @()
$missingMd += "# MIR Missing Dependency Summary"
$missingMd += ""
$missingMd += ('- Audit dir: `{0}`' -f $resolvedAuditDir)
$missingMd += "- Distinct missing/incompatible dependencies: $($missingDependencySummary.Count)"
$missingMd += "- Total dependency failure rows: $($missingDependencyRows.Count)"
$missingMd += ""
if ($missingDependencySummary.Count -eq 0) {
  $missingMd += "No dependency-resolution, metadata, or release-selection failures detected."
} else {
  $missingMd += "| Mod | Count | Phases | Scenarios | Sample error |"
  $missingMd += "| --- | ---: | --- | --- | --- |"
  foreach ($entry in $missingDependencySummary | Select-Object -First 100) {
    $missingMd += "| $($entry.mod) | $($entry.count) | $(@($entry.phases) -join ', ') | $(@($entry.scenarios) -join ', ') | $($entry.sample_error -replace '\|', '/') |"
  }
}
$missingMd -join "`n" | Set-Content -LiteralPath $missingMdPath -Encoding UTF8

$byKind = @($deduped | Group-Object { $_.kind } | Sort-Object Name)
$summary = @()
$summary += "# MIR Compatibility Audit Summary"
$summary += ""
$summary += ('- Audit dir: `{0}`' -f $resolvedAuditDir)
$summary += "- Load results: $($loadResults.Count)"
$summary += "- Manual results: $($manualResults.Count)"
$summary += "- Failure groups: $($deduped.Count)"
$summary += "- Unexpected failure groups: $($unexpected.Count)"
$summary += "- Expected failure groups: $($expected.Count)"
$summary += "- Profile candidates: $($profileCandidates.Count)"
$summary += "- Compatibility observations: $($observationRows.Count)"
$summary += "- Distinct missing/incompatible dependencies: $($missingDependencySummary.Count)"
$summary += ""
$summary += "## Groups By Kind"
$summary += ""
if ($byKind.Count -eq 0) {
  $summary += "No failure groups detected."
} else {
  $summary += "| Kind | Count |"
  $summary += "| --- | ---: |"
  foreach ($group in $byKind) {
    $summary += "| $($group.Name) | $($group.Count) |"
  }
}
$summary += ""
$summary += "## Failure Groups"
$summary += ""
foreach ($group in $deduped) {
  $summary += ('- `{0}` `{1}` expected=`{2}` scenario=`{3}` mod=`{4}` stream=`{5}` recipe=`{6}` reason=`{7}`' -f $group.id, $group.kind, $group.expected, $group.scenario, $group.mod, $group.stream, $group.recipe, $group.reason)
}

$summary -join "`n" | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "[compat-results] wrote $summaryPath"
Write-Host "[compat-results] wrote $groupedPath"
Write-Host "[compat-results] wrote $profilePath"
Write-Host "[compat-results] wrote $observationsMdPath"
Write-Host "[compat-results] wrote $observationsJsonPath"
Write-Host "[compat-results] wrote $observationsCsvPath"
Write-Host "[compat-results] wrote $missingMdPath"
Write-Host "[compat-results] wrote $missingJsonPath"
Write-Host "[compat-results] wrote $missingCsvPath"
