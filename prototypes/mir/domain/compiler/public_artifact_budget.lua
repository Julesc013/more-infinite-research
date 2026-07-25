local M = {}

local SCHEMA = 1
local SAMPLE_LIMIT = 16
local LIMITS = {
  ["mir-generation-plan-public"] = 524288,
  ["mir-technology-catalog-public"] = 131072,
  ["mir-coverage-public"] = 131072,
  ["mir-compiler-evidence-public"] = 131072
}

function M.limit(kind)
  local limit = LIMITS[kind]
  if not limit then
    error("Unknown MIR public artifact byte budget: " .. tostring(kind), 2)
  end
  return limit
end

function M.sample_limit()
  return SAMPLE_LIMIT
end

function M.snapshot()
  local limits = {}
  for kind, limit in pairs(LIMITS) do limits[kind] = limit end
  return {schema = SCHEMA, sample_limit = SAMPLE_LIMIT, limits = limits}
end

return M
