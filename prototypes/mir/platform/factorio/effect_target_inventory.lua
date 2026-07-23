local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local generated = require("prototypes.mir.domain.effects.generated_target_contracts")

local M = {}

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
  local prototype_types = {}
  for _, contract in pairs(generated.contracts) do
    for _, target in ipairs(contract.targets or {}) do
      if target.prototype_type then prototype_types[target.prototype_type] = true end
    end
  end
  local inventory = {resolvers = {}}
  for type_name in pairs(prototype_types) do inventory[type_name] = sorted_names({type_name}) end
  inventory.resolvers.item = sorted_names(lookup.item_types())
  inventory.resolvers.entity = sorted_names(lookup.entity_types())
  inventory.resolvers["space-location"] = sorted_names({"space-location"})
  return inventory
end

return M
