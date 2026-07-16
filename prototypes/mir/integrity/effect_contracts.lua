local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local metadata = require("prototypes.mir.domain.effects.metadata")

local M = {}

local contracts = {
  ["change-recipe-productivity"] = {
    identity_fields = {"type", "recipe"}, field = "recipe", prototype_type = "recipe"
  },
  ["unlock-recipe"] = {
    identity_fields = {"type", "recipe"}, field = "recipe", prototype_type = "recipe"
  },
  ["unlock-space-location"] = {
    identity_fields = {"type", "space_location"}, field = "space_location", prototype_type = "space-location"
  },
  ["give-item"] = {
    identity_fields = {"type", "item"}, field = "item", resolver = "item"
  },
  ["ammo-damage"] = {
    identity_fields = {"type", "ammo_category"}, field = "ammo_category", prototype_type = "ammo-category"
  },
  ["gun-speed"] = {
    identity_fields = {"type", "ammo_category"}, field = "ammo_category", prototype_type = "ammo-category"
  }
}

local function target_exists(contract, name)
  if contract.resolver == "item" then return lookup.item_prototype(name) ~= nil end
  return data_raw.prototype(contract.prototype_type, name) ~= nil
end

function M.contract(effect_type)
  return contracts[effect_type]
end

function M.identity(effect)
  if type(effect) ~= "table" or effect.type == nil or effect.type == "nothing" then return "" end
  local contract = contracts[effect.type]
  local fields = contract and contract.identity_fields or metadata.identity_fields()
  local out = {}
  for _, field in ipairs(fields) do
    if effect[field] ~= nil then
      table.insert(out, tostring(field) .. "=" .. tostring(effect[field]))
    end
  end
  return table.concat(out, ";")
end

function M.target_status(effect)
  if type(effect) ~= "table" then
    return false, "effect_not_table", nil
  end
  local contract = contracts[effect.type]
  if not contract then return true, nil, nil end
  local target = effect[contract.field]
  if type(target) ~= "string" or target == "" then
    return false, "missing_" .. contract.field, target
  end
  if not target_exists(contract, target) then
    return false, "missing_" .. contract.prototype_type .. "_target", target
  end
  return true, nil, target
end

function M.snapshot()
  local out = {}
  for effect_type, contract in pairs(contracts) do
    out[effect_type] = {
      field = contract.field,
      identity_fields = contract.identity_fields,
      prototype_type = contract.prototype_type,
      resolver = contract.resolver
    }
  end
  return out
end

return M
