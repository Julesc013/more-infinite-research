if ([bool]$targetProfile.features.scripted_techs -and [bool]$targetProfile.supports_space_age) {
  Invoke-RuntimeScenario -ScenarioName "base-scripted-candidates-enabled" -EnabledFixtureNames @() -EnabledStreamKeys @(
    "research_spoilage_preservation",
    "research_agricultural_growth_speed"
  )
  foreach ($scriptedStream in @("research_spoilage_preservation", "research_agricultural_growth_speed")) {
    $baseScriptedLine = Get-LastStreamReportLine -Key $scriptedStream
    if ($baseScriptedLine -notmatch "status=skipped" -or $baseScriptedLine -notmatch "missing required mod space-age") {
      throw "Base-only scripted candidate stream $scriptedStream should skip for missing Space Age when force-enabled: $baseScriptedLine"
    }
  }

  Invoke-RuntimeScenario -ScenarioName "space-age-scripted-candidates-enabled" -EnabledFixtureNames @(
    "mir-fixture-assert-generation-integrity"
  ) -EnabledStreamKeys @(
    "research_spoilage_preservation",
    "research_agricultural_growth_speed"
  ) -EffectPerLevelOverrides @{
    research_spoilage_preservation = 2
    research_agricultural_growth_speed = 2
  } -ScriptedDiagnostics -EnableSpaceAge
  foreach ($scriptedStream in @("research_spoilage_preservation", "research_agricultural_growth_speed")) {
    $spaceAgeScriptedLine = Get-LastStreamReportLine -Key $scriptedStream
    Assert-ReportLineGenerated -Line $spaceAgeScriptedLine -Context "Space Age scripted candidate stream $scriptedStream"
    Assert-ReportLineContains -Line $spaceAgeScriptedLine -Expected "effects=1" -Context "Space Age scripted candidate stream $scriptedStream"
    if ($scriptedStream -eq "research_spoilage_preservation") {
      Assert-ReportScienceContains -Line $spaceAgeScriptedLine -Expected "space-science-pack" -Context "Space Age spoilage preservation science pack scenario"
    }
    if ($scriptedStream -eq "research_agricultural_growth_speed") {
      Assert-ReportScienceContains -Line $spaceAgeScriptedLine -Expected "agricultural-science-pack" -Context "Space Age agricultural growth speed agricultural science scenario"
      Assert-ReportScienceContains -Line $spaceAgeScriptedLine -Expected "electromagnetic-science-pack" -Context "Space Age agricultural growth speed electromagnetic science scenario"
      Assert-ReportScienceContains -Line $spaceAgeScriptedLine -Expected "cryogenic-science-pack" -Context "Space Age agricultural growth speed cryogenic science scenario"
      Assert-ReportLineContains -Line $spaceAgeScriptedLine -Expected "icon=tech:agriculture" -Context "Space Age agricultural growth speed icon scenario"
    }
  }
  Assert-LogContains -Expected "spoilage preservation applied level=0" -Context "Checkbox-enabled scripted spoilage runtime scenario"
  Assert-LogContains -Expected "agricultural growth speed force state refreshed enabled=true" -Context "Checkbox-enabled scripted agricultural runtime scenario"
  Assert-LogContains -Expected "spoilage preservation applied level=0 per_level_multiplier=1.02" -Context "Scripted spoilage effect scaling scenario"
  Assert-LogContains -Expected "agricultural growth speed force state refreshed enabled=true per_level_multiplier=1.02" -Context "Scripted agricultural effect scaling scenario"

  Invoke-RuntimeScenario -ScenarioName "space-age-scripted-candidates-disabled" -EnabledFixtureNames @() `
    -DisabledStreamKeys @("research_spoilage_preservation") `
    -ScriptedDiagnostics `
    -EnableSpaceAge
  $disabledSpoilageLine = Get-LastStreamReportLine -Key "research_spoilage_preservation"
  if ($disabledSpoilageLine -notmatch "status=skipped" -or $disabledSpoilageLine -notmatch "disabled") {
    throw "Explicitly disabled scripted spoilage stream should skip when its checkbox is off: $disabledSpoilageLine"
  }
  $defaultAgriculturalLine = Get-LastStreamReportLine -Key "research_agricultural_growth_speed"
  Assert-ReportLineGenerated -Line $defaultAgriculturalLine -Context "Default-enabled scripted agricultural runtime scenario"
  Assert-LogContains -Expected "spoilage preservation skipped: missing technology" -Context "Data-stage-disabled scripted spoilage runtime scenario"
  Assert-LogContains -Expected "agricultural growth speed force state refreshed enabled=true" -Context "Default-enabled scripted agricultural runtime scenario"

  Invoke-RuntimeConfigurationChangeScenario `
    -ScenarioName "space-age-scripted-runtime-lifecycle" `
    -InitialFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
    -ChangedFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
    -EnabledStreamKeys @("research_spoilage_preservation") `
    -EffectPerLevelOverrides @{ research_spoilage_preservation = 2 } `
    -ScriptedDiagnostics `
    -EnableSpaceAge
  Assert-LogContains `
    -Expected "[mir-fixture] scripted lifecycle retention proof complete" `
    -Context "Scripted runtime save/load retention scenario"

  Invoke-RuntimeConfigurationChangeScenario `
    -ScenarioName "space-age-scripted-runtime-disable-restoration" `
    -InitialFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
    -ChangedFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
    -InitialEnabledStreamKeys @("research_spoilage_preservation") `
    -ChangedDisabledStreamKeys @("research_spoilage_preservation") `
    -EffectPerLevelOverrides @{ research_spoilage_preservation = 2 } `
    -ScriptedDiagnostics `
    -EnableSpaceAge
  Assert-LogContains `
    -Expected "[mir-fixture] scripted lifecycle disable proof complete" `
    -Context "Scripted runtime disable restoration scenario"

  Invoke-RuntimeConfigurationChangeScenario `
    -ScenarioName "space-age-scripted-runtime-reenable" `
    -InitialFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
    -ChangedFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
    -InitialDisabledStreamKeys @("research_spoilage_preservation") `
    -ChangedEnabledStreamKeys @("research_spoilage_preservation") `
    -EffectPerLevelOverrides @{ research_spoilage_preservation = 2 } `
    -ScriptedDiagnostics `
    -EnableSpaceAge
  Assert-LogContains `
    -Expected "[mir-fixture] scripted lifecycle enable proof complete" `
    -Context "Scripted runtime re-enable scenario"
}

Invoke-RuntimeConfigurationChangeScenario `
  -ScenarioName "generated-maximum-level-lowering-config-change" `
  -InitialFixtureNames @("mir-fixture-assert-generated-cap-transition") `
  -ChangedFixtureNames @("mir-fixture-assert-generated-cap-transition") `
  -InitialStartupSettingOverrides @{ "ips-max-level-research_copper" = 0 } `
  -ChangedStartupSettingOverrides @{ "ips-max-level-research_copper" = 5 }
Assert-LogContains `
  -Expected "[mir-fixture] generated lowered cap retained completed levels and removed invalid research" `
  -Context "generated-maximum-level-lowering-config-change"

Invoke-RuntimeConfigurationChangeScenario `
  -ScenarioName "base-continuation-maximum-level-lowering-config-change" `
  -InitialFixtureNames @(
    "mir-fixture-finite-base-extension-level",
    "mir-fixture-assert-base-continuation-cap-transition"
  ) `
  -ChangedFixtureNames @(
    "mir-fixture-finite-base-extension-level",
    "mir-fixture-assert-base-continuation-cap-transition"
  ) `
  -InitialStartupSettingOverrides @{ "mir-max-level-research-speed" = 0 } `
  -ChangedStartupSettingOverrides @{ "mir-max-level-research-speed" = 5 }
Assert-LogContains `
  -Expected "[mir-fixture] base continuation survived a cap below its first level without losing completed research" `
  -Context "base-continuation-maximum-level-lowering-config-change"

Invoke-RuntimeScenario -ScenarioName "space-age-generation-integrity" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity",
  "mir-fixture-assert-hidden-setting-readability"
) -EnableSpaceAge
Assert-SpaceAgeVanillaOwnedProductivityStreamsBound -Context "Space Age generation integrity scenario"
Assert-DefaultBaseExtensionDiagnostics -Context "Space Age generation integrity scenario"
$spaceAgeRailsLine = Get-LastStreamReportLine -Key "research_rails"
Assert-ReportLineContains -Line $spaceAgeRailsLine -Expected "effects=3" -Context "Space Age Elevated Rails productivity scenario"
Assert-ReportLineContains -Line $spaceAgeRailsLine -Expected "icon=tech:elevated-rail" -Context "Space Age Elevated Rails productivity icon scenario"
$spaceAgeLandfillLine = Get-LastStreamReportLine -Key "research_landfill"
Assert-ReportLineContains -Line $spaceAgeLandfillLine -Expected "effects=2" -Context "Space Age landfill productivity scenario"
$spaceAgePlatformLine = Get-LastStreamReportLine -Key "research_platform"
Assert-ReportLineContains -Line $spaceAgePlatformLine -Expected "effects=2" -Context "Space Age platform productivity scenario"
Assert-ReportScienceContains -Line $spaceAgePlatformLine -Expected "space-science-pack" -Context "Space Age platform space science scenario"
Assert-ReportScienceContains -Line $spaceAgePlatformLine -Expected "cryogenic-science-pack" -Context "Space Age platform cryogenic science scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgePlatformLine -Unexpected "metallurgic-science-pack" -Context "Space Age platform metallurgic-to-cryogenic replacement scenario"
$spaceAgeArtificialSoilLine = Get-LastStreamReportLine -Key "research_artificial_soil"
Assert-ReportLineGenerated -Line $spaceAgeArtificialSoilLine -Context "Space Age artificial soil productivity scenario"
Assert-ReportScienceContains -Line $spaceAgeArtificialSoilLine -Expected "agricultural-science-pack" -Context "Space Age artificial soil agricultural science scenario"
Assert-ReportScienceContains -Line $spaceAgeArtificialSoilLine -Expected "space-science-pack" -Context "Space Age artificial soil space science scenario"
$spaceAgeBacteriaCultivationLine = Get-LastStreamReportLine -Key "research_bacteria_cultivation"
Assert-ReportLineGenerated -Line $spaceAgeBacteriaCultivationLine -Context "Space Age bacteria cultivation productivity scenario"
Assert-ReportScienceContains -Line $spaceAgeBacteriaCultivationLine -Expected "agricultural-science-pack" -Context "Space Age bacteria cultivation agricultural science scenario"
Assert-ReportScienceContains -Line $spaceAgeBacteriaCultivationLine -Expected "cryogenic-science-pack" -Context "Space Age bacteria cultivation cryogenic science scenario"
$spaceAgeBreedingLine = Get-LastStreamReportLine -Key "research_breeding"
Assert-ReportLineGenerated -Line $spaceAgeBreedingLine -Context "Space Age breeding productivity scenario"
Assert-ReportScienceContains -Line $spaceAgeBreedingLine -Expected "agricultural-science-pack" -Context "Space Age breeding agricultural science scenario"
Assert-ReportScienceContains -Line $spaceAgeBreedingLine -Expected "cryogenic-science-pack" -Context "Space Age breeding cryogenic science scenario"
$spaceAgeNutrientsLine = Get-LastStreamReportLine -Key "research_nutrients"
Assert-ReportLineGenerated -Line $spaceAgeNutrientsLine -Context "Space Age nutrients productivity scenario"
Assert-ReportLineContains -Line $spaceAgeNutrientsLine -Expected "effects=3" -Context "Space Age exact forward nutrient recipes scenario"
Assert-ReportScienceContains -Line $spaceAgeNutrientsLine -Expected "agricultural-science-pack" -Context "Space Age nutrients agricultural science scenario"
Assert-ReportScienceContains -Line $spaceAgeNutrientsLine -Expected "cryogenic-science-pack" -Context "Space Age nutrients cryogenic science scenario"
$spaceAgeCaptureRocketLine = Get-LastStreamReportLine -Key "research_capture_robot_rockets"
Assert-ReportLineGenerated -Line $spaceAgeCaptureRocketLine -Context "Space Age capture bot rocket productivity scenario"
Assert-ReportLineContains -Line $spaceAgeCaptureRocketLine -Expected "effects=1" -Context "Space Age exact capture bot rocket recipe scenario"
Assert-ReportScienceContains -Line $spaceAgeCaptureRocketLine -Expected "military-science-pack" -Context "Space Age capture bot rocket military science scenario"
Assert-ReportScienceContains -Line $spaceAgeCaptureRocketLine -Expected "agricultural-science-pack" -Context "Space Age capture bot rocket agricultural science scenario"
foreach ($weaponSpeedStream in @("research_rocket_shooting_speed", "research_cannon_shooting_speed")) {
  $weaponSpeedLine = Get-LastStreamReportLine -Key $weaponSpeedStream
  Assert-ReportLineGenerated -Line $weaponSpeedLine -Context "Space Age weapon shooting speed stream $weaponSpeedStream"
  Assert-ReportScienceContains -Line $weaponSpeedLine -Expected "electromagnetic-science-pack" -Context "Space Age weapon shooting speed electromagnetic science scenario $weaponSpeedStream"
  Assert-ReportScienceDoesNotContain -Line $weaponSpeedLine -Unexpected "agricultural-science-pack" -Context "Space Age weapon shooting speed agricultural science replacement scenario $weaponSpeedStream"
}

Invoke-RuntimeScenario -ScenarioName "space-age-plates-n-circuit-productivity-compat" -EnabledFixtureNames @(
  "mir-fixture-plates-n-circuit-productivity",
  "mir-fixture-assert-plates-n-circuit-productivity"
) -EnableSpaceAge

Invoke-RuntimeScenario -ScenarioName "scaled-known-productivity-competitor" -EnabledFixtureNames @(
  "mir-fixture-plates-n-circuit-productivity",
  "mir-fixture-assert-plates-n-circuit-productivity"
) -EffectPerLevelOverrides @{
  research_copper = 20
  research_iron = 20
  research_electronic_circuit = 20
  research_advanced_circuit = 20
} -EnableSpaceAge
foreach ($stream in @("research_copper", "research_iron", "research_electronic_circuit", "research_advanced_circuit")) {
  $line = Get-LastStreamReportLine -Key $stream
  Assert-ReportLineGenerated -Line $line -Context "Plates n Circuit Productivity replacement stream $stream"
}
foreach ($techName in @("basic-plate-productivity", "electric-circuit-productivity", "advanced-circuit-productivity")) {
  Assert-LogContains -Expected "Prepared competing recipe productivity technology for MIR replacement: $techName" -Context "Plates n Circuit Productivity prepare $techName"
  Assert-LogContains -Expected "Replaced competing recipe productivity technology: $techName" -Context "Plates n Circuit Productivity cleanup $techName"
}

Invoke-RuntimeScenario -ScenarioName "space-age-plates-n-circuit-productivity-partial-coverage" -EnabledFixtureNames @(
  "mir-fixture-plates-n-circuit-productivity"
) -DisabledStreamKeys @(
  "research_copper"
) -EnableSpaceAge
$partialIronLine = Get-LastStreamReportLine -Key "research_iron"
Assert-ReportLineGenerated -Line $partialIronLine -Context "Partially covered plate competitor can still allow non-owned iron recipes"
Assert-LogContains -Expected "Skipping recipe productivity effect for research_iron recipe=iron-plate because existing infinite technology already owns it: basic-plate-productivity" -Context "Partial coverage should keep exact iron plate owner"
Assert-LogDoesNotContain -Unexpected "Prepared competing recipe productivity technology for MIR replacement: basic-plate-productivity" -Context "Partial coverage should not prepare combined plate competitor"
Assert-LogDoesNotContain -Unexpected "Replaced competing recipe productivity technology: basic-plate-productivity" -Context "Partial coverage should not remove combined plate competitor"

Invoke-RuntimeScenario -ScenarioName "space-age-plates-n-circuit-productivity-change-mismatch" -EnabledFixtureNames @(
  "mir-fixture-plates-n-circuit-productivity-change-mismatch",
  "mir-fixture-assert-plates-n-circuit-productivity-change-mismatch"
) -EnableSpaceAge
Assert-LogDoesNotContain -Unexpected "Prepared competing recipe productivity technology for MIR replacement: electric-circuit-productivity" -Context "Change-mismatched competitor should not be prepared"
Assert-LogDoesNotContain -Unexpected "Replaced competing recipe productivity technology: electric-circuit-productivity" -Context "Change-mismatched competitor should not be removed"

Invoke-RuntimeScenario -ScenarioName "space-age-plates-n-circuit-productivity-blocked-owner" -EnabledFixtureNames @(
  "mir-fixture-plates-n-circuit-productivity-blocked",
  "mir-fixture-assert-plates-n-circuit-productivity-blocked"
) -EnableSpaceAge
Assert-LogDoesNotContain -Unexpected "Prepared competing recipe productivity technology for MIR replacement: basic-plate-productivity" -Context "Blocked combined competitor should not be prepared"
Assert-LogDoesNotContain -Unexpected "Replaced competing recipe productivity technology: basic-plate-productivity" -Context "Blocked combined competitor should not be removed"

Invoke-RuntimeScenario -ScenarioName "space-age-vanilla-family-adoption" -EnabledFixtureNames @(
  "mir-fixture-vanilla-family-adoption-recipes",
  "mir-fixture-assert-vanilla-family-adoption"
) -EnableSpaceAge
$adoptedFamilyExpectations = @{
  research_rocket_fuel = "owners=rocket-fuel-productivity";
  research_low_density_structure = "owners=low-density-structure-productivity";
  research_plastic = "owners=plastic-bar-productivity";
  research_processing_unit = "owners=processing-unit-productivity";
  research_steel = "owners=steel-plate-productivity"
}
foreach ($entry in $adoptedFamilyExpectations.GetEnumerator()) {
  $line = Get-LastStreamReportLine -Key $entry.Key
  Assert-ReportLineAdopted -Line $line -Context "Space Age vanilla family adoption stream $($entry.Key)"
  Assert-ReportLineContains -Line $line -Expected $entry.Value -Context "Space Age vanilla family adoption owner $($entry.Key)"
}
Assert-LogContains -Expected "recipe=mir-fixture-no-productivity-rocket-fuel because recipe_productivity_not_allowed" -Context "Space Age vanilla family adoption allow_productivity=false scenario"

Invoke-RuntimeConfigurationChangeScenario -ScenarioName "space-age-vanilla-family-adoption-config-change" `
  -ChangedFixtureNames @(
    "mir-fixture-vanilla-family-adoption-recipes"
  ) `
  -EnableSpaceAge
Assert-LogContains -Expected "Preserved technology effects without a force-wide reset for productivity family adoption signature change" -Context "Space Age vanilla family adoption configuration-change preservation scenario"
Assert-LogContains -Expected "schema=4|stream=research_rocket_fuel|owner=rocket-fuel-productivity|operation=adopt_native_owner_effects|configured=|effects=1|input-cost=" -Context "Space Age vanilla family adoption configuration-change signature scenario"
Assert-LogContains -Expected "schema=4|stream=research_steel|owner=steel-plate-productivity|operation=adopt_native_owner_effects|configured=|effects=1|input-cost=" -Context "Space Age steel family adoption configuration-change signature scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-vanilla-family-owner-prepatched" -EnabledFixtureNames @(
  "mir-fixture-vanilla-family-owner-prepatched",
  "mir-fixture-assert-vanilla-family-owner-prepatched"
) -EnableSpaceAge
$prepatchedRocketFuelLine = Get-LastStreamReportLine -Key "research_rocket_fuel"
Assert-ReportLineAdopted -Line $prepatchedRocketFuelLine -Context "Prepatched family owner preserve binding"
Assert-ReportLineContains -Line $prepatchedRocketFuelLine -Expected "reason=preserve_native_owner" -Context "Prepatched family owner preserve binding"

Invoke-RuntimeScenario -ScenarioName "space-age-vanilla-family-exact-owner" -EnabledFixtureNames @(
  "mir-fixture-vanilla-family-exact-owner",
  "mir-fixture-assert-vanilla-family-exact-owner"
) -EnableSpaceAge
$exactOwnerRocketFuelLine = Get-LastStreamReportLine -Key "research_rocket_fuel"
Assert-ReportLineAdopted -Line $exactOwnerRocketFuelLine -Context "External exact owner plus native preserve binding"
Assert-ReportLineContains -Line $exactOwnerRocketFuelLine -Expected "reason=preserve_native_owner" -Context "External exact owner plus native preserve binding"
