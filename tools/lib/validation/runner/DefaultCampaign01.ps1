Invoke-RuntimeScenario -ScenarioName "reduce-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-custom-lab",
  "mir-fixture-late-recipe",
  "mir-fixture-assert-science-pack-productivity"
)

$sciencePackProductivityLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineGenerated -Line $sciencePackProductivityLine -Context "Science pack productivity reduce-policy scenario"
Assert-ReportLineContains -Line $sciencePackProductivityLine -Expected "mir-fixture-science-pack" -Context "Science pack productivity reduce-policy scenario"
Assert-ReportLineContains -Line $sciencePackProductivityLine -Expected "tech:space-science-pack" -Context "Base science pack productivity fallback icon scenario"
$effectCountMatch = [regex]::Match($sciencePackProductivityLine, "effects=(\d+)")
if (-not $effectCountMatch.Success) {
  throw "Science pack productivity diagnostics did not include an effect count: $sciencePackProductivityLine"
}
$sciencePackEffectCount = [int]$effectCountMatch.Groups[1].Value
if ($sciencePackEffectCount -lt 1) {
  throw "Science pack productivity stream did not include any recipe productivity effects: $sciencePackProductivityLine"
}
$baseLabProductivityLine = Get-LastStreamReportLine -Key "research_lab_productivity"
Assert-ReportLineGenerated -Line $baseLabProductivityLine -Context "Base research productivity scenario"
Assert-ReportLineContains -Line $baseLabProductivityLine -Expected "effects=1" -Context "Base research productivity scenario"
Assert-ReportLineContains -Line $baseLabProductivityLine -Expected "icon=tech:military-science-pack" -Context "Base research productivity icon scenario"
$compatibilityPlanLine = Get-LastCompatibilityPlanLine -Key "compatibility_planner"
Assert-ReportLineContains -Line $compatibilityPlanLine -Expected "status=diagnostic" -Context "Base compatibility planner diagnostics scenario"
$compilerPlanLine = Get-LastCompatibilityPlanLine -Key "productivity_compiler"
Assert-ReportLineContains -Line $compilerPlanLine -Expected "reason=fact_registry_summary" -Context "Base compiler planner summary scenario"
$ownerRegistryLine = Get-LastCompatibilityPlanLine -Key "owner_registry"
Assert-ReportLineContains -Line $ownerRegistryLine -Expected "reason=owner_facts_indexed" -Context "Base compiler owner registry scenario"
$factRegistryLine = Get-LastDiagnosticReportLine -Kind "fact_registry" -Key "prototype_index"
Assert-ReportLineContains -Line $factRegistryLine -Expected "status=diagnostic" -Context "Base compiler fact registry scenario"
Assert-ReportLineContains -Line $factRegistryLine -Expected "recipes=" -Context "Base compiler fact registry recipe count scenario"
$labMatrixLine = Get-LastDiagnosticReportLine -Kind "lab_matrix" -Key "lab"
Assert-ReportLineContains -Line $labMatrixLine -Expected "reason=lab_inputs_indexed" -Context "Base compiler lab matrix scenario"
$generatedDecisionLine = Get-LastDiagnosticReportLine -Kind "decision" -Key "recipe-prod-research_lab_productivity-1"
Assert-ReportLineContains -Line $generatedDecisionLine -Expected "decision=generate_stream" -Context "Base compiler generated decision scenario"
Assert-ReportLineContains -Line $generatedDecisionLine -Expected "stable_stream_id=recipe-prod-research_lab_productivity-1" -Context "Base compiler stable ID scenario"
$nativeLabCapabilityLine = Get-DiagnosticReportLineContaining -Kind "decision" -Key "laboratory-productivity" -Expected "capability=native-modifier-ownership"
Assert-ReportLineContains -Line $nativeLabCapabilityLine -Expected "decision=observe_existing_owner" -Context "Native modifier ownership resolver scenario"
$nativeMiningCapabilityLine = Get-DiagnosticReportLineContaining -Kind "decision" -Key "mining-drill-productivity-bonus" -Expected "capability=native-modifier-ownership"
Assert-ReportLineContains -Line $nativeMiningCapabilityLine -Expected "subfamily=native_mining_yield" -Context "Native mining-yield resolver scenario"

Invoke-RuntimeScenario -ScenarioName "recipe-cap-diagnostics" -EnabledFixtureNames @(
  "mir-fixture-recipe-cap-diagnostics"
)
$capPlanLine = Get-LastCompatibilityPlanLine -Key "recipe_productivity_caps"
Assert-ReportLineContains -Line $capPlanLine -Expected "warnings=" -Context "Recipe cap diagnostics summary scenario"
$loweredCapLine = Get-LastRecipeCapReportLine -Recipe "iron-gear-wheel"
Assert-ReportLineContains -Line $loweredCapLine -Expected "cap_state=lowered" -Context "Lowered recipe cap diagnostics scenario"
Assert-ReportLineContains -Line $loweredCapLine -Expected "useful_level_estimate=2" -Context "Lowered recipe cap useful-level diagnostics scenario"
$ruleMutationLine = Get-LastDiagnosticReportLine -Kind "rule_mutation" -Key "iron-gear-wheel"
Assert-ReportLineContains -Line $ruleMutationLine -Expected "field=maximum_productivity" -Context "Recipe cap rule-surface diagnostics scenario"
Assert-ReportLineContains -Line $ruleMutationLine -Expected "observed_value=0.2" -Context "Recipe cap rule-surface value scenario"
$raisedCapLine = Get-LastRecipeCapReportLine -Recipe "iron-plate"
Assert-ReportLineContains -Line $raisedCapLine -Expected "cap_state=raised" -Context "Raised recipe cap diagnostics scenario"
$extremeCapLine = Get-LastRecipeCapReportLine -Recipe "copper-cable"
Assert-ReportLineContains -Line $extremeCapLine -Expected "warning_class=uncapped_or_extreme" -Context "Extreme recipe cap diagnostics scenario"

Invoke-RuntimeScenario -ScenarioName "capability-negative-cases" -EnabledFixtureNames @(
  "mir-fixture-capability-negative-cases",
  "mir-fixture-assert-capability-negative-cases"
)
$selfLoopRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-self-loop-filter-cleaning" -Expected "catalyst_or_self_return"
Assert-ReportLineContains -Line $selfLoopRiskLine -Expected "cleaning_or_recovery_loop" -Context "Negative self-loop cleaning risk scenario"
$barrelRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-barrel-return-loop" -Expected "barrel_or_container_return"
Assert-ReportLineContains -Line $barrelRiskLine -Expected "catalyst_or_self_return" -Context "Negative barrel return risk scenario"
$voidRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-voiding-sink" -Expected "voiding_or_destruction"
Assert-ReportLineContains -Line $voidRiskLine -Expected "voiding_or_destruction" -Context "Negative voiding risk scenario"
$matterRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-matter-transmutation" -Expected "matter_or_transmutation"
Assert-ReportLineContains -Line $matterRiskLine -Expected "matter_or_transmutation" -Context "Negative transmutation risk scenario"
$hiddenRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-hidden-internal-recipe" -Expected "hidden_internal"
Assert-ReportLineContains -Line $hiddenRiskLine -Expected "hidden_internal" -Context "Negative hidden recipe risk scenario"
$zeroCapRuleLine = Get-DiagnosticReportLineContaining -Kind "rule_mutation" -Key "mir-zero-cap-productivity" -Expected "observed_value=0"
Assert-ReportLineContains -Line $zeroCapRuleLine -Expected "field=maximum_productivity" -Context "Negative zero-cap rule-surface scenario"
Assert-NoDiagnosticReportLineContaining -Kind "decision" -Key "mir-loader-like-container" -Unexpected "capability=logistics-loader-manufacturing" -Context "Negative loader-like container capability scenario"
Assert-NoDiagnosticReportLineContaining -Kind "decision" -Key "mir-drill-like-container" -Unexpected "capability=mining-drill-manufacturing" -Context "Negative drill-like container capability scenario"

Invoke-RuntimeScenario -ScenarioName "synthetic-scale-graph" -EnabledFixtureNames @(
  "mir-fixture-synthetic-scale-graph",
  "mir-fixture-assert-synthetic-scale-graph"
)
$orderedScaleFingerprint = $null
if (Test-MIRScenarioSelected -Name "synthetic-scale-graph") {
  $orderedScaleMatch = [regex]::Match(
    (Get-Content -Raw -LiteralPath $FactorioLog),
    '\[mir-fixture\] synthetic-graph fingerprints (coverage=\S+ generation=\S+ compilation=\S+ in_memory=\S+)'
  )
  if (-not $orderedScaleMatch.Success) { throw "Ordered 100000-scale compiler fingerprints are missing." }
  $orderedScaleFingerprint = $orderedScaleMatch.Groups[1].Value
}
$syntheticCoverageLine = Get-DiagnosticReportLineContaining -Kind "coverage" -Key "recipe_accounting" -Expected "recipe_count="
Assert-ReportLineContains -Line $syntheticCoverageLine -Expected "candidate_count=" -Context "Synthetic graph candidate count"
Assert-ReportLineContains -Line $syntheticCoverageLine -Expected "effect_count=" -Context "Synthetic graph effect count"
Assert-ReportLineContains -Line $syntheticCoverageLine -Expected "graph_edge_count=" -Context "Synthetic graph edge count"

Invoke-RuntimeScenario -ScenarioName "synthetic-scale-graph-random-order" -EnabledFixtureNames @(
  "mir-fixture-synthetic-scale-graph",
  "mir-fixture-synthetic-scale-random-order",
  "mir-fixture-assert-synthetic-scale-graph"
)
if ($orderedScaleFingerprint -and (Test-MIRScenarioSelected -Name "synthetic-scale-graph-random-order")) {
  $randomScaleMatch = [regex]::Match(
    (Get-Content -Raw -LiteralPath $FactorioLog),
    '\[mir-fixture\] synthetic-graph fingerprints (coverage=\S+ generation=\S+ compilation=\S+ in_memory=\S+)'
  )
  if (-not $randomScaleMatch.Success) { throw "Randomized 100000-scale compiler fingerprints are missing." }
  if ($randomScaleMatch.Groups[1].Value -ne $orderedScaleFingerprint) {
    throw "Randomized insertion changed 100000-scale compiler output: ordered=$orderedScaleFingerprint randomized=$($randomScaleMatch.Groups[1].Value)"
  }
  Write-Host "[ok] 100000-node graph order invariance: $orderedScaleFingerprint"
}
Assert-ReportLineContains -Line $syntheticCoverageLine -Expected "scan_count=2" -Context "Synthetic graph bounded scan count"

Invoke-RuntimeScenario -ScenarioName "synthetic-scale-recipes" -EnabledFixtureNames @(
  "mir-fixture-synthetic-scale-recipes",
  "mir-fixture-assert-synthetic-scale-recipes"
)
$orderedRecipeScaleFingerprint = $null
if (Test-MIRScenarioSelected -Name "synthetic-scale-recipes") {
  $orderedRecipeScaleMatch = [regex]::Match(
    (Get-Content -Raw -LiteralPath $FactorioLog),
    '\[mir-fixture\] synthetic-recipes fingerprints (coverage=\S+ generation=\S+ compilation=\S+ in_memory=\S+)'
  )
  if (-not $orderedRecipeScaleMatch.Success) { throw "Ordered 100000-recipe compiler fingerprints are missing." }
  $orderedRecipeScaleFingerprint = $orderedRecipeScaleMatch.Groups[1].Value
}

Invoke-RuntimeScenario -ScenarioName "synthetic-scale-recipes-random-order" -EnabledFixtureNames @(
  "mir-fixture-synthetic-scale-recipes",
  "mir-fixture-synthetic-scale-random-order",
  "mir-fixture-assert-synthetic-scale-recipes"
)
if ($orderedRecipeScaleFingerprint -and (Test-MIRScenarioSelected -Name "synthetic-scale-recipes-random-order")) {
  $randomRecipeScaleMatch = [regex]::Match(
    (Get-Content -Raw -LiteralPath $FactorioLog),
    '\[mir-fixture\] synthetic-recipes fingerprints (coverage=\S+ generation=\S+ compilation=\S+ in_memory=\S+)'
  )
  if (-not $randomRecipeScaleMatch.Success) { throw "Randomized 100000-recipe compiler fingerprints are missing." }
  if ($randomRecipeScaleMatch.Groups[1].Value -ne $orderedRecipeScaleFingerprint) {
    throw "Randomized insertion changed 100000-recipe compiler output: ordered=$orderedRecipeScaleFingerprint randomized=$($randomRecipeScaleMatch.Groups[1].Value)"
  }
  Write-Host "[ok] 100000-recipe order invariance: $orderedRecipeScaleFingerprint"
}

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

Invoke-RuntimeScenario -ScenarioName "skip-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-custom-lab",
  "mir-fixture-late-recipe",
  "mir-fixture-assert-lab-skip-policy"
) -LabPolicySkip

$skipPolicyLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
if ($skipPolicyLine -notmatch "status=skipped" -or $skipPolicyLine -notmatch "lab_status=invalid") {
  throw "Skip-policy runtime validation did not skip incompatible science-pack productivity as expected: $skipPolicyLine"
}

Invoke-RuntimeScenario -ScenarioName "lab-policy-engine-default" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-custom-lab",
  "mir-fixture-late-recipe"
) -LabPolicyEngineDefault

$engineDefaultLabPolicyLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineContains -Line $engineDefaultLabPolicyLine -Expected "status=skipped" -Context "Engine-unchanged lab policy scenario"
Assert-ReportLineContains -Line $engineDefaultLabPolicyLine -Expected "lab_status=invalid" -Context "Engine-unchanged lab policy scenario"

Invoke-RuntimeScenario -ScenarioName "space-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space"
$spacePackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spacePackLine -Context "Space science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spacePackLine -Expected "space-science-pack" -Context "Space science-pack ingredient policy scenario"
$baseElectricShootingLine = Get-LastStreamReportLine -Key "research_electric_shooting_speed"
Assert-ReportLineGenerated -Line $baseElectricShootingLine -Context "Base electric shooting speed scenario"
Assert-ReportLineContains -Line $baseElectricShootingLine -Expected "effects=1" -Context "Base electric shooting speed scenario"
Assert-ReportLineContains -Line $baseElectricShootingLine -Expected "icon=tech:discharge-defense-equipment" -Context "Base electric shooting speed scenario"
$baseFlamethrowerShootingLine = Get-LastStreamReportLine -Key "research_flamethrower_shooting_speed"
Assert-ReportLineGenerated -Line $baseFlamethrowerShootingLine -Context "Base flamethrower shooting speed scenario"

Invoke-RuntimeScenario -ScenarioName "character-inventory-merged-effects" -EnabledFixtureNames @()
$inventoryCapacityLine = Get-LastStreamReportLine -Key "research_inventory_capacity"
Assert-ReportLineGenerated -Line $inventoryCapacityLine -Context "Merged character inventory/trash slot scenario"
Assert-ReportLineContains -Line $inventoryCapacityLine -Expected "effects=2" -Context "Merged character inventory/trash slot scenario"
Assert-NoStreamReportLine -Key "research_character_trash_slots" -Context "Merged character inventory/trash slot scenario"

Invoke-RuntimeScenario -ScenarioName "approved-delta-automatic-family-controls" -EnabledFixtureNames @(
  "mir-fixture-semantic-family-attach",
  "mir-fixture-export-approved-delta"
)

Invoke-RuntimeScenario -ScenarioName "approved-delta-base" -EnabledFixtureNames @(
  "mir-fixture-export-approved-delta"
)

Invoke-RuntimeScenario -ScenarioName "approved-delta-base-continuations" -EnabledFixtureNames @(
  "mir-fixture-export-approved-delta"
) -EnabledBaseExtensionKeys @(
  "inserter-capacity-bonus"
)

Invoke-RuntimeScenario -ScenarioName "approved-delta-compat-space-age-galore" -EnabledFixtureNames @(
  "mir-fixture-space-age-galore-overlap",
  "mir-fixture-export-approved-delta"
) -EnableSpaceAge

Invoke-RuntimeScenario -ScenarioName "approved-delta-compat-atan" -EnabledFixtureNames @(
  "mir-fixture-atan-nuclear-science",
  "mir-fixture-export-approved-delta"
)

Invoke-RuntimeScenario -ScenarioName "approved-delta-native-owner-adoption" -EnabledFixtureNames @(
  "mir-fixture-vanilla-family-adoption-recipes",
  "mir-fixture-export-approved-delta"
) -EnableSpaceAge

Invoke-RuntimeScenario -ScenarioName "approved-delta-space-age" -EnabledFixtureNames @(
  "mir-fixture-export-approved-delta"
) -EnableSpaceAge

Invoke-RuntimeScenario -ScenarioName "base-generation-integrity" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity",
  "mir-fixture-assert-hidden-setting-readability"
)
Assert-LogDoesNotContain -Unexpected "Applied pipeline extent multiplier" -Context "Default pipeline extent scenario"
Assert-LogDoesNotContain -Unexpected "Applied prototype limits" -Context "Default prototype limit scenario"
Assert-BaseCoreProductivityStreamsGenerated -Context "Base generation integrity scenario"
Assert-DefaultBaseExtensionDiagnostics -Context "Base generation integrity scenario"
$baseRailsLine = Get-LastStreamReportLine -Key "research_rails"
Assert-ReportLineContains -Line $baseRailsLine -Expected "effects=1" -Context "Base rail productivity scenario"
Assert-ReportLineContains -Line $baseRailsLine -Expected "icon=item:rail" -Context "Base rail productivity icon scenario"

Invoke-RuntimeScenario -ScenarioName "generated-prerequisite-safety" -EnabledFixtureNames @(
  "mir-fixture-assert-generated-prerequisite-safety"
) -SciencePackIngredientPolicy "all"

Invoke-RuntimeScenario -ScenarioName "k2-science-phase-policy" -EnabledFixtureNames @(
  "mir-fixture-assert-k2-science-phase-policy"
)

Invoke-RuntimeScenario -ScenarioName "external-technology-cycle" -EnabledFixtureNames @(
  "mir-fixture-external-technology-cycle"
)

Invoke-RuntimeScenario -ScenarioName "rigor-late-recipe-removal" -EnabledFixtureNames @(
  "mir-fixture-rigor-late-recipe-removal"
)

Invoke-RuntimeScenario -ScenarioName "py-postprocessing-stale-unlock" -EnabledFixtureNames @(
  "pypostprocessing",
  "mir-fixture-assert-py-postprocessing-stale-unlock"
)

Invoke-RuntimeScenario -ScenarioName "space-exploration-recipe-removal" -EnabledFixtureNames @(
  "space-exploration",
  "mir-fixture-assert-final-recipe-effect-integrity"
)

Invoke-RuntimeScenario -ScenarioName "base-fluid-productivity" -EnabledFixtureNames @(
  "mir-fixture-assert-fluid-productivity"
)
Assert-FluidProductivityStreamsGenerated -Context "Base fluid productivity scenario"
$baseOilCrackingLine = Get-LastStreamReportLine -Key "research_oil_cracking_productivity"
Assert-ReportLineContains -Line $baseOilCrackingLine -Expected "icon=tech:oil-processing" -Context "Base oil cracking icon scenario"
$baseSulfuricAcidLine = Get-LastStreamReportLine -Key "research_sulfuric_acid_productivity"
Assert-ReportLineContains -Line $baseSulfuricAcidLine -Expected "icon=fluid:sulfuric-acid" -Context "Base sulfuric acid icon scenario"
foreach ($baseThrusterStream in @("research_thruster_fuel_productivity", "research_thruster_oxidizer_productivity")) {
  $baseThrusterLine = Get-LastStreamReportLine -Key $baseThrusterStream
  if ($baseThrusterLine -notmatch "status=skipped" -or $baseThrusterLine -notmatch "missing required fluid") {
    throw "Base-only thruster fluid stream $baseThrusterStream should skip for missing fluid: $baseThrusterLine"
  }
}

Invoke-RuntimeScenario -ScenarioName "aai-loader-belt-productivity" -EnabledFixtureNames @(
  "mir-fixture-aai-loaders",
  "mir-fixture-assert-aai-loader-belt-productivity"
)
$aaiLoaderBeltLine = Get-LastStreamReportLine -Key "research_belts"
Assert-ReportLineGenerated -Line $aaiLoaderBeltLine -Context "AAI loader belt productivity scenario"
$aaiLoaderCapabilityLine = Get-DiagnosticReportLineContaining -Kind "decision" -Key "aai-turbo-loader" -Expected "capability=logistics-loader-manufacturing"
Assert-ReportLineContains -Line $aaiLoaderCapabilityLine -Expected "decision=attach" -Context "AAI loader capability resolver scenario"
Assert-ReportLineContains -Line $aaiLoaderCapabilityLine -Expected "subfamily=loader" -Context "AAI loader capability subfamily scenario"
Assert-ReportLineContains -Line $aaiLoaderCapabilityLine -Expected "evidence=effect-owner-index,place-result-index,recipe-fact-v2" -Context "AAI loader entity-backed evidence scenario"

Invoke-RuntimeScenario -ScenarioName "big-mining-drill-productivity" -EnabledFixtureNames @(
  "mir-fixture-big-mining-drill",
  "mir-fixture-assert-big-mining-drill-productivity"
)
$bigMiningDrillLine = Get-LastStreamReportLine -Key "research_mining_drill"
Assert-ReportLineGenerated -Line $bigMiningDrillLine -Context "Big Mining Drill productivity scenario"
$bigMiningCapabilityLine = Get-DiagnosticReportLineContaining -Kind "decision" -Key "big-mining-drill" -Expected "capability=mining-drill-manufacturing"
Assert-ReportLineContains -Line $bigMiningCapabilityLine -Expected "decision=review-required" -Context "Big Mining Drill automatic-provider safety scenario"
Assert-ReportLineContains -Line $bigMiningCapabilityLine -Expected "blockers=provider_progression_span_budget_exceeded" -Context "Big Mining Drill automatic-provider progression budget scenario"
Assert-ReportLineContains -Line $bigMiningCapabilityLine -Expected "subfamily=mining_drill" -Context "Big Mining Drill capability subfamily scenario"
Assert-ReportLineContains -Line $bigMiningCapabilityLine -Expected "evidence=effect-owner-index,place-result-index,recipe-fact-v2" -Context "Big Mining Drill entity-backed evidence scenario"

Invoke-RuntimeScenario -ScenarioName "compiler-contracts" -EnabledFixtureNames @(
  "mir-fixture-assert-compiler-contracts"
)

