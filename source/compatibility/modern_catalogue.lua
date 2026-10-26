-- Explicit Base/Space Age selection and narrow K2 profile gates for the delivered modern catalogue.
-- The Space Age delta remains in its own module: a base stage never imports or
-- constructs its definitions, recipe patches, or continuation changes.
local M = {}
local target = require("platform.target")

-- These two native modifiers were added in the selected 2.1 engine family.
-- Their absence on 2.0 is an actual capability boundary, not a disabled row.
function M.supports_family(key)
  return target.cargo_research == true
    or (key ~= "research_cargo_landing_pad_count" and key ~= "research_cargo_bay_unloading_distance")
end

local function supported_definitions(definitions)
  if target.cargo_research == true then return definitions end
  local out = {}
  for _, definition in ipairs(definitions) do
    if M.supports_family(definition.key) then
      if target.id == "f200" and definition.key == "research_molten_metals" then
        -- Published 2.0 research targets the two lava recipes only. The ore
        -- recipes entered this authored stream on 2.1; do not add new 2.0
        -- bonuses merely because another producer has the same fluid output.
        local effects = {}
        for _, effect in ipairs(definition.effects) do
          if effect.recipe ~= "copper-ore-melting" and effect.recipe ~= "iron-ore-melting" then
            effects[#effects + 1] = effect
          end
        end
        definition.effects = effects
      end
      out[#out + 1] = definition
    end
  end
  return out
end

local BASE = require("compatibility.modern_catalogue.base")

local SCIENCE = {
  science_automation_logistic = {"automation-science-pack", "logistic-science-pack"},
  science_automation_logistic_chemical = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
  science_automation_logistic_chemical_agricultural = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "agricultural-science-pack"},
  science_automation_logistic_military = {"automation-science-pack", "logistic-science-pack", "military-science-pack"},
  science_military = {"military-science-pack"},
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
  science_automation_logistic_military_chemical_production_utility_space = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_utility_space = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"},
  science_automation_logistic_chemical_production_military_utility_space_py = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "utility-science-pack", "space-science-pack", "py-science-pack-1", "py-science-pack-2", "py-science-pack-3", "py-science-pack-4"},
  -- The named Py continuation bindings retain their captured order and
  -- nonuniform ingredient counts.  They remain vector identities so science
  -- policy can remove or add packs against the generated native row.
  science_py_coal = {"utility-science-pack", "production-science-pack", "chemical-science-pack", "logistic-science-pack", "automation-science-pack", "military-science-pack"},
  science_py_hightech = {"utility-science-pack", "py-science-pack-4", "production-science-pack", "py-science-pack-3", "chemical-science-pack", "py-science-pack-2", "logistic-science-pack", "py-science-pack-1", "automation-science-pack", "military-science-pack"},
  science_py_hightech_space = {"utility-science-pack", "py-science-pack-4", "production-science-pack", "py-science-pack-3", "chemical-science-pack", "py-science-pack-2", "logistic-science-pack", "py-science-pack-1", "automation-science-pack", "military-science-pack", "space-science-pack"},
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
  science_production_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium_k2 = {"production-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", "kr-advanced-tech-card", "kr-matter-tech-card", "kr-singularity-tech-card"},
  -- Exact F210 no-Angel Bob Core vectors.  Each names the captured pack
  -- directly; no installed science-pack or lab pass decides this progression.
  science_bob_core_braking_force = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack", "bob-advanced-logistic-science-pack", "space-science-pack"},
  science_bob_core_inserter_capacity = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack", "bob-advanced-logistic-science-pack", "agricultural-science-pack"},
  science_bob_core_research_speed = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "military-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", "bob-advanced-logistic-science-pack"},
  science_bob_core_worker_robots_storage = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack", "bob-advanced-logistic-science-pack", "electromagnetic-science-pack"},
  science_bob_core_science_pack_productivity = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", "bob-advanced-logistic-science-pack"},
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

-- K2 without Spaced Out has a retained F200 Base admission and captured F210
-- Base, Space Exploration and Space Age inputs. They share the named K2 and
-- K2 Assets sources. Version strings are not consumed by this selector: the
-- named recipe and icon source are preflighted at data stage instead.
function M.is_k2_base(active_mods)
  if type(active_mods) ~= "table"
      or active_mods["Krastorio2-spaced-out"] ~= nil or active_mods["k2so-assets"] ~= nil then
    return false
  end
  if target.id == "f200" then
    return not active_space_age(active_mods)
      and active_mods.Krastorio2 ~= nil and active_mods.Krastorio2Assets ~= nil
  end
  if target.id == "f210" then
    return active_mods.Krastorio2 ~= nil and active_mods.Krastorio2Assets ~= nil
  end
  return false
end

function M.is_space_exploration(active_mods)
  return target.id == "f210" and type(active_mods) == "table"
    and active_mods["space-exploration"] ~= nil and not active_space_age(active_mods)
    and active_mods["Krastorio2-spaced-out"] == nil and active_mods["k2so-assets"] == nil
end

-- Bob Logistics authors these named infinite native tails in its data stage.
-- Its ownership does not depend on the rest of the Bob/Angel selection.
function M.retains_bob_native_continuations(active_mods)
  return target.id == "f210" and type(active_mods) == "table" and active_mods.boblogistics ~= nil
end

local function space_exploration_deltas(active_mods)
  if not M.is_space_exploration(active_mods) then return nil end
  local base = require("compatibility.modern_catalogue.space_exploration")
  local extra = M.is_k2_base(active_mods)
    and require("compatibility.modern_catalogue.k2_space_exploration") or nil
  return base, extra
end

local function apply_authored_definitions(definitions, delta)
  local by_key = {}
  for _, definition in ipairs(definitions) do by_key[definition.key] = definition end
  for key, fields in pairs(delta.definition_overrides or {}) do
    local definition = assert(by_key[key], "MIR authored profile lacks definition " .. key)
    for field, value in pairs(fields) do definition[field] = copy(value) end
    if fields.prerequisites ~= nil then definition.exact_prerequisites = true end
  end
  for _, addition in ipairs(delta.additions or {}) do
    assert(by_key[addition.key] == nil, "MIR authored profile duplicates definition " .. addition.key)
    local definition = copy(addition)
    definition.exact_prerequisites = true
    definitions[#definitions + 1], by_key[definition.key] = definition, definition
  end
end

-- K2SO is an exact delivered tuple, not a broad Krastorio assumption. Keep
-- this gate here so inactive profiles never construct the K2SO body.
function M.is_k2so(active_mods)
  if not active_space_age(active_mods) then return false end
  return active_mods.Krastorio2 ~= nil and active_mods["Krastorio2-spaced-out"] ~= nil
    and active_mods.Krastorio2Assets ~= nil and active_mods["k2so-assets"] ~= nil
end

local function copy_definitions(definitions)
  local out = {}
  for index = 1, #definitions do
    out[index] = copy(definitions[index])
  end
  return out
end

local function apply_space_age(definitions)
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

local function apply_k2so(definitions)
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

local function apply_k2_base(definitions)
  -- Exact F200 K2 Base presentation only; never import the K2SO body here.
  local delta = require("compatibility.modern_catalogue.k2_base")
  local selected_by_key = {}
  for index = 1, #definitions do selected_by_key[definitions[index].key] = definitions[index] end
  for key, changed in pairs(delta.definition_overrides or {}) do
    local definition = selected_by_key[key]
    if not definition then error("MIR K2 Base catalogue lacks declared key " .. key, 3) end
    for field, value in pairs(changed) do definition[field] = copy(value) end
  end
  return delta
end

function M.is_bob_angel(active_mods)
  if type(active_mods) ~= "table" or not active_mods.bobplates or not active_mods.angelssmelting then return false end
  return require("compatibility.bob_angel_profile").applies(active_mods)
end

function M.is_bob_core(active_mods)
  return require("compatibility.bob_core_profile").applies(active_mods)
end

local function apply_bob_angel(definitions)
  local delta = require("compatibility.modern_catalogue.bob_angel")
  for _, definition in ipairs(delta.additions) do definitions[#definitions + 1] = copy(definition) end
  for _, definition in ipairs(definitions) do
    for field, value in pairs(delta.definition_overrides[definition.key] or {}) do definition[field] = copy(value) end
    local science = delta.science[definition.science]
    assert(science, "MIR Bob/Angel has no authored ordinary science for " .. tostring(definition.science))
    definition.science = science
    if (science == "science_military" or science == "science_automation_logistic_military")
      and not delta.native_military_gates[definition.key] then
      table.insert(definition.prerequisites, 1, "angels-water-treatment")
    end
  end
end

local function apply_bob_core(definitions)
  local delta = require("compatibility.modern_catalogue.bob_core")
  local selected_by_key = {}
  for index = 1, #definitions do selected_by_key[definitions[index].key] = definitions[index] end
  for key, changed in pairs(delta.definition_overrides) do
    local definition = selected_by_key[key]
    if not definition then error("MIR Bob Core catalogue lacks declared key " .. key, 3) end
    for field, value in pairs(changed) do definition[field] = copy(value) end
  end
  return delta
end

local function apply_py_profile(definitions, delta, hightech)
  local selected, by_key = {}, {}
  for _, definition in ipairs(definitions) do
    if not delta.omitted_base_families[definition.key] then
      local changed = hightech and delta.hightech_definition_overrides[definition.key] or nil
      if changed then
        for field, value in pairs(changed) do definition[field] = copy(value) end
      end
      selected[#selected + 1], by_key[definition.key] = definition, definition
    end
  end
  return selected, by_key
end

local function apply_py_coal(definitions)
  local delta = require("compatibility.modern_catalogue.py")
  local selected = apply_py_profile(definitions, delta, false)
  return selected, copy(delta.coal_replacement_families), copy(delta.coal_excluded_recipes)
end

local function append_py_hightech(definitions, active_mods)
  local delta = require("compatibility.modern_catalogue.py")
  local selected, known = apply_py_profile(definitions, delta, true)
  for _, definition in ipairs(delta.definitions()) do
    if known[definition.key] then error("MIR duplicate Py HighTech catalogue key " .. definition.key, 3) end
    selected[#selected + 1], known[definition.key] = copy(definition), true
  end
  local required = delta.required_targets()
  local replacement, excluded = copy(delta.hightech_replacement_families), copy(delta.hightech_excluded_recipes)
  local exact_bindings, exact_families = {}, {}
  if target.id == "f210" then
    local current = require("compatibility.modern_catalogue.py_f210")
    for _, definition in ipairs(current.additions) do
      if known[definition.key] then error("MIR duplicate F210 Py catalogue key " .. definition.key, 3) end
      selected[#selected + 1], known[definition.key] = copy(definition), definition
    end
    for family, changed in pairs(current.retained_disabled_identities) do
      local definition = known[family]
      if type(definition) ~= "table" then error("MIR missing retained F210 Py identity " .. family, 3) end
      for field, value in pairs(changed) do definition[field] = copy(value) end
    end
    for _, recipe in ipairs(current.breeding_required_target_additions) do
      required.research_breeding[#required.research_breeding + 1] = recipe
    end
    local targets = copy(current.exact_product_targets)
    if active_mods[current.py_productivity.mod] ~= nil then
      for family, recipes in pairs(current.py_productivity.exact_product_targets) do targets[family] = copy(recipes) end
    end
    local families = {}
    for family in pairs(targets) do families[#families + 1] = family end
    table.sort(families)
    for _, family in ipairs(families) do
      local recipes = targets[family]
      exact_families[family], replacement[family], excluded[family] = true, true, nil
      required[family] = copy(recipes)
      exact_bindings[#exact_bindings + 1] = {family=family, weight=1, recipes=copy(recipes),
        include_recycling=true, allow_shared_input_output=true, reject_explicit_productivity_denial=true}
    end
  end
  return selected, required, delta.product_bindings(), replacement, excluded, exact_bindings, exact_families
end

local function append_bob_warfare(definitions, active_mods)
  local delta = require("compatibility.modern_catalogue.bob_warfare")
  for _, definition in ipairs(definitions) do
    if definition.key == delta.definition.key then
      error("MIR duplicate Bob Warfare catalogue key " .. delta.definition.key, 3)
    end
  end
  local definition = copy(delta.definition)
  if active_space_age(active_mods) then
    definition.science = "science_automation_logistic_chemical_production_military_metallurgic_space"
  end
  definitions[#definitions + 1] = definition
  return delta
end

local function copy_true_fields(destination, source)
  for key, value in pairs(source or {}) do
    if value ~= true then error("MIR modern catalogue has invalid selected family " .. tostring(key), 3) end
    destination[key] = true
  end
end

function M.science_names(key)
  local vector = SCIENCE[key]
  if vector == nil and type(key) == "string" then
    if key:match("^science_se_k2_") then
      vector = require("compatibility.modern_catalogue.k2_space_exploration").science[key]
    elseif key:match("^science_se_") then
      vector = require("compatibility.modern_catalogue.space_exploration").science[key]
    end
  end
  if type(vector) ~= "table" then error("MIR unknown authored science vector " .. tostring(key), 2) end
  local out = {}
  for index = 1, #vector do out[index] = vector[index] end
  return out
end

local function valid_science_amount(value)
  return type(value) == "number" and value == value and value >= 1
    and value == math.floor(value) and value < math.huge
end

-- Keep amounts coupled to the selected science vector.  An adapter may supply
-- weights for a broader sibling vector (for example its optional space pack),
-- but only names selected for this technology are emitted.  Policy later sees
-- ordinary native ingredients and retains these authored amounts.
function M.science_ingredients(key, amounts)
  local names = M.science_names(key)
  if amounts ~= nil and type(amounts) ~= "table" then
    error("MIR authored science amounts must be a table", 2)
  end
  local out = {}
  for index = 1, #names do
    local name = names[index]
    local amount = amounts and amounts[name] or 1
    if not valid_science_amount(amount) then
      error("MIR authored science amount is invalid for " .. name, 2)
    end
    out[index] = {name, amount}
  end
  return out
end

function M.select(active_mods)
  local definitions = copy_definitions(BASE.definitions)
  local recipe_patches = {}
  local profile, k2so = "base", nil
  local py = require("compatibility.py_profile").select(active_mods)
  local bob_warfare = require("compatibility.bob_warfare_profile").applies(active_mods)
  local bob_plates = require("compatibility.bob_plates_profile").select(active_mods)
  local required_product_targets, additional_product_bindings, exact_product_target_families = nil, nil, {}
  local exact_product_bindings = nil
  local replacement_product_target_families, excluded_product_target_recipes = {}, {}
  local k2_base = M.is_k2_base(active_mods)
  if k2_base then profile = target.id == "f200" and "k2-base-f200" or "k2-base-f210" end
  if (target.id == "f200" or target.id == "f210") and not active_space_age(active_mods) then
    -- This published F200 Base identity is also the required F210 Base
    -- continuity correction. Keep the single lazy authored tuple so its
    -- pre-Space-Age effects, settings family, and prototype ID stay identical.
    definitions[#definitions + 1] = {
      key="research_science_pack_productivity", family="research_science_pack_productivity", kind="productivity",
      science="science_automation_logistic_chemical_production_military_utility", prerequisites={},
      effects={{recipe="automation-science-pack",scale=1},{recipe="chemical-science-pack",scale=1},
        {recipe="logistic-science-pack",scale=1},{recipe="military-science-pack",scale=1},
        {recipe="production-science-pack",scale=1},{recipe="utility-science-pack",scale=1}},
      icon="__base__/graphics/technology/space-science-pack.png", icon_size=256,
      overlay="__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name={"technology-name.more-infinite-research.research_science_pack_productivity"},
      localised_description={"technology-description.more-infinite-research.recipe_productivity"},
      order="p[research_science_pack_productivity]",
    }
  end
  if active_space_age(active_mods) then
    local delta
    definitions, delta = apply_space_age(definitions)
    for index = 1, #delta.recipe_patches do recipe_patches[index] = delta.recipe_patches[index] end
    profile = "space-age"
  end
  if k2_base and target.id == "f200" then
    apply_k2_base(definitions)
  end
  if M.is_k2so(active_mods) then
    k2so = apply_k2so(definitions)
    profile = "k2so-f210"
  end
  local bob_angel = M.is_bob_angel(active_mods)
  if bob_angel then apply_bob_angel(definitions); profile = "bob-angel-f200" end
  local bob_core, bob_core_delta = M.is_bob_core(active_mods), nil
  if bob_core then bob_core_delta = apply_bob_core(definitions); profile = "bob-core-f210" end
  if py.coal then
    definitions, replacement_product_target_families, excluded_product_target_recipes = apply_py_coal(definitions)
    profile = "py-coal-f200"
  end
  if py.hightech then
    definitions, required_product_targets, additional_product_bindings,
      replacement_product_target_families, excluded_product_target_recipes,
      exact_product_bindings, exact_product_target_families = append_py_hightech(definitions, active_mods)
    profile = "py-hightech-" .. target.id
  end
  if bob_plates then
    local known = {}
    for _, definition in ipairs(definitions) do known[definition.key] = true end
    for _, definition in ipairs(require("research.bob_plates_materials").product_definitions(bob_plates)) do
      if known[definition.key] then error("MIR duplicate Bob Plates catalogue key " .. definition.key, 2) end
      definitions[#definitions + 1], known[definition.key] = definition, true
    end
    profile = "bob-plates-" .. bob_plates .. "-f210"
  end
  if bob_warfare then
    local delta = append_bob_warfare(definitions, active_mods)
    exact_product_target_families.research_armor_components = true
    exact_product_bindings = delta.product_bindings()
    -- Bob Warfare's captured bullets and rockets add named recipes to the
    -- ordinary Base families.  Rebuild each complete vector through the
    -- existing one-pass product collector so its weight-descending, then
    -- recipe-name presentation order matches the historical F200 output.
    -- The authored Base seeds and ratios remain the inputs to that rebuild.
    copy_true_fields(replacement_product_target_families, {
      research_armor_components=true,
      research_bullets=true,
      research_rockets=true,
    })
    profile = "bob-warfare-" .. target.id
  end
  local se, k2se = space_exploration_deltas(active_mods)
  if se then
    exact_product_bindings, required_product_targets = {}, {}
    local function apply(delta)
      apply_authored_definitions(definitions, delta)
      local kept = {}
      for _, binding in ipairs(exact_product_bindings) do
        if not delta.exact_product_target_families[binding.family] then kept[#kept + 1] = binding end
      end
      for _, binding in ipairs(delta.exact_product_bindings or {}) do kept[#kept + 1] = copy(binding) end
      exact_product_bindings = kept
      for family, recipes in pairs(delta.required_product_targets or {}) do required_product_targets[family] = copy(recipes) end
      copy_true_fields(exact_product_target_families, delta.exact_product_target_families or {})
      copy_true_fields(replacement_product_target_families, delta.replacement_product_target_families or {})
      copy_true_fields(excluded_product_target_recipes, delta.excluded_product_target_recipes or {})
    end
    apply(se)
    if k2se then apply(k2se) end
    profile = k2se and "k2-space-exploration-f210" or "space-exploration-f210"
  end
  -- The independently captured AAI Base/Space Age intersection changes only
  -- these two authored presentations. Keep it separate from SE/K2 semantics.
  if target.id == "f210" and active_mods["aai-industry"] ~= nil then
    for _, definition in ipairs(definitions) do
      if definition.key == "research_engine" then
        definition.icon = "__aai-industry__/graphics/technology/multi-cylinder-engine.png"
        definition.icon_size = 256
      elseif definition.key == "research_electric_engine" then
        definition.icon = "__aai-industry__/graphics/technology/electric-engine.png"
        definition.icon_size = 256
      end
    end
  end
  return {profile = profile, definitions = supported_definitions(definitions), continuations = M.continuations(active_mods),
    native_owners = M.native_owners(active_mods), recipe_patches = recipe_patches,
    k2_imersite = k2so and k2so.imersite or false,
    k2_imersite_carriers = target.id == "f210" and k2_base,
    bob_angel = bob_angel, bob_core = bob_core, bob_plates_profile = bob_plates,
    bob_native_continuations = M.retains_bob_native_continuations(active_mods),
    py_coal = py.coal, py_hightech = py.hightech, bob_warfare = bob_warfare,
    required_product_targets = required_product_targets, additional_product_bindings = additional_product_bindings,
    exact_product_bindings = exact_product_bindings,
    exact_product_target_families = exact_product_target_families,
    replacement_product_target_families = replacement_product_target_families,
    bob_core_progression = bob_core_delta ~= nil,
    excluded_product_target_recipes = excluded_product_target_recipes}
end

-- Settings preserve their historical names across target selection. Space Age
-- does not delete a base stream's setting merely because the emitted row is an
-- admitted native owner there; it only adds its own authored stream settings.
function M.setting_definitions(active_mods)
  local definitions = copy_definitions(BASE.definitions)
  local se = space_exploration_deltas(active_mods)
  if se then
    for _, definition in ipairs(se.additions or {}) do definitions[#definitions + 1] = copy(definition) end
  end
  if active_space_age(active_mods) then
    local delta = require("compatibility.modern_catalogue.space_age")
    for index = 1, #delta.additions do definitions[#definitions + 1] = copy(delta.additions[index]) end
  end
  return supported_definitions(definitions)
end

local function native_modded_continuations(active_mods)
  local py = require("compatibility.py_profile").select(active_mods)
  local bob_warfare = require("compatibility.bob_warfare_profile").applies(active_mods)
  if not py.coal and not py.hightech and not bob_warfare then return nil end
  return require("compatibility.native_modded_continuations")
end

local function merge_continuation_fields(destination, source, known_ids)
  if type(source) ~= "table" then error("MIR native continuation overrides are invalid", 3) end
  for id, fields in pairs(source) do
    if type(id) ~= "string" or known_ids[id] ~= true or type(fields) ~= "table" then
      error("MIR native continuation override names an unknown tail", 3)
    end
    local changed = destination[id] or {}
    for key, value in pairs(fields) do changed[key] = copy(value) end
    destination[id] = changed
  end
end

function M.continuations(active_mods)
  local rows = copy(CONTINUATIONS)
  if M.is_bob_angel(active_mods) then
    local science = require("compatibility.modern_catalogue.bob_angel").science
    for _, row in ipairs(rows) do row.science = assert(science[row.science]) end
  end
  local overrides, overrides_by_id = {}, {}
  local se, k2se = space_exploration_deltas(active_mods)
  if se then
    for key, fields in pairs(se.continuation_overrides or {}) do overrides[key] = copy(fields) end
    if k2se then
      for key, fields in pairs(k2se.continuation_overrides or {}) do
        overrides[key] = overrides[key] or {}
        for field, value in pairs(fields) do overrides[key][field] = copy(value) end
      end
    end
    for _, fields in pairs(overrides) do
      if fields.prerequisites ~= nil then fields.exact_prerequisites = true end
    end
  end
  if active_space_age(active_mods) then
    for key, value in pairs(require("compatibility.modern_catalogue.space_age").continuation_overrides or {}) do
      overrides[key] = value
    end
  end
  -- k2_base.lua contains retained F200 presentation and ammunition-category
  -- substitutions. The F210 K2 admissions use the ordinary authored
  -- continuation rows; do not transport the historical F200 overrides.
  if M.is_k2_base(active_mods) and target.id == "f200" then
    for key, value in pairs(require("compatibility.modern_catalogue.k2_base").continuation_overrides or {}) do
      overrides[key] = value
    end
  end
  if M.is_k2so(active_mods) then
    for key, value in pairs(require("compatibility.modern_catalogue.k2so").continuation_overrides or {}) do
      overrides[key] = value
    end
  end
  if M.is_bob_core(active_mods) then
    for key, value in pairs(require("compatibility.modern_catalogue.bob_core").continuation_overrides or {}) do
      overrides[key] = value
    end
  end
  local adapter = native_modded_continuations(active_mods)
  if adapter then
    local known_ids = {}
    for _, row in ipairs(rows) do known_ids[row.id] = true end
    merge_continuation_fields(overrides_by_id, adapter.continuation_overrides(active_mods), known_ids)
  end
  for index = 1, #rows do
    local row = rows[index]
    local changed = overrides[row.key]
    if changed then for key, value in pairs(changed) do row[key] = copy(value) end end
    changed = overrides_by_id[row.id]
    if changed then for key, value in pairs(changed) do row[key] = copy(value) end end
  end
  if M.retains_bob_native_continuations(active_mods) then
    local retained = {}
    for _, row in ipairs(rows) do
      if row.id ~= "inserter-capacity-bonus-8" and row.id ~= "worker-robots-storage-4" then
        retained[#retained + 1] = row
      end
    end
    return retained
  end
  return rows
end

function M.native_owners(active_mods)
  if M.is_k2so(active_mods) then return copy(require("compatibility.modern_catalogue.k2so").native_owners) end
  if not active_space_age(active_mods) then return {} end
  return copy(require("compatibility.modern_catalogue.space_age").native_owners)
end

return M
