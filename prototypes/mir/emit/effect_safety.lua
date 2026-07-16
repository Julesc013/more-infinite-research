local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")

local S = {}

local blocked_effect_types = {
  ["character-item-pickup-distance"] = "item pickup reach can vacuum nearby belt items into player inventories and cause severe lag",
  ["character-loot-pickup-distance"] = "loot pickup reach can vacuum nearby belt items into player inventories and cause severe lag"
}

function S.assert_effect_allowed(effect, context)
  local effect_type = effect and effect.type
  local reason = blocked_effect_types[effect_type]
  if reason then
    error("MIR safety guard blocked unsafe technology effect "
      .. effect_type
      .. " in "
      .. tostring(context or "unknown technology")
      .. ": "
      .. reason
      .. ".")
  end
end

function S.assert_effects_allowed(effects, context)
  for _, effect in ipairs(effects or {}) do
    S.assert_effect_allowed(effect, context)
  end
end

local function assert_effect_target_exists(effect, technology_name)
  if not effect or effect.type ~= "change-recipe-productivity" then return end

  local recipe_name = effect.recipe
  if type(recipe_name) ~= "string" or not data_raw.prototype("recipe", recipe_name) then
    error("MIR generated technology "
      .. tostring(technology_name)
      .. " references missing recipe "
      .. tostring(recipe_name)
      .. ".")
  end
end

local function missing_recipe_target(effect)
  if not effect or effect.type ~= "change-recipe-productivity" then return nil end
  local recipe_name = effect.recipe
  if type(recipe_name) == "string" and data_raw.prototype("recipe", recipe_name) then return nil end
  return recipe_name
end

local function log_pruned_effect(technology_name, recipe_name)
  if type(log) ~= "function" then return end
  log("[MIR] pruned dangling change-recipe-productivity effect from "
    .. tostring(technology_name)
    .. ": missing recipe "
    .. tostring(recipe_name))
end

function S.prune_missing_recipe_effects(technology, technology_name)
  local effects = technology and technology.effects or {}
  local kept, removed = {}, {}

  for _, effect in ipairs(effects) do
    local recipe_name = missing_recipe_target(effect)
    if recipe_name ~= nil or (effect and effect.type == "change-recipe-productivity" and effect.recipe == nil) then
      table.insert(removed, tostring(recipe_name))
      log_pruned_effect(technology_name, recipe_name)
    else
      table.insert(kept, effect)
    end
  end

  if #removed > 0 then technology.effects = kept end
  return {
    pruned_effect_count = #removed,
    remaining_effect_count = #kept,
    removed_recipes = removed
  }
end

function S.sanitize_registered_technology_effects()
  local summary = {
    pruned_effect_count = 0,
    affected_technology_count = 0,
    emptied_technology_count = 0
  }

  for _, name in ipairs(generated_registry.sorted_names()) do
    local tech = data_raw.technology(name)
    if tech then
      local result = S.prune_missing_recipe_effects(tech, name)
      if result.pruned_effect_count > 0 then
        summary.pruned_effect_count = summary.pruned_effect_count + result.pruned_effect_count
        summary.affected_technology_count = summary.affected_technology_count + 1
        if result.remaining_effect_count == 0 then
          summary.emptied_technology_count = summary.emptied_technology_count + 1
        end
      end
    end
  end

  return summary
end

function S.register_generated_technology(name)
  generated_registry.register(name)
end

function S.assert_registered_technology_effects()
  for _, name in ipairs(generated_registry.sorted_names()) do
    local tech = data_raw.technology(name)
    if tech then
      S.assert_effects_allowed(tech.effects, name)
      for _, effect in ipairs(tech.effects or {}) do
        assert_effect_target_exists(effect, name)
      end
    end
  end
end

return S
