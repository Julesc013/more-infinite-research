if ($StartAtScenario -ne "space-age-vanilla-family-mixed-owner") {
  $nativeOwnerRuntimeCases = @(
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
    "space-age-native-owner-settings-unrecognized-override"
  )
  foreach ($scenarioName in $nativeOwnerRuntimeCases) {
    $declaration = Resolve-MIRScenarioDeclaration -Registry $scenarioRegistry -ScenarioName $scenarioName -Kind "runtime" -EnableSpaceAge
    $parameters = @{
      ScenarioName = $declaration.name
      EnabledFixtureNames = @($declaration.fixtures)
      EnableSpaceAge = $true
    }
    foreach ($property in $declaration.settings.PSObject.Properties) {
      $parameters[$property.Name] = $property.Value
    }
    Invoke-RuntimeScenario @parameters
  }

  Invoke-RuntimeConfigurationChangeScenario `
    -ScenarioName "space-age-native-owner-settings-config-change" `
    -InitialFixtureNames @(
      "mir-fixture-native-owner-settings-source",
      "mir-fixture-assert-native-owner-settings",
      "mir-fixture-assert-native-owner-progress"
    ) `
    -ChangedFixtureNames @(
      "mir-fixture-native-owner-settings-source",
      "mir-fixture-assert-native-owner-settings",
      "mir-fixture-assert-native-owner-progress"
    ) `
    -InitialNativeOwnerSettingsProfile "default" `
    -ChangedNativeOwnerSettingsProfile "combined" `
    -EnableSpaceAge
  Assert-LogContains -Expected "Preserved technology effects without a force-wide reset for productivity family adoption signature change" -Context "space-age-native-owner-settings-config-change"
  Assert-LogContains -Expected "Retained Factorio-normalized current research progress for native owner low-density-structure-productivity" -Context "space-age-native-owner-settings-config-change"
  Assert-LogContains -Expected "[mir-fixture] native-owner force-state preservation proof complete" -Context "space-age-native-owner-settings-config-change"
  Assert-LogContains -Expected "[mir-fixture] native-owner progress configuration-change proof complete" -Context "space-age-native-owner-settings-config-change"
  Assert-LogContains -Expected "[mir-fixture] research-cost transition matrix proof complete phase=configuration-changed rows=16" -Context "space-age-native-owner-settings-config-change"
  Assert-NativeOwnerResearchWorkPreserved -Context "space-age-native-owner-settings-config-change"
  Assert-LogContains -Expected "schema=4|stream=research_rocket_fuel|owner=rocket-fuel-productivity|operation=configure_native_owner|configured=cost_model,effect_per_level,max_level,research_time|effects=0|input-cost=" -Context "space-age-native-owner-settings-config-change"
  Assert-LogContains -Expected "schema=4|stream=research_steel|owner=steel-plate-productivity|operation=configure_native_owner|configured=cost_model,effect_per_level,max_level,research_time|effects=0|input-cost=" -Context "space-age-native-owner-settings-config-change"

  Invoke-RuntimeConfigurationChangeScenario `
    -ScenarioName "space-age-native-owner-cap-lowering-config-change" `
    -InitialFixtureNames @("mir-fixture-assert-native-owner-cap-transition") `
    -ChangedFixtureNames @("mir-fixture-assert-native-owner-cap-transition") `
    -InitialNativeOwnerSettingsProfile "default" `
    -ChangedNativeOwnerSettingsProfile "max-level" `
    -EnableSpaceAge
  Assert-LogContains `
    -Expected "[mir-fixture] native-owner lowered cap retained completed levels and removed invalid current/queued research" `
    -Context "space-age-native-owner-cap-lowering-config-change"

  Invoke-RuntimeConfigurationChangeScenario `
    -ScenarioName "space-age-native-owner-cap-raising-config-change" `
    -InitialFixtureNames @("mir-fixture-assert-native-owner-cap-relaxation") `
    -ChangedFixtureNames @("mir-fixture-assert-native-owner-cap-relaxation") `
    -InitialStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 5 } `
    -ChangedStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 7 } `
    -EnableSpaceAge
  Assert-LogContains `
    -Expected "[mir-fixture] native-owner relaxed cap retained valid progress and restored future levels changed=7" `
    -Context "space-age-native-owner-cap-raising-config-change"

  Invoke-RuntimeConfigurationChangeScenario `
    -ScenarioName "space-age-native-owner-cap-removal-config-change" `
    -InitialFixtureNames @("mir-fixture-assert-native-owner-cap-relaxation") `
    -ChangedFixtureNames @("mir-fixture-assert-native-owner-cap-relaxation") `
    -InitialStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 5 } `
    -ChangedStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 0 } `
    -EnableSpaceAge
  Assert-LogContains `
    -Expected "[mir-fixture] native-owner relaxed cap retained valid progress and restored future levels changed=0" `
    -Context "space-age-native-owner-cap-removal-config-change"
}
