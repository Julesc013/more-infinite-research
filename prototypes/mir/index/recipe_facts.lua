local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}
local canonical = nil
local build_scan_count = 0
local SCHEMA = 2

local function name_of(entry)
  if type(entry) == "string" then return entry end
  return type(entry) == "table" and (entry.name or entry[1]) or nil
end

local function amount_of(entry)
  if type(entry) ~= "table" then return 1 end
  return tonumber(entry.amount or entry[2] or entry.amount_max or entry.amount_min) or 1
end

local function normalized_entry(entry)
  if type(entry) == "string" then
    return {type = "item", name = entry, amount = 1, probability = 1}
  end
  if type(entry) ~= "table" then return nil end
  local name = name_of(entry)
  if not name then return nil end
  return {
    type = entry.type or "item",
    name = name,
    amount = entry.amount or entry[2],
    amount_min = entry.amount_min,
    amount_max = entry.amount_max,
    probability = entry.probability or 1,
    catalyst_amount = entry.catalyst_amount,
    ignored_by_productivity = entry.ignored_by_productivity,
    ignored_by_stats = entry.ignored_by_stats,
    temperature = entry.temperature,
    minimum_temperature = entry.minimum_temperature,
    maximum_temperature = entry.maximum_temperature,
    fluidbox_index = entry.fluidbox_index
  }
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
      if name then
        local identity = ((type(entry) == "table" and entry.type) or "item") .. "\0" .. name
        local aggregate = by_name[identity] or {
          type = (type(entry) == "table" and entry.type) or "item",
          name = name,
          amount = 0
        }
        aggregate.amount = aggregate.amount + amount_of(entry)
        by_name[identity] = aggregate
      end
    end
  end
  local names, seen_names = {}, {}
  for _, entry in pairs(by_name) do
    if not seen_names[entry.name] then
      seen_names[entry.name] = true
      table.insert(names, entry.name)
    end
  end
  table.sort(names)
  local out = {}
  for _, identity in ipairs((function()
    local identities = {}
    for key, _ in pairs(by_name) do table.insert(identities, key) end
    table.sort(identities)
    return identities
  end)()) do
    table.insert(out, by_name[identity])
  end
  return out, names
end

local function normalized_variant(variant)
  local definition = variant.value
  local ingredients, results = {}, {}
  local categories, seen_categories = {}, {}
  local function add_category(category)
    category = category or "crafting"
    if not seen_categories[category] then
      seen_categories[category] = true
      table.insert(categories, category)
    end
  end
  for _, category in ipairs(definition.categories or {}) do add_category(category) end
  if definition.category then add_category(definition.category) end
  if #categories == 0 then add_category("crafting") end
  table.sort(categories)
  for _, entry in pairs(entries_for(definition, "ingredients")) do
    local normalized = normalized_entry(entry)
    if normalized then table.insert(ingredients, normalized) end
  end
  for _, entry in pairs(entries_for(definition, "results")) do
    local normalized = normalized_entry(entry)
    if normalized then table.insert(results, normalized) end
  end
  local function entry_order(a, b)
    if a.type ~= b.type then return a.type < b.type end
    return a.name < b.name
  end
  table.sort(ingredients, entry_order)
  table.sort(results, entry_order)
  return {
    name = variant.name,
    categories = categories,
    ingredients = ingredients,
    results = results,
    enabled = definition.enabled ~= false,
    hidden = definition.hidden == true,
    energy_required = definition.energy_required,
    main_product = definition.main_product or definition.result,
    maximum_productivity = definition.maximum_productivity,
    allow_productivity = definition.allow_productivity,
    allow_quality = definition.allow_quality,
    surface_conditions = deepcopy(definition.surface_conditions)
  }
end

local function variant_facts(recipe)
  local out = {}
  for _, variant in ipairs(variants(recipe)) do table.insert(out, normalized_variant(variant)) end
  return out
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

local function main_product(recipe, result_names)
  if recipe.main_product then return recipe.main_product end
  for _, variant in ipairs(variants(recipe)) do
    if variant.value.main_product then return variant.value.main_product end
    if variant.value.result then return variant.value.result end
  end
  if #result_names == 1 then return result_names[1] end
  return nil
end

local function append_index(index, key, recipe_name)
  index[key] = index[key] or {}
  table.insert(index[key], recipe_name)
end

local function source_class(recipe, categories, is_hidden)
  if recipe.parameter == true then return "parameter" end
  for _, category in ipairs(categories or {}) do
    if category == "recycling" then return "recycling" end
  end
  if is_hidden then return "hidden-internal" end
  return "ordinary"
end

local function build()
  if canonical then return canonical end
  build_scan_count = build_scan_count + 1
  local facts = {}
  local by_output, by_ingredient, by_category, names = {}, {}, {}, {}
  for recipe_name, recipe in pairs(data_raw.prototypes("recipe")) do
    local ingredients, ingredient_names = aggregate_io(recipe, "ingredients")
    local results, result_names = aggregate_io(recipe, "results")
    local categories = categories_for(recipe)
    local is_hidden = hidden(recipe)
    facts[recipe_name] = {
      schema = SCHEMA,
      name = recipe_name,
      variants = variant_facts(recipe),
      categories = categories,
      ingredients = ingredients,
      ingredient_names = ingredient_names,
      results = results,
      result_names = result_names,
      main_product = main_product(recipe, result_names),
      hidden = is_hidden,
      enabled_without_research = enabled_without_research(recipe),
      parameter = recipe.parameter == true,
      maximum_productivity = recipe.maximum_productivity,
      allow_productivity = recipe.allow_productivity,
      allow_quality = recipe.allow_quality,
      surface_conditions = deepcopy(recipe.surface_conditions),
      source_class = source_class(recipe, categories, is_hidden)
    }
    table.insert(names, recipe_name)
    for _, output_name in ipairs(result_names) do append_index(by_output, output_name, recipe_name) end
    for _, ingredient_name in ipairs(ingredient_names) do append_index(by_ingredient, ingredient_name, recipe_name) end
    for _, category in ipairs(categories) do append_index(by_category, category, recipe_name) end
  end
  table.sort(names)
  for _, index in pairs({by_output, by_ingredient, by_category}) do
    for _, recipe_names in pairs(index) do table.sort(recipe_names) end
  end
  canonical = {
    schema = SCHEMA,
    facts = facts,
    names = names,
    by_output = by_output,
    by_ingredient = by_ingredient,
    by_category = by_category
  }
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

function M.recipes_by_output(name)
  return deepcopy(build().by_output[name] or {})
end

function M.recipes_by_ingredient(name)
  return deepcopy(build().by_ingredient[name] or {})
end

function M.recipes_by_category(name)
  return deepcopy(build().by_category[name] or {})
end

function M.snapshot()
  return deepcopy(build())
end

function M.scan_count()
  build()
  return build_scan_count
end

return M
