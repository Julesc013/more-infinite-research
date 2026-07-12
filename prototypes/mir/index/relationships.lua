local deepcopy = require("prototypes.mir.core.deepcopy")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")

local M = {}
local canonical = nil

local ENTITY_TYPES = {
  "accumulator", "ammo-turret", "assembling-machine", "beacon", "boiler",
  "burner-generator", "container", "electric-energy-interface", "electric-pole",
  "furnace", "generator", "inserter", "lab", "loader", "loader-1x1",
  "logistic-container", "mining-drill", "pipe", "pipe-to-ground", "pump",
  "radar", "reactor", "rocket-silo", "roboport", "solar-panel", "splitter",
  "storage-tank", "transport-belt", "underground-belt"
}

local function append(index, key, value)
  if key == nil or value == nil then return end
  index[key] = index[key] or {}
  table.insert(index[key], value)
end

local function sort_index(index)
  for key, values in pairs(index) do
    table.sort(values)
    local unique, previous = {}, nil
    for _, value in ipairs(values) do
      if value ~= previous then table.insert(unique, value) end
      previous = value
    end
    index[key] = unique
  end
end

local function effect_identity(effect)
  local parts = {}
  for _, field in ipairs({"type", "recipe", "ammo_category", "turret_id", "fluid", "item"}) do
    if effect[field] ~= nil then table.insert(parts, field .. "=" .. tostring(effect[field])) end
  end
  return table.concat(parts, ";")
end

local function build()
  if canonical then return canonical end

  local recipe_index = recipe_facts.snapshot()
  local out = {
    schema = 1,
    recipes_by_output = recipe_index.by_output,
    recipes_by_ingredient = recipe_index.by_ingredient,
    recipes_by_category = recipe_index.by_category,
    items = {},
    items_by_place_result = {},
    items_by_subgroup = {},
    entities_by_type = {},
    entity_type_by_name = {},
    entities_by_subgroup = {},
    next_upgrade = {},
    unlocks_by_recipe = {},
    recipes_by_unlock = {},
    technologies_by_effect_identity = {},
    technologies_by_recipe_effect = {},
    labs_by_pack = {},
    modules_by_tier = {},
    surface_conditions = {recipes = {}, entities = {}}
  }

  lookup.each_item_prototype(function(name, item, prototype_type)
    out.items[name] = {
      name = name,
      prototype_type = prototype_type,
      place_result = item.place_result,
      subgroup = item.subgroup
    }
    append(out.items_by_place_result, item.place_result, name)
    append(out.items_by_subgroup, item.subgroup, name)
    if prototype_type == "module" then
      append(out.modules_by_tier, tostring(item.tier or 0), name)
    end
  end)

  for _, prototype_type in ipairs(ENTITY_TYPES) do
    for name, entity in pairs(data_raw.prototypes(prototype_type)) do
      append(out.entities_by_type, prototype_type, name)
      out.entity_type_by_name[name] = prototype_type
      append(out.entities_by_subgroup, entity.subgroup, name)
      if entity.next_upgrade then out.next_upgrade[name] = entity.next_upgrade end
      if entity.surface_conditions then
        out.surface_conditions.entities[name] = deepcopy(entity.surface_conditions)
      end
    end
  end

  for recipe_name, fact in pairs(recipe_index.facts) do
    if fact.surface_conditions then
      out.surface_conditions.recipes[recipe_name] = deepcopy(fact.surface_conditions)
    end
  end

  for technology_name, technology in pairs(data_raw.prototypes("technology")) do
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "unlock-recipe" and effect.recipe then
        append(out.unlocks_by_recipe, effect.recipe, technology_name)
        append(out.recipes_by_unlock, technology_name, effect.recipe)
      elseif effect.type and effect.type ~= "nothing" then
        append(out.technologies_by_effect_identity, effect_identity(effect), technology_name)
        if effect.type == "change-recipe-productivity" and effect.recipe then
          append(out.technologies_by_recipe_effect, effect.recipe, technology_name)
        end
      end
    end
  end

  for lab_name, lab in pairs(data_raw.prototypes("lab")) do
    for _, pack_name in ipairs(lab.inputs or {}) do append(out.labs_by_pack, pack_name, lab_name) end
  end

  for _, index in pairs({
    out.recipes_by_output, out.recipes_by_ingredient, out.recipes_by_category,
    out.items_by_place_result, out.items_by_subgroup, out.entities_by_type,
    out.entities_by_subgroup, out.unlocks_by_recipe, out.recipes_by_unlock,
    out.technologies_by_effect_identity, out.technologies_by_recipe_effect,
    out.labs_by_pack, out.modules_by_tier
  }) do
    sort_index(index)
  end

  canonical = out
  return canonical
end

function M.snapshot()
  return deepcopy(build())
end

function M.entity_type(name)
  return build().entity_type_by_name[name]
end

return M
