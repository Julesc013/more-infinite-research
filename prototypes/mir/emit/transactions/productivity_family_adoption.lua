local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local productivity_owners = require("prototypes.mir.index.productivity_owners")
local mod_data = require("prototypes.mir.emit.mod_data")

local M = {}
local MOD_DATA_NAME = "more-infinite-research-productivity-family-adoption"
local VERSION = 1
local adopted_productivity_family_recipes = {}

local function record(plan, effect)
  table.insert(adopted_productivity_family_recipes, {
    key = plan.key,
    owner = plan.owner,
    recipe = effect.recipe,
    change = effect.change
  })
end

function M.apply(plan)
  if not plan then return {} end
  local owner = data_raw.technology(plan.owner)
  if not owner then
    error("Planned productivity-family adoption owner disappeared: " .. tostring(plan.owner), 2)
  end

  local adopted = {}
  owner.effects = owner.effects or {}
  for _, effect in ipairs(plan.effects or {}) do
    if not productivity_owners.has_recipe_productivity_effect(owner, effect.recipe) then
      table.insert(owner.effects, effect)
      table.insert(adopted, effect)
      record(plan, effect)
      log("[more-infinite-research] Adopted productivity-family recipe for "
        .. plan.key .. " recipe=" .. effect.recipe .. " into " .. plan.owner .. ".")
    end
  end
  return adopted
end

local function signature()
  local entries = {}
  for _, entry in ipairs(adopted_productivity_family_recipes) do
    table.insert(entries,
      "schema=" .. tostring(VERSION)
      .. "|owner=" .. tostring(entry.owner)
      .. "|recipe=" .. tostring(entry.recipe)
      .. "|change=" .. tostring(entry.change))
  end
  table.sort(entries)
  return table.concat(entries, ";")
end

function M.emit_mod_data()
  mod_data.emit_productivity_family_adoption({
    name = MOD_DATA_NAME,
    data_type = "more-infinite-research.productivity-family-adoption",
    data = {
      version = VERSION,
      adopted = #adopted_productivity_family_recipes > 0,
      adopted_count = #adopted_productivity_family_recipes,
      signature = signature()
    }
  })
end

function M.snapshot()
  local out = {}
  for _, entry in ipairs(adopted_productivity_family_recipes) do
    local copy = {}
    for key, value in pairs(entry) do copy[key] = value end
    table.insert(out, copy)
  end
  return out
end

return M
