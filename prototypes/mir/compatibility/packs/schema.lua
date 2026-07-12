local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}

local function data_only(value, path)
  if type(value) == "function" then error("CompatibilityPack must be data-only: " .. path, 3) end
  if type(value) ~= "table" then return end
  for key, child in pairs(value) do data_only(child, path .. "." .. tostring(key)) end
end

function M.validate(pack)
  if type(pack) ~= "table" or pack.schema ~= 1 then
    error("CompatibilityPack schema must be 1", 2)
  end
  if type(pack.id) ~= "string" or pack.id == "" then
    error("CompatibilityPack id is required", 2)
  end
  data_only(pack, "compatibility_pack:" .. pack.id)
  local policy = pack.known_competing_productivity
  if policy and type(policy.tech_patterns) ~= "table" then
    error("CompatibilityPack known competing productivity policy requires tech_patterns", 2)
  end
  return deepcopy(pack)
end

return M

