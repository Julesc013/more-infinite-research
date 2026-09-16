local deepcopy = require("prototypes.mir.core.deepcopy")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}

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
  return effect_contracts.identity(effect)
end

local function build(phase)
  phase = phase or "input"
  if phase ~= "input" and phase ~= "output" then error("Unknown relationship snapshot phase: " .. tostring(phase), 2) end
  local canonical = compiler_context.current():state_view("relationship_indexes", function() return {} end)
  if canonical[phase] then return canonical[phase] end

  local recipe_index = recipe_facts.index_view()
  local out = {
    schema = 2,
    phase = phase,
    recipes_by_output = recipe_index.by_productive_output,
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

  lookup.each_entity_prototype(function(name, entity, prototype_type)
    append(out.entities_by_type, prototype_type, name)
    out.entity_type_by_name[name] = prototype_type
    append(out.entities_by_subgroup, entity.subgroup, name)
    if entity.next_upgrade then out.next_upgrade[name] = entity.next_upgrade end
    if entity.surface_conditions then
      out.surface_conditions.entities[name] = deepcopy(entity.surface_conditions)
    end
  end)

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

  canonical[phase] = out
  return out
end

function M.snapshot(phase)
  return deepcopy(build(phase))
end

-- Internal compiler consumers share the context-owned immutable index. Public
-- exports and callers that need ownership must continue to use snapshot().
function M.view(phase)
  return build(phase)
end

function M.entity_type(name)
  return build("input").entity_type_by_name[name]
end

return M
