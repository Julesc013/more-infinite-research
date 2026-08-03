local model = require("prototypes.mir.domain.research_cost.model")

local M = {}
local EPSILON = 1e-8
local MAXIMUM_FORMULA_BYTES = 512
local MAXIMUM_TOKENS = 128
local MAXIMUM_PARSE_DEPTH = 32

local function close(left, right)
  return math.abs(left - right) <= EPSILON * math.max(1, math.abs(left), math.abs(right))
end

local function tokenize(text)
  if type(text) ~= "string" or #text > MAXIMUM_FORMULA_BYTES then
    return nil, "formula_budget_exceeded"
  end
  local tokens, index = {}, 1
  while index <= #text do
    local char = text:sub(index, index)
    if char:match("%s") then
      index = index + 1
    elseif char:match("[%d%.]") then
      local start = index
      while index <= #text and text:sub(index, index):match("[%d%.]") do index = index + 1 end
      if index <= #text and text:sub(index, index):match("[eE]") then
        index = index + 1
        if text:sub(index, index):match("[%+%-]") then index = index + 1 end
        while index <= #text and text:sub(index, index):match("%d") do index = index + 1 end
      end
      local value = tonumber(text:sub(start, index - 1))
      if not value then return nil, "invalid_number" end
      tokens[#tokens + 1] = {kind = "number", value = value}
    elseif char == "L" or char == "l" then
      tokens[#tokens + 1] = {kind = "level"}
      index = index + 1
    elseif char:match("[%+%-%*%/%^%(%) ]") then
      tokens[#tokens + 1] = {kind = char}
      index = index + 1
    else
      return nil, "unsupported_token"
    end
    if #tokens > MAXIMUM_TOKENS then return nil, "formula_budget_exceeded" end
  end
  return tokens
end

local function parse(text)
  local tokens, reason = tokenize(text)
  if not tokens then return nil, reason end
  local cursor = 1
  local expression

  local function current(kind)
    local token = tokens[cursor]
    return token and (kind == nil or token.kind == kind) and token or nil
  end

  local function primary(depth)
    if depth > MAXIMUM_PARSE_DEPTH then error("formula_budget_exceeded") end
    local token = current()
    if not token then error("unexpected_end") end
    if token.kind == "number" or token.kind == "level" then
      cursor = cursor + 1
      return token
    end
    if token.kind == "-" then
      cursor = cursor + 1
      return {kind = "neg", value = primary(depth + 1)}
    end
    if token.kind == "(" then
      cursor = cursor + 1
      local value = expression(depth + 1)
      if not current(")") then error("missing_parenthesis") end
      cursor = cursor + 1
      return value
    end
    error("unexpected_token")
  end

  local function power(depth)
    local left = primary(depth)
    if current("^") then
      cursor = cursor + 1
      return {kind = "pow", left = left, right = power(depth + 1)}
    end
    return left
  end

  local function product(depth)
    local left = power(depth)
    while current("*") or current("/") do
      local kind = current().kind
      cursor = cursor + 1
      left = {kind = kind == "*" and "mul" or "div", left = left, right = power(depth)}
    end
    return left
  end

  expression = function(depth)
    local left = product(depth)
    while current("+") or current("-") do
      local kind = current().kind
      cursor = cursor + 1
      left = {kind = kind == "+" and "add" or "sub", left = left, right = product(depth)}
    end
    return left
  end

  local ok, tree = pcall(expression, 0)
  if not ok then return nil, tree end
  if cursor <= #tokens then return nil, "trailing_token" end
  return tree
end

local function evaluate(node, level)
  if node.kind == "number" then return node.value end
  if node.kind == "level" then return level end
  if node.kind == "neg" then return -evaluate(node.value, level) end
  local left, right = evaluate(node.left, level), evaluate(node.right, level)
  if node.kind == "add" then return left + right end
  if node.kind == "sub" then return left - right end
  if node.kind == "mul" then return left * right end
  if node.kind == "div" then return left / right end
  if node.kind == "pow" then return left ^ right end
  error("unsupported_expression_node")
end

local function affine(node)
  if node.kind == "number" then return {constant = node.value, slope = 0} end
  if node.kind == "level" then return {constant = 0, slope = 1} end
  if node.kind == "neg" then
    local value = affine(node.value)
    if not value then return nil end
    return {constant = -value.constant, slope = -value.slope}
  end
  if node.kind == "pow" then
    if node.right.kind ~= "number" then return nil end
    if close(node.right.value, 0) then return {constant = 1, slope = 0} end
    if close(node.right.value, 1) then return affine(node.left) end
    return nil
  end

  local left, right = affine(node.left), affine(node.right)
  if not left or not right then return nil end
  if node.kind == "add" then
    return {constant = left.constant + right.constant, slope = left.slope + right.slope}
  end
  if node.kind == "sub" then
    return {constant = left.constant - right.constant, slope = left.slope - right.slope}
  end
  if node.kind == "mul" then
    if left.slope ~= 0 and right.slope ~= 0 then return nil end
    return {
      constant = left.constant * right.constant,
      slope = left.slope * right.constant + right.slope * left.constant
    }
  end
  if node.kind == "div" then
    if right.slope ~= 0 or right.constant == 0 then return nil end
    return {constant = left.constant / right.constant, slope = left.slope / right.constant}
  end
  return nil
end

local function exponential(node)
  if node.kind ~= "pow" then return nil end
  local base = affine(node.left)
  local exponent = affine(node.right)
  if not base or base.slope ~= 0 or base.constant < 1 or not exponent
    or not close(exponent.slope, 1) then return nil end
  return {growth = base.constant, exponent_constant = exponent.constant}
end

local function components(tree)
  local linear = affine(tree)
  if linear then return {linear = linear, growth = 1, exponent_constant = 0} end

  local power = exponential(tree)
  if power then
    return {
      linear = {constant = 1, slope = 0},
      growth = power.growth,
      exponent_constant = power.exponent_constant
    }
  end

  if tree.kind == "mul" then
    local left_linear, right_power = affine(tree.left), exponential(tree.right)
    if left_linear and right_power then
      return {linear = left_linear, growth = right_power.growth, exponent_constant = right_power.exponent_constant}
    end
    local left_power, right_linear = exponential(tree.left), affine(tree.right)
    if left_power and right_linear then
      return {linear = right_linear, growth = left_power.growth, exponent_constant = left_power.exponent_constant}
    end
  end
  return nil
end

local function sample(tree, anchor)
  local out = {}
  for offset = 0, 5 do
    local ok, value = pcall(evaluate, tree, anchor + offset)
    if not ok or type(value) ~= "number" or value ~= value
      or value == math.huge or value == -math.huge then return nil end
    out[offset + 1] = value
  end
  return out
end

local function integral(value)
  local rounded = math.floor(value + 0.5)
  if close(value, rounded) then return rounded end
  return nil
end

local function build(anchor, base, increment, growth, provenance)
  local normalized_increment = integral(increment)
  if not normalized_increment or base < 1 or normalized_increment < 0 or growth < 1 then return nil end
  local ok, result = pcall(model.new, {
    anchor_level = anchor,
    base_cost = base,
    linear_increment = normalized_increment,
    growth_factor = growth,
    provenance = provenance
  })
  return ok and result or nil
end

local function matches(values, candidate, anchor)
  for offset = 0, #values - 1 do
    if not close(values[offset + 1], model.evaluate(candidate, anchor + offset)) then return false end
  end
  return true
end

function M.anchor_level(technology_name, fallback)
  local suffix = tostring(technology_name or ""):match("%-(%d+)$")
  local value = tonumber(suffix) or tonumber(fallback) or 1
  if value < 1 or value ~= math.floor(value) then return 1 end
  return value
end

function M.formula(text, options)
  options = options or {}
  local anchor = M.anchor_level(options.technology_name, options.anchor_level)
  local tree, reason = parse(text)
  if not tree then return {recognized = false, reason = reason, original_formula = text} end
  local values = sample(tree, anchor)
  if not values or values[1] <= 0 then
    return {recognized = false, reason = "invalid_cost_values", original_formula = text}
  end
  local provenance = options.provenance or {
    base_cost = "external-formula",
    linear_increment = "external-formula",
    growth_factor = "external-formula",
    anchor_level = "technology-first-level"
  }

  local shape = components(tree)
  if shape then
    local scale = shape.growth ^ (anchor + shape.exponent_constant)
    local base = (shape.linear.constant + shape.linear.slope * anchor) * scale
    local increment = shape.linear.slope * scale
    local candidate = build(anchor, base, increment, shape.growth, provenance)
    if candidate and matches(values, candidate, anchor) then
      local style = candidate.derived_kind == "fixed" and "fixed-formula"
        or ("recognized-" .. candidate.derived_kind)
      return {recognized = true, style = style, model = candidate, original_formula = text}
    end
  end

  return {recognized = false, reason = "unrecognized_cost_formula", original_formula = text}
end

return M
