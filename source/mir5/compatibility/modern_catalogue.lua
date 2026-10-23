-- Explicit F210 base and Space Age selection for the delivered modern catalogue.
-- The Space Age delta remains in its own module: a base stage never imports or
-- constructs its definitions, recipe patches, or continuation changes.
local M = {}

local BASE = require("compatibility.modern_catalogue.base")

local SCIENCE = {
  science_automation_logistic_chemical_production = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
  science_automation_logistic_chemical_production_military = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack"},
  science_utility_military = {"utility-science-pack", "military-science-pack"},
  science_automation_logistic_military_chemical_production_utility = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"},
  science_automation_logistic_chemical_production_electromagnetic = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "electromagnetic-science-pack"},
  science_automation_logistic_chemical_production_agricultural_space = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "agricultural-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_agricultural_cryogenic = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "agricultural-science-pack", "cryogenic-science-pack"},
  science_automation_logistic_chemical_production_space = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_agricultural = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "agricultural-science-pack"},
  science_automation_logistic_chemical_production_military_space = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_military_electromagnetic = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "electromagnetic-science-pack"},
  science_automation_logistic_chemical_production_military_agricultural = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "agricultural-science-pack"},
  science_automation_logistic_chemical_production_military_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"},
  science_utility_military_agricultural_electromagnetic = {"utility-science-pack", "military-science-pack", "agricultural-science-pack", "electromagnetic-science-pack"},
  science_utility_military_agricultural_cryogenic = {"utility-science-pack", "military-science-pack", "agricultural-science-pack", "cryogenic-science-pack"},
  science_automation_logistic_chemical_production_metallurgic = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "metallurgic-science-pack"},
  science_automation_logistic_chemical_production_military_metallurgic_space = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "metallurgic-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_space_cryogenic = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack", "cryogenic-science-pack"},
  science_utility_military_agricultural = {"utility-science-pack", "military-science-pack", "agricultural-science-pack"},
  science_automation_logistic_chemical_production_metallurgic_space = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "metallurgic-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_cryogenic = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "cryogenic-science-pack"},
  science_automation_logistic_chemical_production_agricultural_military = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "agricultural-science-pack", "military-science-pack"},
  science_automation_logistic_chemical_production_space_agricultural = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack", "agricultural-science-pack"},
  science_automation_logistic_chemical_production_utility = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"},
  science_automation_logistic_chemical_production_military_utility = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "utility-science-pack"},
  science_automation_logistic_chemical_production_utility_space = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_utility_agricultural = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "agricultural-science-pack"},
  science_automation_logistic_chemical_production_utility_military_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "military-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"},
  science_automation_logistic_chemical_production_military_utility_space = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "utility-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_utility_electromagnetic = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "electromagnetic-science-pack"},
  science_automation_logistic_chemical_military_utility = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack", "utility-science-pack"},
  science_automation_logistic_chemical_military_utility_space = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack", "utility-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_utility_military = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "military-science-pack"},
  science_production_agricultural_space = {"production-science-pack", "agricultural-science-pack", "space-science-pack"},
  science_production_space = {"production-science-pack", "space-science-pack"},
  science_production_space_agricultural = {"production-science-pack", "space-science-pack", "agricultural-science-pack"},
  science_production_metallurgic_space = {"production-science-pack", "metallurgic-science-pack", "space-science-pack"},
  science_production_space_cryogenic = {"production-science-pack", "space-science-pack", "cryogenic-science-pack"},
  science_production_utility_space = {"production-science-pack", "utility-science-pack", "space-science-pack"},
  science_utility_space = {"utility-science-pack", "space-science-pack"},
  science_production_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium = {"production-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"},
  science_production_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium_k2 = {"production-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", "kr-advanced-tech-card", "kr-matter-tech-card", "kr-singularity-tech-card"}
}

-- These are declared continuations of the six named native chains. They are
-- not a discovery list: predecessor, effects, and stage-specific science are
-- each authored and checked at the Generator write boundary.
local CONTINUATIONS = {
  {
    key = "braking_force",
    id = "braking-force-8",
    family = "braking-force",
    setting_key = "braking-force",
    level = 8,
    predecessor = "braking-force-7",
    prerequisites = {"braking-force-6", "braking-force-7"},
    science = "science_automation_logistic_chemical_production_utility",
    effects = {
      {
        type = "train-braking-force-bonus",
        scale = 1,
      },
    },
    icon = "__base__/graphics/technology/braking-force.png",
    overlay = "__core__/graphics/icons/technology/constants/constant-braking-force.png",
    localised_name = "technology-name.braking-force",
    localised_description = "technology-description.braking-force",
    defaults = {
      base_cost = 115,
      effect_percent = 15,
      enabled = true,
      growth_factor = 1.333333333333,
      linear_increment = 0,
      max_level = 0,
      research_time = 60,
    },
    formula = {
      coefficient = "861.51212960553",
      growth = "1.33333",
    },
    inheritance = {
      last_count = 650,
      previous_count = 550,
      research_time = 60,
    },
    setting_order = "b-050-braking-force-base-braking-force-",
    source = "base-continuation",
    operation = "emit_base_extension",
  },
  {
    key = "inserter_capacity_bonus",
    id = "inserter-capacity-bonus-8",
    family = "inserter-capacity-bonus",
    setting_key = "inserter-capacity-bonus",
    level = 8,
    predecessor = "inserter-capacity-bonus-7",
    prerequisites = {"inserter-capacity-bonus-6", "utility-science-pack", "inserter-capacity-bonus-7"},
    science = "science_automation_logistic_chemical_production_utility",
    effects = {
      {
        type = "inserter-stack-size-bonus",
        scale = 0.5,
      },
      {
        type = "bulk-inserter-capacity-bonus",
        scale = 1,
      },
    },
    icon = "__base__/graphics/technology/inserter-capacity.png",
    overlay = "__core__/graphics/icons/technology/constants/constant-capacity.png",
    localised_name = "technology-name.inserter-capacity-bonus",
    localised_description = {
      "",
      {"technology-description.inserter-capacity-bonus"},
      "\n\n",
      {"mod-setting-description.mir-note-inserter-capacity"},
    },
    setting_notes = {
      enabled = {"mod-setting-description.mir-note-inserter-capacity"},
    },
    defaults = {
      base_cost = 200,
      effect_percent = 4,
      enabled = true,
      growth_factor = 3.333333333333,
      linear_increment = 0,
      max_level = 0,
      research_time = 60,
    },
    formula = {
      coefficient = "914488.340211249",
      growth = "3.33333",
    },
    inheritance = {
      last_count = 600,
      previous_count = 400,
      research_time = 60,
    },
    setting_order = "b-000-inserter-capacity-bonus-base-inserter-capacity-bonus-",
    source = "base-continuation",
    operation = "emit_base_extension",
  },
  {
    key = "laser_shooting_speed",
    id = "laser-shooting-speed-8",
    family = "laser-shooting-speed",
    setting_key = "laser-shooting-speed",
    level = 8,
    predecessor = "laser-shooting-speed-7",
    prerequisites = {"laser-shooting-speed-6", "laser-shooting-speed-7"},
    science = "science_automation_logistic_chemical_military_utility",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "laser",
        scale = 1,
      },
    },
    icon = "__base__/graphics/technology/laser-shooting-speed.png",
    overlay = "__core__/graphics/icons/technology/constants/constant-speed.png",
    localised_name = "technology-name.laser-shooting-speed",
    localised_description = "technology-description.laser-shooting-speed",
    defaults = {
      base_cost = 60,
      effect_percent = 50,
      enabled = true,
      growth_factor = 1.5,
      linear_increment = 0,
      max_level = 0,
      research_time = 120,
    },
    formula = {
      coefficient = "1025.15625",
      growth = "1.5",
    },
    inheritance = {
      last_count = 450,
      previous_count = 350,
      research_time = 60,
    },
    setting_order = "b-050-laser-shooting-speed-base-laser-shooting-speed-",
    source = "base-continuation",
    operation = "emit_base_extension",
  },
  {
    key = "research_speed",
    id = "research-speed-7",
    family = "research-speed",
    setting_key = "research-speed",
    level = 7,
    predecessor = "research-speed-6",
    prerequisites = {"research-speed-5", "utility-science-pack", "research-speed-6"},
    science = "science_automation_logistic_chemical_production_utility_military",
    effects = {
      {
        type = "laboratory-speed",
        scale = 1,
      },
    },
    icon = "__base__/graphics/technology/research-speed.png",
    overlay = "__core__/graphics/icons/technology/constants/constant-speed.png",
    localised_name = "technology-name.research-speed",
    localised_description = "technology-description.research-speed",
    defaults = {
      base_cost = 60,
      effect_percent = 60,
      enabled = true,
      growth_factor = 1.5,
      linear_increment = 0,
      max_level = 0,
      research_time = 120,
    },
    formula = {
      coefficient = "683.4375",
      growth = "1.5",
    },
    inheritance = {
      last_count = 500,
      previous_count = 500,
      research_time = 60,
    },
    setting_order = "b-050-lab-research-speed-base-research-speed-",
    source = "base-continuation",
    operation = "emit_base_extension",
  },
  {
    key = "weapon_shooting_speed",
    id = "weapon-shooting-speed-7",
    family = "weapon-shooting-speed",
    setting_key = "weapon-shooting-speed",
    level = 7,
    predecessor = "weapon-shooting-speed-6",
    prerequisites = {"weapon-shooting-speed-5", "utility-science-pack", "weapon-shooting-speed-6"},
    science = "science_automation_logistic_chemical_military_utility",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "bullet",
        scale = 1,
      },
      {
        type = "gun-speed",
        ammo_category = "shotgun-shell",
        scale = 1,
      },
    },
    icon = "__base__/graphics/technology/weapon-shooting-speed-3.png",
    overlay = "__core__/graphics/icons/technology/constants/constant-speed.png",
    localised_name = "technology-name.weapon-shooting-speed",
    localised_description = "technology-description.weapon-shooting-speed",
    defaults = {
      base_cost = 60,
      effect_percent = 40,
      enabled = true,
      growth_factor = 1.5,
      linear_increment = 0,
      max_level = 0,
      research_time = 120,
    },
    formula = {
      coefficient = "683.4375",
      growth = "1.5",
    },
    inheritance = {
      last_count = 600,
      previous_count = 500,
      research_time = 60,
    },
    setting_order = "b-050-weapon-shooting-speed-base-weapon-shooting-speed-",
    source = "base-continuation",
    operation = "emit_base_extension",
  },
  {
    key = "worker_robots_storage",
    id = "worker-robots-storage-4",
    family = "worker-robots-storage",
    setting_key = "worker-robots-storage",
    level = 4,
    predecessor = "worker-robots-storage-3",
    prerequisites = {"worker-robots-storage-2", "utility-science-pack", "worker-robots-storage-3"},
    science = "science_automation_logistic_chemical_production_utility",
    effects = {
      {
        type = "worker-robot-storage",
        scale = 1,
      },
    },
    icon = "__base__/graphics/technology/worker-robots-storage.png",
    overlay = "__core__/graphics/icons/technology/constants/constant-capacity.png",
    localised_name = "technology-name.worker-robots-storage",
    localised_description = "technology-description.worker-robots-storage",
    defaults = {
      base_cost = 200,
      effect_percent = 1,
      enabled = true,
      growth_factor = 1.5,
      linear_increment = 0,
      max_level = 0,
      research_time = 60,
    },
    formula = {
      coefficient = "675",
      growth = "1.5",
    },
    inheritance = {
      last_count = 450,
      previous_count = 300,
      research_time = 60,
    },
    setting_order = "b-050-worker-robot-cargo-size-base-worker-robots-storage-",
    source = "base-continuation",
    operation = "emit_base_extension",
  },
}

local function copy(value, seen)
  local kind = type(value)
  if kind ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR modern catalogue contains a cycle", 3) end
  seen[value] = true
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item, seen) end
  seen[value] = nil
  return result
end

local function active_space_age(active_mods)
  return type(active_mods) == "table" and active_mods["space-age"] ~= nil
end

-- K2SO is an exact delivered tuple, not a broad Krastorio assumption. Keep
-- this gate here so inactive profiles never construct the K2SO body.
function M.is_k2so(active_mods)
  if not active_space_age(active_mods) then return false end
  return active_mods.Krastorio2 ~= nil and active_mods["Krastorio2-spaced-out"] ~= nil
    and active_mods.Krastorio2Assets ~= nil and active_mods["k2so-assets"] ~= nil
end

local function copy_definitions(definitions)
  local out, by_key = {}, {}
  for index = 1, #definitions do
    local definition = copy(definitions[index])
    out[#out + 1], by_key[definition.key] = definition, definition
  end
  return out, by_key
end

local function apply_space_age(definitions, by_key)
  -- Required laziness: do not move this require above the active profile gate.
  local delta = require("compatibility.modern_catalogue.space_age")
  local omit = {}
  for index = 1, #delta.omit do omit[delta.omit[index]] = true end
  local selected, selected_by_key = {}, {}
  for index = 1, #definitions do
    local definition = definitions[index]
    if not omit[definition.key] then
      local changed = delta.overrides[definition.key]
      if changed then
        for key, value in pairs(changed) do definition[key] = copy(value) end
      end
      selected[#selected + 1], selected_by_key[definition.key] = definition, definition
    end
  end
  for index = 1, #delta.additions do
    local definition = copy(delta.additions[index])
    if selected_by_key[definition.key] then error("MIR duplicate Space Age catalogue key " .. definition.key, 3) end
    selected[#selected + 1], selected_by_key[definition.key] = definition, definition
  end
  return selected, delta
end

local function apply_k2so(definitions, by_key)
  -- Required laziness: only an exact K2SO profile creates this map.
  local delta = require("compatibility.modern_catalogue.k2so")
  local selected_by_key = {}
  for index = 1, #definitions do selected_by_key[definitions[index].key] = definitions[index] end
  for key, changed in pairs(delta.definition_overrides) do
    local definition = selected_by_key[key]
    if not definition then error("MIR K2SO catalogue lacks declared key " .. key, 3) end
    for field, value in pairs(changed) do definition[field] = copy(value) end
  end
  return delta
end

function M.science_names(key)
  local vector = SCIENCE[key]
  if type(vector) ~= "table" then error("MIR unknown authored science vector " .. tostring(key), 2) end
  local out = {}
  for index = 1, #vector do out[index] = vector[index] end
  return out
end

function M.science_ingredients(key)
  local names = M.science_names(key)
  local out = {}
  for index = 1, #names do out[index] = {names[index], 1} end
  return out
end

function M.select(active_mods)
  local definitions, by_key = copy_definitions(BASE.definitions)
  local recipe_patches = {}
  local profile, k2so = "base", nil
  if active_space_age(active_mods) then
    local delta
    definitions, delta = apply_space_age(definitions, by_key)
    for index = 1, #delta.recipe_patches do recipe_patches[index] = delta.recipe_patches[index] end
    profile = "space-age"
  end
  if M.is_k2so(active_mods) then
    k2so = apply_k2so(definitions, by_key)
    profile = "k2so-f210"
  end
  return {profile = profile, definitions = definitions, continuations = M.continuations(active_mods),
    native_owners = M.native_owners(active_mods), recipe_patches = recipe_patches,
    k2_imersite = k2so and k2so.imersite or false}
end

-- Settings preserve their historical names across target selection. Space Age
-- does not delete a base stream's setting merely because the emitted row is an
-- admitted native owner there; it only adds its own authored stream settings.
function M.setting_definitions(active_mods)
  local definitions = copy_definitions(BASE.definitions)
  if active_space_age(active_mods) then
    local delta = require("compatibility.modern_catalogue.space_age")
    for index = 1, #delta.additions do definitions[#definitions + 1] = copy(delta.additions[index]) end
  end
  return definitions
end

function M.continuations(active_mods)
  local rows = copy(CONTINUATIONS)
  local overrides = {}
  if active_space_age(active_mods) then
    for key, value in pairs(require("compatibility.modern_catalogue.space_age").continuation_overrides or {}) do
      overrides[key] = value
    end
  end
  if M.is_k2so(active_mods) then
    for key, value in pairs(require("compatibility.modern_catalogue.k2so").continuation_overrides or {}) do
      overrides[key] = value
    end
  end
  for index = 1, #rows do
    local changed = overrides[rows[index].key]
    if changed then for key, value in pairs(changed) do rows[index][key] = copy(value) end end
  end
  return rows
end

function M.native_owners(active_mods)
  if M.is_k2so(active_mods) then return copy(require("compatibility.modern_catalogue.k2so").native_owners) end
  if not active_space_age(active_mods) then return {} end
  return copy(require("compatibility.modern_catalogue.space_age").native_owners)
end

return M
