Invoke-PackageZipSmokeScenario -ScenarioName "package-zip-base"
if ([bool]$targetProfile.supports_space_age) {
  Invoke-PackageZipSmokeScenario -ScenarioName "package-zip-space-age" -EnableSpaceAge
}

if ($isReducedLegacyLine) {
  $reducedLineLabel = "Factorio $($repoInfo.factorio_version)"
  Write-Host "[info] $reducedLineLabel reduced runtime gate skips 2.x recipe-productivity and DLC scenarios."

  $directEffectFixtureNames = @()
  if ($isFactorio017Line -or $isFactorio018Line -or $isFactorio10Line -or $isFactorio11Line) {
    $directEffectFixtureNames += "mir-fixture-assert-legacy-effect-icons"
  }
  Invoke-RuntimeScenario -ScenarioName "factorio-$($repoInfo.factorio_version)-direct-effects" -EnabledFixtureNames $directEffectFixtureNames
  foreach ($stream in @(
    "research_cannon_shooting_speed",
    "research_character_crafting_speed",
    "research_character_mining_speed",
    "research_character_reach",
    "research_character_walking_speed",
    "research_electric_shooting_speed",
    "research_flamethrower_shooting_speed",
    "research_inventory_capacity",
    "research_lab_productivity",
    "research_robot_battery",
    "research_rocket_shooting_speed"
  )) {
    $line = Get-LastStreamReportLine -Key $stream
    Assert-ReportLineGenerated -Line $line -Context "$reducedLineLabel direct-effect stream $stream"
  }
  Assert-NoStreamReportLine -Key "research_science_pack_productivity" -Context "$reducedLineLabel recipe-productivity cut"
  Assert-NoStreamReportLine -Key "research_gears" -Context "$reducedLineLabel recipe-productivity cut"
  Assert-DefaultBaseExtensionDiagnostics -Context "$reducedLineLabel base-extension scenario"

  Invoke-RuntimeScenario -ScenarioName "lab-productivity-owner-skip" -EnabledFixtureNames @(
    "mir-fixture-lab-productivity-owner",
    "mir-fixture-assert-lab-productivity-owner-skip"
  )
  $labProductivityOwnerSkipLine = Get-LastStreamReportLine -Key "research_lab_productivity"
  if ($labProductivityOwnerSkipLine -notmatch "status=skipped" -or $labProductivityOwnerSkipLine -notmatch "existing technology effect laboratory-productivity-4 laboratory-productivity") {
    throw "MIR research productivity should skip when laboratory-productivity-4 has the expected native effect: $labProductivityOwnerSkipLine"
  }

  Invoke-RuntimeScenario -ScenarioName "better-bot-battery-owner-skip" -EnabledFixtureNames @(
    "mir-fixture-better-bot-battery-owner",
    "mir-fixture-assert-better-bot-battery-skip"
  )
  $betterBotBatterySkipLine = Get-LastStreamReportLine -Key "research_robot_battery"
  if ($betterBotBatterySkipLine -notmatch "status=skipped" -or $betterBotBatterySkipLine -notmatch "existing technology effect worker-robots-battery-6 worker-robot-battery") {
    throw "MIR robot battery should skip when worker-robots-battery-6 has the expected native effect: $betterBotBatterySkipLine"
  }

  Invoke-RuntimeScenario -ScenarioName "character-inventory-merged-effects" -EnabledFixtureNames @()
  $inventoryCapacityLine = Get-LastStreamReportLine -Key "research_inventory_capacity"
  Assert-ReportLineGenerated -Line $inventoryCapacityLine -Context "$reducedLineLabel merged character inventory/trash slot scenario"
  Assert-ReportLineContains -Line $inventoryCapacityLine -Expected "effects=2" -Context "$reducedLineLabel merged character inventory/trash slot scenario"
  Assert-NoStreamReportLine -Key "research_character_trash_slots" -Context "$reducedLineLabel merged character inventory/trash slot scenario"

  Invoke-RuntimeScenario -ScenarioName "reduced-settings-surface" -EnabledFixtureNames @(
    "mir-fixture-assert-reduced-settings-surface"
  )

  Invoke-RuntimeScenario -ScenarioName "checkbox-enabled-default-off-features" -EnabledFixtureNames @() `
    -EnabledBaseExtensionKeys @("inserter-capacity-bonus")
  $checkboxEnabledInserterLine = Get-LastExtensionReportLine -Key "inserter-capacity-bonus"
  Assert-ReportLineGenerated -Line $checkboxEnabledInserterLine -Context "$reducedLineLabel checkbox-enabled base extension scenario"

  Invoke-RuntimeScenario -ScenarioName "checkbox-disabled-default-on-features" -EnabledFixtureNames @() `
    -DisabledStreamKeys @("research_character_reach") `
    -DisabledBaseExtensionKeys @("research-speed")
  $checkboxDisabledReachLine = Get-LastStreamReportLine -Key "research_character_reach"
  if ($checkboxDisabledReachLine -notmatch "status=skipped" -or $checkboxDisabledReachLine -notmatch "disabled") {
    throw "Disabled direct-effect stream checkbox should skip generated research: $checkboxDisabledReachLine"
  }
  $checkboxDisabledResearchSpeedLine = Get-LastExtensionReportLine -Key "research-speed"
  if ($checkboxDisabledResearchSpeedLine -notmatch "status=skipped" -or $checkboxDisabledResearchSpeedLine -notmatch "disabled") {
    throw "Disabled base extension checkbox should skip generated continuation: $checkboxDisabledResearchSpeedLine"
  }

  Invoke-WeaponSpeedPolicyMatrix -Context "$reducedLineLabel weapon shooting speed policy"

  Complete-MIRValidationRun
  Remove-MIRGeneratedValidationUserData

  Write-Host "[ok] Validation completed."
  $global:LASTEXITCODE = 0
  $validationCampaignCompleted = $true
  return
}
