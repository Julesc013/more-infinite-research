local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local recipe_semantics = require("prototypes.mir.domain.facts.recipe_semantics")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}
local SCHEMA = 2

local function name_of(entry)
  if type(entry) == "string" then return entry end
  return type(entry) == "table" and (entry.name or entry[1]) or nil
end

local function amount_of(entry)
  if type(entry) ~= "table" then return 1 end
  return tonumber(entry.amount or entry[2] or entry.amount_max or entry.amount_min) or 1
end

local function productive_amount(entry)
  if type(entry) ~= "table" then return 1 end
  local maximum = tonumber(entry.amount_max or entry.amount or entry[2] or entry.amount_min) or 1
  local ignored = tonumber(entry.ignored_by_productivity or 0) or 0
  local probability = tonumber(entry.independent_probability)
  if probability == nil then probability = tonumber(entry.probability) end
  if probability == nil then probability = 1 end
  return math.max(0, maximum - ignored) * probability
end

local function normalized_entry(entry)
  if type(entry) == "string" then
    return {type = "item", name = entry, amount = 1, probability = 1}
  end
  if type(entry) ~= "table" then return nil end
  local name = name_of(entry)
  if not name then return nil end
  local probability = entry.independent_probability
  if probability == nil then probability = entry.probability end
  if probability == nil then probability = 1 end
  return {
    type = entry.type or "item",
    name = name,
    amount = entry.amount or entry[2],
    amount_min = entry.amount_min,
    amount_max = entry.amount_max,
    probability = probability,
    independent_probability = probability,
    declared_probability = entry.probability,
    declared_independent_probability = entry.independent_probability,
    shared_probability = entry.shared_probability,
    extra_count_fraction = entry.extra_count_fraction,
    catalyst_amount = entry.catalyst_amount,
    ignored_by_productivity = entry.ignored_by_productivity,
    ignored_by_stats = entry.ignored_by_stats,
    temperature = entry.temperature,
    minimum_temperature = entry.minimum_temperature,
    maximum_temperature = entry.maximum_temperature,
    fluidbox_index = entry.fluidbox_index,
    percent_spoiled = entry.percent_spoiled,
    always_fresh = entry.always_fresh,
    reset_freshness_on_craft = entry.reset_freshness_on_craft,
    quality_min = entry.quality_min,
    quality_max = entry.quality_max,
    quality_change = entry.quality_change,
    affected_by_quality = entry.affected_by_quality
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
  local semantics = recipe_semantics.resolve(variant.recipe, definition, target_profiles.current())
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
    maximum_productivity = semantics.effective_maximum_productivity,
    declared_maximum_productivity = semantics.declared_maximum_productivity,
    effective_maximum_productivity = semantics.effective_maximum_productivity,
    allow_productivity = semantics.effective_allow_productivity,
    declared_allow_productivity = semantics.declared_allow_productivity,
    effective_allow_productivity = semantics.effective_allow_productivity,
    allow_quality = semantics.effective_allow_quality,
    declared_allow_quality = semantics.declared_allow_quality,
    effective_allow_quality = semantics.effective_allow_quality,
    surface_conditions = deepcopy(definition.surface_conditions)
  }
end

local function variant_facts(recipe)
  local out = {}
  for _, variant in ipairs(variants(recipe)) do
    variant.recipe = recipe
    table.insert(out, normalized_variant(variant))
  end
  return out
end

local function productive_result_names(recipe)
  local seen, out = {}, {}
  for _, variant in ipairs(variants(recipe)) do
    for _, entry in pairs(entries_for(variant.value, "results")) do
      local name = name_of(entry)
      if name and productive_amount(entry) > 0 and not seen[name] then
        seen[name] = true
        table.insert(out, name)
      end
    end
  end
  table.sort(out)
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

local function build_index(recipe_prototypes)
  local facts = {}
  local by_output, by_productive_output, by_ingredient, by_category, names = {}, {}, {}, {}, {}
  for recipe_name, recipe in pairs(recipe_prototypes or {}) do
    local semantics = recipe_semantics.resolve(recipe, recipe, target_profiles.current())
    local normalized_variants = variant_facts(recipe)
    local all_variants_allow_productivity = #normalized_variants > 0
    local effective_maximum_productivity = nil
    for _, variant in ipairs(normalized_variants) do
      if variant.effective_allow_productivity ~= true then all_variants_allow_productivity = false end
      local variant_maximum = tonumber(variant.effective_maximum_productivity)
      if variant_maximum and (effective_maximum_productivity == nil or variant_maximum < effective_maximum_productivity) then
        effective_maximum_productivity = variant_maximum
      end
    end
    local ingredients, ingredient_names = aggregate_io(recipe, "ingredients")
    local results, result_names = aggregate_io(recipe, "results")
    local categories = categories_for(recipe)
    local is_hidden = hidden(recipe)
    local productive_outputs = productive_result_names(recipe)
    facts[recipe_name] = {
      schema = SCHEMA,
      name = recipe_name,
      variants = normalized_variants,
      categories = categories,
      ingredients = ingredients,
      ingredient_names = ingredient_names,
      results = results,
      result_names = result_names,
      productive_result_names = productive_outputs,
      main_product = main_product(recipe, result_names),
      hidden = is_hidden,
      enabled_without_research = enabled_without_research(recipe),
      parameter = recipe.parameter == true,
      maximum_productivity = effective_maximum_productivity,
      declared_maximum_productivity = semantics.declared_maximum_productivity,
      effective_maximum_productivity = effective_maximum_productivity,
      allow_productivity = all_variants_allow_productivity,
      declared_allow_productivity = semantics.declared_allow_productivity,
      effective_allow_productivity = all_variants_allow_productivity,
      allow_quality = semantics.effective_allow_quality,
      declared_allow_quality = semantics.declared_allow_quality,
      effective_allow_quality = semantics.effective_allow_quality,
      surface_conditions = deepcopy(recipe.surface_conditions),
      source_class = source_class(recipe, categories, is_hidden)
    }
    table.insert(names, recipe_name)
    for _, output_name in ipairs(result_names) do append_index(by_output, output_name, recipe_name) end
    for _, output_name in ipairs(productive_outputs) do append_index(by_productive_output, output_name, recipe_name) end
    for _, ingredient_name in ipairs(ingredient_names) do append_index(by_ingredient, ingredient_name, recipe_name) end
    for _, category in ipairs(categories) do append_index(by_category, category, recipe_name) end
  end
  table.sort(names)
  for _, index in pairs({by_output, by_productive_output, by_ingredient, by_category}) do
    for _, recipe_names in pairs(index) do table.sort(recipe_names) end
  end
  local canonical = {
    schema = SCHEMA,
    facts = facts,
    names = names,
    by_output = by_output,
    by_productive_output = by_productive_output,
    by_ingredient = by_ingredient,
    by_category = by_category
  }
  return canonical
end

local function build()
  local context = compiler_context.current()
  local cached = context:state_view("recipe_index")
  if cached then return cached end
  telemetry.start_phase("snapshot")
  local metrics = context:state_view("recipe_index_metrics", function() return {scan_count = 0} end)
  metrics.scan_count = metrics.scan_count + 1
  local canonical = build_index(data_raw.prototypes("recipe"))
  telemetry.count("recipe_index_scans", 1)
  telemetry.count("recipes", #canonical.names)
  telemetry.finish_phase("snapshot")
  return context:set_state("recipe_index", canonical)
end

-- Builds the same canonical index from an explicit prototype map.
-- Offline review and scale tooling use this without mutating the prototype registry
-- or the active CompilerContext.
function M.index_prototypes(recipe_prototypes)
  if type(recipe_prototypes) ~= "table" then
    error("recipe_facts.index_prototypes expects a recipe prototype map", 2)
  end
  return build_index(recipe_prototypes)
end

function M.get(recipe_name)
  local fact = build().facts[recipe_name]
  if fact then telemetry.count("recipe_fact_copies", 1) end
  return fact and deepcopy(fact) or nil
end

-- Internal compiler views avoid repeated deep copies during one immutable
-- data-final-fixes planning pass. Callers must treat returned tables as
-- read-only.
function M.view(recipe_name)
  return build().facts[recipe_name]
end

function M.index_view()
  return build()
end

function M.for_each(callback)
  if type(callback) ~= "function" then error("recipe_facts.for_each expects a callback", 2) end
  local index = build()
  for _, recipe_name in ipairs(index.names) do callback(recipe_name, index.facts[recipe_name]) end
end

function M.summary()
  local index = build()
  return {schema = index.schema, recipe_count = #index.names}
end

function M.fingerprint()
  local context = compiler_context.current()
  return context:state_view("recipe_index_fingerprint", function()
    return require("prototypes.mir.core.fingerprint").of(build())
  end)
end

function M.recipes_by_output_view(name)
  return build().by_output[name] or {}
end

function M.all_names()
  return deepcopy(build().names)
end

function M.candidate_names(outputs, categories, name_patterns)
  local index, selected = build(), {}
  for output_name, wanted in pairs(outputs or {}) do
    if wanted then
      for _, recipe_name in ipairs(index.by_productive_output[output_name] or {}) do selected[recipe_name] = true end
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
  local index = build()
  telemetry.count("recipe_fact_copies", #index.names)
  return deepcopy(index)
end

function M.scan_count()
  build()
  return compiler_context.current():state_view("recipe_index_metrics").scan_count
end

return M
