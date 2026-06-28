local C = require("prototypes.config")
local U = require("prototypes.util")

local M = {}

local KNOWN_COMPETING_MODS = {
  ["plates-n-circuit-productivity"] = true
}

local KNOWN_TECH_PATTERNS = {
  "^basic%-plate%-productivity",
  "^plate%-productivity",
  "^electric%-circuit%-productivity",
  "^electronic%-circuit%-productivity",
  "^advanced%-circuit%-productivity"
}

local function prefer_this_mod_for_competing_techs()
  local setting = settings and settings.startup and settings.startup["mir-prefer-this-mod-for-competing-techs"]
  if setting == nil then return true end
  return setting.value ~= false
end

local function known_competing_mod_active()
  if not mods then return false end
  for mod_name, _ in pairs(KNOWN_COMPETING_MODS) do
    if mods[mod_name] then return true end
  end
  return false
end

local function known_competing_tech_name(name)
  for _, pattern in ipairs(KNOWN_TECH_PATTERNS) do
    if string.find(name, pattern) then return true end
  end
  return false
end

local function stream_available(key, spec)
  if spec.direct_effects then return false end
  if not U.enabled_for(key, spec) then return false end
  if spec.hide_in_space_age and U.is_space_age() then return false end
  if spec.requires_space_age and not U.is_space_age() then return false end
  for _, item_name in ipairs(spec.required_items or {}) do
    if not U.item_prototype(item_name) then return false end
  end
  for _, tech_name in ipairs(spec.required_technologies or {}) do
    if not U.technology_exists(tech_name) then return false end
  end
  for _, category in ipairs(spec.required_ammo_categories or {}) do
    if not U.ammo_category_exists(category) then return false end
  end
  return true
end

local function collect_owned_recipes()
  local owned = {}
  for key, spec in pairs(C.streams) do
    if stream_available(key, spec) then
      for _, bucket in ipairs(U.recipes_for_stream(spec) or {}) do
        for _, recipe_name in ipairs(bucket.recipes or {}) do
          owned[recipe_name] = key
        end
      end
    end
  end
  return owned
end

local function is_external_recipe_productivity_tech(name, tech, owned_recipes)
  if string.find(name, "^recipe%-prod%-") then return false end
  if not known_competing_tech_name(name) then return false end
  if tech.max_level ~= "infinite" and tech.upgrade ~= true then return false end

  local effects = tech.effects or {}
  if #effects == 0 then return false end
  for _, effect in ipairs(effects) do
    if effect.type ~= "change-recipe-productivity" or not effect.recipe then return false end
    if not owned_recipes[effect.recipe] then return false end
  end
  return true
end

function M.apply()
  if not prefer_this_mod_for_competing_techs() then return end
  if not known_competing_mod_active() then return end

  local owned_recipes = collect_owned_recipes()
  for name, tech in pairs(data.raw.technology or {}) do
    if is_external_recipe_productivity_tech(name, tech, owned_recipes) then
      data.raw.technology[name] = nil
      log("[more-infinite-research] Removed competing recipe productivity technology: " .. name)
    end
  end
end

return M
