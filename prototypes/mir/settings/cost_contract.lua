local M = {}

M.schema = 1
M.formula_abi = "mir-research-cost-v1"
M.bounds = {
  base_cost = {minimum = 1, maximum = 2147483647, integer = true},
  linear_increment = {minimum = 0, maximum = 2147483647, integer = true},
  growth_factor = {minimum = 1, integer = false}
}

M.stream_patterns = {
  base_cost = "ips-cost-base-%s",
  linear_increment = "ips-cost-linear-increment-%s",
  growth_factor = "ips-cost-growth-%s"
}

M.base_patterns = {
  base_cost = "mir-cost-base-%s",
  linear_increment = "mir-cost-linear-increment-%s",
  growth_factor = "mir-cost-growth-%s"
}

local function name(patterns, field, key)
  return string.format(assert(patterns[field], "Unknown research cost setting field: " .. tostring(field)), key)
end

function M.stream_name(field, key) return name(M.stream_patterns, field, key) end
function M.base_name(field, key) return name(M.base_patterns, field, key) end

function M.stream_linear_increment_spec(key, default_value)
  return {
    type = "int-setting",
    name = M.stream_name("linear_increment", key),
    default_value = default_value or 0,
    minimum_value = M.bounds.linear_increment.minimum,
    maximum_value = M.bounds.linear_increment.maximum
  }
end

function M.base_linear_increment_spec(key, default_value)
  return {
    type = "int-setting",
    name = M.base_name("linear_increment", key),
    default_value = default_value or 0,
    minimum_value = M.bounds.linear_increment.minimum,
    maximum_value = M.bounds.linear_increment.maximum
  }
end

return M
