local data_raw = require("prototypes.mir.platform.factorio.data_raw")

-- Immutable recipe/recycling facts. Safety decisions live in policy so the
-- final recipe graph is indexed once even on very large mod packs.
local M = {}

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
  return type(entry) == "table" and (entry.name or entry[1]) or nil
end

local function type_of(entry)
  return type(entry) == "table" and (entry.type or "item") or nil
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
  local singular = field == "results" and variant.result or variant.ingredient
  if singular == nil then return {} end
  return {{
    name = singular,
    type = "item",
    amount = field == "results" and (variant.result_count or 1) or (variant.ingredient_amount or 1)
  }}
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
    local probability = probability_of(entry)
    if not amount or amount <= 0 or not probability or probability < 0 or probability > 1 then
      return nil, "unsupported-product-shape"
    end
    table.insert(out, {
      name = name,
      amount = amount,
      probability = probability,
      ignored_by_productivity = tonumber(entry.ignored_by_productivity or 0) or 0
    })
  end
  return out
end

local function parse_recipe(recipe)
  if type(recipe) ~= "table" or recipe.parameter == true then
    return {valid = false, reason = "unsupported-product-shape"}
  end
  local all = variants(recipe)
  if #all ~= 1 then return {valid = false, reason = "ambiguous-recycling-path"} end
  local ingredients, ingredient_reason = item_entries(all[1], "ingredients")
  local results, result_reason = item_entries(all[1], "results")
  if not ingredients or not results then
    return {valid = false, reason = ingredient_reason or result_reason}
  end
  return {
    valid = true,
    ingredients = ingredients,
    results = results
  }
end

local function returns_item(results, item_name)
  for _, result in ipairs(results or {}) do
    if result.name == item_name then return true end
  end
  return false
end

function M.build()
  local facts = {
    graph = {},
    recipes = {},
    self_return_paths = {}
  }

  for name, recipe in pairs(data_raw.prototypes("recipe")) do
    local parsed = parse_recipe(recipe)
    facts.recipes[name] = parsed
    if parsed.valid then
      for _, ingredient in ipairs(parsed.ingredients) do
        facts.graph[ingredient.name] = facts.graph[ingredient.name] or {}
        for _, result in ipairs(parsed.results) do
          facts.graph[ingredient.name][result.name] = true
        end
      end

      if #parsed.ingredients == 1 then
        local input = parsed.ingredients[1]
        if returns_item(parsed.results, input.name) then
          facts.self_return_paths[input.name] = facts.self_return_paths[input.name] or {}
          table.insert(facts.self_return_paths[input.name], {
            name = name,
            recipe = recipe,
            input = input,
            results = parsed.results,
            exact_identity = #parsed.results == 1 and parsed.results[1].name == input.name
          })
        end
      end
    end
  end

  for _, paths in pairs(facts.self_return_paths) do
    table.sort(paths, function(a, b) return a.name < b.name end)
  end
  return facts
end

function M.recipe_facts(index, recipe)
  local name = type(recipe) == "table" and recipe.name or nil
  return (name and index.recipes[name]) or parse_recipe(recipe)
end

function M.reaches(index, start, target_set)
  local pending, seen = {start}, {[start] = true}
  local cursor = 1
  while cursor <= #pending do
    local current = pending[cursor]
    cursor = cursor + 1
    for next_name, _ in pairs(index.graph[current] or {}) do
      if next_name ~= start and target_set[next_name] then return true end
      if not seen[next_name] then
        seen[next_name] = true
        table.insert(pending, next_name)
      end
    end
  end
  return false
end

return M
