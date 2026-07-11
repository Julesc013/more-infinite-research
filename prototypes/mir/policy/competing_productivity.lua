local C = require("prototypes.mir.streams.registry")
local costs = require("prototypes.mir.planner.costs")
local profiles = require("prototypes.mir.compatibility.profiles")
local productivity_owners = require("prototypes.mir.index.productivity_owners")
local replacement = require("prototypes.mir.emit.technology_replacement")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local effect_contracts = require("prototypes.mir.settings.effect_contracts")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local recipe_matching = require("prototypes.mir.capabilities.recipe_productivity.recipe_matching")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")
local technology_requirements = require("prototypes.mir.planner.technology_requirements")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}

local prepared_removable_techs = nil

local function same_change(a, b)
  local left = tonumber(a)
  local right = tonumber(b)
  if not left or not right then return false end
  return math.abs(left - right) < 0.000000001
end

local function prefer_this_mod_for_competing_techs()
  local setting = effective_settings.get("mir-prefer-this-mod-for-competing-techs")
  if setting == nil then return true end
  return setting ~= false
end

local function known_competing_mod_active()
  return #profiles.active_known_competing_productivity_profiles() > 0
end

local function stream_requirement_missing(spec)
  for _, mod_name in ipairs(spec.required_mods or {}) do
    if not lookup.mod_exists(mod_name) then return true end
  end
  for _, item_name in ipairs(spec.required_items or {}) do
    if not lookup.item_prototype(item_name) then return true end
  end
  for _, fluid_name in ipairs(spec.required_fluids or {}) do
    if not lookup.fluid_prototype(fluid_name) then return true end
  end
  for _, tech_name in ipairs(spec.required_technologies or {}) do
    if not lookup.technology_exists(tech_name) then return true end
  end
  for _, candidates in ipairs(spec.required_technology_candidates or {}) do
    local found = false
    for _, tech_name in ipairs(candidates or {}) do
      if lookup.technology_exists(tech_name) then
        found = true
        break
      end
    end
    if not found then return true end
  end
  if technology_requirements.skip_reason(spec) then return true end
  for _, category in ipairs(spec.required_ammo_categories or {}) do
    if not lookup.ammo_category_exists(category) then return true end
  end
  return false
end

local function collect_enabled_stream_recipe_coverage()
  local covered = {}
  for key, spec in pairs(C.snapshot()) do
    if not spec.direct_effects and costs.enabled_for(key, spec) and not stream_requirement_missing(spec) then
      local ingredients = science_packs.best_lab_compatible_ingredients(science_selector.pick_science_for_stream(spec, key), key)
      if not ingredients or #ingredients == 0 then goto continue end

      for _, bucket in ipairs(recipe_matching.recipes_for_stream(spec, C.shared.per_level_default) or {}) do
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

local function replacement_names_for_effects(effects)
  local replacements, seen = {}, {}
  for _, expected in ipairs(effects or {}) do
    local expected_identity = effect_contracts.effect_identity_signature(expected)
    local owner = nil
    for _, name in ipairs(generated_registry.sorted_names({ kind = "stream" })) do
      local technology = data_raw.technology(name)
      if technology and technology.max_level == "infinite" then
        for _, effect in ipairs(technology.effects or {}) do
          if effect_contracts.effect_identity_signature(effect) == expected_identity
            and effect_contracts.effect_has_positive_numeric_value(effect) then
            owner = name
            break
          end
        end
      end
      if owner then break end
    end
    if not owner then return nil end
    if not seen[owner] then
      seen[owner] = true
      table.insert(replacements, owner)
    end
  end
  table.sort(replacements)
  return replacements
end

function M.prepare()
  prepared_removable_techs = {}
  if not prefer_this_mod_for_competing_techs() then return end
  if not known_competing_mod_active() then return end

  local covered_recipes = collect_enabled_stream_recipe_coverage()
  for name, tech in pairs(data_raw.prototypes("technology")) do
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

  local candidates = prepared_removable_techs or {}
  for name, _ in pairs(candidates) do
    local tech = data_raw.technology(name)
    local effects = productivity_owners.recipe_productivity_effects_only(tech)
    local replacement_names = effects and replacement_names_for_effects(effects) or nil
    if replacement_names and #replacement_names > 0 then
      local replaced, reason = replacement.replace_technology(name, replacement_names)
      if replaced then
        log("[more-infinite-research] Replaced competing recipe productivity technology: "
          .. name .. " -> " .. table.concat(replacement_names, ","))
      else
        log("[more-infinite-research] Retained competing recipe productivity technology because replacement was unsafe: "
          .. name .. " reason=" .. tostring(reason))
      end
    else
      log("[more-infinite-research] Retained competing recipe productivity technology because MIR did not emit complete replacement coverage: " .. name)
    end
  end
end

return M
