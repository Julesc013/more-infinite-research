local M = {}

local SCHEMA = 1
local SAMPLE_LIMIT = 16
local LIMITS = {
  ["mir-generation-plan-public"] = 524288,
  ["mir-technology-catalog-public"] = 131072,
  ["mir-coverage-public"] = 131072,
  ["mir-compiler-evidence-public"] = 131072,
  ["mir-research-cost-support-public"] = 16384
}

function M.limit(kind)
  local limit = LIMITS[kind]
  if not limit then
    error("Unknown MIR public artifact byte budget: " .. tostring(kind), 2)
  end
  return limit
end

-- Enforces a scalar count against the registered kind limit. It does not
-- inspect or serialize an artifact; callers that hold arbitrary records must
-- canonicalize them independently before invoking this boundary.
function M.assert_byte_count_within_limit(kind, bytes)
  local limit = M.limit(kind)
  if type(bytes) ~= "number" or bytes < 0 or bytes ~= math.floor(bytes) then
    error("Owned public artifact byte count is invalid.", 2)
  end
  if bytes > limit then
    error("MIR public artifact exceeds its hard byte budget: " .. kind
      .. " bytes=" .. bytes .. " budget=" .. limit, 2)
  end
  return bytes, limit
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
