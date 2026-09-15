local M = {}

M.proof_abi = "mir-research-cost-algebraic-proof-v1"

M.bounds = {
  anchor_level = {minimum = 1, maximum = 1000000},
  base_cost = {minimum = 1, maximum = 2147483647},
  linear_increment = {minimum = 0, maximum = 2147483647},
  growth_factor = {minimum = 1, maximum = 1000},
  evaluated_cost = {minimum = 1, maximum = 1e300},
  qualification_offset = 100,
  maximum_exponent = 100
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

function M.algebraic_proof(record)
  local parameters, reason = M.parameters(record)
  if not parameters then return nil, reason end
  return {
    proof_abi = M.proof_abi,
    property = "positive-nondecreasing",
    constraints = {
      "base_cost>=1",
      "linear_increment>=0",
      "growth_factor>=1",
      "offset>=0"
    },
    argument = "C(n+1)/C(n)>=1 from nonnegative affine growth and growth_factor>=1",
    maximum_offset = M.bounds.qualification_offset,
    maximum_exponent = M.bounds.maximum_exponent,
    status = "passed"
  }
end

function M.assert_algebraic_proof(record)
  local proof, reason = M.algebraic_proof(record)
  if not proof then error("ResearchCostModel algebraic proof failed: " .. tostring(reason), 2) end
  return proof
end

function M.is_positive_nondecreasing(record, maximum_offset)
  local parameters, reason = M.parameters(record)
  if not parameters then return false, reason end
  maximum_offset = maximum_offset or M.bounds.qualification_offset
  if not integer(maximum_offset) or maximum_offset < 0
      or maximum_offset > M.bounds.maximum_exponent then return false, "qualification_offset_out_of_bounds" end
  -- Positivity and monotonicity follow algebraically from B >= 1, A >= 0,
  -- G >= 1, and n >= 0. Because the curve is nondecreasing, one bounded
  -- endpoint evaluation proves the complete governed qualification interval.
  local endpoint = (parameters.base_cost + parameters.linear_increment * maximum_offset)
    * (parameters.growth_factor ^ maximum_offset)
  if not M.evaluated_cost(endpoint) then return false, "evaluated_cost_out_of_bounds" end
  return true
end

return M
