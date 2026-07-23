local metadata = require("prototypes.mir.domain.effects.metadata")
local deepcopy = require("prototypes.mir.core.deepcopy")
local generated = require("prototypes.mir.domain.effects.generated_target_contracts")

local M = {}

local contracts = generated.contracts

local function contains(values, name)
  for _, value in ipairs(values or {}) do if value == name then return true end end
  return false
end

local function target_exists(target, name, inventory)
  local values = target.resolver and (inventory.resolvers or {})[target.resolver]
    or inventory[target.prototype_type]
  return contains(values, name)
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

function M.target_status(effect, inventory)
  if type(effect) ~= "table" then
    return false, "effect_not_table", nil
  end
  local contract = contracts[effect.type]
  if not contract then return true, nil, nil end
  if type(inventory) ~= "table" then
    error("Effect target validation requires an explicit target inventory.", 2)
  end
  for _, target in ipairs(contract.targets or {}) do
    local value = target_value(effect, target)
    if value == nil and target.required ~= true then
      -- Optional targets without defaults are absent by design.
    elseif type(value) ~= "string" or value == "" then
      return false, "missing_" .. target.field, value, target.field
    elseif not target_exists(target, value, inventory) then
      return false, "missing_" .. target_kind(target) .. "_target", value, target.field
    end
  end
  return true, nil, nil, nil
end

function M.snapshot()
  return deepcopy(generated)
end

return M
