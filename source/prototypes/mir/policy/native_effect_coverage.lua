local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effective_settings = require("prototypes.mir.settings.effective")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local table_utils = require("prototypes.mir.core.table")
local effect_contracts = require("prototypes.mir.settings.effect_contracts")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")

local M = {}

local ignored_effect_fields = {
  effect_description = true,
  icon = true,
  icons = true
}

local function value_signature(value)
  if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
  local parts = {}
  for _, key in ipairs(table_utils.sorted_keys(value)) do
    table.insert(parts, tostring(key) .. "=" .. value_signature(value[key]))
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.effect_signature(effect)
  local parts = {}
  for _, key in ipairs(table_utils.sorted_keys(effect or {})) do
    if not ignored_effect_fields[key] then
      table.insert(parts, tostring(key) .. "=" .. value_signature(effect[key]))
    end
  end
  return table.concat(parts, ";")
end

function M.prefer_mir()
  local value = effective_settings.get("mir-prefer-this-mod-for-competing-techs")
  if value == nil then return true end
  return value ~= false
end

function M.technology_is_researchable_infinite(name)
  local technology = data_raw.technology(name)
  if not technology or technology.enabled == false or technology.max_level ~= "infinite" then return false end
  if not technology.unit or not technology.unit.ingredients or #technology.unit.ingredients == 0 then return false end
  if technology.unit.count == nil and technology.unit.count_formula == nil then return false end
  return science.technology_is_researchable(name)
end

function M.technology_has_exact_effect(name, expected_effect)
  if not M.technology_is_researchable_infinite(name) then return false end
  local expected_signature = M.effect_signature(expected_effect)
  for _, effect in ipairs((data_raw.technology(name) or {}).effects or {}) do
    if M.effect_signature(effect) == expected_signature then return true end
  end
  return false
end

function M.technology_effect_identity_qualification_reason(name, expected_effect, options)
  local technology = data_raw.technology(name)
  if not technology then return "technology_absent" end
  if technology.enabled == false then return "technology_disabled" end
  if technology.max_level ~= "infinite" then return "technology_not_infinite" end
  if not technology.unit or not technology.unit.ingredients or #technology.unit.ingredients == 0 then
    return "technology_missing_science_ingredients"
  end
  if technology.unit.count == nil and technology.unit.count_formula == nil then
    return "technology_missing_research_cost"
  end
  if not science.technology_is_researchable(name) then return "technology_science_unreachable" end
  local expected_identity = effect_contracts.effect_identity_signature(expected_effect)
  local found_identity = false
  for _, effect in ipairs(technology.effects or {}) do
    if effect_contracts.effect_identity_signature(effect) == expected_identity then
      found_identity = true
      if not (options and options.positive_numeric_value) then return nil end
      if effect_contracts.effect_has_positive_numeric_value(effect) then return nil end
    end
  end
  if found_identity and options and options.positive_numeric_value then
    return "effect_identity_nonpositive_or_non_numeric"
  end
  return "effect_identity_absent"
end

function M.technology_has_effect_identity(name, expected_effect, options)
  return M.technology_effect_identity_qualification_reason(name, expected_effect, options) == nil
end

-- A generated stream is a MIR-owned replacement.  A generated base extension
-- is deliberately not: it retains a native technology identity and remains a
-- candidate native owner while deciding whether a dedicated stream is useful.
function M.is_mir_generated_stream(name)
  local entry = generated_registry.get(name)
  return entry ~= nil and entry.kind == "stream"
end

function M.exact_owner_names(expected_effect, options)
  options = options or {}
  local excluded = options.excluded_names or {}
  local owners = {}
  for _, name in ipairs(table_utils.sorted_keys(data_raw.prototypes("technology"))) do
    if not excluded[name]
      and (not options.external_only or not M.is_mir_generated_stream(name))
      and M.technology_has_exact_effect(name, expected_effect)
    then
      table.insert(owners, name)
    end
  end
  return owners
end

function M.identity_owner_names(expected_effect, options)
  options = options or {}
  local excluded = options.excluded_names or {}
  local owners = {}
  for _, name in ipairs(table_utils.sorted_keys(data_raw.prototypes("technology"))) do
    if not excluded[name]
      and (not options.external_only or not M.is_mir_generated_stream(name))
      and M.technology_has_effect_identity(name, expected_effect, {
        positive_numeric_value = options.positive_numeric_value ~= false
      })
    then
      table.insert(owners, name)
    end
  end
  return owners
end

local function append_unique(list, seen, value)
  if not seen[value] then
    seen[value] = true
    table.insert(list, value)
  end
end

local function gun_speed_category(effect)
  if effect and effect.type == "gun-speed" and type(effect.ammo_category) == "string" then
    return effect.ammo_category
  end
  return nil
end

function M.is_mir_weapon_speed_base_extension_owner(name)
  if type(name) ~= "string" or string.match(name, "^weapon%-shooting%-speed%-%d+$") == nil then
    return false
  end
  local entry = generated_registry.get(name)
  return entry ~= nil and entry.kind == "base_extension"
end

local function mir_may_replace_owners(effect, owners)
  local mode = effective_settings.get("mir-adjust-vanilla-weapon-speed-techs")
  if mode == nil then mode = "only-when-dedicated-tech-enabled" end
  if mode == "off" or not gun_speed_category(effect) or #(owners or {}) == 0 then return false end
  for _, owner in ipairs(owners or {}) do
    -- A numbered name is not MIR authority.  An external
    -- weapon-shooting-speed-N continuation must remain the final owner even
    -- when it happens to use the same conventional naming pattern.
    if not M.is_mir_weapon_speed_base_extension_owner(owner) then return false end
  end
  return true
end

-- Decide each identity independently.  A mixed stream such as the electric
-- one may have a native owner for Tesla but not the older electric category;
-- retaining the owned identity must not suppress the useful unowned one, nor
-- may it emit a second owner for the covered identity.
function M.resolve_direct_effect_ownership(effects)
  local result = {
    emitted_effects = {},
    covered_effects = {},
    owners = {},
    owners_seen = {},
    replaced_owners = {},
    replaced_owners_seen = {},
    emitted_identities = {},
    emitted_identities_seen = {},
    covered_identities = {},
    covered_identities_seen = {},
    emitted_categories = {},
    emitted_categories_seen = {},
    covered_categories = {},
    covered_categories_seen = {},
    invalid_identities = {},
    policy = M.prefer_mir() and "prefer-mir-when-native-continuation-is-replaceable"
      or "preserve-existing-native-owner"
  }

  for _, effect in ipairs(effects or {}) do
    local identity = effect_contracts.effect_identity_signature(effect)
    local category = gun_speed_category(effect)
    local is_gun_speed = effect and effect.type == "gun-speed"
    if is_gun_speed and (not category or not effect_contracts.effect_has_positive_numeric_value(effect)) then
      table.insert(result.invalid_identities, identity)
    else
      local owners = M.identity_owner_names(effect, {
        external_only = true,
        positive_numeric_value = true
      })
      local may_replace = M.prefer_mir() and mir_may_replace_owners(effect, owners)
      for _, owner in ipairs(owners) do append_unique(result.owners, result.owners_seen, owner) end
      if #owners == 0 or may_replace then
        table.insert(result.emitted_effects, effect)
        append_unique(result.emitted_identities, result.emitted_identities_seen, identity)
        if category then append_unique(result.emitted_categories, result.emitted_categories_seen, category) end
        if may_replace then
          for _, owner in ipairs(owners) do
            append_unique(result.replaced_owners, result.replaced_owners_seen, owner)
          end
        end
      else
        table.insert(result.covered_effects, effect)
        append_unique(result.covered_identities, result.covered_identities_seen, identity)
        if category then append_unique(result.covered_categories, result.covered_categories_seen, category) end
      end
    end
  end

  table.sort(result.owners)
  table.sort(result.replaced_owners)
  table.sort(result.emitted_identities)
  table.sort(result.covered_identities)
  table.sort(result.emitted_categories)
  table.sort(result.covered_categories)
  table.sort(result.invalid_identities)
  return result
end

function M.direct_effect_diagnostics(coverage)
  coverage = coverage or {}
  return {
    native_effect_policy = coverage.policy or "not-applicable",
    native_effect_owners = table.concat(coverage.owners or {}, ","),
    native_effect_replaced_owners = table.concat(coverage.replaced_owners or {}, ","),
    native_effect_emitted_identities = table.concat(coverage.emitted_identities or {}, ","),
    native_effect_covered_identities = table.concat(coverage.covered_identities or {}, ","),
    native_effect_emitted_categories = table.concat(coverage.emitted_categories or {}, ","),
    native_effect_covered_categories = table.concat(coverage.covered_categories or {}, ","),
    native_effect_invalid_identities = table.concat(coverage.invalid_identities or {}, ","),
    -- Static planning establishes the positive effect and owner identity only.
    -- It never turns that into a transport, energy, visual, or cap claim.
    native_effect_saturation = "not-proven-by-static-analysis",
    native_effect_paid_noop_guard = "positive-effect-and-single-owner-required"
  }
end

function M.external_coverage_for_effects(effects)
  local all_owners, seen = {}, {}
  for _, effect in ipairs(effects or {}) do
    local owners = M.identity_owner_names(effect, {
      external_only = true,
      positive_numeric_value = true
    })
    if #owners == 0 then return false, {} end
    for _, owner in ipairs(owners) do append_unique(all_owners, seen, owner) end
  end
  table.sort(all_owners)
  return #all_owners > 0, all_owners
end

return M
