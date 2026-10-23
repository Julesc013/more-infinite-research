-- Exact F200 binding for Expanded Productivity Research 1.3.8.
--
-- These declarations retain the thirty published competing tails as foreign
-- technologies.  They only name the proved one-to-one (or explicitly split)
-- productivity coverage that can be capped at runtime; no recipe or
-- technology discovery is performed here.
local M = {}

local PROVIDER = "ExpandedProductivityResearch"
local PROVIDER_VERSION = "1.3.8"
local BASE_VERSION = "2.0.77"
local EFFECT = 0.1

local function effects(recipes)
  local out = {}
  for index = 1, #recipes do out[index] = {recipe = recipes[index], change = EFFECT} end
  return out
end

local function replacement(id, recipes)
  return {id = id, effects = effects(recipes)}
end

local function binding(id, first_level, predecessor, recipes, replacements)
  return {
    id = id,
    first_level = first_level,
    predecessor = predecessor,
    effects = effects(recipes),
    replacements = replacements,
  }
end

local BINDINGS = {
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

local function exact_profile(active_mods, target)
  return type(active_mods) == "table" and type(target) == "table"
    and target.id == "f200" and target.factorio_version == "2.0"
    and active_mods.base == BASE_VERSION and active_mods[PROVIDER] == PROVIDER_VERSION
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
  if not exact_profile(active_mods, target) then return nil end
  return {provider = PROVIDER, provider_version = PROVIDER_VERSION, base_version = BASE_VERSION,
    effect_change = EFFECT, bindings = BINDINGS}
end

function M.active(active_mods, target)
  return type(active_mods) == "table" and type(target) == "table"
    and target.id == "f200" and active_mods[PROVIDER] ~= nil
end

function M.bindings()
  return BINDINGS
end

function M.runtime_effects_match(actual, expected)
  return runtime_exact_effects(actual, expected)
end

function M.runtime_effects_include(actual, expected)
  return runtime_includes_effects(actual, expected)
end

return M
