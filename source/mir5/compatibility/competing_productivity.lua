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

local PROFILES = {
  {key = "epr-base-f200", provider = PROVIDER, version = PROVIDER_VERSION, bindings = EPR_BINDINGS},
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
  local epr, fixed = nil, {}
  for _, profile in ipairs(PROFILES) do
    local actual = active_mods[profile.provider]
    if actual ~= nil then
      if actual ~= profile.version then return nil end
      if profile.space_age == true then
        if active_mods["space-age"] ~= BASE_VERSION then return nil end
        fixed[#fixed + 1] = profile
      else
        epr = profile
      end
    end
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
    local previous = false
    for _, name in ipairs(foreign and foreign.prerequisites or {}) do
      if name == item.predecessor then previous = true end
    end
    if foreign and foreign.type == "technology" and foreign.name == item.id
        and foreign.enabled ~= false and foreign.max_level == "infinite"
        and (foreign.level == nil or foreign.level == item.first_level) and previous then
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
