-- Bounded display-only context for a caller-selected configuration-change row.
-- This module has no admission, storage, event enumeration, or reporting role.
local M = {}

function M.value(item)
  if type(item) == "string" then
    return (item:sub(1, 96):gsub("[%z\1-\32\127-\255]", function(byte)
      return string.format("\\x%02X", string.byte(byte))
    end))
  end
  if type(item) == "number" or type(item) == "boolean" then return tostring(item) end
  return "unknown"
end

function M.rejected_value(item)
  if item == nil then return "absent" end
  if type(item) == "string" or type(item) == "number" or type(item) == "boolean" then return M.value(item) end
  return "malformed-" .. type(item)
end

function M.row_value(row, key)
  if type(row) ~= "table" or getmetatable(row) ~= nil then return "malformed-" .. type(row) end
  return M.rejected_value(rawget(row, key))
end

function M.row_pair(name, row)
  if type(row) ~= "table" or getmetatable(row) ~= nil then return M.value(name) .. "=malformed-" .. type(row) end
  return M.value(name) .. "=" .. M.value(rawget(row, "old_version")) .. "->" .. M.value(rawget(row, "new_version"))
end

function M.rejected_fields(rejected)
  return {
    "rejecting_mod_name=" .. M.rejected_value(rejected.name),
    "rejecting_old_version=" .. M.row_value(rejected.row, "old_version"),
    "rejecting_new_version=" .. M.row_value(rejected.row, "new_version"),
    "rejecting_active_version=" .. M.rejected_value(rejected.active_version)
  }
end

return M
