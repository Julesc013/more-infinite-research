-- Pure formatting for the published exponential research-cost model.
-- This module has no catalogue or prototype-world dependency so a reduced
-- target can share the exact formula without loading the modern catalogue.
local M = {}

local function number_text(value)
  assert(type(value) == "number" and value == value and value < math.huge and value >= 0,
    "MIR invalid research cost value")
  if value == math.floor(value) then return tostring(math.floor(value)) end
  return string.format("%.15g", value)
end

function M.cost(base, increment, growth)
  assert(base >= 1 and increment >= 0 and growth >= 1 and growth <= 1000, "MIR invalid research cost bounds")
  local b, d, g = number_text(base), number_text(increment), number_text(growth)
  if growth == 1 then
    if increment == 0 then return b end
    return b .. "+" .. d .. "*(L-1)"
  end
  if increment == 0 then return b .. "*" .. g .. "^(L-1)" end
  return "(" .. b .. "+" .. d .. "*(L-1))*" .. g .. "^(L-1)"
end

return M
