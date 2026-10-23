-- Pure formatting for the published exponential research-cost model.
-- This module has no catalogue or prototype-world dependency so a reduced
-- target can share the exact formula without loading the modern catalogue.
local M = {}

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function number_text(value)
  assert(finite(value) and value >= 0,
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

local function legacy_six(value)
  assert(finite(value) and value >= 0,
    "MIR invalid continuation cost value")
  local text = string.format("%.6g", value)
  local number = tonumber(text)
  assert(number ~= nil, "MIR invalid continuation formula value")
  return number, text
end

-- Exact formatting for the named historical base-continuation shape.  Its
-- base coefficient belongs to L=1; a zero setting inherits that coefficient
-- from the finite predecessor.  This remains separate from `cost`, whose
-- native model starts at L=1 without a predecessor.
function M.continuation(stream, first_level, predecessor_count, previous_count)
  assert(type(stream) == "table", "MIR continuation stream is required")
  assert(finite(first_level) and first_level == math.floor(first_level) and first_level >= 2,
    "MIR invalid continuation first level")
  assert(finite(predecessor_count) and predecessor_count > 0
      and finite(previous_count) and previous_count > 0,
    "MIR invalid continuation predecessor costs")
  local base, increment, growth = stream.base_cost, stream.linear_increment, stream.growth_factor
  assert(finite(base) and base >= 0 and finite(increment) and increment >= 0 and finite(growth) and growth >= 0,
    "MIR invalid continuation settings")

  if growth == 0 then growth = predecessor_count / previous_count end
  if growth < 1 then growth = 1 end
  if base == 0 then base = predecessor_count / (growth ^ (first_level - 2)) end
  assert(base > 0 and base < math.huge, "MIR invalid inherited continuation base")

  local legacy_base = legacy_six(base)
  local legacy_growth, growth_text = legacy_six(growth)
  local first_text = number_text(legacy_base * (legacy_growth ^ (first_level - 1)))
  if legacy_growth == 1 then
    if increment == 0 then return first_text end
    return first_text .. "+" .. number_text(increment) .. "*(L-" .. first_level .. ")"
  end
  if increment == 0 then return first_text .. "*" .. growth_text .. "^(L-" .. first_level .. ")" end
  return "(" .. first_text .. "+" .. number_text(increment) .. "*(L-" .. first_level .. "))*"
    .. growth_text .. "^(L-" .. first_level .. ")"
end

return M
