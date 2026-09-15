local recycling = require("prototypes.mir.index.recycling")

local M = {}
local EPSILON = 0.000001

local function safe_productivity_cap(path)
  local result = path and path.results and path.results[1]
  if not result then return nil end
  local input_amount = tonumber(path.input and path.input.amount)
  local result_amount = tonumber(result.amount) and (result.amount * result.probability) or nil
  if not input_amount or input_amount <= 0 or not result_amount then return nil end
  local productive_amount = math.max(0, result_amount - result.ignored_by_productivity)
  if productive_amount <= EPSILON then
    if result_amount <= input_amount + EPSILON then return math.huge end
    return nil
  end
  local cap = (input_amount - result_amount) / productive_amount
  if cap < -EPSILON then return nil end
  return math.max(0, cap)
end

function M.build(fallback_recycling_cap)
  local index = recycling.build()
  local classifier = {}
  local path_caps = {}

  for _, paths in pairs(index.self_return_paths) do
    for _, path in ipairs(paths) do
      local cap = path.exact_identity and safe_productivity_cap(path) or nil
      if cap ~= nil then
        local current = path_caps[path.name]
        if current == nil or cap < current then path_caps[path.name] = cap end
      end
    end
  end

  function classifier.maximum_safe_productivity(recipe)
    local name = type(recipe) == "table" and recipe.name or recipe
    return name and path_caps[name] or nil
  end

  function classifier.approve(recipe)
    local parsed = recycling.recipe_facts(index, recipe)
    if not parsed.valid then return false, parsed.reason end
    if #parsed.results ~= 1 then return false, "multiple-production-products" end

    local product = parsed.results[1]
    if product.probability < 1 then return false, "probabilistic-identity" end

    local inputs = {}
    for _, ingredient in ipairs(parsed.ingredients) do
      inputs[ingredient.name] = true
      if ingredient.name == product.name then return false, "candidate-consumes-own-product" end
    end

    local paths = index.self_return_paths[product.name] or {}
    if #paths == 0 then return false, "no-self-return-recipe" end
    if #paths ~= 1 then return false, "ambiguous-recycling-path" end
    local path = paths[1]
    if not path.exact_identity then return false, "self-return-has-byproducts" end
    if recycling.reaches(index, product.name, inputs) then return false, "conversion-cycle-to-input" end

    local result = path.results[1]
    if result.probability < 0 or result.probability > 1 then
      return false, "unsupported-product-shape"
    end
    local recycling_cap = tonumber(path.recipe.maximum_productivity)
    if recycling_cap == nil then recycling_cap = tonumber(fallback_recycling_cap) or 3.0 end
    local path_cap = safe_productivity_cap(path)
    if path_cap == nil then return false, "recycling-loop-gain-above-one" end
    recycling_cap = math.min(recycling_cap, path_cap)
    if recycling_cap < 0 then return false, "unsupported-product-shape" end

    local input_amount = path.input.amount
    local result_amount = result.amount * result.probability
    local productive_amount = math.max(0, result_amount - result.ignored_by_productivity)
    local gain = (result_amount + productive_amount * recycling_cap) / input_amount
    if gain > 1 + EPSILON then return false, "recycling-loop-gain-above-one" end

    return true, "safe-single-item-self-return", {
      product = product.name,
      recycling_recipe = path.name,
      return_ratio = result_amount / input_amount,
      maximum_loop_gain = gain,
      maximum_safe_recycling_productivity = path_cap
    }
  end

  return classifier
end

return M
