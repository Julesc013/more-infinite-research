local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}
local EPSILON = 0.000001

local function variants(recipe)
  if type(recipe.normal) == "table" or type(recipe.expensive) == "table" then
    local out = {}
    if type(recipe.normal) == "table" then table.insert(out, recipe.normal) end
    if type(recipe.expensive) == "table" then table.insert(out, recipe.expensive) end
    return out
  end
  return {recipe}
end

local function name_of(entry)
  if type(entry) ~= "table" then return nil end
  return entry.name or entry[1]
end

local function type_of(entry)
  if type(entry) ~= "table" then return nil end
  return entry.type or "item"
end

local function amount_of(entry)
  if type(entry) ~= "table" then return nil end
  local amount = entry.amount
  if amount == nil then amount = entry[2] end
  if amount == nil then amount = entry.amount_max or entry.amount_min end
  return tonumber(amount)
end

local function max_amount_of(entry)
  if type(entry) ~= "table" then return nil end
  return tonumber(entry.amount_max or entry.amount or entry[2] or entry.amount_min)
end

local function probability_of(entry)
  if type(entry) ~= "table" then return nil end
  local independent = entry.independent_probability
  if independent == nil then independent = entry.probability end
  if independent == nil then independent = 1 end
  local shared = entry.shared_probability
  local shared_width = 1
  if type(shared) == "table" then
    shared_width = (tonumber(shared.max) or 1) - (tonumber(shared.min) or 0)
  end
  return tonumber(independent) * shared_width
end

local function list_for(variant, field)
  local entries = variant[field]
  if type(entries) == "table" then return entries end
  local singular = field == "results" and variant.result or variant["ingredient"]
  if singular ~= nil then
    return {{name = singular, type = field == "results" and "item" or "item", amount = field == "results" and (variant.result_count or 1) or (variant.ingredient_amount or 1)}}
  end
  return {}
end

local function item_entries(variant, field)
  local out = {}
  for _, entry in ipairs(list_for(variant, field)) do
    local name = name_of(entry)
    local kind = type_of(entry)
    if not name or not kind then return nil, "unsupported-product-shape" end
    if kind == "fluid" then return nil, "fluid-product" end
    if kind ~= "item" then return nil, "unsupported-product-shape" end
    local amount = max_amount_of(entry)
    if not amount or amount <= 0 then return nil, "unsupported-product-shape" end
    local probability = probability_of(entry)
    if not probability or probability < 0 or probability > 1 then return nil, "unsupported-product-shape" end
    table.insert(out, {name = name, amount = amount, probability = probability, ignored_by_productivity = tonumber(entry.ignored_by_productivity or 0) or 0})
  end
  return out
end

local function canonical_variant(recipe)
  local all = variants(recipe)
  if #all ~= 1 then return nil, "ambiguous-recycling-path" end
  return all[1]
end

local function conversion_graph()
  local graph = {}
  for _, recipe in pairs(data_raw.prototypes("recipe")) do
    local variant = canonical_variant(recipe)
    if variant then
      local ingredients = item_entries(variant, "ingredients") or {}
      local results = item_entries(variant, "results") or {}
      for _, ingredient in ipairs(ingredients) do
        graph[ingredient.name] = graph[ingredient.name] or {}
        for _, result in ipairs(results) do graph[ingredient.name][result.name] = true end
      end
    end
  end
  return graph
end

local function reaches(graph, start, target_set)
  local pending, seen = {start}, {[start] = true}
  while #pending > 0 do
    local current = table.remove(pending, 1)
    for next_name, _ in pairs(graph[current] or {}) do
      if next_name ~= start and target_set[next_name] then return true end
      if not seen[next_name] then
        seen[next_name] = true
        table.insert(pending, next_name)
      end
    end
  end
  return false
end

local function self_return_recipe(product)
  local found = nil
  for name, recipe in pairs(data_raw.prototypes("recipe")) do
    if recipe.parameter ~= true then
      local variant = canonical_variant(recipe)
      if variant then
        local ingredients = item_entries(variant, "ingredients")
        local results = item_entries(variant, "results")
        if ingredients and results and #ingredients == 1 and #results == 1 and ingredients[1].name == product and results[1].name == product then
          if found then return nil, "ambiguous-recycling-path" end
          found = {name = name, recipe = recipe, input = ingredients[1], result = results[1]}
        end
      end
    end
  end
  if not found then return nil, "no-self-return-recipe" end
  return found
end

function M.classify(recipe)
  if type(recipe) ~= "table" or recipe.parameter == true then return false, "unsupported-product-shape" end
  local variant, variant_reason = canonical_variant(recipe)
  if not variant then return false, variant_reason end
  local ingredients, ingredient_reason = item_entries(variant, "ingredients")
  local results, result_reason = item_entries(variant, "results")
  if not ingredients or not results then return false, ingredient_reason or result_reason end
  if #results ~= 1 then return false, "multiple-production-products" end
  local product = results[1]
  if product.probability < 1 then return false, "probabilistic-identity" end

  local inputs = {}
  for _, ingredient in ipairs(ingredients) do
    inputs[ingredient.name] = true
    if ingredient.name == product.name then return false, "candidate-consumes-own-product" end
  end
  local self_return, self_reason = self_return_recipe(product.name)
  if not self_return then return false, self_reason end
  local graph = conversion_graph()
  if reaches(graph, product.name, inputs) then return false, "conversion-cycle-to-input" end

  local recycling_cap = tonumber(self_return.recipe.maximum_productivity)
  if recycling_cap == nil then recycling_cap = 3.0 end
  if recycling_cap < 0 then return false, "unsupported-product-shape" end
  local input_amount = self_return.input.amount
  local result_amount = self_return.result.amount * self_return.result.probability
  local bonus_amount = self_return.result.ignored_by_productivity >= result_amount and 0 or result_amount * recycling_cap
  local gain = (result_amount + bonus_amount) / input_amount
  if gain > 1 + EPSILON then return false, "recycling-loop-gain-above-one" end

  return true, "safe-single-item-self-return", {
    product = product.name,
    recycling_recipe = self_return.name,
    return_ratio = result_amount / input_amount,
    maximum_loop_gain = gain
  }
end

return M
