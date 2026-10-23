-- Source-characterized from published 4.7.0 commit
-- 84bd157ad7b63b7d171fac2311bf30de70429c11,
-- prototypes/mir/pipeline/module_permissions.lua (SHA-256
-- dbac07646aefdb16dbc6c09a990be6b665ca1559aa99ae585c82cd1461f614fd).
-- The F200 and F210 archive members have identical bytes.  The caller owns
-- target capability selection and supplies the effective mir-unrestricted-modules
-- value; this module has no stage globals, settings imports, or research-emitter use.

local M = {}

local receiver_types = {
  "assembling-machine",
  "furnace",
  "rocket-silo",
  "beacon",
  "lab",
  "mining-drill",
  "agricultural-tower"
}

local allowed_effects = {"speed", "productivity", "consumption", "pollution", "quality"}

local function copy_array(values)
  local out = {}
  for index, value in ipairs(values) do out[index] = value end
  return out
end

local function add_category(seen, categories, value)
  if type(value) == "string" and not seen[value] then
    seen[value] = true
    categories[#categories + 1] = value
  end
end

local function discover_categories(raw, facts)
  local seen, categories = {}, {}
  local declared = raw["module-category"]
  if type(declared) == "table" then
    for name in pairs(declared) do
      facts.visited = facts.visited + 1
      add_category(seen, categories, name)
    end
  end

  local modules = raw.module
  if type(modules) == "table" then
    for _, module in pairs(modules) do
      facts.visited = facts.visited + 1
      if type(module) == "table" then add_category(seen, categories, module.category) end
    end
  end

  table.sort(categories)
  return categories
end

local function apply_recipe(recipe, categories)
  if type(recipe) ~= "table" or recipe.parameter == true then return false end
  recipe.allow_speed = true
  recipe.allow_productivity = true
  recipe.allow_consumption = true
  recipe.allow_pollution = true
  recipe.allow_quality = true
  recipe.allowed_module_categories = copy_array(categories)
  return true
end

local function apply_receiver(prototype, categories)
  if type(prototype) ~= "table" then return false end
  local slots = tonumber(prototype.module_slots)
  if not slots or slots <= 0 then return false end
  prototype.allowed_effects = copy_array(allowed_effects)
  prototype.allowed_module_categories = copy_array(categories)
  return true
end

-- Applies the published unrestricted-module permission fields to the supplied
-- data-stage raw map.  When enabled is not exactly true it does not inspect raw.
function M.apply(raw, enabled)
  if enabled ~= true then
    return {
      active = false,
      recipes_changed = 0,
      receivers_changed = 0,
      visited = 0
    }
  end

  local facts = {
    active = true,
    recipes_changed = 0,
    receivers_changed = 0,
    visited = 0,
    receiver_counts = {}
  }
  if type(raw) ~= "table" then
    facts.module_categories = {}
    return facts
  end

  local categories = discover_categories(raw, facts)
  facts.module_categories = copy_array(categories)

  local recipes = raw.recipe
  if type(recipes) == "table" then
    for _, recipe in pairs(recipes) do
      facts.visited = facts.visited + 1
      if apply_recipe(recipe, categories) then
        facts.recipes_changed = facts.recipes_changed + 1
      end
    end
  end

  for _, prototype_type in ipairs(receiver_types) do
    local count = 0
    local receivers = raw[prototype_type]
    if type(receivers) == "table" then
      for _, prototype in pairs(receivers) do
        facts.visited = facts.visited + 1
        if apply_receiver(prototype, categories) then
          count = count + 1
          facts.receivers_changed = facts.receivers_changed + 1
        end
      end
    end
    facts.receiver_counts[prototype_type] = count
  end

  return facts
end

return M
