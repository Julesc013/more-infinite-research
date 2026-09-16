local settings_resolver = require("prototypes.mir.settings.resolver")
local deepcopy = require("prototypes.mir.core.deepcopy")
local planner_prerequisites = require("prototypes.mir.planner.prerequisites")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}

function M.startup_setting(name)
  return effective_settings.get(name)
end

function M.prefer_this_mod_for_competing_techs()
  local value = M.startup_setting("mir-prefer-this-mod-for-competing-techs")
  if value == nil then return true end
  return value ~= false
end

function M.is_enabled(key, spec)
  return settings_resolver.base_enabled(key, spec)
end

function M.sanitize_number(value)
  if type(value) ~= "number" then return nil end
  return value
end

function M.coerce_max_level_value(value)
  if value == nil then return "infinite" end
  if value == "infinite" then return "infinite" end
  if type(value) == "number" then
    if value <= 0 then return "infinite" end
    return math.floor(value + 0.5)
  end
  if type(value) == "string" then
    local num = tonumber(value)
    if not num or num <= 0 then return "infinite" end
    return math.floor(num + 0.5)
  end
  return "infinite"
end

function M.build_prerequisites(previous_name, last_prereqs)
  local out, seen = {}, {}
  if last_prereqs then
    for _, name in ipairs(last_prereqs) do
      if name ~= previous_name and not seen[name] then
        seen[name] = true
        table.insert(out, name)
      end
    end
  end
  if previous_name and not seen[previous_name] then table.insert(out, previous_name) end
  return out
end

local function resolve_science_packs(spec, fallback_unit, key)
  local base_ingredients = deepcopy((fallback_unit or {}).ingredients or {})
  local seen_packs = {}
  for _, pair in ipairs(base_ingredients) do
    local pack_name = pair.name or pair[1]
    if pack_name then seen_packs[pack_name] = true end
  end

  local function append_pack_list(list)
    for _, pack in ipairs(list or {}) do
      if science_packs.science_pack_exists(pack) and not seen_packs[pack] then
        seen_packs[pack] = true
        table.insert(base_ingredients, {pack, 1})
      end
    end
  end

  local desired = spec and spec.science_packs or nil
  local add_list = spec and spec.add_science_packs or nil
  if add_list == nil and not (spec and spec.override_science_packs == true) then
    if desired ~= nil and desired ~= "inherit" then
      add_list = desired
    else
      add_list = science_packs.pack_list_for_extension(key)
    end
  end
  if type(add_list) == "string" then
    add_list = science_packs.pack_list_for_extension(key, add_list)
      or science_packs.pack_list_for_extension(add_list)
  end
  if type(add_list) == "table" then append_pack_list(add_list) end

  if desired == nil or desired == "inherit" then return base_ingredients end
  if not (spec and spec.override_science_packs == true) then return base_ingredients end
  local list = nil
  if desired == "all" then
    list = science_packs.pack_list_all()
  elseif desired then
    if type(desired) == "table" then
      list = {}
      for _, name in ipairs(desired) do table.insert(list, name) end
    else
      list = science_packs.pack_list_for_extension(desired)
    end
  end
  if list and #list > 0 then
    local out = {}
    local out_seen = {}
    for _, pack in ipairs(list) do
      if science_packs.science_pack_exists(pack) then
        out_seen[pack] = true
        table.insert(out, {pack, 1})
      end
    end
    for _, pair in ipairs(base_ingredients) do
      local pack_name = pair.name or pair[1]
      if pack_name and not out_seen[pack_name] then
        out_seen[pack_name] = true
        table.insert(out, {pack_name, 1})
      end
    end
    if #out > 0 then return out end
  end
  return base_ingredients
end

local function append_pack_prerequisites(prereqs, ingredients)
  local seen = {}
  for _, name in ipairs(prereqs or {}) do seen[name] = true end
  for _, pair in ipairs(ingredients or {}) do
    local pack_name = pair.name or pair[1]
    local prereq = science_packs.prereq_tech_for_science_pack(pack_name)
    if prereq and science_packs.technology_is_researchable(prereq) and not seen[prereq] then
      seen[prereq] = true
      table.insert(prereqs, prereq)
    end
  end
  return prereqs
end

function M.resolve_ingredients(spec, base_unit, key)
  local selected = science_selector.apply_science_pack_ingredient_policy(resolve_science_packs(spec, base_unit, key))
  local resolved, lab_status = science_packs.best_lab_compatible_ingredients(selected, key)
  return resolved, lab_status or "full", nil
end

function M.append_end_game_prerequisite(prereqs, ingredients)
  return planner_prerequisites.append_end_game_gate_prerequisite(
    append_pack_prerequisites(prereqs, ingredients)
  )
end

return M
