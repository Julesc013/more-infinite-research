local recycling = require("prototypes.mir.index.recycling")

local M = {}
local EPSILON = 0.000001

function M.build()
  local index = recycling.build()
  local classifier = {}

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
    if recycling_cap == nil then recycling_cap = 3.0 end
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
      maximum_loop_gain = gain
    }
  end

  return classifier
end

return M
