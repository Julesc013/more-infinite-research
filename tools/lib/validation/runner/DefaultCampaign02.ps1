Invoke-RuntimeScenario -ScenarioName "space-age-galore-effect-ownership" -EnabledFixtureNames @(
  "mir-fixture-space-age-galore-overlap"
) -EnableSpaceAge

Invoke-RuntimeScenario -ScenarioName "semantic-family-attach" -EnabledFixtureNames @(
  "mir-fixture-semantic-family-attach",
  "mir-fixture-assert-semantic-family-attach"
)
$semanticFamilyLine = Get-LastStreamReportLine -Key "research_belts"
Assert-ReportLineGenerated -Line $semanticFamilyLine -Context "Semantic family attach scenario"
$semanticLoaderDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "assemble-alpha" -Expected "family=loader-manufacturing"
Assert-ReportLineContains -Line $semanticLoaderDecision -Expected "decision=attach" -Context "Semantic loader attachment decision"
$semanticLabDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "assemble-zeta" -Expected "family=lab-manufacturing"
Assert-ReportLineContains -Line $semanticLabDecision -Expected "decision=attach" -Context "Semantic lab gated-family decision"

Invoke-RuntimeScenario -ScenarioName "semantic-family-generate" -EnabledFixtureNames @(
  "mir-fixture-semantic-family-attach",
  "mir-fixture-assert-semantic-family-generate"
)
$semanticAssemblerFamilyLine = Get-LastStreamReportLine -Key "research_auto_assembling_machine"
Assert-ReportLineGenerated -Line $semanticAssemblerFamilyLine -Context "Semantic assembling-machine family generation"
$semanticLabFamilyLine = Get-LastStreamReportLine -Key "research_auto_lab"
Assert-ReportLineGenerated -Line $semanticLabFamilyLine -Context "Semantic lab family generation"

Invoke-RuntimeScenario -ScenarioName "semantic-family-off" -EnabledFixtureNames @(
  "mir-fixture-semantic-family-attach",
  "mir-fixture-assert-semantic-family-off"
)

Invoke-RuntimeScenario -ScenarioName "semantic-family-report" -EnabledFixtureNames @(
  "mir-fixture-semantic-family-attach",
  "mir-fixture-assert-semantic-family-report"
)

Invoke-RuntimeScenario -ScenarioName "semantic-family-exact-pack" -EnabledFixtureNames @(
  "mir-fixture-semantic-family-attach",
  "mir-fixture-assert-semantic-family-exact-pack"
)

Invoke-RuntimeScenario -ScenarioName "atan-nuclear-science-productivity" -EnabledFixtureNames @(
  "mir-fixture-atan-nuclear-science",
  "mir-fixture-assert-hidden-setting-readability",
  "mir-fixture-assert-atan-nuclear-science-productivity"
)
$atanNuclearScienceLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineGenerated -Line $atanNuclearScienceLine -Context "ATAN Nuclear Science science-pack productivity scenario"
Assert-ReportLineContains -Line $atanNuclearScienceLine -Expected "nuclear-science-pack" -Context "ATAN Nuclear Science lab-input science scenario"
Assert-ReportLineContains -Line $atanNuclearScienceLine -Expected "atan-nuclear-science" -Context "ATAN Nuclear Science unlock prerequisite scenario"

Invoke-RuntimeScenario -ScenarioName "atan-ash-separation" -EnabledFixtureNames @(
  "mir-fixture-atan-ash",
  "mir-fixture-assert-hidden-setting-readability",
  "mir-fixture-assert-atan-ash-separation"
)
$atanAshLine = Get-LastStreamReportLine -Key "research_ash_separation"
Assert-ReportLineGenerated -Line $atanAshLine -Context "ATAN Ash separation productivity scenario"
Assert-ReportLineContains -Line $atanAshLine -Expected "effects=1" -Context "ATAN Ash separation effect count scenario"
Assert-ReportLineContains -Line $atanAshLine -Expected "atan-ash-processing" -Context "ATAN Ash unlock prerequisite scenario"
Assert-NoDiagnosticReportLineContaining -Kind "stream" -Key "research_landfill" -Unexpected "atan-landfill-from-ash" -Context "ATAN Ash landfill sink exclusion scenario"
Assert-NoDiagnosticReportLineContaining -Kind "stream" -Key "research_concrete" -Unexpected "atan-stone-brick-from-ash" -Context "ATAN Ash brick sink exclusion scenario"
$atanAshPlanLine = Get-LastCompatibilityPlanLine -Key "research_ash_separation"
Assert-ReportLineContains -Line $atanAshPlanLine -Expected "reason=atan_ash_policy_summary" -Context "ATAN Ash policy summary scenario"
Assert-ReportLineContains -Line $atanAshPlanLine -Expected "generated=1" -Context "ATAN Ash generated target count scenario"
Assert-ReportLineContains -Line $atanAshPlanLine -Expected "rejected=4" -Context "ATAN Ash rejected sink count scenario"
$atanAshAllowedDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-ash-seperation" -Expected "stable_stream_id=mir-prod-atan-ash-separation"
Assert-ReportLineContains -Line $atanAshAllowedDecision -Expected "decision=generate_stream" -Context "ATAN Ash allowed decision scenario"
$atanAshTileDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-landfill-from-ash" -Expected "risks=tile_surface"
Assert-ReportLineContains -Line $atanAshTileDecision -Expected "decision=diagnose_only" -Context "ATAN Ash tile-surface deny decision scenario"
$atanAshSinkDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-stone-brick-from-ash" -Expected "risks=ash_sink"
Assert-ReportLineContains -Line $atanAshSinkDecision -Expected "decision=diagnose_only" -Context "ATAN Ash sink deny decision scenario"
$atanAshTileRisk = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "atan-landfill-from-ash" -Expected "risks=tile_surface"
Assert-ReportLineContains -Line $atanAshTileRisk -Expected "risks=tile_surface" -Context "ATAN Ash tile-surface loop-risk scenario"
$atanAshSinkRisk = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "atan-stone-brick-from-ash" -Expected "risks=ash_sink"
Assert-ReportLineContains -Line $atanAshSinkRisk -Expected "risks=ash_sink" -Context "ATAN Ash sink loop-risk scenario"

Invoke-RuntimeScenario -ScenarioName "combination-atan-ash-big-mining-drill" -EnabledFixtureNames @(
  "mir-fixture-atan-ash",
  "mir-fixture-assert-hidden-setting-readability",
  "mir-fixture-assert-atan-ash-separation",
  "mir-fixture-big-mining-drill",
  "mir-fixture-assert-big-mining-drill-productivity"
)
$combinationAtanAshLine = Get-LastStreamReportLine -Key "research_ash_separation"
Assert-ReportLineGenerated -Line $combinationAtanAshLine -Context "Independent ATAN Ash plus Big Mining Drill composition"
$combinationBigDrillLine = Get-LastStreamReportLine -Key "research_mining_drill"
Assert-ReportLineGenerated -Line $combinationBigDrillLine -Context "Independent Big Mining Drill plus ATAN Ash composition"

Invoke-RuntimeScenario -ScenarioName "combination-space-age-big-mining-drill" -EnabledFixtureNames @(
  "mir-fixture-big-mining-drill",
  "mir-fixture-assert-big-mining-drill-productivity"
) -EnableSpaceAge
$combinationSpaceAgeDrillLine = Get-LastStreamReportLine -Key "research_mining_drill"
Assert-ReportLineGenerated -Line $combinationSpaceAgeDrillLine -Context "Space Age plus Big Mining Drill targeted interaction"

Invoke-RuntimeScenario -ScenarioName "air-scrubbing-clean-filter" -EnabledFixtureNames @(
  "mir-fixture-air-scrubbing",
  "mir-fixture-assert-hidden-setting-readability",
  "mir-fixture-assert-air-scrubbing-clean-filter"
)
$airScrubbingLine = Get-LastStreamReportLine -Key "research_air_scrubbing_clean_filter"
Assert-ReportLineGenerated -Line $airScrubbingLine -Context "Air Scrubbing clean-filter productivity scenario"
Assert-ReportLineContains -Line $airScrubbingLine -Expected "effects=2" -Context "Air Scrubbing clean-filter effect count scenario"
Assert-ReportLineContains -Line $airScrubbingLine -Expected "atan-pollution-scrubbing" -Context "Air Scrubbing pollution unlock prerequisite scenario"
Assert-ReportLineContains -Line $airScrubbingLine -Expected "atan-spore-scrubbing" -Context "Air Scrubbing spore unlock prerequisite scenario"
$airScrubbingPlanLine = Get-LastCompatibilityPlanLine -Key "research_air_scrubbing_clean_filter"
Assert-ReportLineContains -Line $airScrubbingPlanLine -Expected "reason=air_scrubbing_policy_summary" -Context "Air Scrubbing policy summary scenario"
Assert-ReportLineContains -Line $airScrubbingPlanLine -Expected "generated=2" -Context "Air Scrubbing generated target count scenario"
Assert-ReportLineContains -Line $airScrubbingPlanLine -Expected "rejected=4" -Context "Air Scrubbing rejected target count scenario"
Assert-ReportLineContains -Line $airScrubbingPlanLine -Expected "unknown=1" -Context "Air Scrubbing unknown target count scenario"
$airScrubbingAllowedDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-pollution-filter" -Expected "stable_stream_id=mir-prod-air-scrubbing-clean-filter"
Assert-ReportLineContains -Line $airScrubbingAllowedDecision -Expected "decision=generate_stream" -Context "Air Scrubbing allowed decision scenario"
Assert-ReportLineContains -Line $airScrubbingAllowedDecision -Expected "stable_stream_id=mir-prod-air-scrubbing-clean-filter" -Context "Air Scrubbing stable stream ID scenario"
$airScrubbingScrubDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-pollution-scrubbing" -Expected "risks=scrubbing_environmental"
Assert-ReportLineContains -Line $airScrubbingScrubDecision -Expected "decision=diagnose_only" -Context "Air Scrubbing scrubbing deny decision scenario"
Assert-ReportLineContains -Line $airScrubbingScrubDecision -Expected "risks=scrubbing_environmental" -Context "Air Scrubbing scrubbing risk scenario"
$airScrubbingScrubRisk = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "atan-pollution-scrubbing" -Expected "risks=scrubbing_environmental"
Assert-ReportLineContains -Line $airScrubbingScrubRisk -Expected "risks=scrubbing_environmental" -Context "Air Scrubbing scrubbing loop-risk scenario"
$airScrubbingCleaningDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-pollution-filter-cleaning" -Expected "risks=cleaning_recovery"
Assert-ReportLineContains -Line $airScrubbingCleaningDecision -Expected "decision=diagnose_only" -Context "Air Scrubbing cleaning deny decision scenario"
Assert-ReportLineContains -Line $airScrubbingCleaningDecision -Expected "risks=cleaning_recovery" -Context "Air Scrubbing cleaning risk scenario"
$airScrubbingCleaningRisk = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "atan-pollution-filter-cleaning" -Expected "risks=cleaning_recovery"
Assert-ReportLineContains -Line $airScrubbingCleaningRisk -Expected "risks=cleaning_recovery" -Context "Air Scrubbing cleaning loop-risk scenario"
$airScrubbingUnknownDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-filter-resin" -Expected "decision=observe_unknown"
Assert-ReportLineContains -Line $airScrubbingUnknownDecision -Expected "decision=observe_unknown" -Context "Air Scrubbing unknown related decision scenario"

Invoke-RuntimeScenario -ScenarioName "pipeline-extent-multiplier" -EnabledFixtureNames @(
  "mir-fixture-assert-pipeline-extent"
) -PipelineExtentMultiplier 10
Assert-LogContains -Expected "Applied pipeline extent multiplier 10" -Context "Pipeline extent multiplier scenario"

Invoke-RuntimeScenario -ScenarioName "pipeline-extent-multiplier-50" -EnabledFixtureNames @(
  "mir-fixture-assert-pipeline-extent"
) -PipelineExtentMultiplier 0.5
Assert-LogContains -Expected "Applied pipeline extent multiplier 0.5" -Context "Pipeline extent multiplier 50 percent scenario"

Invoke-RuntimeScenario -ScenarioName "prototype-limit-overrides-base" -EnabledFixtureNames @(
  "mir-fixture-assert-prototype-limits"
) `
  -PrototypeProductivityCap "percent-750" `
  -PrototypeEfficiencyCap "saving-25" `
  -PrototypePollutionCap "saving-25" `
  -PrototypeSpeedFloor "saving-25" `
  -PrototypeSpeedCap "bonus-25000" `
  -PrototypeQualityCap "bonus-25" `
  -RecyclingReturnChance "percent-0-1" `
  -PrototypePositivePowerFloor
Assert-LogContains -Expected "Applied prototype limits: productivity_recipes=" -Context "Base prototype limit override scenario"

Invoke-RuntimeScenario -ScenarioName "prototype-limit-overrides-space-age" -EnabledFixtureNames @(
  "mir-fixture-assert-prototype-limits"
) `
  -PrototypeProductivityCap "percent-25000" `
  -PrototypeEfficiencyCap "saving-99" `
  -PrototypePollutionCap "saving-99" `
  -PrototypeSpeedFloor "saving-9999" `
  -PrototypeSpeedCap "bonus-2500" `
  -PrototypeQualityCap "bonus-2500" `
  -RecyclingReturnChance "match-productivity-cap" `
  -EnableSpaceAge
Assert-LogContains -Expected "Applied prototype limits: productivity_recipes=" -Context "Space Age prototype limit override scenario"

Invoke-RuntimeScenario -ScenarioName "prototype-limit-self-recycling-and-unrestricted-modules" -EnabledFixtureNames @(
  "mir-fixture-assert-prototype-limits"
) `
  -PrototypeProductivityCap "percent-1000" `
  -RecyclingReturnChance "percent-10" `
  -ProductivityCapSelfRecyclingOnly `
  -UnrestrictedModules
Assert-LogContains -Expected "Productivity cap self-recycling scope: approved=" -Context "Self-recycling productivity cap scope scenario"
Assert-LogContains -Expected "Unrestricted module permissions enabled:" -Context "Unrestricted module permission scenario"

Invoke-RuntimeScenario -ScenarioName "prototype-limit-scope-inert-at-fixed-threshold" -EnabledFixtureNames @(
  "mir-fixture-assert-prototype-limits"
) `
  -PrototypeProductivityCap "percent-400" `
  -RecyclingReturnChance "percent-20" `
  -ProductivityCapSelfRecyclingOnly

Invoke-RuntimeScenario -ScenarioName "prototype-limit-scope-engine-unchanged-baseline" -EnabledFixtureNames @(
  "mir-fixture-assert-prototype-limits"
) `
  -PrototypeProductivityCap "percent-500" `
  -ProductivityCapSelfRecyclingOnly
Assert-LogContains -Expected "inverse_threshold=3" -Context "Engine-unchanged recycler threshold scenario"

Invoke-RuntimeScenario -ScenarioName "prototype-limit-scope-inert-at-matched-threshold" -EnabledFixtureNames @(
  "mir-fixture-assert-prototype-limits"
) `
  -PrototypeProductivityCap "percent-25000" `
  -RecyclingReturnChance "match-productivity-cap" `
  -ProductivityCapSelfRecyclingOnly

Invoke-RuntimeScenario -ScenarioName "effect-scaling-mixed-tier" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity"
) -EffectPerLevelOverrides @{
  research_furnace = 40
}
Assert-BaseCoreProductivityStreamsGenerated -Context "Mixed-tier effect scaling scenario"

Invoke-RuntimeScenario -ScenarioName "settings-profile-roundtrip" -EnabledFixtureNames @(
  "mir-fixture-assert-settings-profile-roundtrip"
)

Invoke-RuntimeScenario -ScenarioName "base-generation-integrity-inserter-enabled" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity"
) -EnabledBaseExtensionKeys @(
  "inserter-capacity-bonus"
)
Assert-BaseCoreProductivityStreamsGenerated -Context "Base generation integrity with inserter enabled scenario"
Assert-DefaultBaseExtensionDiagnostics -Context "Base generation integrity with inserter enabled scenario"

Invoke-RuntimeScenario -ScenarioName "base-installed-space-age-icon-assets" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity"
) -UseInstalledSpaceAgeIcons
Assert-BaseCoreProductivityStreamsGenerated -Context "Base installed Space Age icon asset scenario"
$baseInstalledElectricIconLine = Get-LastStreamReportLine -Key "research_electric_shooting_speed"
Assert-ReportLineGenerated -Line $baseInstalledElectricIconLine -Context "Base installed Space Age electric icon scenario"
Assert-ReportLineContains -Line $baseInstalledElectricIconLine -Expected "icon=__space-age__/graphics/technology/electric-weapons-damage.png" -Context "Base installed Space Age electric icon scenario"
$baseInstalledScienceIconLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineGenerated -Line $baseInstalledScienceIconLine -Context "Base installed Space Age science productivity icon scenario"
Assert-ReportLineContains -Line $baseInstalledScienceIconLine -Expected "icon=__space-age__/graphics/technology/research-productivity.png" -Context "Base installed Space Age science productivity icon scenario"
$baseInstalledRailsIconLine = Get-LastStreamReportLine -Key "research_rails"
Assert-ReportLineGenerated -Line $baseInstalledRailsIconLine -Context "Base installed official DLC rail productivity icon scenario"
Assert-ReportLineContains -Line $baseInstalledRailsIconLine -Expected "icon=__elevated-rails__/graphics/technology/elevated-rail.png" -Context "Base installed official DLC rail productivity icon scenario"

Invoke-RuntimeScenario -ScenarioName "checkbox-enabled-default-off-features" -EnabledFixtureNames @() `
  -EnabledBaseExtensionKeys @("inserter-capacity-bonus")
$checkboxEnabledInserterLine = Get-LastExtensionReportLine -Key "inserter-capacity-bonus"
Assert-ReportLineGenerated -Line $checkboxEnabledInserterLine -Context "Checkbox-enabled base extension scenario"

Invoke-RuntimeScenario -ScenarioName "checkbox-disabled-default-on-features" -EnabledFixtureNames @() `
  -DisabledStreamKeys @("research_gears", "research_character_reach") `
  -DisabledBaseExtensionKeys @("research-speed")
$checkboxDisabledGearsLine = Get-LastStreamReportLine -Key "research_gears"
if ($checkboxDisabledGearsLine -notmatch "status=skipped" -or $checkboxDisabledGearsLine -notmatch "disabled") {
  throw "Disabled stream checkbox should skip generated research: $checkboxDisabledGearsLine"
}
$checkboxDisabledReachLine = Get-LastStreamReportLine -Key "research_character_reach"
if ($checkboxDisabledReachLine -notmatch "status=skipped" -or $checkboxDisabledReachLine -notmatch "disabled") {
  throw "Disabled promoted special stream checkbox should skip generated research: $checkboxDisabledReachLine"
}
$checkboxDisabledResearchSpeedLine = Get-LastExtensionReportLine -Key "research-speed"
if ($checkboxDisabledResearchSpeedLine -notmatch "status=skipped" -or $checkboxDisabledResearchSpeedLine -notmatch "disabled") {
  throw "Disabled base extension checkbox should skip generated continuation: $checkboxDisabledResearchSpeedLine"
}

Invoke-RuntimeScenario -ScenarioName "base-space-promethium-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space-and-promethium"
$baseSpacePromethiumPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $baseSpacePromethiumPackLine -Context "Base space and promethium science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $baseSpacePromethiumPackLine -Expected "space-science-pack" -Context "Base space and promethium science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $baseSpacePromethiumPackLine -Unexpected "promethium-science-pack" -Context "Base space and promethium science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-space-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space" -EnableSpaceAge
$spaceAgeSpacePackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spaceAgeSpacePackLine -Context "Space Age space-only science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spaceAgeSpacePackLine -Expected "space-science-pack" -Context "Space Age space-only science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $spaceAgeSpacePackLine -Unexpected "promethium-science-pack" -Context "Space Age space-only science-pack ingredient policy scenario"
$spaceAgeElectricShootingLine = Get-LastStreamReportLine -Key "research_electric_shooting_speed"
Assert-ReportLineGenerated -Line $spaceAgeElectricShootingLine -Context "Space Age electric and Tesla shooting speed scenario"
Assert-ReportLineContains -Line $spaceAgeElectricShootingLine -Expected "effects=2" -Context "Space Age electric and Tesla shooting speed scenario"
Assert-ReportLineContains -Line $spaceAgeElectricShootingLine -Expected "icon=tech:electric-weapons-damage-1" -Context "Space Age electric and Tesla shooting speed icon scenario"
$spaceAgeLabProductivityLine = Get-LastStreamReportLine -Key "research_lab_productivity"
if ($spaceAgeLabProductivityLine -notmatch "status=skipped" -or $spaceAgeLabProductivityLine -notmatch "existing technology effect research-productivity laboratory-productivity") {
  throw "Space Age should skip MIR research productivity because vanilla research-productivity already exists: $spaceAgeLabProductivityLine"
}

Invoke-RuntimeScenario -ScenarioName "space-age-progression-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space-age-progression" -EnableSpaceAge
$spaceAgeProgressionGearsLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spaceAgeProgressionGearsLine -Context "Space Age progression science-pack ingredient policy base stream scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeProgressionGearsLine -Unexpected "space-science-pack" -Context "Space Age progression science-pack ingredient policy base stream scenario"
$spaceAgeProgressionOilLine = Get-LastStreamReportLine -Key "research_oil_processing_productivity"
Assert-ReportLineGenerated -Line $spaceAgeProgressionOilLine -Context "Space Age progression science-pack ingredient policy planet stream scenario"
Assert-ReportScienceContains -Line $spaceAgeProgressionOilLine -Expected "cryogenic-science-pack" -Context "Space Age progression science-pack ingredient policy planet stream scenario"
Assert-ReportScienceContains -Line $spaceAgeProgressionOilLine -Expected "space-science-pack" -Context "Space Age progression science-pack ingredient policy planet stream scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeProgressionOilLine -Unexpected "promethium-science-pack" -Context "Space Age progression science-pack ingredient policy planet stream scenario"

Invoke-RuntimeScenario -ScenarioName "official-progression-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "official-progression" -EnableSpaceAge
$officialProgressionOilLine = Get-LastStreamReportLine -Key "research_oil_processing_productivity"
Assert-ReportLineGenerated -Line $officialProgressionOilLine -Context "Official progression science-pack ingredient policy scenario"
Assert-ReportScienceContains -Line $officialProgressionOilLine -Expected "utility-science-pack" -Context "Official progression science-pack ingredient policy scenario"
Assert-ReportScienceContains -Line $officialProgressionOilLine -Expected "space-science-pack" -Context "Official progression science-pack ingredient policy scenario"
Assert-ReportScienceContains -Line $officialProgressionOilLine -Expected "cryogenic-science-pack" -Context "Official progression science-pack ingredient policy scenario"
Assert-ReportScienceDoesNotContain -Line $officialProgressionOilLine -Unexpected "agricultural-science-pack" -Context "Official progression science-pack ingredient policy should not add unrelated planet packs"

Invoke-RuntimeScenario -ScenarioName "mod-progression-pack-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack"
) -SciencePackIngredientPolicy "mod-progression"
$modProgressionGearsLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $modProgressionGearsLine -Context "Mod progression science-pack ingredient policy base stream scenario"
Assert-ReportScienceDoesNotContain -Line $modProgressionGearsLine -Unexpected "mir-fixture-science-pack" -Context "Mod progression science-pack ingredient policy base stream scenario"
$modProgressionScienceLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineGenerated -Line $modProgressionScienceLine -Context "Mod progression science-pack ingredient policy selected mod pack scenario"
Assert-ReportScienceContains -Line $modProgressionScienceLine -Expected "mir-fixture-science-pack" -Context "Mod progression science-pack ingredient policy selected mod pack scenario"

