local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}
local canonical = nil
local build_scan_count = 0

local function name_of(entry)
  if type(entry) == "string" then return entry end
  return type(entry) == "table" and (entry.name or entry[1]) or nil
end

local function amount_of(entry)
  if type(entry) ~= "table" then return 1 end
  return tonumber(entry.amount or entry[2] or entry.amount_max or entry.amount_min) or 1
end

local function variants(recipe)
  if type(recipe.normal) == "table" or type(recipe.expensive) == "table" then
    local out = {}
    if type(recipe.normal) == "table" then table.insert(out, {name = "normal", value = recipe.normal}) end
    if type(recipe.expensive) == "table" then table.insert(out, {name = "expensive", value = recipe.expensive}) end
    return out
  end
  return {{name = "default", value = recipe}}
end

local function entries_for(definition, field)
  local entries = definition[field]
  if entries then return entries end
  if field == "results" and definition.result then
    return {{name = definition.result, amount = definition.result_count or 1}}
  end
  return {}
end

local function aggregate_io(recipe, field)
  local by_name = {}
  for _, variant in ipairs(variants(recipe)) do
    for _, entry in pairs(entries_for(variant.value, field)) do
      local name = name_of(entry)
      if name then by_name[name] = (by_name[name] or 0) + amount_of(entry) end
    end
  end
  local names = {}
  for name, _ in pairs(by_name) do table.insert(names, name) end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do table.insert(out, {name = name, amount = by_name[name]}) end
  return out, names
end

local function categories_for(recipe)
  local seen, out = {}, {}
  local function add(category)
    category = category or "crafting"
    if not seen[category] then seen[category] = true; table.insert(out, category) end
  end
  for _, category in ipairs(recipe.categories or {}) do add(category) end
  if recipe.category then add(recipe.category) end
  for _, variant in ipairs(variants(recipe)) do
    for _, category in ipairs(variant.value.categories or {}) do add(category) end
    if variant.value.category then add(variant.value.category) end
  end
  if #out == 0 then add("crafting") end
  table.sort(out)
  return out
end

local function hidden(recipe)
  if recipe.hidden == true then return true end
  for _, variant in ipairs(variants(recipe)) do
    if variant.value.hidden == true then return true end
  end
  return false
end

local function enabled_without_research(recipe)
  if recipe.hidden == true or recipe.enabled == false then return false end
  for _, variant in ipairs(variants(recipe)) do
    if variant.value.hidden == true or variant.value.enabled == false then return false end
  end
  return true
end

local function append_index(index, key, recipe_name)
  index[key] = index[key] or {}
  table.insert(index[key], recipe_name)
end

local function build()
  if canonical then return canonical end
  build_scan_count = build_scan_count + 1
  local facts = {}
  local by_output, by_category, names = {}, {}, {}
  for recipe_name, recipe in pairs(data_raw.prototypes("recipe")) do
    local ingredients, ingredient_names = aggregate_io(recipe, "ingredients")
    local results, result_names = aggregate_io(recipe, "results")
    local categories = categories_for(recipe)
    facts[recipe_name] = {
      name = recipe_name,
      categories = categories,
      ingredients = ingredients,
      ingredient_names = ingredient_names,
      results = results,
      result_names = result_names,
      hidden = hidden(recipe),
      enabled_without_research = enabled_without_research(recipe),
      parameter = recipe.parameter == true,
      maximum_productivity = recipe.maximum_productivity,
      allow_productivity = recipe.allow_productivity,
      allow_quality = recipe.allow_quality,
      surface_conditions = deepcopy(recipe.surface_conditions)
    }
    table.insert(names, recipe_name)
    for _, output_name in ipairs(result_names) do append_index(by_output, output_name, recipe_name) end
    for _, category in ipairs(categories) do append_index(by_category, category, recipe_name) end
  end
  table.sort(names)
  for _, index in pairs({by_output, by_category}) do
    for _, recipe_names in pairs(index) do table.sort(recipe_names) end
  end
  canonical = {facts = facts, names = names, by_output = by_output, by_category = by_category}
  return canonical
end

function M.get(recipe_name)
  local fact = build().facts[recipe_name]
  return fact and deepcopy(fact) or nil
end

function M.all_names()
  return deepcopy(build().names)
end

function M.candidate_names(outputs, categories, name_patterns)
  local index, selected = build(), {}
  for output_name, wanted in pairs(outputs or {}) do
    if wanted then
      for _, recipe_name in ipairs(index.by_output[output_name] or {}) do selected[recipe_name] = true end
    end
  end
  for _, category in ipairs(categories or {}) do
    for _, recipe_name in ipairs(index.by_category[category] or {}) do selected[recipe_name] = true end
  end
  if name_patterns and #name_patterns > 0 then
    for _, recipe_name in ipairs(index.names) do
      for _, pattern in ipairs(name_patterns) do
        if string.find(recipe_name, pattern) then selected[recipe_name] = true; break end
      end
    end
  end
  local out = {}
  for recipe_name, _ in pairs(selected) do table.insert(out, recipe_name) end
  table.sort(out)
  return out
end

function M.scan_count()
  build()
  return build_scan_count
end

return M
