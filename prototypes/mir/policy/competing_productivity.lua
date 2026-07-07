local C = require("prototypes.config")
local U = require("prototypes.util")
local profiles = require("prototypes.mir.compatibility.profiles")
local productivity_owners = require("prototypes.mir.index.productivity_owners")
local cleanup = require("prototypes.lib.technology-cleanup")
local technology_requirements = require("prototypes.lib.technology-requirements")

local M = {}

local prepared_removable_techs = nil

local function same_change(a, b)
  local left = tonumber(a)
  local right = tonumber(b)
  if not left or not right then return false end
  return math.abs(left - right) < 0.000000001
end

local function prefer_this_mod_for_competing_techs()
  local setting = settings and settings.startup and settings.startup["mir-prefer-this-mod-for-competing-techs"]
  if setting == nil then return true end
  return setting.value ~= false
end

local function known_competing_mod_active()
  return #profiles.active_known_competing_productivity_profiles() > 0
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
  if technology_requirements.skip_reason(spec) then return true end
  for _, category in ipairs(spec.required_ammo_categories or {}) do
    if not U.ammo_category_exists(category) then return true end
  end
  return false
end

local function collect_enabled_stream_recipe_coverage()
  local covered = {}
  for key, spec in pairs(C.streams or {}) do
    if not spec.direct_effects and U.enabled_for(key, spec) and not stream_requirement_missing(spec) then
      local ingredients = U.best_lab_compatible_ingredients(U.pick_science_for_stream(spec, key), key)
      if not ingredients or #ingredients == 0 then goto continue end

      for _, bucket in ipairs(U.recipes_for_stream(spec) or {}) do
        for _, recipe_name in ipairs(bucket.recipes or {}) do
          covered[recipe_name] = {
            stream = key,
            change = bucket.change or C.shared.per_level_default
          }
        end
      end
    end
    ::continue::
  end
  return covered
end

local function known_competing_tech_name(name)
  local known = profiles.known_competing_productivity_tech_name(name)
  return known == true
end

local function collect_owned_recipes()
  local owned = {}
  for key, _ in pairs(C.streams or {}) do
    local tech_name = "recipe-prod-" .. key .. "-1"
    local tech = data.raw.technology and data.raw.technology[tech_name]
    for _, effect in ipairs((tech and tech.effects) or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe then
        owned[effect.recipe] = {
          tech = tech_name,
          change = effect.change
        }
      end
    end
  end
  return owned
end

local function is_external_recipe_productivity_tech(name, tech, owned_recipes)
  if productivity_owners.is_mir_recipe_productivity_tech(name) then return false end
  if not known_competing_tech_name(name) then return false end
  if tech.max_level ~= "infinite" then return false end

  local effects = productivity_owners.recipe_productivity_effects_only(tech)
  if not effects then return false end
  for _, effect in ipairs(effects) do
    local owned = owned_recipes[effect.recipe]
    if not owned or not same_change(owned.change, effect.change) then return false end
  end
  return true
end

function M.prepare()
  prepared_removable_techs = {}
  if not prefer_this_mod_for_competing_techs() then return end
  if not known_competing_mod_active() then return end

  local covered_recipes = collect_enabled_stream_recipe_coverage()
  for name, tech in pairs(data.raw.technology or {}) do
    if not productivity_owners.is_mir_recipe_productivity_tech(name)
      and known_competing_tech_name(name)
      and tech.max_level == "infinite" then
      local effects = productivity_owners.recipe_productivity_effects_only(tech)
      local removable = effects ~= nil
      for _, effect in ipairs(effects or {}) do
        local covered = covered_recipes[effect.recipe]
        if not covered or not same_change(covered.change, effect.change) then
          removable = false
          break
        end

        local blockers = productivity_owners.blocking_recipe_productivity_owner_records(effect.recipe, {
          ignore_owner = function(owner_name)
            return owner_name == name
          end
        })
        if #blockers > 0 then
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
