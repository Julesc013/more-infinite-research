local profiles = require("prototypes.mir.compatibility.profiles")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local relationships = require("prototypes.mir.index.relationships")

local O = {}

function O.is_mir_recipe_productivity_tech(tech_name)
  return generated_registry.contains(tech_name)
end

function O.recipe_productivity_effects(tech)
  local effects = {}
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe then
      table.insert(effects, effect)
    end
  end
  return effects
end

function O.recipe_productivity_effects_only(tech)
  local effects = tech and tech.effects or {}
  if #effects == 0 then return nil end

  local out = {}
  for _, effect in ipairs(effects) do
    if effect.type ~= "change-recipe-productivity" or not effect.recipe then return nil end
    table.insert(out, effect)
  end
  return out
end

function O.has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

function O.recipe_allows_productivity(recipe_name)
  local fact = recipe_facts.view(recipe_name)
  if not fact or fact.allow_productivity ~= true then return false end
  for _, variant in ipairs(fact.variants or {}) do
    if variant.effective_allow_productivity ~= true then return false end
  end
  return true
end

function O.recipe_outputs_any_product(recipe_name, products)
  if not products then return true end

  local wanted = {}
  for _, product in ipairs(products) do wanted[product] = true end
  local recipe = data_raw.prototype("recipe", recipe_name)
  if not recipe then return false end

  local function product_name(product)
    if not product then return nil end
    if type(product) == "string" then return product end
    return product.name or product[1]
  end

  local function scan(def)
    if not def then return false end
    if def.results then
      for _, product in pairs(def.results) do
        local name = product_name(product)
        if name and wanted[name] then return true end
      end
    elseif def.result and wanted[def.result] then
      return true
    end
    return false
  end

  if recipe.normal or recipe.expensive then
    return scan(recipe.normal) or scan(recipe.expensive)
  end
  return scan(recipe)
end

function O.recipe_names_from_effects(effects)
  local names = {}
  for _, effect in ipairs(effects or {}) do
    if effect.recipe then table.insert(names, effect.recipe) end
  end
  table.sort(names)
  return table.concat(names, ",")
end

local function ignore_owner(options, tech_name)
  return options and options.ignore_owner and options.ignore_owner(tech_name) == true
end

function O.classify_recipe_productivity_owner(tech_name, tech, options)
  if O.is_mir_recipe_productivity_tech(tech_name) then
    return {
      kind = "mir",
      action = "ignore",
      reason = "mir_generated_owner"
    }
  end

  if ignore_owner(options, tech_name) then
    return {
      kind = "known_removable_competitor",
      action = "replace",
      reason = "prepared_for_mir_replacement"
    }
  end

  local adoption_tech = options and options.adoption_tech
  if adoption_tech and tech_name == adoption_tech then
    return {
      kind = "known_external_adoption_target",
      action = "adopt_or_skip",
      reason = "configured_productivity_family_owner"
    }
  end

  local known_competitor, mod_name = profiles.known_competing_productivity_tech_name(tech_name)
  if known_competitor then
    return {
      kind = "known_competitor",
      action = "skip",
      profile = mod_name,
      reason = "known_competing_profile_not_prepared_for_replacement"
    }
  end

  return {
    kind = "unknown_external",
    action = "skip",
    reason = "unknown_external_infinite_recipe_productivity_owner"
  }
end

function O.external_recipe_productivity_owner_records(recipe_name, options)
  local records = {}
  local snapshot_phase = options and options.snapshot_phase or "input"
  local owner_names = relationships.view(snapshot_phase).technologies_by_recipe_effect[recipe_name] or {}
  for _, tech_name in ipairs(owner_names) do
    local tech = data_raw.technology(tech_name)
    if tech.max_level == "infinite" and not O.is_mir_recipe_productivity_tech(tech_name) then
      local classification = O.classify_recipe_productivity_owner(tech_name, tech, options)
      table.insert(records, {
        tech = tech_name,
        kind = classification.kind,
        action = classification.action,
        profile = classification.profile,
        reason = classification.reason
      })
    end
  end

  table.sort(records, function(a, b) return tostring(a.tech) < tostring(b.tech) end)
  return records
end

function O.blocking_recipe_productivity_owner_records(recipe_name, options)
  local records = {}
  for _, record in ipairs(O.external_recipe_productivity_owner_records(recipe_name, options)) do
    if record.action ~= "replace" then
      table.insert(records, record)
    end
  end
  return records
end

local function joined_field(records, field)
  local values = {}
  local seen = {}
  for _, record in ipairs(records or {}) do
    local value = record[field]
    if value and not seen[value] then
      seen[value] = true
      table.insert(values, value)
    end
  end
  table.sort(values)
  return table.concat(values, ",")
end

function O.owner_names(records)
  return joined_field(records, "tech")
end

function O.owner_kinds(records)
  return joined_field(records, "kind")
end

function O.owner_actions(records)
  return joined_field(records, "action")
end

return O
