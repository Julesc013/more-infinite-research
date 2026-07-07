local C = require("prototypes.config")
local defaults = require("defaults")
local settings_resolver = require("prototypes.settings-resolver")

local deepcopy = require("prototypes.mir.core.deepcopy")
local lookup = require("prototypes.lib.prototype-lookup")
local science = require("prototypes.lib.science-packs")
local icons = require("prototypes.lib.technology-icons")
local recipes = require("prototypes.lib.recipe-matching")

local U = {}

U.item_prototype = lookup.item_prototype
U.fluid_prototype = lookup.fluid_prototype
U.technology_exists = lookup.technology_exists
U.ammo_category_exists = lookup.ammo_category_exists
U.is_space_age = lookup.is_space_age
U.mod_exists = lookup.mod_exists

U.all_lab_inputs = science.all_lab_inputs
U.science_pack_exists = science.science_pack_exists
U.any_lab_accepts_all = science.any_lab_accepts_all
U.valid_research_ingredients = science.valid_research_ingredients
U.best_lab_compatible_ingredients = science.best_lab_compatible_ingredients
U.pack_list_all = science.pack_list_all
U.pack_list_official = science.pack_list_official
U.is_official_science_pack = science.is_official_science_pack
U.space_age_progression_packs_for = science.space_age_progression_packs_for
U.official_progression_packs_for = science.official_progression_packs_for
U.mod_progression_packs_for = science.mod_progression_packs_for
U.pack_list_for_extension = science.pack_list_for_extension
U.prereq_tech_for_science_pack = science.prereq_tech_for_science_pack
U.end_game_science_pack = science.end_game_science_pack

U.icons_for_stream = icons.icons_for_stream
U.effect_icons_for_stream = icons.effect_icons_for_stream
U.matches_stream_recipe_filter = recipes.matches_stream_recipe_filter

local STREAM_EXTRA_PACKS = {
  research_concrete = {"space-science-pack"},
  research_furnace = {"metallurgic-science-pack"},
  research_landfill = {"metallurgic-science-pack", "space-science-pack"},
  research_artificial_soil = {"agricultural-science-pack", "space-science-pack"},
  research_molten_metals = {"metallurgic-science-pack"},
  research_mining_drill = {"metallurgic-science-pack"},
  research_walls = {"military-science-pack", "space-science-pack"},
  research_grenades = {"military-science-pack", "space-science-pack"},
  research_rails = {"space-science-pack"},
  research_electric_energy = {"electromagnetic-science-pack"},

  research_breeding = {"agricultural-science-pack", "cryogenic-science-pack"},
  research_plastic = {"agricultural-science-pack"},
  research_rocket_fuel = {"agricultural-science-pack"},
  research_thruster_fuel_productivity = {"space-science-pack", "agricultural-science-pack"},
  research_thruster_oxidizer_productivity = {"space-science-pack", "agricultural-science-pack"},
  research_oil_processing_productivity = {"cryogenic-science-pack"},
  research_oil_cracking_productivity = {"agricultural-science-pack"},
  research_lubricant_productivity = {"electromagnetic-science-pack"},
  research_sulfuric_acid_productivity = {"metallurgic-science-pack"},
  research_bacteria_cultivation = {"agricultural-science-pack", "cryogenic-science-pack"},
  research_bioflux = {"agricultural-science-pack"},
  research_carbon = {"space-science-pack"},
  research_carbon_fiber = {"agricultural-science-pack"},
  research_ice = {"space-science-pack"},
  research_rockets = {"agricultural-science-pack", "military-science-pack"},

  research_sulfur = {"metallurgic-science-pack"},
  research_explosives = {"metallurgic-science-pack"},
  research_low_density_structure = {"metallurgic-science-pack"},
  research_engine = {"metallurgic-science-pack"},
  research_tungsten = {"metallurgic-science-pack"},

  research_batteries = {"electromagnetic-science-pack"},
  research_electronic_circuit = {"electromagnetic-science-pack"},
  research_advanced_circuit = {"electromagnetic-science-pack"},
  research_processing_unit = {"electromagnetic-science-pack"},
  research_electric_engine = {"electromagnetic-science-pack"},
  research_flying_robot_frame = {"electromagnetic-science-pack"},
  research_holmium = {"electromagnetic-science-pack"},
  research_supercapacitor = {"electromagnetic-science-pack"},
  research_superconductor = {"electromagnetic-science-pack"},

  research_lithium = {"cryogenic-science-pack"},
  research_quantum_processor = {"cryogenic-science-pack"},
  research_modules = {"cryogenic-science-pack"},

  research_belts = {"space-science-pack"},
  research_inserters = {"space-science-pack"},
  research_bullets = {"military-science-pack", "space-science-pack"},
  research_heavy_ammo = {"military-science-pack", "metallurgic-science-pack", "space-science-pack"},
  research_armor_components = {"military-science-pack", "metallurgic-science-pack", "space-science-pack"},

  research_inventory_capacity = {"agricultural-science-pack"},
  research_robot_battery = {"space-science-pack"},
  research_science_pack_productivity = {}
}

local function startup_setting(name)
  local s = settings and settings.startup and settings.startup[name]
  if s then return s.value end
  return nil
end

local function ensure_minimum(value, fallback, minimum)
  minimum = minimum or 0
  if type(value) ~= "number" then return fallback end
  if value < minimum then return fallback end
  return value
end

local function lookup_default(key, field, spec, fallback)
  local stream_defaults = defaults.streams and defaults.streams[key]
  if stream_defaults and stream_defaults[field] ~= nil then return stream_defaults[field] end
  if spec and spec[field] ~= nil then return spec[field] end
  local shared_defaults = defaults.shared or {}
  if shared_defaults[field] ~= nil then return shared_defaults[field] end
  return fallback
end

local function coerce_max_level(value)
  if value == nil then return nil end
  if value == "infinite" then return "infinite" end
  if type(value) == "number" then
    if value <= 0 then return "infinite" end
    return math.floor(value)
  end
  if type(value) == "string" then
    local num = tonumber(value)
    if not num or num <= 0 then return "infinite" end
    return math.floor(num)
  end
  return "infinite"
end

function U.enabled_for(key, spec)
  return settings_resolver.stream_enabled(key, spec)
end

function U.base_cost_for(key, spec)
  local default = lookup_default(key, "base_cost", spec, C.shared.base_cost)
  local value = startup_setting("ips-cost-base-" .. key)
  if value ~= nil then return ensure_minimum(value, default, 1) end
  return ensure_minimum(default, C.shared.base_cost, 1)
end

function U.growth_factor_for(key, spec)
  local default = lookup_default(key, "growth_factor", spec, C.shared.growth_factor)
  local value = startup_setting("ips-cost-growth-" .. key)
  if value ~= nil then return ensure_minimum(value, default, 1) end
  return ensure_minimum(default, C.shared.growth_factor, 1)
end

function U.research_time_for(key, spec)
  local default = ensure_minimum(lookup_default(key, "research_time", spec, C.shared.research_time), C.shared.research_time, 1)
  local value = startup_setting("ips-research-time-" .. key)
  if value ~= nil then
    if value <= 0 then return default end
    return ensure_minimum(value, default, 1)
  end
  return default
end

function U.max_level_for(key, spec)
  local setting_value = startup_setting("ips-max-level-" .. key)
  if setting_value ~= nil then
    if setting_value <= 0 then return "infinite" end
    return math.floor(setting_value)
  end
  local from_spec = coerce_max_level(lookup_default(key, "max_level", spec, nil))
  if from_spec ~= nil then return from_spec end
  return "infinite"
end

local function add_if_science_pack_exists(list, name)
  if U.science_pack_exists(name) then table.insert(list, name) end
end

local function ingredient_name(ingredient)
  if not ingredient then return nil end
  if type(ingredient) == "string" then return ingredient end
  return ingredient.name or ingredient[1]
end

local function ingredient_amount(ingredient)
  if not ingredient or type(ingredient) == "string" then return 1 end
  return ingredient.amount or ingredient[2] or 1
end

local function append_ingredient(out, seen, name, amount)
  if name and U.science_pack_exists(name) and not seen[name] then
    seen[name] = true
    table.insert(out, {name, amount or 1})
  end
end

local function sorted_keys(tbl)
  local keys = {}
  for key, _ in pairs(tbl or {}) do table.insert(keys, key) end
  table.sort(keys)
  return keys
end

local function recipe_unlock_techs(recipe_name)
  local out = {}
  for _, tech_name in ipairs(sorted_keys(data.raw.technology or {})) do
    local tech = data.raw.technology[tech_name]
    for _, effect in ipairs((tech and tech.effects) or {}) do
      if effect.type == "unlock-recipe" and effect.recipe == recipe_name then
        table.insert(out, tech_name)
        break
      end
    end
  end
  return out
end

local function stream_recipe_names(spec)
  local seen = {}
  local out = {}
  for _, bucket in ipairs(recipes.recipes_for_stream(spec or {}, C.shared.per_level_default) or {}) do
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      if not seen[recipe_name] then
        seen[recipe_name] = true
        table.insert(out, recipe_name)
      end
    end
  end
  table.sort(out)
  return out
end

local function science_from_unlocks(spec)
  local out, seen = {}, {}
  for _, recipe_name in ipairs(stream_recipe_names(spec)) do
    for _, tech_name in ipairs(recipe_unlock_techs(recipe_name)) do
      local tech = (data.raw.technology or {})[tech_name]
      for _, ingredient in ipairs(((tech and tech.unit) and tech.unit.ingredients) or {}) do
        append_ingredient(out, seen, ingredient_name(ingredient), ingredient_amount(ingredient))
      end
    end
  end
  return out
end

function U.apply_science_pack_ingredient_policy(ingredients)
  local out, seen = {}, {}
  local selected_packs = {}
  local policy = startup_setting("mir-science-pack-ingredient-policy") or "configured"
  for _, ingredient in ipairs(ingredients or {}) do
    local name = ingredient_name(ingredient)
    if name then table.insert(selected_packs, name) end
    if policy ~= "all-official" or U.is_official_science_pack(name) then
      append_ingredient(out, seen, name, ingredient_amount(ingredient))
    end
  end

  -- This setting intentionally changes only research ingredients. The
  -- finish-game prerequisite gate is handled separately in prerequisites.
  if policy == "space" then
    append_ingredient(out, seen, "space-science-pack", 1)
  elseif policy == "space-and-promethium" then
    append_ingredient(out, seen, "space-science-pack", 1)
    append_ingredient(out, seen, "promethium-science-pack", 1)
  elseif policy == "space-age-progression" then
    for _, pack in ipairs(U.space_age_progression_packs_for(selected_packs)) do
      append_ingredient(out, seen, pack, 1)
    end
  elseif policy == "official-progression" then
    for _, pack in ipairs(U.official_progression_packs_for(selected_packs)) do
      append_ingredient(out, seen, pack, 1)
    end
  elseif policy == "mod-progression" then
    for _, pack in ipairs(U.mod_progression_packs_for(selected_packs)) do
      append_ingredient(out, seen, pack, 1)
    end
  elseif policy == "all-official" then
    for _, pack in ipairs(U.pack_list_official()) do
      append_ingredient(out, seen, pack, 1)
    end
  elseif policy == "all" then
    for _, pack in ipairs(U.pack_list_all()) do
      append_ingredient(out, seen, pack, 1)
    end
  end

  return out
end

function U.pick_science_for_stream(spec, key)
  local packs = {}
  local desired = spec and spec.science_packs
  if desired == "all" then
    for _, p in ipairs(U.pack_list_all()) do add_if_science_pack_exists(packs, p) end
  elseif desired == "derive-from-unlocks" then
    for _, ingredient in ipairs(science_from_unlocks(spec)) do
      add_if_science_pack_exists(packs, ingredient_name(ingredient))
    end
  elseif type(desired) == "table" then
    for _, p in ipairs(desired) do add_if_science_pack_exists(packs, p) end
  elseif type(desired) == "string" then
    local list = U.pack_list_for_extension(key, desired) or U.pack_list_for_extension(desired)
    if list then for _, p in ipairs(list) do add_if_science_pack_exists(packs, p) end end
  elseif key == "research_science_pack_productivity" then
    for _, p in ipairs(U.pack_list_all()) do add_if_science_pack_exists(packs, p) end
  else
    for _, p in ipairs({"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}) do
      add_if_science_pack_exists(packs, p)
    end
    for _, p in ipairs(STREAM_EXTRA_PACKS[key] or {}) do add_if_science_pack_exists(packs, p) end
  end

  if desired == "derive-from-unlocks" and #packs == 0 then
    for _, p in ipairs({"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}) do
      add_if_science_pack_exists(packs, p)
    end
  end

  local out, seen = {}, {}
  for _, name in ipairs(packs) do
    if not seen[name] then
      seen[name] = true
      table.insert(out, {name, 1})
    end
  end
  return U.apply_science_pack_ingredient_policy(out)
end

function U.build_prereqs_for(key, ingredients)
  local spec = C.streams[key] or {}
  local packs = ingredients or U.best_lab_compatible_ingredients(U.pick_science_for_stream(C.streams[key], key), key)
  local reqs, seen = {}, {}
  local function add(t)
    if t and U.technology_exists(t) and not seen[t] then
      seen[t] = true
      table.insert(reqs, t)
    end
  end
  for _, pair in ipairs(packs or {}) do
    local pack_name = pair.name or pair[1]
    add(U.prereq_tech_for_science_pack(pack_name))
  end
  for _, tech_name in ipairs(spec.required_technologies or {}) do
    add(tech_name)
  end
  if spec.prerequisites == "derive-from-unlocks" then
    for _, recipe_name in ipairs(stream_recipe_names(spec)) do
      for _, tech_name in ipairs(recipe_unlock_techs(recipe_name)) do
        add(tech_name)
      end
    end
  end

  return U.append_end_game_gate_prerequisite(reqs)
end

function U.append_end_game_gate_prerequisite(prereqs)
  local out = prereqs or {}
  local seen = {}
  for _, name in ipairs(out) do seen[name] = true end

  local gate_on = startup_setting("ips-require-space-gate") == true
  if gate_on then
    local prereq = U.prereq_tech_for_science_pack(U.end_game_science_pack())
    if prereq and U.technology_exists(prereq) and not seen[prereq] then
      table.insert(out, prereq)
    end
  end

  return out
end

function U.recipes_for_stream(spec)
  return recipes.recipes_for_stream(spec, C.shared.per_level_default)
end

function U.deepcopy(value)
  return deepcopy(value)
end

return U
