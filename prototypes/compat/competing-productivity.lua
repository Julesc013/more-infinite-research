local C = require("prototypes.config")

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

local function collect_owned_recipes()
  local owned = {}
  for key, _ in pairs(C.streams or {}) do
    local tech_name = "recipe-prod-" .. key .. "-1"
    local tech = data.raw.technology and data.raw.technology[tech_name]
    for _, effect in ipairs((tech and tech.effects) or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe then
        owned[effect.recipe] = tech_name
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
