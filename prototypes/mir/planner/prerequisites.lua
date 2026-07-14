local C = require("prototypes.mir.streams.registry")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local recipes = require("prototypes.mir.capabilities.recipe_productivity.recipe_matching")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}

local function startup_setting(name)
  return effective_settings.get(name)
end

local function sorted_keys(tbl)
  local keys = {}
  for key, _ in pairs(tbl or {}) do table.insert(keys, key) end
  table.sort(keys)
  return keys
end

local function recipe_unlock_techs(recipe_name)
  local out = {}
  for _, tech_name in ipairs(sorted_keys(data_raw.prototypes("technology"))) do
    local tech = data_raw.technology(tech_name)
    for _, effect in ipairs((tech and tech.effects) or {}) do
      if effect.type == "unlock-recipe" and effect.recipe == recipe_name then
        table.insert(out, tech_name)
        break
      end
    end
  end
  return out
end

local function stream_recipe_names(spec)
  local seen = {}
  local out = {}
  for _, bucket in ipairs(recipes.recipes_for_stream(spec or {}, C.shared.per_level_default) or {}) do
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      if not seen[recipe_name] then
        seen[recipe_name] = true
        table.insert(out, recipe_name)
      end
    end
  end
  table.sort(out)
  return out
end

function M.append_end_game_gate_prerequisite(prereqs)
  local out = prereqs or {}
  local seen = {}
  for _, name in ipairs(out) do seen[name] = true end

  local gate_on = startup_setting("ips-require-space-gate") == true
  if gate_on then
    local prereq = science.prereq_tech_for_science_pack(science.end_game_science_pack())
    if prereq and lookup.technology_exists(prereq) and not seen[prereq] then
      table.insert(out, prereq)
    end
  end

  return out
end

function M.build_for(key, ingredients)
  local spec = C.streams[key] or {}
  local packs = ingredients or science.best_lab_compatible_ingredients(science_selector.pick_science_for_stream(C.streams[key], key), key)
  local reqs, seen = {}, {}
  local function add(t)
    if t and lookup.technology_exists(t) and not seen[t] then
      seen[t] = true
      table.insert(reqs, t)
    end
  end
  for _, pair in ipairs(packs or {}) do
    local pack_name = pair.name or pair[1]
    add(science.prereq_tech_for_science_pack(pack_name))
  end
  for _, tech_name in ipairs(spec.required_technologies or {}) do
    add(tech_name)
  end
  for _, candidates in ipairs(spec.required_technology_candidates or {}) do
    for _, tech_name in ipairs(candidates or {}) do
      if lookup.technology_exists(tech_name) then
        add(tech_name)
        break
      end
    end
  end
  if spec.prerequisites == "derive-from-unlocks" then
    for _, recipe_name in ipairs(stream_recipe_names(spec)) do
      for _, tech_name in ipairs(recipe_unlock_techs(recipe_name)) do
        add(tech_name)
      end
    end
  end

  return M.append_end_game_gate_prerequisite(reqs)
end

return M
