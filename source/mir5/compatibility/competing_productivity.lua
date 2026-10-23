-- Exact F200 bindings for named competing productivity providers.
--
-- These declarations name only proved foreign tails or initial identities and
-- their one-to-one (or explicitly split) MIR productivity coverage. Runtime
-- retirement never discovers recipes or technologies.
local M = {}

local PROVIDER = "ExpandedProductivityResearch"
local PROVIDER_VERSION = "1.3.8"
local BASE_VERSION = "2.0.77"
local EFFECT = 0.1
-- An explicit false keeps a captured no-prerequisite identity distinct from a
-- missing authored field. It admits only a native/data row with no entries.
local NO_PREDECESSOR = false

local function effects(recipes)
  local out = {}
  for index = 1, #recipes do out[index] = {recipe = recipes[index], change = EFFECT} end
  return out
end

local function replacement(id, recipes)
  return {id = id, first_level = 1, effects = effects(recipes)}
end

local function binding(id, first_level, predecessor, recipes, replacements, initial_retirement)
  return {
    id = id,
    first_level = first_level,
    predecessor = predecessor,
    effects = effects(recipes),
    replacements = replacements,
    initial_retirement = initial_retirement == true,
  }
end

local EPR_BINDINGS = {
  binding("epr_advanced-circuit-productivity-5", 5, "epr_advanced-circuit-productivity-4", {"advanced-circuit"},
    {replacement("recipe-prod-research_advanced_circuit-1", {"advanced-circuit"})}),
  binding("epr_automation-science-pack-productivity-5", 5, "epr_automation-science-pack-productivity-4", {"automation-science-pack"},
    {replacement("recipe-prod-research_science_pack_productivity-1", {"automation-science-pack"})}),
  binding("epr_battery-productivity-5", 5, "epr_battery-productivity-4", {"battery"},
    {replacement("recipe-prod-research_batteries-1", {"battery"})}),
  binding("epr_chemical-science-pack-productivity-5", 5, "epr_chemical-science-pack-productivity-4", {"chemical-science-pack"},
    {replacement("recipe-prod-research_science_pack_productivity-1", {"chemical-science-pack"})}),
  binding("epr_copper-cable-productivity-5", 5, "epr_copper-cable-productivity-4", {"copper-cable"},
    {replacement("recipe-prod-research_copper_cable-1", {"copper-cable"})}),
  binding("epr_copper-plate-productivity-5", 5, "epr_copper-plate-productivity-4", {"copper-plate"},
    {replacement("recipe-prod-research_copper-1", {"copper-plate"})}),
  binding("epr_electric-engine-unit-productivity-4", 4, "epr_electric-engine-unit-productivity-3", {"electric-engine-unit"},
    {replacement("recipe-prod-research_electric_engine-1", {"electric-engine-unit"})}),
  binding("epr_electronic-circuit-productivity-5", 5, "epr_electronic-circuit-productivity-4", {"electronic-circuit"},
    {replacement("recipe-prod-research_electronic_circuit-1", {"electronic-circuit"})}),
  binding("epr_engine-unit-productivity-5", 5, "epr_engine-unit-productivity-4", {"engine-unit"},
    {replacement("recipe-prod-research_engine-1", {"engine-unit"})}),
  binding("epr_explosives-productivity-5", 5, "epr_explosives-productivity-4", {"explosives"},
    {replacement("recipe-prod-research_explosives-1", {"explosives"})}),
  binding("epr_flying-robot-frame-productivity-4", 4, "epr_flying-robot-frame-productivity-3", {"flying-robot-frame"},
    {replacement("recipe-prod-research_flying_robot_frame-1", {"flying-robot-frame"})}),
  binding("epr_heavy-oil-productivity-4", 4, "epr_heavy-oil-productivity-3", {"advanced-oil-processing", "coal-liquefaction"},
    {replacement("recipe-prod-research_oil_processing_productivity-1", {"advanced-oil-processing", "coal-liquefaction"})}),
  binding("epr_iron-gear-wheel-productivity-5", 5, "epr_iron-gear-wheel-productivity-4", {"iron-gear-wheel"},
    {replacement("recipe-prod-research_gears-1", {"iron-gear-wheel"})}),
  binding("epr_iron-plate-productivity-5", 5, "epr_iron-plate-productivity-4", {"iron-plate"},
    {replacement("recipe-prod-research_iron-1", {"iron-plate"})}),
  binding("epr_iron-stick-productivity-5", 5, "epr_iron-stick-productivity-4", {"iron-stick"},
    {replacement("recipe-prod-research_iron_sticks-1", {"iron-stick"})}),
  binding("epr_light-oil-productivity-4", 4, "epr_light-oil-productivity-3", {"heavy-oil-cracking"},
    {replacement("recipe-prod-research_oil_cracking_productivity-1", {"heavy-oil-cracking"})}),
  binding("epr_logistic-science-pack-productivity-5", 5, "epr_logistic-science-pack-productivity-4", {"logistic-science-pack"},
    {replacement("recipe-prod-research_science_pack_productivity-1", {"logistic-science-pack"})}),
  binding("epr_low-density-structure-productivity-4", 4, "epr_low-density-structure-productivity-3", {"low-density-structure"},
    {replacement("recipe-prod-research_low_density_structure-1", {"low-density-structure"})}),
  binding("epr_lubricant-productivity-4", 4, "epr_lubricant-productivity-3", {"lubricant"},
    {replacement("recipe-prod-research_lubricant_productivity-1", {"lubricant"})}),
  binding("epr_military-science-pack-productivity-5", 5, "epr_military-science-pack-productivity-4", {"military-science-pack"},
    {replacement("recipe-prod-research_science_pack_productivity-1", {"military-science-pack"})}),
  binding("epr_petroleum-gas-productivity-5", 5, "epr_petroleum-gas-productivity-4", {"basic-oil-processing", "light-oil-cracking"}, {
    replacement("recipe-prod-research_oil_processing_productivity-1", {"basic-oil-processing"}),
    replacement("recipe-prod-research_oil_cracking_productivity-1", {"light-oil-cracking"}),
  }),
  binding("epr_plastic-bar-productivity-5", 5, "epr_plastic-bar-productivity-4", {"plastic-bar"},
    {replacement("recipe-prod-research_plastic-1", {"plastic-bar"})}),
  binding("epr_processing-unit-productivity-4", 4, "epr_processing-unit-productivity-3", {"processing-unit"},
    {replacement("recipe-prod-research_processing_unit-1", {"processing-unit"})}),
  binding("epr_production-science-pack-productivity-4", 4, "epr_production-science-pack-productivity-3", {"production-science-pack"},
    {replacement("recipe-prod-research_science_pack_productivity-1", {"production-science-pack"})}),
  binding("epr_rocket-fuel-productivity-4", 4, "epr_rocket-fuel-productivity-3", {"rocket-fuel"},
    {replacement("recipe-prod-research_rocket_fuel-1", {"rocket-fuel"})}),
  binding("epr_steel-plate-productivity-5", 5, "epr_steel-plate-productivity-4", {"steel-plate"},
    {replacement("recipe-prod-research_steel-1", {"steel-plate"})}),
  binding("epr_stone-brick-productivity-5", 5, "epr_stone-brick-productivity-4", {"stone-brick"},
    {replacement("recipe-prod-research_concrete-1", {"stone-brick"})}),
  binding("epr_sulfur-productivity-5", 5, "epr_sulfur-productivity-4", {"sulfur"},
    {replacement("recipe-prod-research_sulfur-1", {"sulfur"})}),
  binding("epr_sulfuric-acid-productivity-5", 5, "epr_sulfuric-acid-productivity-4", {"sulfuric-acid"},
    {replacement("recipe-prod-research_sulfuric_acid_productivity-1", {"sulfuric-acid"})}),
  binding("epr_utility-science-pack-productivity-4", 4, "epr_utility-science-pack-productivity-3", {"utility-science-pack"},
    {replacement("recipe-prod-research_science_pack_productivity-1", {"utility-science-pack"})}),
}

-- Exact F200 Space Age rows from the independent dynamic-provider capture.
-- These remain flat literals: no runtime identifier or recipe discovery occurs.
local CRAFTING_EFFICIENCY_BINDINGS = {
  binding("ce-advanced-circuit-16", 16, "ce-advanced-circuit-11", {"advanced-circuit"}, {replacement("recipe-prod-research_advanced_circuit-1", {"advanced-circuit"})}, true),
  binding("ce-advanced-oil-processing-11", 11, "ce-advanced-oil-processing-7", {"advanced-oil-processing"}, {replacement("recipe-prod-research_oil_processing_productivity-1", {"advanced-oil-processing"})}, true),
  binding("ce-agricultural-science-pack-30", 30, "ce-agricultural-science-pack-16", {"agricultural-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"agricultural-science-pack"})}, true),
  binding("ce-automation-science-pack-42", 42, "ce-automation-science-pack-28", {"automation-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"automation-science-pack"})}, true),
  binding("ce-basic-oil-processing-16", 16, "ce-basic-oil-processing-11", {"basic-oil-processing"}, {replacement("recipe-prod-research_oil_processing_productivity-1", {"basic-oil-processing"})}, true),
  binding("ce-battery-16", 16, "ce-battery-11", {"battery"}, {replacement("recipe-prod-research_batteries-1", {"battery"})}, true),
  binding("ce-chemical-science-pack-30", 30, "ce-chemical-science-pack-16", {"chemical-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"chemical-science-pack"})}, true),
  binding("ce-coal-liquefaction-8", 8, "ce-coal-liquefaction-4", {"coal-liquefaction"}, {replacement("recipe-prod-research_oil_processing_productivity-1", {"coal-liquefaction"})}, true),
  binding("ce-copper-cable-19", 19, "ce-copper-cable-14", {"copper-cable", "casting-copper-cable"}, {replacement("recipe-prod-research_copper_cable-1", {"copper-cable", "casting-copper-cable"})}, true),
  binding("ce-cryogenic-science-pack-15", 15, "ce-cryogenic-science-pack-1", {"cryogenic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"cryogenic-science-pack"})}, true),
  binding("ce-electric-engine-unit-11", 11, "ce-electric-engine-unit-7", {"electric-engine-unit"}, {replacement("recipe-prod-research_electric_engine-1", {"electric-engine-unit"})}, true),
  binding("ce-electromagnetic-science-pack-30", 30, "ce-electromagnetic-science-pack-16", {"electromagnetic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"electromagnetic-science-pack"})}, true),
  binding("ce-electronic-circuit-19", 19, "ce-electronic-circuit-14", {"electronic-circuit"}, {replacement("recipe-prod-research_electronic_circuit-1", {"electronic-circuit"})}, true),
  binding("ce-engine-unit-19", 19, "ce-engine-unit-14", {"engine-unit"}, {replacement("recipe-prod-research_engine-1", {"engine-unit"})}, true),
  binding("ce-firearm-magazine-17", 17, "ce-firearm-magazine-13", {"firearm-magazine"}, {replacement("recipe-prod-research_bullets-1", {"firearm-magazine"})}, true),
  binding("ce-flying-robot-frame-11", 11, "ce-flying-robot-frame-7", {"flying-robot-frame"}, {replacement("recipe-prod-research_flying_robot_frame-1", {"flying-robot-frame"})}, true),
  binding("ce-grenade-14", 14, "ce-grenade-10", {"grenade"}, {replacement("recipe-prod-research_grenades-1", {"grenade"})}, true),
  binding("ce-iron-gear-wheel-19", 19, "ce-iron-gear-wheel-14", {"iron-gear-wheel", "casting-iron-gear-wheel"}, {replacement("recipe-prod-research_gears-1", {"iron-gear-wheel", "casting-iron-gear-wheel"})}, true),
  binding("ce-iron-stick-19", 19, "ce-iron-stick-14", {"iron-stick", "casting-iron-stick"}, {replacement("recipe-prod-research_iron_sticks-1", {"iron-stick", "casting-iron-stick"})}, true),
  binding("ce-logistic-science-pack-36", 36, "ce-logistic-science-pack-22", {"logistic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"logistic-science-pack"})}, true),
  binding("ce-lubricant-8", 8, "ce-lubricant-4", {"lubricant"}, {replacement("recipe-prod-research_lubricant_productivity-1", {"lubricant"})}, true),
  binding("ce-metallurgic-science-pack-30", 30, "ce-metallurgic-science-pack-16", {"metallurgic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"metallurgic-science-pack"})}, true),
  binding("ce-military-science-pack-30", 30, "ce-military-science-pack-16", {"military-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"military-science-pack"})}, true),
  binding("ce-production-science-pack-24", 24, "ce-production-science-pack-10", {"production-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"production-science-pack"})}, true),
  binding("ce-promethium-science-pack-15", 15, "ce-promethium-science-pack-1", {"promethium-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"promethium-science-pack"})}, true),
  binding("ce-space-science-pack-15", 15, "ce-space-science-pack-1", {"space-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"space-science-pack"})}, true),
  binding("ce-sulfur-16", 16, "ce-sulfur-11", {"sulfur", "biosulfur"}, {replacement("recipe-prod-research_sulfur-1", {"sulfur", "biosulfur"})}, true),
  binding("ce-utility-science-pack-15", 15, "ce-utility-science-pack-1", {"utility-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"utility-science-pack"})}, true),
}

local PRODUCTIVITY_RESEARCH_BINDINGS = {
  binding("sem-prfe_advanced-circuit-productivity-1", 1, "advanced-circuit", {"advanced-circuit"}, {replacement("recipe-prod-research_advanced_circuit-1", {"advanced-circuit"})}, true),
  binding("sem-prfe_advanced-oil-processing-productivity-1", 1, "advanced-oil-processing", {"advanced-oil-processing", "coal-liquefaction", "simple-coal-liquefaction"}, {replacement("recipe-prod-research_oil_processing_productivity-1", {"advanced-oil-processing", "coal-liquefaction", "simple-coal-liquefaction"})}, true),
  binding("sem-prfe_agricultural-science-pack-productivity-1", 1, "agricultural-science-pack", {"agricultural-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"agricultural-science-pack"})}, true),
  binding("sem-prfe_artificial-jellynut-soil-productivity-1", 1, "artificial-soil", {"artificial-jellynut-soil"}, {replacement("recipe-prod-research_artificial_soil-1", {"artificial-jellynut-soil"})}, true),
  binding("sem-prfe_artificial-yumako-soil-productivity-1", 1, "artificial-soil", {"artificial-yumako-soil"}, {replacement("recipe-prod-research_artificial_soil-1", {"artificial-yumako-soil"})}, true),
  binding("sem-prfe_automation-science-pack-productivity-1", 1, "automation-science-pack", {"automation-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"automation-science-pack"})}, true),
  binding("sem-prfe_battery-productivity-1", 1, "battery", {"battery"}, {replacement("recipe-prod-research_batteries-1", {"battery"})}, true),
  binding("sem-prfe_bioflux-productivity-1", 1, "bioflux", {"bioflux"}, {replacement("recipe-prod-research_bioflux-1", {"bioflux"})}, true),
  binding("sem-prfe_carbon-fiber-productivity-1", 1, "carbon-fiber", {"carbon-fiber"}, {replacement("recipe-prod-research_carbon_fiber-1", {"carbon-fiber"})}, true),
  binding("sem-prfe_chemical-science-pack-productivity-1", 1, "chemical-science-pack", {"chemical-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"chemical-science-pack"})}, true),
  binding("sem-prfe_copper-cable-productivity-1", 1, "electronics", {"copper-cable", "casting-copper-cable"}, {replacement("recipe-prod-research_copper_cable-1", {"copper-cable", "casting-copper-cable"})}, true),
  binding("sem-prfe_copper-plate-productivity-1", 1, NO_PREDECESSOR, {"copper-plate", "casting-copper"}, {replacement("recipe-prod-research_copper-1", {"copper-plate", "casting-copper"})}, true),
  binding("sem-prfe_cryogenic-science-pack-productivity-1", 1, "cryogenic-science-pack", {"cryogenic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"cryogenic-science-pack"})}, true),
  binding("sem-prfe_electric-engine-unit-productivity-1", 1, "electric-engine", {"electric-engine-unit"}, {replacement("recipe-prod-research_electric_engine-1", {"electric-engine-unit"})}, true),
  binding("sem-prfe_electromagnetic-science-pack-productivity-1", 1, "electromagnetic-science-pack", {"electromagnetic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"electromagnetic-science-pack"})}, true),
  binding("sem-prfe_electronic-circuit-productivity-1", 1, "electronics", {"electronic-circuit"}, {replacement("recipe-prod-research_electronic_circuit-1", {"electronic-circuit"})}, true),
  binding("sem-prfe_engine-unit-productivity-1", 1, "engine", {"engine-unit"}, {replacement("recipe-prod-research_engine-1", {"engine-unit"})}, true),
  binding("sem-prfe_explosives-productivity-1", 1, "explosives", {"explosives"}, {replacement("recipe-prod-research_explosives-1", {"explosives"})}, true),
  binding("sem-prfe_flying-robot-frame-productivity-1", 1, "robotics", {"flying-robot-frame"}, {replacement("recipe-prod-research_flying_robot_frame-1", {"flying-robot-frame"})}, true),
  binding("sem-prfe_holmium-plate-productivity-1", 1, "holmium-processing", {"holmium-plate"}, {replacement("recipe-prod-research_holmium-1", {"holmium-plate"})}, true),
  binding("sem-prfe_iron-gear-wheel-productivity-1", 1, NO_PREDECESSOR, {"iron-gear-wheel", "casting-iron-gear-wheel"}, {replacement("recipe-prod-research_gears-1", {"iron-gear-wheel", "casting-iron-gear-wheel"})}, true),
  binding("sem-prfe_iron-plate-productivity-1", 1, NO_PREDECESSOR, {"iron-plate", "casting-iron"}, {replacement("recipe-prod-research_iron-1", {"iron-plate", "casting-iron"})}, true),
  binding("sem-prfe_iron-stick-productivity-1", 1, "railway", {"iron-stick", "casting-iron-stick"}, {replacement("recipe-prod-research_iron_sticks-1", {"iron-stick", "casting-iron-stick"})}, true),
  binding("sem-prfe_lithium-plate-productivity-1", 1, "lithium-processing", {"lithium-plate"}, {replacement("recipe-prod-research_lithium-1", {"lithium-plate"})}, true),
  binding("sem-prfe_logistic-science-pack-productivity-1", 1, "logistic-science-pack", {"logistic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"logistic-science-pack"})}, true),
  binding("sem-prfe_lubricant-productivity-1", 1, "lubricant", {"lubricant", "biolubricant"}, {replacement("recipe-prod-research_lubricant_productivity-1", {"lubricant", "biolubricant"})}, true),
  binding("sem-prfe_metallurgic-science-pack-productivity-1", 1, "metallurgic-science-pack", {"metallurgic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"metallurgic-science-pack"})}, true),
  binding("sem-prfe_military-science-pack-productivity-1", 1, "military-science-pack", {"military-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"military-science-pack"})}, true),
  binding("sem-prfe_pentapod-egg-productivity-1", 1, "biochamber", {"pentapod-egg"}, {replacement("recipe-prod-research_breeding-1", {"pentapod-egg"})}, true),
  binding("sem-prfe_production-science-pack-productivity-1", 1, "production-science-pack", {"production-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"production-science-pack"})}, true),
  binding("sem-prfe_promethium-science-pack-productivity-1", 1, "promethium-science-pack", {"promethium-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"promethium-science-pack"})}, true),
  binding("sem-prfe_quantum-processor-productivity-1", 1, "quantum-processor", {"quantum-processor"}, {replacement("recipe-prod-research_quantum_processor-1", {"quantum-processor"})}, true),
  binding("sem-prfe_space-science-pack-productivity-1", 1, "space-science-pack", {"space-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"space-science-pack"})}, true),
  binding("sem-prfe_stone-brick-productivity-1", 1, NO_PREDECESSOR, {"stone-brick"}, {replacement("recipe-prod-research_concrete-1", {"stone-brick"})}, true),
  binding("sem-prfe_sulfur-productivity-1", 1, "sulfur-processing", {"sulfur", "biosulfur"}, {replacement("recipe-prod-research_sulfur-1", {"sulfur", "biosulfur"})}, true),
  binding("sem-prfe_sulfuric-acid-productivity-1", 1, "sulfur-processing", {"sulfuric-acid"}, {replacement("recipe-prod-research_sulfuric_acid_productivity-1", {"sulfuric-acid"})}, true),
  binding("sem-prfe_supercapacitor-productivity-1", 1, "electromagnetic-plant", {"supercapacitor"}, {replacement("recipe-prod-research_supercapacitor-1", {"supercapacitor"})}, true),
  binding("sem-prfe_superconductor-productivity-1", 1, "electromagnetic-plant", {"superconductor"}, {replacement("recipe-prod-research_superconductor-1", {"superconductor"})}, true),
  binding("sem-prfe_thruster-fuel-productivity-1", 1, "space-platform-thruster", {"thruster-fuel", "advanced-thruster-fuel"}, {replacement("recipe-prod-research_thruster_fuel_productivity-1", {"thruster-fuel", "advanced-thruster-fuel"})}, true),
  binding("sem-prfe_thruster-oxidizer-productivity-1", 1, "space-platform-thruster", {"thruster-oxidizer", "advanced-thruster-oxidizer"}, {replacement("recipe-prod-research_thruster_oxidizer_productivity-1", {"thruster-oxidizer", "advanced-thruster-oxidizer"})}, true),
  binding("sem-prfe_tungsten-carbide-productivity-1", 1, "tungsten-carbide", {"tungsten-carbide"}, {replacement("recipe-prod-research_tungsten-1", {"tungsten-carbide"})}, true),
  binding("sem-prfe_tungsten-plate-productivity-1", 1, "tungsten-steel", {"tungsten-plate"}, {replacement("recipe-prod-research_tungsten-1", {"tungsten-plate"})}, true),
  binding("sem-prfe_utility-science-pack-productivity-1", 1, "utility-science-pack", {"utility-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"utility-science-pack"})}, true),
}

-- The four F200 Space Age providers below are deliberately flat authored
-- groups. They have disjoint foreign identities and recipe effects, so exact
-- simultaneous groups compose without any arbitrary priority. EPR plus a
-- fixed Space Age provider has no admitted mixed contract.
local PLATES_BINDINGS = {
  binding("basic-plate-productivity", 1, "advanced-material-processing", {"copper-plate", "iron-plate"}, {
    replacement("recipe-prod-research_copper-1", {"copper-plate"}),
    replacement("recipe-prod-research_iron-1", {"iron-plate"}),
  }, true),
  binding("electric-circuit-productivity", 1, "automation-2", {"electronic-circuit"}, {
    replacement("recipe-prod-research_electronic_circuit-1", {"electronic-circuit"}),
  }, true),
  binding("advanced-circuit-productivity", 1, "chemical-science-pack", {"advanced-circuit"}, {
    replacement("recipe-prod-research_advanced_circuit-1", {"advanced-circuit"}),
  }, true),
}

local SCIENCE_PACK_BINDINGS = {
  binding("automation-science-productivity-4", 4, "automation-science-productivity-3", {"automation-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"automation-science-pack"})}),
  binding("logistic-science-productivity-4", 4, "logistic-science-productivity-3", {"logistic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"logistic-science-pack"})}),
  binding("military-science-productivity-4", 4, "military-science-productivity-3", {"military-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"military-science-pack"})}),
  binding("chemical-science-productivity-4", 4, "chemical-science-productivity-3", {"chemical-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"chemical-science-pack"})}),
  binding("production-science-productivity-4", 4, "production-science-productivity-3", {"production-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"production-science-pack"})}),
  binding("utility-science-productivity-4", 4, "utility-science-productivity-3", {"utility-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"utility-science-pack"})}),
  binding("space-science-productivity-4", 4, "space-science-productivity-3", {"space-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"space-science-pack"})}),
  binding("metallurgic-science-productivity-4", 4, "metallurgic-science-productivity-3", {"metallurgic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"metallurgic-science-pack"})}),
  binding("electromagnetic-science-productivity-4", 4, "electromagnetic-science-productivity-3", {"electromagnetic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"electromagnetic-science-pack"})}),
  binding("agricultural-science-productivity-4", 4, "agricultural-science-productivity-3", {"agricultural-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"agricultural-science-pack"})}),
  binding("cryogenic-science-productivity-4", 4, "cryogenic-science-productivity-3", {"cryogenic-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"cryogenic-science-pack"})}),
  binding("promethium-science-productivity-4", 4, "promethium-science-productivity-3", {"promethium-science-pack"}, {replacement("recipe-prod-research_science_pack_productivity-1", {"promethium-science-pack"})}),
}

local BIOFLUX_BINDINGS = {
  binding("bioflux-productivity", 1, "bioflux", {"bioflux"}, {
    replacement("recipe-prod-research_bioflux-1", {"bioflux"}),
  }, true),
}

local FISH_BINDINGS = {
  binding("fish-breeding-productivity", 1, "fish-breeding", {"fish-breeding"}, {
    replacement("recipe-prod-research_breeding-1", {"fish-breeding"}),
  }, true),
}

-- These two exact providers were independently observed to have no default
-- replacement removals. They remain non-admissions, and their presence keeps
-- an otherwise selected dynamic profile out of an unqualified co-owner mix.
local UNQUALIFIED_DYNAMIC_PROVIDERS = {
  "ProductivityResearchForEveryone",
  "ProductivityResearchForEveryoneFG",
}

local PROFILES = {
  {key = "epr-base-f200", provider = PROVIDER, version = PROVIDER_VERSION, bindings = EPR_BINDINGS},
  {key = "crafting-efficiency-f200-space-age", provider = "crafting-efficiency-2", version = "0.2.20", space_age = true, dynamic = true, bindings = CRAFTING_EFFICIENCY_BINDINGS},
  {key = "productivity-research-f200-space-age", provider = "ProductivityResearch", version = "1.3.2", space_age = true, dynamic = true, bindings = PRODUCTIVITY_RESEARCH_BINDINGS},
  {key = "plates-f200-space-age", provider = "plates-n-circuit-productivity", version = "0.0.2", space_age = true, bindings = PLATES_BINDINGS},
  {key = "science-packs-f200-space-age", provider = "Science_packs_productivity", version = "0.0.1", space_age = true, bindings = SCIENCE_PACK_BINDINGS},
  {key = "bioflux-f200-space-age", provider = "bioflux-productivity", version = "0.1.0", space_age = true, bindings = BIOFLUX_BINDINGS},
  {key = "fish-f200-space-age", provider = "fish-productivity", version = "1.0.0", space_age = true, bindings = FISH_BINDINGS},
}

local ALL_BINDINGS = {}
for _, profile in ipairs(PROFILES) do
  for _, item in ipairs(profile.bindings) do ALL_BINDINGS[#ALL_BINDINGS + 1] = item end
end

local function selected_profiles(active_mods, target)
  if type(active_mods) ~= "table" or type(target) ~= "table"
      or target.id ~= "f200" or target.factorio_version ~= "2.0" or active_mods.base ~= BASE_VERSION then
    return nil
  end
  local epr, fixed, dynamic = nil, {}, {}
  for _, profile in ipairs(PROFILES) do
    local actual = active_mods[profile.provider]
    if actual ~= nil then
      if actual ~= profile.version then return nil end
      if profile.dynamic == true then
        if active_mods["space-age"] ~= BASE_VERSION then return nil end
        dynamic[#dynamic + 1] = profile
      elseif profile.space_age == true then
        if active_mods["space-age"] ~= BASE_VERSION then return nil end
        fixed[#fixed + 1] = profile
      else
        epr = profile
      end
    end
  end
  if #dynamic ~= 0 then
    -- Each dynamic provider has only an individual captured profile. A mixed
    -- dynamic or fixed/EPR closure has no named native contract yet.
    if #dynamic ~= 1 or epr ~= nil or #fixed ~= 0 then return nil end
    for _, provider in ipairs(UNQUALIFIED_DYNAMIC_PROVIDERS) do
      if active_mods[provider] ~= nil then return nil end
    end
    return dynamic
  end
  if epr ~= nil then
    if #fixed ~= 0 then return nil end
    return {epr}
  end
  if #fixed == 0 then return nil end
  return fixed
end

local function close(actual, expected)
  return type(actual) == "number" and type(expected) == "number"
    and math.abs(actual - expected) <= 0.00000001
end

local function runtime_exact_effects(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  local expected_by_recipe, seen = {}, {}
  for _, effect in ipairs(expected) do expected_by_recipe[effect.recipe] = effect.change end
  for _, effect in ipairs(actual) do
    local wanted = type(effect) == "table" and expected_by_recipe[effect.recipe] or nil
    if not wanted or effect.type ~= "change-recipe-productivity" or not close(effect.change, wanted)
        or seen[effect.recipe] then
      return false
    end
    seen[effect.recipe] = true
  end
  return true
end

local function runtime_includes_effects(actual, required)
  if type(actual) ~= "table" then return false end
  local found = {}
  for _, effect in ipairs(actual) do
    if type(effect) == "table" and effect.type == "change-recipe-productivity"
        and effect.recipe ~= nil then
      found[effect.recipe] = effect.change
    end
  end
  for _, effect in ipairs(required) do
    if not close(found[effect.recipe], effect.change) then return false end
  end
  return true
end

function M.select(active_mods, target)
  local profiles = selected_profiles(active_mods, target)
  if profiles == nil then return nil end
  local bindings, providers = {}, {}
  for _, profile in ipairs(profiles) do
    providers[#providers + 1] = {name = profile.provider, version = profile.version, key = profile.key}
    for _, item in ipairs(profile.bindings) do bindings[#bindings + 1] = item end
  end
  return {provider = providers[1].name, provider_version = providers[1].version,
    providers = providers, base_version = BASE_VERSION, effect_change = EFFECT, bindings = bindings}
end

function M.active(active_mods, target)
  if type(active_mods) ~= "table" or type(target) ~= "table" or target.id ~= "f200" then return false end
  for _, profile in ipairs(PROFILES) do
    if active_mods[profile.provider] ~= nil then return true end
  end
  return false
end

function M.bindings()
  return ALL_BINDINGS
end

function M.runtime_effects_match(actual, expected)
  return runtime_exact_effects(actual, expected)
end

function M.runtime_effects_include(actual, expected)
  return runtime_includes_effects(actual, expected)
end

local function data_predecessor_matches(foreign, item)
  local prerequisites = foreign.prerequisites
  if item.predecessor == NO_PREDECESSOR then
    -- Data raw omits an empty prerequisite array. A present non-empty array
    -- is a changed native identity and cannot receive this narrow binding.
    return prerequisites == nil or (type(prerequisites) == "table" and next(prerequisites) == nil)
  end
  if type(prerequisites) ~= "table" then return false end
  for _, name in ipairs(prerequisites) do
    if name == item.predecessor then return true end
  end
  return false
end

-- Edit only detached MIR effects for the flat, named foreign-owner bindings.
-- Kept foreign coverage excludes future MIR increments without removing IDs.
function M.retain_foreign_coverage(technologies, raw, active_mods, selected_target, prefer_mir)
  local contract = M.select(active_mods, selected_target)
  if contract == nil then return end
  local owned, effect_indexes, excluded = {}, {}, {}
  for _, row in ipairs(technologies) do owned[row.name] = row end
  local function effect_index(row)
    local found = {}
    for _, effect in ipairs(row.effects or {}) do
      if effect.type == "change-recipe-productivity" then found[effect.recipe] = effect.change end
    end
    return found
  end
  local function replacement_index(name)
    if effect_indexes[name] == nil then
      local row = owned[name]
      effect_indexes[name] = row and effect_index(row) or false
    end
    return effect_indexes[name]
  end
  for _, item in ipairs(contract.bindings) do
    local foreign = raw.technology and raw.technology[item.id]
    if foreign and foreign.type == "technology" and foreign.name == item.id
        and foreign.enabled ~= false and foreign.max_level == "infinite"
        and (foreign.level == nil or foreign.level == item.first_level)
        and data_predecessor_matches(foreign, item) then
      local replace = prefer_mir == true and runtime_exact_effects(foreign.effects, item.effects)
      if replace then
        for _, replacement in ipairs(item.replacements) do
          local row, index = owned[replacement.id], replacement_index(replacement.id)
          if not row or row.enabled == false or row.level ~= replacement.first_level
              or row.max_level ~= "infinite" then
            replace = false
            break
          end
          for _, effect in ipairs(replacement.effects) do
            if not index or not close(index[effect.recipe], effect.change) then replace = false; break end
          end
          if not replace then break end
        end
      end
      if not replace then
        local foreign_effects = effect_index(foreign)
        for _, replacement in ipairs(item.replacements) do
          if owned[replacement.id] then
            for _, effect in ipairs(replacement.effects) do
              local value = foreign_effects[effect.recipe]
              if type(value) == "number" and value > 0 and value < math.huge then
                excluded[replacement.id] = excluded[replacement.id] or {}
                excluded[replacement.id][effect.recipe] = true
              end
            end
          end
        end
      end
    end
  end
  for _, row in ipairs(technologies) do
    local recipes = excluded[row.name]
    if recipes then
      local effects = {}
      for _, effect in ipairs(row.effects or {}) do
        if effect.type ~= "change-recipe-productivity" or not recipes[effect.recipe] then
          effects[#effects + 1] = effect
        end
      end
      row.effects = effects
      if #effects == 0 then row.enabled = false end
    end
  end
end

return M
