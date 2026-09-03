if ($ScenarioWorker) {
  if ([string]::IsNullOrWhiteSpace($CandidateZip)) {
    throw "-ScenarioWorker requires -CandidateZip with the exact candidate archive."
  }
  if ($Scenario.Count -ne 1 -or $Group.Count -gt 0 -or $Tag.Count -gt 0 -or $Tier) {
    throw "-ScenarioWorker requires exactly one -Scenario and cannot be combined with -Group, -Tag, or -Tier."
  }
  $candidatePath = if ([IO.Path]::IsPathRooted($CandidateZip)) { $CandidateZip } else { Join-Path $repo $CandidateZip }
  if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
    throw "Scenario worker candidate package not found: $CandidateZip"
  }
  $script:ValidationPackageZipPath = (Resolve-Path -LiteralPath $candidatePath).Path
}

if ($StaticOnly -or [string]::IsNullOrWhiteSpace($FactorioBin)) {
  Write-Host "[skip] Factorio runtime validation skipped. Set FACTORIO_BIN or pass -FactorioBin to run load tests."
  exit 0
}

if (-not (Test-Path -LiteralPath $FactorioBin)) {
  throw "Factorio binary not found: $FactorioBin"
}

if ([string]::IsNullOrWhiteSpace($ValidationSummaryPath)) {
  $ValidationSummaryPath = Join-Path $repo "build\results\validation\factorio-$($repoInfo.factorio_version)-summary.json"
}
if ($Tier -eq "impacted" -and [string]::IsNullOrWhiteSpace($ChangedSince)) {
  throw "The impacted tier requires -ChangedSince <commit>."
}
if (-not [string]::IsNullOrWhiteSpace($ChangedSince)) {
  $impactPath = Join-Path $repo ".mir\test-impact.yml"
  $impact = Get-Content -Raw -LiteralPath $impactPath | ConvertFrom-Json
  if ($impact.schema -ne 1) { throw "Test-impact manifest schema must be 1." }
  $changedPaths = @(& git -C $repo diff --name-only "$ChangedSince...HEAD")
  if ($LASTEXITCODE -ne 0) { throw "Unable to resolve changed paths since $ChangedSince." }
  $Scenario += @($impact.baseline_scenarios | ForEach-Object { [string]$_ })
  foreach ($path in $changedPaths) {
    $normalizedPath = ([string]$path).Replace("\", "/")
    foreach ($rule in @($impact.paths)) {
      if ($normalizedPath -like [string]$rule.pattern) {
        $Scenario += @($rule.scenarios | ForEach-Object { [string]$_ })
        $Group += @($rule.groups | ForEach-Object { [string]$_ })
        $Tag += @($rule.tags | ForEach-Object { [string]$_ })
      }
    }
  }
  $Scenario = @($Scenario | Sort-Object -Unique)
  $Group = @($Group | Sort-Object -Unique)
  $Tag = @($Tag | Sort-Object -Unique)
}
$checkpointActive = -not [string]::IsNullOrWhiteSpace($StartAtScenario)
if ($checkpointActive) {
  if ($Scenario.Count -gt 0 -or $Group.Count -gt 0 -or $Tag.Count -gt 0) {
    throw "-StartAtScenario cannot be combined with -Scenario, -Group, or -Tag."
  }
  $checkpointTailScenarios = @(
    "static-validation",
    "package-build",
    "runtime-state-contract",
    "space-age-vanilla-family-mixed-owner",
    "space-age-fluid-productivity",
    "space-age-generation-integrity-inserter-enabled",
    "space-age-space-promethium-pack-policy",
    "all-official-pack-policy",
    "all-pack-policy",
    "base-extension-boundary-policy",
    "base-effect-setting-retention",
    "weapon-overlap-off-coverage-absent",
    "weapon-overlap-off-coverage-present",
    "weapon-overlap-conditional-coverage-absent",
    "weapon-overlap-conditional-coverage-present",
    "weapon-overlap-always-coverage-absent",
    "weapon-overlap-always-coverage-present",
    "scaled-weapon-overlap",
    "weapon-overlap-conditional-external-owner",
    "omega-drill-productivity",
    "base-competitor-rollback",
    "technology-prerequisite-rewire",
    "end-game-prerequisite-gate"
  )
  $nativeOwnerSettingsScenarios = @(
    "space-age-native-owner-settings-default",
    "space-age-native-owner-settings-disabled",
    "space-age-native-owner-settings-cost-base",
    "space-age-native-owner-settings-cost-linear",
    "space-age-native-owner-settings-cost-growth",
    "space-age-native-owner-settings-fixed-default",
    "space-age-native-owner-settings-fixed-override",
    "space-age-native-owner-settings-linear-default",
    "space-age-native-owner-settings-linear-override",
    "space-age-native-owner-settings-research-time",
    "space-age-native-owner-settings-max-level",
    "space-age-native-owner-settings-effect",
    "space-age-native-owner-settings-combined",
    "space-age-native-owner-settings-unrecognized-default",
    "space-age-native-owner-settings-unrecognized-override",
    "space-age-native-owner-settings-config-change"
  )
  $Scenario = if ($StartAtScenario -eq "space-age-native-owner-settings-default") {
    @(@($checkpointTailScenarios + $nativeOwnerSettingsScenarios) | Sort-Object -Unique)
  } else {
    $checkpointTailScenarios
  }
}
$scenarioRegistry = Import-MIRScenarioRegistry -Path $expectedScenariosPath -TargetProfile $repoInfo.factorio_version
$selectionActive = $Scenario.Count -gt 0 -or $Group.Count -gt 0 -or $Tag.Count -gt 0
$scenarioRegistry = Select-MIRScenarioRegistry -Registry $scenarioRegistry -Scenario $Scenario -Group $Group -Tag $Tag
if ($ScenarioWorker) {
  $scenarioRegistry = [pscustomobject]@{
    schema=3
    target_profile=$scenarioRegistry.target_profile
    records=@($scenarioRegistry.records | Where-Object kind -ne "gate")
  }
  if (@($scenarioRegistry.records).Count -ne 1) {
    throw "Scenario worker selection did not resolve exactly one executable scenario."
  }
}
$expectedScenarios = Get-MIRExpectedScenarioNames -Registry $scenarioRegistry
$selectedScenarioNames = @{}
foreach ($name in $expectedScenarios) { $selectedScenarioNames[$name] = $true }
$requiredGroupsForRun = if ($selectionActive) {
  @($scenarioRegistry.records | ForEach-Object group | Sort-Object -Unique)
} else {
  @($targetProfile.required_validation_groups)
}

function Test-MIRScenarioSelected {
  param([Parameter(Mandatory)][string]$Name)
  return $selectedScenarioNames.ContainsKey($Name)
}
