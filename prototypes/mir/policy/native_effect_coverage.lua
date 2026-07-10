local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effective_settings = require("prototypes.mir.settings.effective")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local table_utils = require("prototypes.mir.core.table")

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

function M.exact_owner_names(expected_effect, options)
  options = options or {}
  local excluded = options.excluded_names or {}
  local owners = {}
  for _, name in ipairs(table_utils.sorted_keys(data_raw.prototypes("technology"))) do
    if not excluded[name]
      and (not options.external_only or not string.match(name, "^recipe%-prod%-"))
      and M.technology_has_exact_effect(name, expected_effect)
    then
      table.insert(owners, name)
    end
  end
  return owners
end

function M.external_coverage_for_effects(effects)
  local all_owners = {}
  local seen = {}
  for _, effect in ipairs(effects or {}) do
    local owners = M.exact_owner_names(effect, { external_only = true })
    if #owners == 0 then return false, {} end
    for _, owner in ipairs(owners) do
      if not seen[owner] then
        seen[owner] = true
        table.insert(all_owners, owner)
      end
    end
  end
  table.sort(all_owners)
  return #all_owners > 0, all_owners
end

return M
