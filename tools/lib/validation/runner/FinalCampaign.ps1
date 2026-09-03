Invoke-RuntimeScenario -ScenarioName "space-age-vanilla-family-mixed-owner" -EnabledFixtureNames @(
  "mir-fixture-vanilla-family-mixed-owner",
  "mir-fixture-assert-vanilla-family-mixed-owner"
) -EnableSpaceAge
$mixedOwnerRocketFuelLine = Get-LastStreamReportLine -Key "research_rocket_fuel"
Assert-ReportLineGenerated -Line $mixedOwnerRocketFuelLine -Context "Mixed owner change fallback scenario"
Assert-LogContains -Expected "owner_mixed_change_values; eligible recipes fall back to MIR generation." -Context "Mixed owner change fallback scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-fluid-productivity" -EnabledFixtureNames @(
  "mir-fixture-assert-fluid-productivity"
) -EnableSpaceAge
Assert-FluidProductivityStreamsGenerated -Context "Space Age fluid productivity scenario" -IncludeThruster
$spaceAgeOilProcessingLine = Get-LastStreamReportLine -Key "research_oil_processing_productivity"
Assert-ReportScienceContains -Line $spaceAgeOilProcessingLine -Expected "cryogenic-science-pack" -Context "Space Age oil processing cryogenic science scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeOilProcessingLine -Unexpected "space-science-pack" -Context "Space Age oil processing space science replacement scenario"
$spaceAgeOilCrackingLine = Get-LastStreamReportLine -Key "research_oil_cracking_productivity"
Assert-ReportLineContains -Line $spaceAgeOilCrackingLine -Expected "icon=tech:oil-processing" -Context "Space Age oil cracking icon scenario"
Assert-ReportScienceContains -Line $spaceAgeOilCrackingLine -Expected "agricultural-science-pack" -Context "Space Age oil cracking agricultural science scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeOilCrackingLine -Unexpected "space-science-pack" -Context "Space Age oil cracking space science replacement scenario"
$spaceAgeLubricantLine = Get-LastStreamReportLine -Key "research_lubricant_productivity"
Assert-ReportScienceContains -Line $spaceAgeLubricantLine -Expected "electromagnetic-science-pack" -Context "Space Age lubricant electromagnetic science scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeLubricantLine -Unexpected "space-science-pack" -Context "Space Age lubricant space science replacement scenario"
$spaceAgeSulfuricAcidLine = Get-LastStreamReportLine -Key "research_sulfuric_acid_productivity"
Assert-ReportLineContains -Line $spaceAgeSulfuricAcidLine -Expected "icon=fluid:sulfuric-acid" -Context "Space Age sulfuric acid icon scenario"
Assert-ReportScienceContains -Line $spaceAgeSulfuricAcidLine -Expected "metallurgic-science-pack" -Context "Space Age sulfuric acid metallurgic science scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeSulfuricAcidLine -Unexpected "space-science-pack" -Context "Space Age sulfuric acid space science replacement scenario"
$spaceAgeThrusterFuelLine = Get-LastStreamReportLine -Key "research_thruster_fuel_productivity"
Assert-ReportLineContains -Line $spaceAgeThrusterFuelLine -Expected "effects=2" -Context "Space Age thruster fuel productivity scenario"
$spaceAgeThrusterOxidizerLine = Get-LastStreamReportLine -Key "research_thruster_oxidizer_productivity"
Assert-ReportLineContains -Line $spaceAgeThrusterOxidizerLine -Expected "effects=2" -Context "Space Age thruster oxidizer productivity scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-generation-integrity-inserter-enabled" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity"
) -EnabledBaseExtensionKeys @(
  "inserter-capacity-bonus"
) -EnableSpaceAge
Assert-SpaceAgeVanillaOwnedProductivityStreamsBound -Context "Space Age generation integrity with inserter enabled scenario"
Assert-DefaultBaseExtensionDiagnostics -Context "Space Age generation integrity with inserter enabled scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-space-promethium-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space-and-promethium" -EnableSpaceAge
$spaceAgeSpacePromethiumPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spaceAgeSpacePromethiumPackLine -Context "Space Age space and promethium science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spaceAgeSpacePromethiumPackLine -Expected "space-science-pack" -Context "Space Age space and promethium science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spaceAgeSpacePromethiumPackLine -Expected "promethium-science-pack" -Context "Space Age space and promethium science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "all-official-pack-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack"
) -SciencePackIngredientPolicy "all-official"
$allOfficialPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $allOfficialPackLine -Context "All official science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allOfficialPackLine -Expected "space-science-pack" -Context "All official science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $allOfficialPackLine -Unexpected "mir-fixture-science-pack" -Context "All official science-pack ingredient policy scenario"
$allOfficialExtensionLine = Get-LastExtensionReportLine -Key "research-speed"
Assert-ReportLineGenerated -Line $allOfficialExtensionLine -Context "All official base-extension science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allOfficialExtensionLine -Expected "space-science-pack" -Context "All official base-extension science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $allOfficialExtensionLine -Unexpected "mir-fixture-science-pack" -Context "All official base-extension science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "all-pack-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack"
) -SciencePackIngredientPolicy "all"
$allPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $allPackLine -Context "All lab science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allPackLine -Expected "mir-fixture-science-pack" -Context "All lab science-pack ingredient policy scenario"
$allPackExtensionLine = Get-LastExtensionReportLine -Key "braking-force"
Assert-ReportLineGenerated -Line $allPackExtensionLine -Context "All lab base-extension science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allPackExtensionLine -Expected "mir-fixture-science-pack" -Context "All lab base-extension science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "base-extension-boundary-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-finite-base-extension-level",
  "mir-fixture-assert-base-extension-boundary"
) -SciencePackIngredientPolicy "all"
$baseExtensionBoundaryLine = Get-LastExtensionReportLine -Key "research-speed"
Assert-ReportLineGenerated -Line $baseExtensionBoundaryLine -Context "Base extension boundary scenario"
Assert-ReportLineContains -Line $baseExtensionBoundaryLine -Expected "mir-fixture-science-pack" -Context "Base extension boundary scenario"

Invoke-RuntimeScenario -ScenarioName "base-effect-setting-retention" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity"
) -BaseEffectPerLevelOverrides @{
  "research-speed" = 120
  "worker-robots-storage" = 2
}

Invoke-RuntimeScenario -ScenarioName "base-research-cost-linear" -EnabledFixtureNames @(
  "mir-fixture-assert-base-research-cost"
) -EnabledBaseExtensionKeys @("worker-robots-storage") -StartupSettingOverrides @{
  "mir-cost-base-worker-robots-storage" = 1000
  "mir-cost-linear-increment-worker-robots-storage" = 250
  "mir-cost-growth-worker-robots-storage" = 1
}

Invoke-RuntimeScenario -ScenarioName "base-stream-research-cost-hybrid" -EnabledFixtureNames @(
  "mir-fixture-assert-stream-research-cost"
) -EnabledStreamKeys @("research_gears") -StartupSettingOverrides @{
  "ips-cost-base-research_gears" = 1000
  "ips-cost-linear-increment-research_gears" = 250
  "ips-cost-growth-research_gears" = 1.5
}

Invoke-WeaponSpeedPolicyMatrix -Context "Weapon shooting speed policy"

Invoke-RuntimeScenario -ScenarioName "omega-drill-productivity" -EnabledFixtureNames @(
  "mir-fixture-omega-drill",
  "mir-fixture-assert-omega-drill-productivity"
)

$omegaDrillLine = Get-LastStreamReportLine -Key "research_mining_drill"
Assert-ReportLineGenerated -Line $omegaDrillLine -Context "Omega-style drill productivity scenario"
$omegaEffectCountMatch = [regex]::Match($omegaDrillLine, "effects=(\d+)")
if (-not $omegaEffectCountMatch.Success -or [int]$omegaEffectCountMatch.Groups[1].Value -lt 4) {
  throw "Omega-style drill productivity scenario did not include the expected mining drill effect count: $omegaDrillLine"
}

Invoke-RuntimeScenario -ScenarioName "base-competitor-rollback" -EnabledFixtureNames @(
  "Better_Robots_Extended",
  "mir-fixture-assert-base-competitor-transaction"
) -BaseMaxLevelOverrides @{
  "worker-robots-storage" = 3
}

Invoke-RuntimeScenario -ScenarioName "technology-prerequisite-rewire" -EnabledFixtureNames @(
  "Better_Robots_Extended",
  "mir-fixture-assert-base-competitor-transaction"
)

Invoke-RuntimeScenario -ScenarioName "end-game-prerequisite-gate" -EnabledFixtureNames @() -RequireSpaceGate
$gateLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $gateLine -Context "End-game prerequisite gate scenario"
Assert-ReportLineContains -Line $gateLine -Expected "prerequisites=automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,space-science-pack" -Context "End-game prerequisite gate scenario"
Assert-ReportLineDoesNotContain -Line $gateLine -Unexpected "science=automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,space-science-pack" -Context "End-game prerequisite gate scenario"

if (-not $isFactorio21Line) {
  Write-Host "[skip] Factorio 2.1 cargo runtime fixture scenarios skipped for Factorio $($repoInfo.factorio_version) metadata."
} else {
  Invoke-RuntimeScenario -ScenarioName "base-cargo-space-age-gate" -EnabledFixtureNames @()
  $cargoPadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  if ($cargoPadLine -notmatch "status=skipped" -or $cargoPadLine -notmatch "missing required mod space-age") {
    throw "Cargo landing pad count generated or skipped for the wrong reason without Space Age: $cargoPadLine"
  }

  Invoke-RuntimeScenario -ScenarioName "space-age-cargo-pad-enabled" -EnabledFixtureNames @() -EnableSpaceAge
  $spaceAgeCargoPadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineGenerated -Line $spaceAgeCargoPadLine -Context "Space Age cargo landing pad count scenario"
  $spaceAgeCargoDistanceLine = Get-LastStreamReportLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineGenerated -Line $spaceAgeCargoDistanceLine -Context "Space Age cargo bay unloading distance scenario"

  Invoke-RuntimeScenario -ScenarioName "space-age-cargo-logistics-shape" -EnabledFixtureNames @(
    "mir-fixture-assert-cargo-logistics"
  ) -EnableSpaceAge
  $spaceAgeCargoShapePadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineGenerated -Line $spaceAgeCargoShapePadLine -Context "Space Age cargo logistics shape scenario"
  $spaceAgeCargoShapeDistanceLine = Get-LastStreamReportLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineGenerated -Line $spaceAgeCargoShapeDistanceLine -Context "Space Age cargo logistics shape scenario"

  Invoke-RuntimeScenario -ScenarioName "space-age-duplicate-cargo-diagnostics" -EnabledFixtureNames @(
    "mir-fixture-duplicate-cargo-tech",
    "mir-fixture-assert-cargo-logistics"
  ) -EnableSpaceAge
  $duplicateCargoPadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineGenerated -Line $duplicateCargoPadLine -Context "Duplicate cargo landing pad diagnostics scenario"
  $duplicateCargoPadOverlapLine = Get-LastNativeModifierOverlapLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineContains -Line $duplicateCargoPadOverlapLine -Expected "effect=cargo-landing-pad-count" -Context "Duplicate cargo landing pad diagnostics scenario"
  Assert-ReportLineContains -Line $duplicateCargoPadOverlapLine -Expected "owners=mir-fixture-duplicate-cargo-landing-pad-count" -Context "Duplicate cargo landing pad diagnostics scenario"

  $duplicateCargoDistanceLine = Get-LastStreamReportLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineGenerated -Line $duplicateCargoDistanceLine -Context "Duplicate cargo bay diagnostics scenario"
  $duplicateCargoDistanceOverlapLine = Get-LastNativeModifierOverlapLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineContains -Line $duplicateCargoDistanceOverlapLine -Expected "effect=max-cargo-bay-unloading-distance" -Context "Duplicate cargo bay diagnostics scenario"
  Assert-ReportLineContains -Line $duplicateCargoDistanceOverlapLine -Expected "owners=mir-fixture-duplicate-cargo-bay-unloading-distance" -Context "Duplicate cargo bay diagnostics scenario"
}
