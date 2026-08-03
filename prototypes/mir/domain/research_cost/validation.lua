local M = {}

M.bounds = {
  anchor_level = {minimum = 1, maximum = 1000000},
  base_cost = {minimum = 1, maximum = 2147483647},
  linear_increment = {minimum = 0, maximum = 2147483647},
  growth_factor = {minimum = 1, maximum = 1000},
  evaluated_cost = {minimum = 1, maximum = 1e300},
  qualification_offset = 100
}

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

  if not integer(anchor) or anchor < M.bounds.anchor_level.minimum
      or anchor > M.bounds.anchor_level.maximum then return nil, "invalid_anchor_level" end
  -- Player-facing base controls are integers. Target projection may derive a
  -- positive fractional first-level value when preserving an inherited
  -- vanilla continuation curve exactly.
  if not finite(base) or base < M.bounds.base_cost.minimum
      or base > M.bounds.base_cost.maximum then return nil, "invalid_base_cost" end
  if not integer(increment) or increment < M.bounds.linear_increment.minimum
      or increment > M.bounds.linear_increment.maximum then return nil, "invalid_linear_increment" end
  if not finite(growth) or growth < M.bounds.growth_factor.minimum
      or growth > M.bounds.growth_factor.maximum then return nil, "invalid_growth_factor" end

  return {
    anchor_level = anchor,
    base_cost = base,
    linear_increment = increment,
    growth_factor = growth
  }
end

function M.level(value, anchor_level)
  local level = tonumber(value)
  if not integer(level) or level < M.bounds.anchor_level.minimum
      or level > M.bounds.anchor_level.maximum then return nil, "invalid_research_level" end
  if anchor_level and level < anchor_level then return nil, "research_level_before_anchor" end
  return level
end

function M.evaluated_cost(value)
  if not finite(value) or value < M.bounds.evaluated_cost.minimum
      or value > M.bounds.evaluated_cost.maximum then return nil, "evaluated_cost_out_of_bounds" end
  return value
end

function M.assert_parameters(record)
  local normalized, reason = M.parameters(record)
  if not normalized then error("Invalid ResearchCostModel: " .. tostring(reason), 2) end
  return normalized
end

function M.is_positive_nondecreasing(record, maximum_offset)
  local parameters, reason = M.parameters(record)
  if not parameters then return false, reason end
  maximum_offset = maximum_offset or M.bounds.qualification_offset
  local previous
  for offset = 0, maximum_offset do
    local value = (parameters.base_cost + parameters.linear_increment * offset)
      * (parameters.growth_factor ^ offset)
    if not M.evaluated_cost(value) then return false, "evaluated_cost_out_of_bounds" end
    if previous and value < previous then return false, "decreasing_cost" end
    previous = value
  end
  return true
end

return M
