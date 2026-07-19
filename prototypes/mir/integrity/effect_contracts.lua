local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local metadata = require("prototypes.mir.domain.effects.metadata")

local M = {}

local contracts = {
  ["change-recipe-productivity"] = {
    identity_fields = {"type", "recipe"},
    targets = {{field = "recipe", prototype_type = "recipe", required = true}}
  },
  ["unlock-recipe"] = {
    identity_fields = {"type", "recipe"},
    targets = {{field = "recipe", prototype_type = "recipe", required = true}}
  },
  ["unlock-space-location"] = {
    identity_fields = {"type", "space_location"},
    targets = {{field = "space_location", resolver = "space-location", required = true}}
  },
  ["give-item"] = {
    identity_fields = {"type", "item", "quality"},
    targets = {
      {field = "item", resolver = "item", required = true},
      {field = "quality", prototype_type = "quality", required = false, default = "normal"}
    }
  },
  ["ammo-damage"] = {
    identity_fields = {"type", "ammo_category"},
    targets = {{field = "ammo_category", prototype_type = "ammo-category", required = true}}
  },
  ["gun-speed"] = {
    identity_fields = {"type", "ammo_category"},
    targets = {{field = "ammo_category", prototype_type = "ammo-category", required = true}}
  },
  ["unlock-quality"] = {
    identity_fields = {"type", "quality"},
    targets = {{field = "quality", prototype_type = "quality", required = true}}
  },
  ["turret-attack"] = {
    identity_fields = {"type", "turret_id"},
    targets = {{field = "turret_id", resolver = "entity", required = true}}
  }
}

local function target_exists(target, name)
  if target.resolver == "item" then return lookup.item_prototype(name) ~= nil end
  if target.resolver == "entity" then return lookup.entity_prototype(name) ~= nil end
  if target.resolver == "space-location" then return lookup.space_location_prototype(name) ~= nil end
  return data_raw.prototype(target.prototype_type, name) ~= nil
end

local function target_kind(target)
  return target.prototype_type or target.resolver or target.field
end

local function target_value(effect, target)
  local value = effect[target.field]
  if value == nil then value = target.default end
  return value
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
    local value = effect[field]
    if value == nil and contract then
      for _, target in ipairs(contract.targets or {}) do
        if target.field == field then value = target.default; break end
      end
    end
    if value ~= nil then
      table.insert(out, tostring(field) .. "=" .. tostring(value))
    end
  end
  return table.concat(out, ";")
end

function M.targets(effect)
  if type(effect) ~= "table" then return {} end
  local contract = contracts[effect.type]
  local out = {}
  for _, target in ipairs((contract and contract.targets) or {}) do
    local value = target_value(effect, target)
    if value ~= nil then
      table.insert(out, {
        type = effect.type,
        target_type = target.field,
        name = tostring(value),
        resolver = target.resolver,
        prototype_type = target.prototype_type,
        required = target.required == true,
        defaulted = effect[target.field] == nil and target.default ~= nil
      })
    end
  end
  return out
end

function M.target_status(effect)
  if type(effect) ~= "table" then
    return false, "effect_not_table", nil
  end
  local contract = contracts[effect.type]
  if not contract then return true, nil, nil end
  for _, target in ipairs(contract.targets or {}) do
    local value = target_value(effect, target)
    if value == nil and target.required ~= true then
      -- Optional targets without defaults are absent by design.
    elseif type(value) ~= "string" or value == "" then
      return false, "missing_" .. target.field, value, target.field
    elseif not target_exists(target, value) then
      return false, "missing_" .. target_kind(target) .. "_target", value, target.field
    end
  end
  return true, nil, nil, nil
end

function M.snapshot()
  local out = {}
  for effect_type, contract in pairs(contracts) do
    out[effect_type] = {
      identity_fields = contract.identity_fields,
      targets = contract.targets
    }
  end
  return out
end

function M.target_inventory()
  local prototype_types = {}
  for _, contract in pairs(contracts) do
    for _, target in ipairs(contract.targets or {}) do
      if target.prototype_type then prototype_types[target.prototype_type] = true end
    end
  end
  for _, type_name in ipairs(lookup.item_types()) do prototype_types[type_name] = true end
  for _, type_name in ipairs(lookup.entity_types()) do prototype_types[type_name] = true end
  local inventory = {}
  for type_name, _ in pairs(prototype_types) do
    local names = {}
    for name, _ in pairs(data_raw.prototypes(type_name)) do table.insert(names, name) end
    table.sort(names)
    inventory[type_name] = names
  end
  return inventory
end

return M
