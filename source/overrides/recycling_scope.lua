-- One optional recipe index for the self-recycling productivity control.
-- No research, science, ownership discovery or prototype mutation occurs here.
local M = {}
local EPSILON = 0.000001

function M.is_recycling(recipe)
  if recipe.categories ~= nil then
    if type(recipe.categories) ~= "table" then return false end
    local found = false
    for _, category in ipairs(recipe.categories) do
      if type(category) ~= "string" or category == "" then return false end
      if category == "recycling" then found = true end
    end
    return found
  end
  return recipe.category == "recycling"
end

local function finite(value)
  local number = tonumber(value)
  if number and number == number and number > -math.huge and number < math.huge then return number end
end

local function entries(variant, field, inherit_stats)
  local declared = variant[field]
  if type(declared) ~= "table" then
    local name = field == "results" and variant.result or variant.ingredient
    declared = name and {{name, field == "results" and (variant.result_count or 1)
      or (variant.ingredient_amount or 1)}} or {}
  end
  local out = {}
  for _, entry in ipairs(declared) do
    if type(entry) ~= "table" or (entry.type ~= nil and entry.type ~= "item") then return nil end
    local name = entry.name or entry[1]
    if type(name) ~= "string" then return nil end
    local amount = entry.amount or entry[2]
    if amount ~= nil then amount = finite(amount)
    else
      local low, high = entry.amount_min, entry.amount_max
      if low ~= nil and not finite(low) or high ~= nil and not finite(high) then return nil end
      high = finite(high) or finite(low) or 1
      amount = math.max(finite(low) or high, high)
    end
    local probability = entry.independent_probability
    if probability == nil then probability = entry.probability end
    if probability == nil then probability = 1 end
    probability = finite(probability)
    if not amount or amount <= 0 or not probability or probability < 0 or probability > 1 then return nil end
    if entry.shared_probability ~= nil then
      local shared = entry.shared_probability
      if type(shared) ~= "table" then return nil end
      local low = shared.min == nil and 0 or finite(shared.min)
      local high = shared.max == nil and 1 or finite(shared.max)
      if not low or not high or low < 0 or high > 1 or high < low then return nil end
      probability = probability * (high - low)
    end
    local ignored = 0
    if field == "results" then
      if entry.extra_count_fraction ~= nil and finite(entry.extra_count_fraction) ~= 0 then return nil end
      for _, key in ipairs({"ignored_by_productivity", "ignored_by_stats"}) do
        if entry[key] ~= nil and (not finite(entry[key]) or finite(entry[key]) < 0) then return nil end
      end
      ignored = finite(entry.ignored_by_productivity)
      if ignored == nil then ignored = inherit_stats and finite(entry.ignored_by_stats) or 0 end
      ignored = ignored or 0
    end
    out[#out + 1] = {name = name, amount = amount, probability = probability, ignored = ignored}
  end
  return out
end

local function parse(recipe, inherit_stats)
  if type(recipe) ~= "table" or recipe.parameter == true then return nil end
  local normal, expensive = recipe.normal, recipe.expensive
  if type(normal) == "table" and type(expensive) == "table" then return nil end
  local variant = type(normal) == "table" and normal or type(expensive) == "table" and expensive or recipe
  local ingredients = entries(variant, "ingredients", inherit_stats)
  local results = entries(variant, "results", inherit_stats)
  if not ingredients or not results then return nil end
  local cap = variant.maximum_productivity
  if cap == nil then cap = recipe.maximum_productivity end
  if cap == nil then cap = 3 end
  return {ingredients = ingredients, results = results, cap = cap, owned = M.is_recycling(recipe)}
end

local function path_cap(path)
  local result = path.results[1]
  local ordinary = result.amount * result.probability
  local productive = math.max(0, result.amount - result.ignored) * result.probability
  if productive == 0 then return ordinary <= path.ingredients[1].amount + EPSILON and math.huge or nil end
  local cap = (path.ingredients[1].amount - ordinary) / productive
  if not finite(cap) or cap < -EPSILON then return nil end
  return math.max(0, cap)
end

-- `inherit_stats` describes the selected native product default. Both
-- Factorio 2.0.77 and 2.1.23 inherit ignored_by_stats; callers with different
-- actual product semantics supply false explicitly.
function M.build(recipes, fallback, inherit_stats)
  local facts, paths, graph, caps = {}, {}, {}, {}
  local visited = 0
  for name, recipe in pairs(recipes) do
    visited = visited + 1
    local fact = parse(recipe, inherit_stats)
    facts[name] = fact
    if fact then
      for _, ingredient in ipairs(fact.ingredients) do
        local edges = graph[ingredient.name] or {}; graph[ingredient.name] = edges
        for _, result in ipairs(fact.results) do edges[result.name] = true end
      end
      if #fact.ingredients == 1 then
        local item = fact.ingredients[1].name
        for _, result in ipairs(fact.results) do
          if result.name == item then
            local list = paths[item] or {}; paths[item] = list
            list[#list + 1] = {name = name, fact = fact}
            if #fact.results == 1 then
              local cap = path_cap(fact)
              if cap ~= nil and (caps[name] == nil or cap < caps[name]) then caps[name] = cap end
            end
            break
          end
        end
      end
    end
  end
  local function reaches(start, inputs)
    local pending, seen, cursor = {start}, {[start] = true}, 1
    while cursor <= #pending do
      local current = pending[cursor]; cursor = cursor + 1
      for name in pairs(graph[current] or {}) do
        if name ~= start and inputs[name] then return true end
        if not seen[name] then seen[name] = true; pending[#pending + 1] = name end
      end
    end
    return false
  end
  return {
    visited = visited,
    maximum_safe_productivity = function(name) return caps[name] end,
    approve = function(name)
      local fact = facts[name]
      if not fact or #fact.results ~= 1 or fact.results[1].probability < 1 then return false end
      local item, inputs = fact.results[1].name, {}
      for _, ingredient in ipairs(fact.ingredients) do
        if ingredient.name == item then return false end
        inputs[ingredient.name] = true
      end
      local list = paths[item]
      if not list or #list ~= 1 or #list[1].fact.results ~= 1 or reaches(item, inputs) then return false end
      local path, cap = list[1].fact, caps[list[1].name]
      if cap == nil then return false end
      local current = tonumber(path.cap)
      if not path.owned then current = tonumber(recipes[list[1].name].maximum_productivity) or fallback end
      if not finite(current) or current < 0 or (path.owned and current > cap + EPSILON) then return false end
      return true
    end
  }
end

return M
