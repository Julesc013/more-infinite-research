local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local deepcopy = require("prototypes.mir.core.deepcopy")

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
  return deepcopy(contracts[effect_type])
end

function M.identity(effect)
  if type(effect) ~= "table" then return "" end
  local contract = contracts[effect.type]
  local fields = contract and contract.identity_fields or {"type"}
  local out = {}
  for _, field in ipairs(fields) do
    local value = effect[field]
    if value == nil and contract then
      for _, target in ipairs(contract.targets or {}) do
        if target.field == field then value = target.default; break end
      end
    end
    if value ~= nil then table.insert(out, field .. "=" .. tostring(value)) end
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
  if type(effect) ~= "table" then return false, "effect_not_table", nil, nil end
  local contract = contracts[effect.type]
  if not contract then return true, nil, nil, nil end
  for _, target in ipairs(contract.targets or {}) do
    local explicit_value = effect[target.field]
    local value = target_value(effect, target)
    if value == nil and target.required ~= true then
      -- Optional target is absent by design.
    elseif type(value) ~= "string" or value == "" then
      return false, "missing_" .. target.field, value, target.field
    elseif not (explicit_value == nil and target.required ~= true and target.default ~= nil)
        and not target_exists(target, value) then
      return false, "missing_" .. target_kind(target) .. "_target", value, target.field
    end
  end
  return true, nil, nil, nil
end

function M.snapshot()
  return deepcopy(contracts)
end

return M
