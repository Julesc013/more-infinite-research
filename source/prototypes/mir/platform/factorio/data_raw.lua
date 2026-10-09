local M = {}

local function require_data()
  if data == nil or type(data.extend) ~= "function" then
    error("Factorio data table is not available in this stage", 3)
  end
  return data
end

function M.raw()
  local factorio_data = require_data()
  return factorio_data.raw
end

function M.extend(prototypes)
  if type(prototypes) ~= "table" then
    error("data_raw.extend expects a prototype array", 2)
  end

  local factorio_data = require_data()
  factorio_data:extend(prototypes)
end

function M.prototype(prototype_type, name)
  local raw = M.raw()
  if raw == nil or raw[prototype_type] == nil then return nil end
  return raw[prototype_type][name]
end

function M.prototypes(prototype_type)
  local raw = M.raw()
  if raw == nil or raw[prototype_type] == nil then return {} end
  return raw[prototype_type]
end

function M.technology(name)
  return M.prototype("technology", name)
end

return M
