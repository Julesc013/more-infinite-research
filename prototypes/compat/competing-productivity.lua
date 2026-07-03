local C = require("prototypes.config")
local U = require("prototypes.util")
local cleanup = require("prototypes.lib.technology-cleanup")

local M = {}

local KNOWN_COMPETING_MODS = {
  ["mir-fixture-plates-n-circuit-productivity"] = true,
  ["plates-n-circuit-productivity"] = true
}

local KNOWN_TECH_PATTERNS = {
  "^basic%-plate%-productivity",
  "^plate%-productivity",
  "^electric%-circuit%-productivity",
  "^electronic%-circuit%-productivity",
  "^advanced%-circuit%-productivity"
}

local prepared_removable_techs = nil

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

local function stream_requirement_missing(spec)
  for _, mod_name in ipairs(spec.required_mods or {}) do
    if not U.mod_exists(mod_name) then return true end
  end
  for _, item_name in ipairs(spec.required_items or {}) do
    if not U.item_prototype(item_name) then return true end
  end
  for _, fluid_name in ipairs(spec.required_fluids or {}) do
    if not U.fluid_prototype(fluid_name) then return true end
  end
  for _, tech_name in ipairs(spec.required_technologies or {}) do
    if not U.technology_exists(tech_name) then return true end
  end
  for _, tech_name in ipairs(spec.skip_if_technologies or {}) do
    if U.technology_exists(tech_name) then return true end
  end
  for _, category in ipairs(spec.required_ammo_categories or {}) do
    if not U.ammo_category_exists(category) then return true end
  end
  return false
end

local function collect_enabled_stream_recipe_coverage()
  local covered = {}
  for key, spec in pairs(C.streams or {}) do
    if not spec.direct_effects and U.enabled_for(key, spec) and not stream_requirement_missing(spec) then
      for _, bucket in ipairs(U.recipes_for_stream(spec) or {}) do
        for _, recipe_name in ipairs(bucket.recipes or {}) do
          covered[recipe_name] = key
        end
      end
    end
  end
  return covered
end

local function known_competing_tech_name(name)
  for _, pattern in ipairs(KNOWN_TECH_PATTERNS) do
    if string.find(name, pattern) then return true end
  end
  return false
end

local function recipe_productivity_effects_only(tech)
  local effects = tech and tech.effects or {}
  if #effects == 0 then return nil end

  local out = {}
  for _, effect in ipairs(effects) do
    if effect.type ~= "change-recipe-productivity" or not effect.recipe then return nil end
    table.insert(out, effect)
  end
  return out
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
  if tech.max_level ~= "infinite" then return false end

  local effects = recipe_productivity_effects_only(tech)
  if not effects then return false end
  for _, effect in ipairs(effects) do
    if not owned_recipes[effect.recipe] then return false end
  end
  return true
end

function M.prepare()
  prepared_removable_techs = {}
  if not prefer_this_mod_for_competing_techs() then return end
  if not known_competing_mod_active() then return end

  local covered_recipes = collect_enabled_stream_recipe_coverage()
  for name, tech in pairs(data.raw.technology or {}) do
    if not string.find(name, "^recipe%-prod%-")
      and known_competing_tech_name(name)
      and tech.max_level == "infinite" then
      local effects = recipe_productivity_effects_only(tech)
      local removable = effects ~= nil
      for _, effect in ipairs(effects or {}) do
        if not covered_recipes[effect.recipe] then
          removable = false
          break
        end
      end
      if removable then
        prepared_removable_techs[name] = true
        log("[more-infinite-research] Prepared competing recipe productivity technology for MIR replacement: " .. name)
      end
    end
  end
end

function M.ignores_existing_owner(tech_name)
  return prepared_removable_techs and prepared_removable_techs[tech_name] == true
end

function M.apply()
  if not prefer_this_mod_for_competing_techs() then return end
  if not known_competing_mod_active() then return end

  local owned_recipes = collect_owned_recipes()
  local to_remove = {}
  local candidates = prepared_removable_techs or {}
  if not prepared_removable_techs then
    for name, _ in pairs(data.raw.technology or {}) do
      candidates[name] = true
    end
  end

  for name, _ in pairs(candidates) do
    local tech = data.raw.technology and data.raw.technology[name]
    if is_external_recipe_productivity_tech(name, tech, owned_recipes) then
      table.insert(to_remove, name)
    end
  end
  for _, name in ipairs(to_remove) do
    cleanup.remove_technology_and_prereq_refs(name)
    log("[more-infinite-research] Removed competing recipe productivity technology: " .. name)
  end
end

return M
