local validation = require("prototypes.mir.domain.research_cost.validation")

local M = {}

function M.number_text(value)
  local numeric = assert(tonumber(value), "research cost value must be numeric")
  if numeric == math.floor(numeric) then return tostring(math.floor(numeric)) end
  return string.format("%.15g", numeric)
end

function M.kind(parameters)
  if parameters.linear_increment == 0 and parameters.growth_factor == 1 then return "fixed" end
  if parameters.linear_increment > 0 and parameters.growth_factor == 1 then return "linear" end
  if parameters.linear_increment == 0 and parameters.growth_factor > 1 then return "exponential" end
  return "hybrid"
end

function M.compile(record)
  local parameters = validation.assert_parameters(record)
  local kind = M.kind(parameters)
  local base = M.number_text(parameters.base_cost)
  local increment = M.number_text(parameters.linear_increment)
  local growth = M.number_text(parameters.growth_factor)
  local offset = "(L-" .. M.number_text(parameters.anchor_level) .. ")"

  if kind == "fixed" then return base end
  if kind == "linear" then return base .. "+" .. increment .. "*" .. offset end
  if kind == "exponential" then return base .. "*" .. growth .. "^" .. offset end
  return "(" .. base .. "+" .. increment .. "*" .. offset .. ")*" .. growth .. "^" .. offset
end

function M.evaluate(record, level)
  local parameters = validation.assert_parameters(record)
  local reason
  level, reason = validation.level(level, parameters.anchor_level)
  if not level then error("Research cost evaluation failed: " .. tostring(reason), 2) end
  local offset = level - parameters.anchor_level
  local value = (parameters.base_cost + parameters.linear_increment * offset)
    * (parameters.growth_factor ^ offset)
  local bounded, bounded_reason = validation.evaluated_cost(value)
  if not bounded then error("Research cost evaluation failed: " .. tostring(bounded_reason), 2) end
  return bounded
end

return M
