local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local recipe_semantics = require("prototypes.mir.domain.facts.recipe_semantics")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}
local SCHEMA = 2
local RECIPE_DOMAIN_FIELDS = {"facts", "names", "schema"}
-- This is the active compiler's source-input contract, not the established
-- full recipe-index fingerprint used by generic snapshot/export consumers.
-- Index maps are deterministic derived views of this normalized domain; the
-- explicit revision makes a change to that derivation an input change too.
local ACTIVE_INPUT_SCHEMA = 2
local ACTIVE_INPUT_CONTRACT = "mir-recipe-semantic-source-v2"
local INDEX_DERIVATION_REVISION = 2
local SEMANTIC_SOURCE_SCHEMA = 1
local SEMANTIC_SOURCE_DERIVATION_REVISION = 1

-- A Factorio recipe map is ordinarily a plain unique-keyed table. A custom
-- __pairs iterator can yield a recipe key more than once: facts
-- keep the final row but discovery maps retain every yielded row. Keep that
-- exceptional complete-index binding private to this owner; normal maps still
-- hash only their normalized fact domain.
local exceptional_complete_index_identity = setmetatable({}, {__mode = "k"})

-- Active-only source ownership is intentionally module-local.  Context state
-- is part of a supported generic export, so persisting these implementation
-- records there would change a requested schema-2 Context snapshot even when
-- its ordinary full recipe index remains byte-for-byte identical.  Each cache
-- is keyed by the actual Context and checked against recipe_source_epoch.
local semantic_sources = setmetatable({}, {__mode = "k"})
local semantic_projections = setmetatable({}, {__mode = "k"})
local semantic_facts = setmetatable({}, {__mode = "k"})
local recipe_source_modes = setmetatable({}, {__mode = "k"})

-- replace_source() is a controlled pre-snapshot operation, not a general
-- mutable-prototype escape hatch. The science indexes below deliberately
-- key themselves to recipe_source_epoch, but these immutable compiler
-- snapshots have broader recipe-derived closure and cannot be soundly
-- rewritten by replacing one recipe map in place.
local RECIPE_SNAPSHOT_STATE_NAMES = {
  "approved_lab_bindings",
  "approved_research_bindings",
  "relationship_indexes",
  "recipe_risk_index",
  "recipe_risk_materialization",
  "mod_progression_cache",
  "material_route_graph",
  "stream_match_index",
  "family_resolution",
  "family_resolution_query_index",
  "generation_plan",
  "compilation_snapshot",
  "qualification_snapshot",
  "compiler_input",
  "pure_compilation",
  "compilation_plan",
  "technology_candidate_catalog",
  "technology_qualifications",
  "compiler_result",
  "final_compiler_result",
  "coverage_report"
}

local function name_of(entry)
  if type(entry) == "string" then return entry end
  return type(entry) == "table" and (entry.name or entry[1]) or nil
end

-- Recipe ingredients and products share a textual namespace only by
-- coincidence.  Keep the legacy name-only projections for existing callers,
-- but give route planning an exact type/name projection so an item called
-- "water" can never satisfy a fluid requirement called "water".
local function identity_key(entry_type, name)
  return tostring(entry_type or "item") .. "\0" .. tostring(name or "")
end

local function amount_of(entry)
  if type(entry) ~= "table" then return 1 end
  return tonumber(entry.amount or entry[2] or entry.amount_max or entry.amount_min) or 1
end

local function has_productive_output(entry)
  if type(entry) ~= "table" then return true end
  local profile = target_profiles.current()
  local fields = profile and profile.prototype_shapes and profile.prototype_shapes.product_probability_fields or {}
  local function supports(field)
    for _, declared in ipairs(fields) do if declared == field then return true end end
    return false
  end
  -- Modern authored fields cannot grant productive identities on an older
  -- target. Normalized facts retain those fields separately for diagnostics.
  for _, field in ipairs({"independent_probability", "shared_probability", "extra_count_fraction"}) do
    if entry[field] ~= nil and not supports(field) then return false end
  end
  local maximum = recipe_semantics.maximum_base_result_amount(entry)
  local ignored = recipe_semantics.productivity_excluded_amount(entry, profile)
  local probability = entry.independent_probability
  if probability == nil then probability = entry.probability end
  if probability == nil then probability = 1 end
  probability = tonumber(probability)
  if probability == nil or probability ~= probability or probability <= 0 or probability > 1 then return false end
  local shared = entry.shared_probability
  if shared ~= nil then
    if type(shared) ~= "table" or type(shared.min) ~= "number" or type(shared.max) ~= "number"
      or shared.min ~= shared.min or shared.max ~= shared.max
      or shared.min < 0 or shared.max > 1 or shared.min >= shared.max then return false end
  end
  local extra = 0
  if (entry.type or "item") == "item" and ignored == 0 then
    extra = tonumber(entry.extra_count_fraction or 0)
    if extra == nil or extra ~= extra or extra < 0 or extra > 1 then return false end
  end
  -- This projection asks whether a useful bonus output is possible. It is
  -- not an expected-yield or profitable-loop certificate. An unexcluded
  -- fractional item roll is productive even when the base amount is zero;
  -- excluded-base fractional returns still need their own native witness.
  return maximum - ignored > 0 or extra > 0
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
  local amount = entry.amount
  if amount == nil then amount = entry[2] end
  return {
    type = entry.type or "item",
    name = name,
    amount = amount,
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
        local identity = identity_key((type(entry) == "table" and entry.type) or "item", name)
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
  local out, identities = {}, {}
  for _, identity in ipairs((function()
    local identities = {}
    for key, _ in pairs(by_name) do table.insert(identities, key) end
    table.sort(identities)
    return identities
  end)()) do
    table.insert(out, by_name[identity])
    table.insert(identities, by_name[identity])
  end
  return out, names, identities
end

local function normalized_variant(variant)
  local definition = variant.value
  local semantics = recipe_semantics.resolve(variant.recipe, definition, target_profiles.current())
  local ingredients, results = {}, {}
  local categories = recipe_semantics.recipe_categories(variant.recipe, definition)
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

local function productive_results(recipe)
  local seen_names, seen_identities, names, identities = {}, {}, {}, {}
  for _, variant in ipairs(variants(recipe)) do
    for _, entry in pairs(entries_for(variant.value, "results")) do
      local name = name_of(entry)
      local entry_type = (type(entry) == "table" and entry.type) or "item"
      local key = identity_key(entry_type, name)
      if name and has_productive_output(entry) then
        if not seen_names[name] then
          seen_names[name] = true
          table.insert(names, name)
        end
        if not seen_identities[key] then
          seen_identities[key] = true
          table.insert(identities, {type = entry_type, name = name})
        end
      end
    end
  end
  table.sort(names)
  table.sort(identities, function(a, b)
    if a.type ~= b.type then return a.type < b.type end
    return a.name < b.name
  end)
  return names, identities
end

local function categories_for(normalized_variants)
  local seen, out = {}, {}
  local function add(category)
    if not seen[category] then seen[category] = true; table.insert(out, category) end
  end
  for _, variant in ipairs(normalized_variants) do
    for _, category in ipairs(variant.categories) do add(category) end
  end
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
  local by_output, by_output_identity = {}, {}
  local by_productive_output, by_productive_output_identity = {}, {}
  local by_ingredient, by_ingredient_identity, by_category, names = {}, {}, {}, {}
  local duplicate_recipe_name = false
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
    local ingredients, ingredient_names, ingredient_identities = aggregate_io(recipe, "ingredients")
    local results, result_names, result_identities = aggregate_io(recipe, "results")
    local categories = categories_for(normalized_variants)
    local is_hidden = hidden(recipe)
    local productive_outputs, productive_output_identities = productive_results(recipe)
    if facts[recipe_name] ~= nil then duplicate_recipe_name = true end
    facts[recipe_name] = {
      schema = SCHEMA,
      name = recipe_name,
      variants = normalized_variants,
      categories = categories,
      ingredients = ingredients,
      ingredient_names = ingredient_names,
      ingredient_identities = ingredient_identities,
      results = results,
      result_names = result_names,
      result_identities = result_identities,
      productive_result_names = productive_outputs,
      productive_result_identities = productive_output_identities,
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
    for _, output in ipairs(result_identities) do
      append_index(by_output_identity, identity_key(output.type, output.name), recipe_name)
    end
    for _, output_name in ipairs(productive_outputs) do append_index(by_productive_output, output_name, recipe_name) end
    for _, output in ipairs(productive_output_identities) do
      append_index(by_productive_output_identity, identity_key(output.type, output.name), recipe_name)
    end
    for _, ingredient_name in ipairs(ingredient_names) do append_index(by_ingredient, ingredient_name, recipe_name) end
    for _, ingredient in ipairs(ingredient_identities) do
      append_index(by_ingredient_identity, identity_key(ingredient.type, ingredient.name), recipe_name)
    end
    for _, category in ipairs(categories) do append_index(by_category, category, recipe_name) end
  end
  table.sort(names)
  for _, index in pairs({
    by_output, by_output_identity,
    by_productive_output, by_productive_output_identity,
    by_ingredient, by_ingredient_identity, by_category
  }) do
    for _, recipe_names in pairs(index) do table.sort(recipe_names) end
  end
  local canonical = {
    schema = SCHEMA,
    facts = facts,
    names = names,
    by_output = by_output,
    by_output_identity = by_output_identity,
    by_productive_output = by_productive_output,
    by_productive_output_identity = by_productive_output_identity,
    by_ingredient = by_ingredient,
    by_ingredient_identity = by_ingredient_identity,
    by_category = by_category
  }
  if duplicate_recipe_name then exceptional_complete_index_identity[canonical] = true end
  return canonical
end

-- Recipe facts are a snapshot, not a live view of data.raw.  A writer that
-- changes recipes after this module has been queried must replace the source
-- through replace_source().  That single operation advances the Context
-- epoch and gives all epoch-aware consumers an unambiguous invalidation point.
-- The active Factorio source is captured into one Context-owned semantic record.
-- It is deliberately not a public view: generic indexes and exports still build
-- detached schema-2 RecipeFacts only at their explicit boundary.  Explicit
-- caller-supplied sources retain the legacy converter below, because table
-- identity and an external table's apparent shape never prove immutability.
local function state_replace_or_set(context, name, value)
  if context:has_state(name) then
    return context:replace_epoch(name, value, context:state_epoch(name))
  end
  return context:set_state(name, value)
end

local function source_requires_legacy_conversion(context)
  return recipe_source_modes[context] == "legacy"
end

-- Forward declarations are required because the Context source/epoch owner is
-- defined after the source record helpers below.  Keeping this one source
-- authority in the same module avoids an ambient platform dependency.
local source_prototypes
local source_epoch

-- This structural admission happens before *any* semantic reader. In
-- particular, has_productive_output() consults probability fields, so calling
-- it before rejecting a dynamic entry could observe a getter once here and
-- again in the established generic fallback.
-- Retained metadata is exceptional: unlike scalar entry fields, it is copied
-- into the semantic owner. Validate only those retained subtrees before
-- deepcopy can invoke a virtual iterator. An alias is safe; a cycle cannot be
-- fingerprinted by the semantic owner without changing the established active
-- `get`/`view` behavior, so it selects the existing generic converter instead
-- of rejecting the caller's source outright.
local function scalar_value_is_admissible(value)
  local kind = type(value)
  return kind == "nil" or kind == "boolean" or kind == "number" or kind == "string"
end

local function metadata_tree_is_admissible(value, visiting, completed)
  if type(value) ~= "table" then return scalar_value_is_admissible(value) end
  if getmetatable(value) ~= nil then return false end
  if completed[value] then return true end
  if visiting[value] then return false end
  visiting[value] = true
  for key, nested in next, value do
    local key_kind = type(key)
    if (key_kind ~= "string" and key_kind ~= "number")
        or not metadata_tree_is_admissible(nested, visiting, completed) then
      visiting[value] = nil
      return false
    end
  end
  visiting[value] = nil
  completed[value] = true
  return true
end

local function retained_metadata_is_admissible(value)
  if type(value) ~= "table" then return scalar_value_is_admissible(value) end
  return metadata_tree_is_admissible(value, {}, {})
end

-- Normalized records have owned string keys, but malformed imported scalar
-- fields can still contain a table, callback or cycle. Inspect the retained
-- values before copying or hashing them; otherwise active source installation
-- could reject an input whose established generic view succeeds until an
-- explicit fingerprint request. Valid scalar fields take no tree allocation.
local function retained_values_are_admissible(record)
  for _, value in pairs(record) do
    if not retained_metadata_is_admissible(value) then return false end
  end
  return true
end

local function scalar_values_are_admissible(record)
  for _, value in pairs(record) do
    if not scalar_value_is_admissible(value) then return false end
  end
  return true
end

local function source_entry_is_plain(entry)
  if type(entry) ~= "table" then return true end
  if getmetatable(entry) ~= nil then return false end
  return retained_metadata_is_admissible(rawget(entry, "shared_probability"))
end

local function new_owned_metadata_copier()
  local copies = setmetatable({}, {__mode = "k"})
  return function(value)
    if value == nil then return nil, true end
    if type(value) ~= "table" then
      if not retained_metadata_is_admissible(value) then return nil, false end
      return deepcopy(value), true
    end
    if copies[value] then return copies[value], true end
    if not retained_metadata_is_admissible(value) then return nil, false end
    local copied = deepcopy(value)
    copies[value] = copied
    return copied, true
  end
end

local function source_entry(entry, productive, copy_metadata)
  if not source_entry_is_plain(entry) then return nil end
  local shared_value
  if type(entry) == "table" then shared_value = rawget(entry, "shared_probability") end
  local shared_probability, shared_ok = copy_metadata(shared_value)
  if not shared_ok then return nil end
  local normalized = normalized_entry(entry)
  if not normalized then return nil end
  -- The semantic owner must not borrow a raw retained descriptor. The generic
  -- full fact is later rebuilt from this detached value, so a source mutation
  -- after capture cannot silently change planning or active identity.
  normalized.shared_probability = shared_probability
  if not retained_values_are_admissible(normalized) then return nil end
  return {value = deepcopy(normalized), productive = productive == true}
end

local function source_entries(definition, field, copy_metadata)
  if type(definition) == "table" and getmetatable(definition) ~= nil then return nil end
  local entries = entries_for(definition, field)
  if type(entries) ~= "table" or getmetatable(entries) ~= nil then return nil end
  local out = {}
  for _, entry in pairs(entries) do
    -- Do not make an eligibility-failing dynamic entry observable merely to
    -- determine productivity. The legacy converter owns its original read
    -- order and will handle this source after this function returns nil.
    if not source_entry_is_plain(entry) then return nil end
    local productive = field == "results" and has_productive_output(entry)
    local value = source_entry(entry, productive, copy_metadata)
    if not value then return nil end
    table.insert(out, value)
  end
  return out
end

local function source_variant(recipe, variant, copy_metadata)
  local definition = variant.value
  if type(definition) ~= "table" or getmetatable(definition) ~= nil then return nil end
  if type(rawget(definition, "categories")) == "table" and getmetatable(rawget(definition, "categories")) ~= nil then return nil end
  local surface_conditions, surface_ok = copy_metadata(rawget(definition, "surface_conditions"))
  if not surface_ok then return nil end
  local ingredients = source_entries(definition, "ingredients", copy_metadata)
  local results = source_entries(definition, "results", copy_metadata)
  if not ingredients or not results then return nil end
  local semantics = recipe_semantics.resolve(recipe, definition, target_profiles.current())
  local energy_required = definition.energy_required
  local main_product = definition.main_product or definition.result
  if not scalar_values_are_admissible(semantics)
      or not scalar_value_is_admissible(energy_required)
      or not scalar_value_is_admissible(main_product) then return nil end
  return {
    name = variant.name,
    categories = deepcopy(recipe_semantics.recipe_categories(recipe, definition)),
    ingredients = ingredients,
    results = results,
    enabled = definition.enabled ~= false,
    hidden = definition.hidden == true,
    energy_required = energy_required,
    main_product = main_product,
    maximum_productivity = semantics.effective_maximum_productivity,
    declared_maximum_productivity = semantics.declared_maximum_productivity,
    effective_maximum_productivity = semantics.effective_maximum_productivity,
    allow_productivity = semantics.effective_allow_productivity,
    declared_allow_productivity = semantics.declared_allow_productivity,
    effective_allow_productivity = semantics.effective_allow_productivity,
    allow_quality = semantics.effective_allow_quality,
    declared_allow_quality = semantics.declared_allow_quality,
    effective_allow_quality = semantics.effective_allow_quality,
    surface_conditions = surface_conditions
  }
end

local function source_recipe(recipe_name, recipe)
  if type(recipe) ~= "table" or getmetatable(recipe) ~= nil then return nil end
  if type(rawget(recipe, "categories")) == "table" and getmetatable(rawget(recipe, "categories")) ~= nil then return nil end
  local copy_metadata = new_owned_metadata_copier()
  local surface_conditions, surface_ok = copy_metadata(rawget(recipe, "surface_conditions"))
  if not surface_ok then return nil end
  local semantics = recipe_semantics.resolve(recipe, recipe, target_profiles.current())
  if not scalar_values_are_admissible(semantics)
      or not scalar_value_is_admissible(recipe.main_product) then return nil end
  local variants_out = {}
  for _, variant in ipairs(variants(recipe)) do
    local value = source_variant(recipe, variant, copy_metadata)
    if not value then return nil end
    table.insert(variants_out, value)
  end
  return {
    name = recipe_name,
    variants = variants_out,
    root_hidden = recipe.hidden == true,
    root_enabled = recipe.enabled ~= false,
    root_main_product = recipe.main_product,
    parameter = recipe.parameter == true,
    surface_conditions = surface_conditions,
    semantics = deepcopy(semantics)
  }
end

local function build_semantic_source(recipe_prototypes)
  if type(recipe_prototypes) ~= "table" or getmetatable(recipe_prototypes) ~= nil then return nil end
  local recipes, names = {}, {}
  for recipe_name, recipe in pairs(recipe_prototypes) do
    -- Duplicate virtual keys are a documented generic input shape.  The active
    -- semantic owner is only for ordinary unique Factorio prototype maps; the
    -- full legacy index keeps the exceptional discovery-map binding.
    if type(recipe_name) ~= "string" or recipes[recipe_name] ~= nil then return nil end
    local record = source_recipe(recipe_name, recipe)
    if not record then return nil end
    recipes[recipe_name] = record
    table.insert(names, recipe_name)
  end
  table.sort(names)
  return {schema = SEMANTIC_SOURCE_SCHEMA, names = names, recipes = recipes}
end

local function source_variant_entries(source_variant_value, field)
  local out = {}
  for _, entry in ipairs(source_variant_value[field] or {}) do table.insert(out, entry.value) end
  return out
end

-- Material-route callbacks need only a typed identity and the exact fields
-- consulted by result_is_definitely_zero(). Do not expose private normalized
-- entry tables to a callback that can retain or mutate them.
local function route_entry_descriptor(entry)
  local shared = entry.shared_probability
  return {
    type = entry.type,
    name = entry.name,
    amount = entry.amount,
    amount_min = entry.amount_min,
    amount_max = entry.amount_max,
    probability = entry.probability,
    independent_probability = entry.independent_probability,
    declared_probability = entry.declared_probability,
    declared_independent_probability = entry.declared_independent_probability,
    shared_probability = type(shared) == "table" and {min = shared.min, max = shared.max} or shared,
    extra_count_fraction = entry.extra_count_fraction
  }
end

local function route_variant_entries(source_variant_value, field)
  local out = {}
  for _, entry in ipairs(source_variant_value[field] or {}) do
    table.insert(out, route_entry_descriptor(entry.value))
  end
  return out
end

local function semantic_variant_fact(source_variant_value)
  local ingredients = deepcopy(source_variant_entries(source_variant_value, "ingredients"))
  local results = deepcopy(source_variant_entries(source_variant_value, "results"))
  local function entry_order(a, b)
    if a.type ~= b.type then return a.type < b.type end
    return a.name < b.name
  end
  table.sort(ingredients, entry_order)
  table.sort(results, entry_order)
  return {
    name = source_variant_value.name,
    categories = deepcopy(source_variant_value.categories),
    ingredients = ingredients,
    results = results,
    enabled = source_variant_value.enabled,
    hidden = source_variant_value.hidden,
    energy_required = source_variant_value.energy_required,
    main_product = source_variant_value.main_product,
    maximum_productivity = source_variant_value.maximum_productivity,
    declared_maximum_productivity = source_variant_value.declared_maximum_productivity,
    effective_maximum_productivity = source_variant_value.effective_maximum_productivity,
    allow_productivity = source_variant_value.allow_productivity,
    declared_allow_productivity = source_variant_value.declared_allow_productivity,
    effective_allow_productivity = source_variant_value.effective_allow_productivity,
    allow_quality = source_variant_value.allow_quality,
    declared_allow_quality = source_variant_value.declared_allow_quality,
    effective_allow_quality = source_variant_value.effective_allow_quality,
    surface_conditions = deepcopy(source_variant_value.surface_conditions)
  }
end

local function aggregate_source_io(record, field)
  local by_name = {}
  for _, variant in ipairs(record.variants) do
    for _, wrapper in ipairs(variant[field] or {}) do
      local entry = wrapper.value
      local identity = identity_key(entry.type, entry.name)
      local aggregate = by_name[identity] or {type = entry.type, name = entry.name, amount = 0}
      aggregate.amount = aggregate.amount + amount_of(entry)
      by_name[identity] = aggregate
    end
  end
  local names, seen_names, ordered = {}, {}, {}
  for identity, entry in pairs(by_name) do
    table.insert(ordered, identity)
    if not seen_names[entry.name] then seen_names[entry.name] = true; table.insert(names, entry.name) end
  end
  table.sort(names)
  table.sort(ordered)
  local rows, identities = {}, {}
  for _, identity in ipairs(ordered) do
    table.insert(rows, by_name[identity])
    table.insert(identities, by_name[identity])
  end
  return rows, names, identities
end

local function productive_source_results(record)
  local seen_names, seen_identities, names, identities = {}, {}, {}, {}
  for _, variant in ipairs(record.variants) do
    for _, wrapper in ipairs(variant.results or {}) do
      local entry = wrapper.value
      local key = identity_key(entry.type, entry.name)
      if wrapper.productive then
        if not seen_names[entry.name] then seen_names[entry.name] = true; table.insert(names, entry.name) end
        if not seen_identities[key] then
          seen_identities[key] = true
          table.insert(identities, {type = entry.type, name = entry.name})
        end
      end
    end
  end
  table.sort(names)
  table.sort(identities, function(a, b)
    if a.type ~= b.type then return a.type < b.type end
    return a.name < b.name
  end)
  return names, identities
end

local function categories_from_source(record)
  local seen, out = {}, {}
  for _, variant in ipairs(record.variants) do
    for _, category in ipairs(variant.categories or {}) do
      if not seen[category] then seen[category] = true; table.insert(out, category) end
    end
  end
  table.sort(out)
  return out
end

local function hidden_from_source(record)
  if record.root_hidden then return true end
  for _, variant in ipairs(record.variants) do if variant.hidden then return true end end
  return false
end

local function enabled_from_source(record)
  if record.root_hidden or not record.root_enabled then return false end
  for _, variant in ipairs(record.variants) do if variant.hidden or not variant.enabled then return false end end
  return true
end

local function main_product_from_source(record, result_names)
  if record.root_main_product then return record.root_main_product end
  for _, variant in ipairs(record.variants) do if variant.main_product then return variant.main_product end end
  return #result_names == 1 and result_names[1] or nil
end

local function coverage_fact_from_source(record)
  local all_allow, effective_maximum = #record.variants > 0, nil
  local variants_out = {}
  for _, variant in ipairs(record.variants) do
    if variant.effective_allow_productivity ~= true then all_allow = false end
    local maximum = tonumber(variant.effective_maximum_productivity)
    if maximum and (effective_maximum == nil or maximum < effective_maximum) then effective_maximum = maximum end
    local function entries(field)
      local out = {}
      for _, wrapper in ipairs(variant[field] or {}) do
        local entry = wrapper.value
        out[#out + 1] = {
          name = entry.name,
          amount = entry.amount,
          amount_min = entry.amount_min,
          amount_max = entry.amount_max,
          ignored_by_productivity = entry.ignored_by_productivity
        }
      end
      return out
    end
    variants_out[#variants_out + 1] = {
      ingredients = entries("ingredients"),
      results = entries("results")
    }
  end
  local categories = categories_from_source(record)
  local is_hidden = hidden_from_source(record)
  return {
    name = record.name,
    hidden = is_hidden,
    parameter = record.parameter,
    source_class = source_class({parameter = record.parameter}, categories, is_hidden),
    allow_productivity = all_allow,
    maximum_productivity = effective_maximum,
    variants = variants_out
  }
end

local function fact_from_source(record)
  local variants_out, all_allow, effective_maximum = {}, #record.variants > 0, nil
  for _, variant in ipairs(record.variants) do
    local fact_variant = semantic_variant_fact(variant)
    table.insert(variants_out, fact_variant)
    if fact_variant.effective_allow_productivity ~= true then all_allow = false end
    local maximum = tonumber(fact_variant.effective_maximum_productivity)
    if maximum and (effective_maximum == nil or maximum < effective_maximum) then effective_maximum = maximum end
  end
  local ingredients, ingredient_names, ingredient_identities = aggregate_source_io(record, "ingredients")
  local results, result_names, result_identities = aggregate_source_io(record, "results")
  local categories = categories_from_source(record)
  local is_hidden = hidden_from_source(record)
  local productive_names, productive_identities = productive_source_results(record)
  return {
    schema = SCHEMA, name = record.name, variants = variants_out, categories = categories,
    ingredients = ingredients, ingredient_names = ingredient_names, ingredient_identities = ingredient_identities,
    results = results, result_names = result_names, result_identities = result_identities,
    productive_result_names = productive_names, productive_result_identities = productive_identities,
    main_product = main_product_from_source(record, result_names), hidden = is_hidden,
    enabled_without_research = enabled_from_source(record), parameter = record.parameter,
    maximum_productivity = effective_maximum,
    declared_maximum_productivity = record.semantics.declared_maximum_productivity,
    effective_maximum_productivity = effective_maximum, allow_productivity = all_allow,
    declared_allow_productivity = record.semantics.declared_allow_productivity,
    effective_allow_productivity = all_allow,
    allow_quality = record.semantics.effective_allow_quality,
    declared_allow_quality = record.semantics.declared_allow_quality,
    effective_allow_quality = record.semantics.effective_allow_quality,
    surface_conditions = deepcopy(record.surface_conditions),
    source_class = source_class({parameter = record.parameter}, categories, is_hidden)
  }
end

local function append_semantic_index(index, key, recipe_name)
  index[key] = index[key] or {}
  table.insert(index[key], recipe_name)
end

local function sort_semantic_indexes(indexes)
  for _, index in pairs(indexes) do
    for _, recipe_names in pairs(index) do table.sort(recipe_names) end
  end
end

local function membership_from_source(record, field, productive_only)
  local names, identities, seen_names, seen_identities = {}, {}, {}, {}
  for _, variant in ipairs(record.variants) do
    for _, wrapper in ipairs(variant[field] or {}) do
      if not productive_only or wrapper.productive then
        local entry = wrapper.value
        local key = identity_key(entry.type, entry.name)
        if not seen_names[entry.name] then
          seen_names[entry.name] = true
          names[#names + 1] = entry.name
        end
        if not seen_identities[key] then
          seen_identities[key] = true
          identities[#identities + 1] = {type = entry.type, name = entry.name}
        end
      end
    end
  end
  table.sort(names)
  table.sort(identities, function(a, b)
    if a.type ~= b.type then return a.type < b.type end
    return a.name < b.name
  end)
  return names, identities
end

local function projection_from_source(source)
  local projection = {
    schema = SCHEMA, names = deepcopy(source.names), name_set = {},
    by_output = {}, by_output_identity = {},
    by_productive_output = {}, by_productive_output_identity = {},
    by_ingredient = {}, by_ingredient_identity = {}, by_category = {},
    surface_conditions = {}
  }
  for _, recipe_name in ipairs(source.names) do
    projection.name_set[recipe_name] = true
    local record = source.recipes[recipe_name]
    local categories = categories_from_source(record)
    local result_names, result_identities = membership_from_source(record, "results", false)
    local ingredient_names, ingredient_identities = membership_from_source(record, "ingredients", false)
    local productive_names, productive_identities = membership_from_source(record, "results", true)
    for _, name in ipairs(result_names) do append_semantic_index(projection.by_output, name, recipe_name) end
    for _, row in ipairs(result_identities) do append_semantic_index(projection.by_output_identity, identity_key(row.type, row.name), recipe_name) end
    for _, name in ipairs(productive_names) do append_semantic_index(projection.by_productive_output, name, recipe_name) end
    for _, row in ipairs(productive_identities) do append_semantic_index(projection.by_productive_output_identity, identity_key(row.type, row.name), recipe_name) end
    for _, name in ipairs(ingredient_names) do append_semantic_index(projection.by_ingredient, name, recipe_name) end
    for _, row in ipairs(ingredient_identities) do append_semantic_index(projection.by_ingredient_identity, identity_key(row.type, row.name), recipe_name) end
    for _, category in ipairs(categories) do append_semantic_index(projection.by_category, category, recipe_name) end
    if record.surface_conditions then projection.surface_conditions[recipe_name] = deepcopy(record.surface_conditions) end
  end
  sort_semantic_indexes({projection.by_output, projection.by_output_identity,
    projection.by_productive_output, projection.by_productive_output_identity,
    projection.by_ingredient, projection.by_ingredient_identity, projection.by_category})
  return projection
end

local function build_index_from_source(source)
  local projection = projection_from_source(source)
  local facts = {}
  for _, recipe_name in ipairs(source.names) do facts[recipe_name] = fact_from_source(source.recipes[recipe_name]) end
  return {
    schema = SCHEMA, facts = facts, names = projection.names,
    by_output = projection.by_output, by_output_identity = projection.by_output_identity,
    by_productive_output = projection.by_productive_output,
    by_productive_output_identity = projection.by_productive_output_identity,
    by_ingredient = projection.by_ingredient,
    by_ingredient_identity = projection.by_ingredient_identity,
    by_category = projection.by_category
  }
end

-- The owner callback is installed exactly once per CompilerContext.  Its
-- closed-over `build` resolves the current Context source epoch when an
-- explicit legacy export asks for schema-2 recipe facts; it never calls a
-- caller-replaceable public API or recreates compiler decisions.
local build

local function install_semantic_source(context, epoch, source)
  -- Keep the established scan/recipe accounting associated with the one
  -- authoritative source capture. An explicit generic full-index boundary
  -- below reuses this material and must not count the world a second time.
  local metrics = context:state_view("recipe_index_metrics", function() return {scan_count = 0} end)
  metrics.scan_count = metrics.scan_count + 1
  telemetry.count("recipe_index_scans", 1)
  telemetry.count("recipes", #source.names)
  semantic_sources[context] = {
    recipe_source_epoch = epoch,
    source = source,
    -- This digest is the one authoritative active input witness for the
    -- owned semantic source. It is scalar cache material, never a claimed
    -- immutable caller-owned table or a generic exported RecipeFacts digest.
    semantic_fingerprint = fingerprint.of({
      schema = source.schema,
      names = source.names,
      recipes = source.recipes
    })
  }
  semantic_projections[context] = nil
  semantic_facts[context] = nil
  if not context:has_service("recipe_facts.materialize_export") then
    context:set_service("recipe_facts.materialize_export", function()
      -- `build` uses compiler_context.current(), and state_snapshot()/snapshot()
      -- establish this exact Context with with_active before calling us.
      return build()
    end)
  end
  return source
end

local function semantic_source(context)
  -- A default Context has an established byte-stable schema-2 export
  -- contract. It deliberately retains the complete fact/index identity and
  -- materializes through the generic path. The semantic source is private to
  -- the ordinary active-only compiler; this is an export-mode boundary, not
  -- an environment- or caller-origin exemption.
  if context:legacy_compiler_export_requested() then return nil end
  if source_requires_legacy_conversion(context) then return nil end
  local epoch = source_epoch(context)
  local cached = semantic_sources[context]
  if cached and cached.recipe_source_epoch == epoch then return cached.source end
  local source = build_semantic_source(source_prototypes(context))
  if not source then
    -- The real boundary is structural: dynamic/metatable-backed sources and
    -- duplicate virtual keys retain the established converter. This is not
    -- an environment-name or caller-origin branch.
    recipe_source_modes[context] = "legacy"
    return nil
  end
  recipe_source_modes[context] = "owned"
  return install_semantic_source(context, epoch, source)
end

local function semantic_material(context)
  local source = semantic_source(context)
  if not source then return nil end
  return semantic_sources[context]
end

local function semantic_projection(context)
  local source = semantic_source(context)
  if not source then return nil end
  local epoch = source_epoch(context)
  local cached = semantic_projections[context]
  if cached and cached.recipe_source_epoch == epoch then return cached.projection end
  local material = {recipe_source_epoch = epoch, projection = projection_from_source(source)}
  semantic_projections[context] = material
  return material.projection
end

local function semantic_fact(context, recipe_name)
  local source = semantic_source(context)
  if not source then return nil end
  local epoch = source_epoch(context)
  local cached = semantic_facts[context]
  if not cached or cached.recipe_source_epoch ~= epoch then
    cached = {recipe_source_epoch = epoch, facts = {}}
    semantic_facts[context] = cached
  end
  if cached.facts[recipe_name] == nil and source.recipes[recipe_name] then
    cached.facts[recipe_name] = fact_from_source(source.recipes[recipe_name])
    telemetry.count("recipe_semantic_lazy_facts", 1)
  end
  return cached.facts[recipe_name]
end

source_prototypes = function(context)
  return context:state_view("recipe_source", function()
    return data_raw.prototypes("recipe")
  end)
end

source_epoch = function(context)
  source_prototypes(context)
  return context:state_epoch("recipe_source") or 1
end

local function rebuild(context)
  telemetry.start_phase("snapshot")
  local source = semantic_source(context)
  local canonical
  if source then
    canonical = build_index_from_source(source)
  else
    local metrics = context:state_view("recipe_index_metrics", function() return {scan_count = 0} end)
    metrics.scan_count = metrics.scan_count + 1
    canonical = build_index(source_prototypes(context))
    telemetry.count("recipe_index_scans", 1)
    telemetry.count("recipes", #canonical.names)
  end
  telemetry.finish_phase("snapshot")
  if context:has_state("recipe_index") then
    return context:replace_epoch("recipe_index", canonical, context:state_epoch("recipe_index"))
  end
  return context:set_state("recipe_index", canonical)
end

build = function()
  local context = compiler_context.current()
  local cached = context:state_view("recipe_index")
  if cached then return cached end
  return rebuild(context)
end

-- The full recipe index and the compiler snapshot's recipes domain share the
-- same owned facts/names/schema fields.  Keep only their scalar digests and
-- byte count under the Context epoch: no canonical text or mutable index
-- reference escapes into this cache.  The projection helper validates every
-- field of the complete index, so the full digest retains its established
-- identity while the later snapshot need not traverse the shared facts again.
local function new_fingerprint_material(context, index)
  local full, recipe_domain, recipe_domain_bytes = fingerprint.of_map_with_projection(
    index, RECIPE_DOMAIN_FIELDS)
  return {
    recipe_source_epoch = source_epoch(context),
    recipe_index_epoch = context:state_epoch("recipe_index"),
    full = full,
    recipe_domain = recipe_domain,
    recipe_domain_bytes = recipe_domain_bytes
  }
end

local function fingerprint_material(context)
  local index = build()
  local source = source_epoch(context)
  local index_epoch = context:state_epoch("recipe_index")
  local cached = context:state_view("recipe_index_fingerprint_material")
  if cached
    and cached.recipe_source_epoch == source
    and cached.recipe_index_epoch == index_epoch then
    return cached
  end
  local material = new_fingerprint_material(context, index)
  if cached then
    context:replace_epoch("recipe_index_fingerprint_material", material,
      context:state_epoch("recipe_index_fingerprint_material"))
  else
    context:set_state("recipe_index_fingerprint_material", material)
  end
  return material
end

local function active_input_identity_material(context)
  local source = semantic_material(context)
  if source then
    return {
      recipe_source_epoch = source.recipe_source_epoch,
      recipe_index_epoch = nil,
      mode = "semantic-source",
      identity = {
        schema = ACTIVE_INPUT_SCHEMA,
        record_type = "RecipeSemanticInput",
        contract = ACTIVE_INPUT_CONTRACT,
        semantic_source_schema = source.source.schema,
        semantic_source_derivation_revision = SEMANTIC_SOURCE_DERIVATION_REVISION,
        semantic_source_fingerprint = source.semantic_fingerprint
      }
    }
  end

  -- Explicit caller-owned sources retain the established v1 normalized-index
  -- contract.  This preserves duplicate virtual-key and dynamic reader
  -- semantics at the generic boundary rather than treating table identity or
  -- a shallow plain-table check as proof of immutable source ownership.
  local index = build()
  local identity = {
    schema = ACTIVE_INPUT_SCHEMA,
    record_type = "RecipeNormalizedInput",
    contract = "mir-recipe-normalized-input-v1",
    recipe_index_schema = index.schema,
    index_derivation_revision = 1,
    normalized_fact_domain_fingerprint = fingerprint.of({
      schema = index.schema,
      names = index.names,
      facts = index.facts
    })
  }
  if exceptional_complete_index_identity[index] then
    identity.exceptional_complete_index_fingerprint = fingerprint.of(index)
  end
  return {
    recipe_source_epoch = source_epoch(context),
    recipe_index_epoch = context:state_epoch("recipe_index"),
    mode = "legacy-index",
    identity = identity
  }
end

-- The ordinary compiler records a versioned identity of its Context-owned
-- semantic source.  Generic snapshot/export paths retain fingerprint(),
-- which materializes the established full schema-2 index at that boundary.
function M.active_input_identity()
  local context = compiler_context.current()
  local source = source_epoch(context)
  local cached = context:state_view("recipe_active_input_identity")
  local expected_mode = semantic_source(context) and "semantic-source" or "legacy-index"
  if cached and cached.recipe_source_epoch == source and cached.mode == expected_mode then
    if expected_mode ~= "legacy-index"
      or cached.recipe_index_epoch == context:state_epoch("recipe_index") then
      return deepcopy(cached.identity)
    end
  end
  local material = active_input_identity_material(context)
  if cached then
    context:replace_epoch("recipe_active_input_identity", material,
      context:state_epoch("recipe_active_input_identity"))
  else
    context:set_state("recipe_active_input_identity", material)
  end
  return deepcopy(material.identity)
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

-- Replace the active recipe source for the current CompilerContext.  This is
-- deliberately an explicit operation: direct data.raw mutation after a fact
-- snapshot has been built cannot safely invalidate derived planning state.
-- The returned epoch is the dependency key for recipe-aware caches.
function M.replace_source(recipe_prototypes, expected_epoch)
  if type(recipe_prototypes) ~= "table" then
    error("recipe_facts.replace_source expects a recipe prototype map", 2)
  end
  local context = compiler_context.current()
  for _, state_name in ipairs(RECIPE_SNAPSHOT_STATE_NAMES) do
    if context:has_state(state_name) then
      error("recipe_facts.replace_source must run before recipe-derived compiler snapshots: " .. state_name, 2)
    end
  end
  local current_epoch = source_epoch(context)
  if expected_epoch ~= nil and expected_epoch ~= current_epoch then
    error("recipe_facts.replace_source epoch mismatch: expected " .. tostring(expected_epoch)
      .. ", current " .. tostring(current_epoch), 2)
  end
  -- Capture an eligible caller-supplied plain source *before* it becomes
  -- Context state. The retained record owns every semantic field, so a caller
  -- mutation after replace_source cannot alter active planning or a later
  -- generic full-index boundary. Unsupported dynamic/duplicate shapes retain
  -- the established converter instead of being mistaken for owned data.
  -- Explicit replacement also owns the supported raw-source export below.
  -- Inspect the complete caller map before that whole-map copy: ignored
  -- custom metadata may have virtual iterators even when every consumed
  -- semantic field is ordinary. Such inputs keep the generic converter's
  -- original observation timing. Ordinary engine capture does not make this
  -- extra full-source traversal.
  local prepared_semantic_source = retained_metadata_is_admissible(recipe_prototypes)
    and build_semantic_source(recipe_prototypes) or nil
  -- The Context's supported raw source state must agree with the captured
  -- semantic owner. Retain a Factorio-faithful defensive copy for an
  -- admissible plain source; otherwise a caller could mutate exported raw
  -- state after capture while planning reads the frozen owner. The dynamic
  -- compatibility path deliberately keeps the original source semantics.
  local installed_source = prepared_semantic_source and deepcopy(recipe_prototypes) or recipe_prototypes
  semantic_sources[context], semantic_projections[context], semantic_facts[context] = nil, nil, nil
  context:replace_epoch("recipe_source", installed_source, current_epoch)
  local next_epoch = context:state_epoch("recipe_source")
  if prepared_semantic_source then
    recipe_source_modes[context] = "owned"
    install_semantic_source(context, next_epoch, prepared_semantic_source)
  else
    recipe_source_modes[context] = "legacy"
  end

  -- Rebuild the direct index immediately so callers holding no other cache
  -- never observe a stale recipe snapshot.  Downstream caches key themselves
  -- to source_epoch() and refresh lazily on their next query.
  if context:has_state("recipe_index") then rebuild(context) end
  if context:has_state("recipe_index_fingerprint_material") then
    local material = new_fingerprint_material(context, build())
    context:replace_epoch(
      "recipe_index_fingerprint_material",
      material,
      context:state_epoch("recipe_index_fingerprint_material")
    )
    if context:has_state("recipe_index_fingerprint") then
      context:replace_epoch(
        "recipe_index_fingerprint",
        material.full,
        context:state_epoch("recipe_index_fingerprint")
      )
    end
  elseif context:has_state("recipe_index_fingerprint") then
    -- Retain the established state name for an already-active legacy
    -- context even if it predates the paired projection material.
    context:replace_epoch(
      "recipe_index_fingerprint",
      fingerprint.of(build()),
      context:state_epoch("recipe_index_fingerprint")
    )
  end
  if context:has_state("recipe_active_input_identity") then
    context:replace_epoch(
      "recipe_active_input_identity",
      active_input_identity_material(context),
      context:state_epoch("recipe_active_input_identity")
    )
  end
  return next_epoch
end

function M.source_epoch()
  return source_epoch(compiler_context.current())
end

function M.get(recipe_name)
  local fact = M.view(recipe_name)
  if fact then telemetry.count("recipe_fact_copies", 1) end
  return fact and deepcopy(fact) or nil
end

-- Internal compiler views avoid repeated deep copies during one immutable
-- data-final-fixes planning pass. Callers must treat returned tables as
-- read-only. The owned semantic source itself never escapes: this is a
-- lazily materialized RecipeFact projection.
function M.view(recipe_name)
  local context = compiler_context.current()
  local source = semantic_source(context)
  if source then return semantic_fact(context, recipe_name) end
  return build().facts[recipe_name]
end

-- Generic schema-2 snapshot/export boundary.  Do not substitute the thin
-- active projection here: callers of this API retain complete canonical maps
-- and detached public snapshots through snapshot()/get().
function M.index_view()
  return build()
end

function M.for_each(callback)
  if type(callback) ~= "function" then error("recipe_facts.for_each expects a callback", 2) end
  local index = build()
  for _, recipe_name in ipairs(index.names) do callback(recipe_name, index.facts[recipe_name]) end
end

function M.summary()
  local context = compiler_context.current()
  local source = semantic_source(context)
  if source then return {schema = SCHEMA, recipe_count = #source.names} end
  local index = build()
  return {schema = index.schema, recipe_count = #index.names}
end

-- These owner projections are internal, deterministic derived views.  They
-- intentionally expose only the fields each ordinary consumer needs; callers
-- must not retain or mutate them. Public callers use index_view()/snapshot().
function M.relationship_projection_view()
  local projection = semantic_projection(compiler_context.current())
  if projection then return projection end
  local index = build()
  return {
    schema = index.schema,
    names = index.names,
    by_productive_output = index.by_productive_output,
    by_ingredient = index.by_ingredient,
    by_category = index.by_category,
    surface_conditions = (function()
      local out = {}
      for name, fact in pairs(index.facts) do
        if fact.surface_conditions then out[name] = fact.surface_conditions end
      end
      return out
    end)()
  }
end

-- This is a narrow ownership query, not an immutability marker. The semantic
-- projection is created only after its source normalizer has de-duplicated and
-- sorted every relationship map. A current Context/material/epoch match and
-- an admitted phase are therefore sufficient to skip the relationship
-- builder's identical second pass. Copied, generic, dynamic, stale, and
-- cross-Context values fail closed to its existing normalizer.
function M.current_normalized_relationship_projection(projection, phase)
  if phase ~= "input" and phase ~= "output" then return false end
  local context = compiler_context.current()
  local material = semantic_projections[context]
  return material ~= nil
    and material.projection == projection
    and material.recipe_source_epoch == source_epoch(context)
end

function M.route_projection_view()
  local projection = semantic_projection(compiler_context.current())
  if projection then return {
    schema = projection.schema,
    names = projection.names,
    name_set = projection.name_set,
    by_ingredient_identity = projection.by_ingredient_identity,
    by_output_identity = projection.by_output_identity
  } end
  local index = build()
  return {
    schema = index.schema,
    names = index.names,
    name_set = (function()
      local out = {}
      for _, name in ipairs(index.names) do out[name] = true end
      return out
    end)(),
    by_ingredient_identity = index.by_ingredient_identity,
    by_output_identity = index.by_output_identity
  }
end

function M.projection_epoch()
  local context = compiler_context.current()
  if semantic_source(context) then return source_epoch(context) end
  build()
  return context:state_epoch("recipe_index")
end

function M.for_each_route_variant(callback)
  if type(callback) ~= "function" then error("recipe_facts.for_each_route_variant expects a callback", 2) end
  local context = compiler_context.current()
  local source = semantic_source(context)
  if not source then
    return M.for_each(function(recipe_name, fact)
      for _, variant in ipairs(fact.variants or {}) do callback(recipe_name, variant) end
    end)
  end
  for _, recipe_name in ipairs(source.names) do
    for _, variant in ipairs(source.recipes[recipe_name].variants or {}) do
      callback(recipe_name, {
        ingredients = route_variant_entries(variant, "ingredients"),
        results = route_variant_entries(variant, "results")
      })
    end
  end
end

function M.for_each_coverage(callback)
  if type(callback) ~= "function" then error("recipe_facts.for_each_coverage expects a callback", 2) end
  local context = compiler_context.current()
  local source = semantic_source(context)
  if not source then return M.for_each(callback) end
  for _, recipe_name in ipairs(source.names) do
    callback(recipe_name, coverage_fact_from_source(source.recipes[recipe_name]))
  end
end

function M.has_name(recipe_name)
  local context = compiler_context.current()
  local source = semantic_source(context)
  if source then return source.recipes[recipe_name] ~= nil end
  return build().facts[recipe_name] ~= nil
end

function M.fingerprint()
  local context = compiler_context.current()
  local material = fingerprint_material(context)
  local cached = context:state_view("recipe_index_fingerprint")
  if cached == nil then
    return context:set_state("recipe_index_fingerprint", material.full)
  end
  if cached ~= material.full then
    return context:replace_epoch("recipe_index_fingerprint", material.full,
      context:state_epoch("recipe_index_fingerprint"))
  end
  return cached
end

-- This is intentionally narrower than a public snapshot API.  The adapter
-- may reuse the digest only for the exact Context-owned index it just read;
-- supplied, copied, or caller-owned indexes receive no trusted component.
function M.snapshot_recipe_domain_fingerprint(index)
  local context = compiler_context.current()
  if index == nil or index ~= context:state_view("recipe_index") then return nil end
  local material = fingerprint_material(context)
  if material.recipe_source_epoch ~= source_epoch(context)
    or material.recipe_index_epoch ~= context:state_epoch("recipe_index") then
    return nil
  end
  return {
    fingerprint = material.recipe_domain,
    canonical_bytes = material.recipe_domain_bytes,
    recipe_source_epoch = material.recipe_source_epoch,
    recipe_index_epoch = material.recipe_index_epoch
  }
end

function M.recipes_by_output_view(name)
  local projection = semantic_projection(compiler_context.current())
  if projection then return projection.by_output[name] or {} end
  return build().by_output[name] or {}
end

-- Exact type/name query for consumers that cannot safely use the historical
-- name-only convenience index (notably recipe-route feasibility).
function M.recipes_by_output_identity_view(entry_type, name)
  local projection = semantic_projection(compiler_context.current())
  local key = identity_key(entry_type, name)
  if projection then return projection.by_output_identity[key] or {} end
  return build().by_output_identity[key] or {}
end

function M.all_names()
  local source = semantic_source(compiler_context.current())
  return deepcopy(source and source.names or build().names)
end

function M.candidate_names(outputs, categories, name_patterns)
  local projection = semantic_projection(compiler_context.current())
  local index = projection or build()
  local selected = {}
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
  local projection = semantic_projection(compiler_context.current())
  if projection then return deepcopy(projection.by_output[name] or {}) end
  return deepcopy(build().by_output[name] or {})
end

function M.recipes_by_output_identity(entry_type, name)
  local projection = semantic_projection(compiler_context.current())
  local key = identity_key(entry_type, name)
  if projection then return deepcopy(projection.by_output_identity[key] or {}) end
  return deepcopy(build().by_output_identity[key] or {})
end

function M.recipes_by_ingredient(name)
  local projection = semantic_projection(compiler_context.current())
  if projection then return deepcopy(projection.by_ingredient[name] or {}) end
  return deepcopy(build().by_ingredient[name] or {})
end

function M.recipes_by_category(name)
  local projection = semantic_projection(compiler_context.current())
  if projection then return deepcopy(projection.by_category[name] or {}) end
  return deepcopy(build().by_category[name] or {})
end

function M.snapshot()
  local index = build()
  telemetry.count("recipe_fact_copies", #index.names)
  return deepcopy(index)
end

function M.scan_count()
  local context = compiler_context.current()
  semantic_source(context)
  return context:state_view("recipe_index_metrics", function() return {scan_count = 0} end).scan_count
end

return M
