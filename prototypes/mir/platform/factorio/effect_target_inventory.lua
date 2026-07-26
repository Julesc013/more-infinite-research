local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local generated = require("prototypes.mir.domain.effects.generated_target_contracts")

local M = {}

local function target_prototype_types()
  local prototype_types = {}
  for _, contract in pairs(generated.contracts) do
    for _, target in ipairs(contract.targets or {}) do
      if target.prototype_type then prototype_types[target.prototype_type] = true end
    end
  end
  return prototype_types
end

local function sorted_names(type_names)
  local seen, out = {}, {}
  for _, type_name in ipairs(type_names) do
    for name in pairs(data_raw.prototypes(type_name)) do
      if not seen[name] then seen[name] = true; table.insert(out, name) end
    end
  end
  table.sort(out)
  return out
end

function M.capture()
  local prototype_types = target_prototype_types()
  local inventory = {resolvers = {}}
  for type_name in pairs(prototype_types) do inventory[type_name] = sorted_names({type_name}) end
  inventory.resolvers.item = sorted_names(lookup.item_types())
  inventory.resolvers.entity = sorted_names(lookup.entity_types())
  inventory.resolvers["space-location"] = sorted_names({"space-location", "planet"})
  return inventory
end

local function exact_name_set(values, type_names)
  local expected = {}
  for _, name in ipairs(values or {}) do expected[name] = true end
  local seen, count = {}, 0
  for _, type_name in ipairs(type_names) do
    for name in pairs(data_raw.prototypes(type_name)) do
      if not expected[name] then return false end
      if not seen[name] then seen[name] = true; count = count + 1 end
    end
  end
  return count == #(values or {})
end

function M.assert_unchanged(expected)
  if type(expected) ~= "table" or type(expected.resolvers) ~= "table" then
    error("Effect target inventory comparison requires the captured input inventory.", 2)
  end
  for type_name in pairs(target_prototype_types()) do
    if not exact_name_set(expected[type_name], {type_name}) then
      error("Effect target prototype inventory changed after input sanitation: " .. type_name, 2)
    end
  end
  local resolver_types = {
    item = lookup.item_types(),
    entity = lookup.entity_types(),
    ["space-location"] = {"space-location", "planet"}
  }
  for resolver, type_names in pairs(resolver_types) do
    if not exact_name_set(expected.resolvers[resolver], type_names) then
      error("Effect target resolver inventory changed after input sanitation: " .. resolver, 2)
    end
  end
  return true
end

return M
