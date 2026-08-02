local M = {}

local function finite(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function integer(value)
  return finite(value) and value == math.floor(value)
end

function M.parameters(record)
  if type(record) ~= "table" then return nil, "research_cost_model_required" end

  local anchor = tonumber(record.anchor_level)
  local base = tonumber(record.base_cost)
  local increment = tonumber(record.linear_increment)
  local growth = tonumber(record.growth_factor)

  if not integer(anchor) or anchor < 1 then return nil, "invalid_anchor_level" end
  -- Player-facing base controls are integers. Target projection may derive a
  -- positive fractional first-level value when preserving an inherited
  -- vanilla continuation curve exactly.
  if not finite(base) or base < 1 then return nil, "invalid_base_cost" end
  if not integer(increment) or increment < 0 then return nil, "invalid_linear_increment" end
  if not finite(growth) or growth < 1 then return nil, "invalid_growth_factor" end

  return {
    anchor_level = anchor,
    base_cost = base,
    linear_increment = increment,
    growth_factor = growth
  }
end

function M.assert_parameters(record)
  local normalized, reason = M.parameters(record)
  if not normalized then error("Invalid ResearchCostModel: " .. tostring(reason), 2) end
  return normalized
end

function M.is_positive_nondecreasing(record, maximum_offset)
  local parameters, reason = M.parameters(record)
  if not parameters then return false, reason end
  maximum_offset = maximum_offset or 100
  local previous
  for offset = 0, maximum_offset do
    local value = (parameters.base_cost + parameters.linear_increment * offset)
      * (parameters.growth_factor ^ offset)
    if value <= 0 then return false, "non_positive_cost" end
    if previous and value < previous then return false, "decreasing_cost" end
    previous = value
  end
  return true
end

return M
