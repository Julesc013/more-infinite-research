local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local recipe_semantics = require("prototypes.mir.domain.facts.recipe_semantics")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")

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

local function finite_number(value)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
  return number
end

local function nonnegative_or_absent(value)
  if value == nil then return true end
  local number = finite_number(value)
  return number ~= nil and number >= 0
end

local function max_amount_of(entry)
  if type(entry) ~= "table" then return nil end
  local declared = entry.amount or entry[2]
  if declared ~= nil then
    if not finite_number(declared) then return nil end
  else
    if entry.amount_min ~= nil and not finite_number(entry.amount_min) then return nil end
    if entry.amount_max ~= nil and not finite_number(entry.amount_max) then return nil end
  end
  return recipe_semantics.maximum_base_result_amount(entry)
end

local function probability_of(entry)
  if type(entry) ~= "table" then return nil end
  local independent = entry.independent_probability
  if independent == nil then independent = entry.probability end
  if independent == nil then independent = 1 end
  independent = finite_number(independent)
  if not independent or independent < 0 or independent > 1 then return nil end
  local shared = entry.shared_probability
  local shared_width = 1
  if shared ~= nil then
    if type(shared) ~= "table" then return nil end
    local minimum = shared.min == nil and 0 or finite_number(shared.min)
    local maximum = shared.max == nil and 1 or finite_number(shared.max)
    if not minimum or not maximum or minimum < 0 or maximum > 1 or maximum < minimum then return nil end
    shared_width = maximum - minimum
  end
  return independent * shared_width
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
    local ignored = 0
    if field == "results" then
      -- A base exclusion does not describe the additional bonus-craft roll.
      -- Withhold those shapes until their return semantics are qualified.
      if entry.extra_count_fraction ~= nil and finite_number(entry.extra_count_fraction) ~= 0 then
        return nil, "unsupported-product-shape"
      end
      if not nonnegative_or_absent(entry.ignored_by_productivity) or not nonnegative_or_absent(entry.ignored_by_stats) then
        return nil, "unsupported-product-shape"
      end
      ignored = recipe_semantics.productivity_excluded_amount(entry, target_profiles.current())
    end
    table.insert(out, {
      name = name,
      amount = amount,
      probability = probability,
      ignored_by_productivity = ignored
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
    results = results,
    cap_owned_by_recycling = recipe_semantics.has_recipe_category(recipe, "recycling"),
    effective_maximum_productivity = recipe_semantics.resolve(recipe, all[1], target_profiles.current()).effective_maximum_productivity
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
            cap_owned_by_recycling = parsed.cap_owned_by_recycling,
            effective_maximum_productivity = parsed.effective_maximum_productivity,
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
