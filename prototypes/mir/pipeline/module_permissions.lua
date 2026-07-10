local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effective_settings = require("prototypes.mir.settings.effective")
local prototype_limit_settings = require("prototypes.mir.settings.prototype_limits")
local table_utils = require("prototypes.mir.core.table")

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

local function discovered_categories()
  local seen = {}
  for name, _ in pairs(data_raw.prototypes("module-category")) do seen[name] = true end
  -- A few older 2.0-compatible mods declare a module category only on their
  -- module prototype.  Include those final references as well.
  for _, module in pairs(data_raw.prototypes("module")) do
    if type(module) == "table" and module.category then seen[module.category] = true end
  end
  return table_utils.sorted_keys(seen)
end

local function enabled()
  return effective_settings.get(prototype_limit_settings.unrestricted_modules_setting_name) == true
end

local function apply_recipe(recipe, categories)
  if type(recipe) ~= "table" or recipe.parameter == true then return false end
  recipe.allow_speed = true
  recipe.allow_productivity = true
  recipe.allow_consumption = true
  recipe.allow_pollution = true
  recipe.allow_quality = true
  recipe.allowed_module_categories = categories
  return true
end

local function apply_receiver(prototype, categories)
  if type(prototype) ~= "table" then return false end
  local slots = tonumber(prototype.module_slots)
  if not slots or slots <= 0 then return false end
  prototype.allowed_effects = allowed_effects
  prototype.allowed_module_categories = categories
  return true
end

function M.apply()
  if not enabled() then return {enabled = false, recipes_changed = 0, receivers_changed = 0} end

  local categories = discovered_categories()
  local recipes_changed = 0
  for _, recipe in pairs(data_raw.prototypes("recipe")) do
    if apply_recipe(recipe, categories) then recipes_changed = recipes_changed + 1 end
  end

  local receivers_changed = 0
  local receiver_counts = {}
  for _, prototype_type in ipairs(receiver_types) do
    local count = 0
    for _, prototype in pairs(data_raw.prototypes(prototype_type)) do
      if apply_receiver(prototype, categories) then
        count = count + 1
        receivers_changed = receivers_changed + 1
      end
    end
    receiver_counts[prototype_type] = count
  end

  log("[more-infinite-research] Unrestricted module permissions enabled: recipes="
    .. tostring(recipes_changed)
    .. " receivers=" .. tostring(receivers_changed)
    .. " categories=" .. table.concat(categories, ",") .. ".")
  return {
    enabled = true,
    recipes_changed = recipes_changed,
    receivers_changed = receivers_changed,
    receiver_counts = receiver_counts,
    module_categories = categories
  }
end

return M
