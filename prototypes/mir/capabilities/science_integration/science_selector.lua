local C = require("prototypes.mir.streams.registry")
local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local recipes = require("prototypes.mir.capabilities.recipe_productivity.recipe_matching")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}

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
  return effective_settings.get(name)
end

local function add_if_science_pack_exists(list, name)
  if science.science_pack_exists(name) then table.insert(list, name) end
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
  if name and science.science_pack_exists(name) and not seen[name] then
    seen[name] = true
    table.insert(out, {name, amount or 1})
  end
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
    for _, tech_name in ipairs(science.researchable_unlockers_for_recipe(recipe_name)) do
      local tech = data_raw.technology(tech_name)
      for _, ingredient in ipairs(((tech and tech.unit) and tech.unit.ingredients) or {}) do
        append_ingredient(out, seen, ingredient_name(ingredient), ingredient_amount(ingredient))
      end
    end
  end
  return out
end

function M.apply_science_pack_ingredient_policy(ingredients)
  local policy = startup_setting("mir-science-pack-ingredient-policy") or "configured"
  if policy == "configured" then
    -- Neutral/bypass option: preserve the stream's configured ingredients
    -- without loading any of the optional ingredient expansion policies.
    return deepcopy(ingredients or {})
  end

  local out, seen = {}, {}
  local selected_packs = {}
  for _, ingredient in ipairs(ingredients or {}) do
    local name = ingredient_name(ingredient)
    if name then table.insert(selected_packs, name) end
    if policy ~= "all-official" or science.is_official_science_pack(name) then
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
    for _, pack in ipairs(science.space_age_progression_packs_for(selected_packs)) do
      append_ingredient(out, seen, pack, 1)
    end
  elseif policy == "official-progression" then
    for _, pack in ipairs(science.official_progression_packs_for(selected_packs)) do
      append_ingredient(out, seen, pack, 1)
    end
  elseif policy == "mod-progression" then
    for _, pack in ipairs(science.mod_progression_packs_for(selected_packs)) do
      append_ingredient(out, seen, pack, 1)
    end
  elseif policy == "all-official" then
    for _, pack in ipairs(science.pack_list_official()) do
      append_ingredient(out, seen, pack, 1)
    end
  elseif policy == "all" then
    for _, pack in ipairs(science.pack_list_all()) do
      append_ingredient(out, seen, pack, 1)
    end
  end

  return out
end

function M.pick_science_for_stream(spec, key)
  local packs = {}
  local desired = spec and spec.science_packs
  if desired == "all" then
    for _, p in ipairs(science.pack_list_all()) do add_if_science_pack_exists(packs, p) end
  elseif desired == "derive-from-unlocks" then
    for _, ingredient in ipairs(science_from_unlocks(spec)) do
      add_if_science_pack_exists(packs, ingredient_name(ingredient))
    end
  elseif type(desired) == "table" then
    for _, p in ipairs(desired) do add_if_science_pack_exists(packs, p) end
  elseif type(desired) == "string" then
    local list = science.pack_list_for_extension(key, desired) or science.pack_list_for_extension(desired)
    if list then for _, p in ipairs(list) do add_if_science_pack_exists(packs, p) end end
  elseif key == "research_science_pack_productivity" then
    for _, p in ipairs(science.pack_list_all()) do add_if_science_pack_exists(packs, p) end
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
  return M.apply_science_pack_ingredient_policy(out)
end

return M
