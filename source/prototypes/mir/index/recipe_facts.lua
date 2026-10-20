local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local recipe_semantics = require("prototypes.mir.domain.facts.recipe_semantics")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}
-- Schema 2 remains the established explicit snapshot/export shape. Ordinary
-- compilation owns ActiveRecipeIndex1 instead; legacy aggregate aliases are
-- expanded only when a supported export asks for them.
local SCHEMA = 2
local ACTIVE_SCHEMA = 1
local ACTIVE_RECORD_TYPE = "ActiveRecipeIndex"
local RECIPE_DOMAIN_FIELDS = {"facts", "names", "schema"}
-- This is the active compiler's source-input contract, not the established
-- full recipe-index fingerprint used by generic snapshot/export consumers.
-- Index maps are deterministic derived views of this normalized domain; the
-- explicit revision makes a change to that derivation an input change too.
local ACTIVE_INPUT_SCHEMA = 2
local ACTIVE_INPUT_CONTRACT = "mir-recipe-normalized-input-v2"
local INDEX_DERIVATION_REVISION = 2

-- A Factorio recipe map is ordinarily a plain unique-keyed table. A custom
-- __pairs iterator can yield a recipe key more than once: facts
-- keep the final row but discovery maps retain every yielded row. Keep that
-- exceptional complete-index binding private to this owner; normal maps still
-- hash only their normalized fact domain.
local exceptional_complete_index_identity = setmetatable({}, {__mode = "k"})

-- Active recipe values stay private to this owner. The view tables below are
-- empty read-only facades: assignments never shadow an existing raw key, and
-- nested arrays/maps are wrapped before they can escape. Views are deliberately
-- not cached. Lua rawset can add an own key to any table, so reusing a facade
-- would let a caller's shadow field affect a later normal owner query.
-- Factorio table.deepcopy preserves a table metatable, so each facade has its
-- own protected metatable which lets a deep-copied facade traverse its newly
-- copied raw fields. The weak mapping records only an original facade's raw
-- owner for exact-owner APIs; it is not a source-value cache or trust marker.
local active_proxy_sources = setmetatable({}, {__mode = "k"})
-- The raw active owner is held outside CompilerContext.state. Context state is
-- intentionally available to all compiler modules; exposing this raw index
-- there would let a consumer mutate planning decisions behind the views.
local owned_indexes = setmetatable({}, {__mode = "k"})

local function active_view(value)
  if type(value) ~= "table" then return value end
  local proxy = {}
  active_proxy_sources[proxy] = value
  local function read(key) return active_view(value[key]) end
  local meta = {}
  meta.__index = function(subject, key)
    if subject == proxy then return read(key) end
    return rawget(subject, key)
  end
  meta.__newindex = function(_, key)
      error("Active recipe owner views are read-only: " .. tostring(key), 2)
  end
  meta.__len = function(subject)
    if subject == proxy then return #value end
    return rawlen(subject)
  end
  meta.__pairs = function(subject)
    if subject ~= proxy then return next, subject, nil end
      local function iterator(_, previous)
        local key, next_value = next(value, previous)
        if key ~= nil then return key, active_view(next_value) end
      end
      return iterator, nil, nil
  end
  meta.__ipairs = function(subject)
    if subject ~= proxy then
      local position = 0
      local function copied_iterator()
        position = position + 1
        local next_value = rawget(subject, position)
        if next_value ~= nil then return position, next_value end
      end
      return copied_iterator, nil, nil
    end
      local position = 0
      local function iterator()
        position = position + 1
        local next_value = value[position]
        if next_value ~= nil then return position, active_view(next_value) end
      end
      return iterator, nil, nil
  end
  -- Keep the live metamethod table private. Factorio's table.deepcopy obtains
  -- getmetatable(proxy) and installs that returned table on its detached copy,
  -- so expose a separate inert lock that is settable but has no metamethods.
  -- Mutating the returned lock cannot alter this live facade or a later owner
  -- query; the copied facade already owns plain copied values.
  local copy_lock = {}
  meta.__metatable = copy_lock
  setmetatable(proxy, meta)
  fingerprint.register_opaque_recipe_view(proxy)
  return proxy
end

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

-- ActiveRecipeFact1 retains one typed aggregate entry array for each IO
-- direction. Schema-2 export expands the historical identities alias later.
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
    local ingredients, ingredient_names = aggregate_io(recipe, "ingredients")
    local results, result_names = aggregate_io(recipe, "results")
    local categories = categories_for(normalized_variants)
    local is_hidden = hidden(recipe)
    local productive_outputs, productive_output_identities = productive_results(recipe)
    if facts[recipe_name] ~= nil then duplicate_recipe_name = true end
    facts[recipe_name] = {
      schema = ACTIVE_SCHEMA,
      record_type = "ActiveRecipeFact",
      name = recipe_name,
      variants = normalized_variants,
      categories = categories,
      ingredients = ingredients,
      ingredient_names = ingredient_names,
      results = results,
      result_names = result_names,
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
    for _, output in ipairs(results) do
      append_index(by_output_identity, identity_key(output.type, output.name), recipe_name)
    end
    for _, output_name in ipairs(productive_outputs) do append_index(by_productive_output, output_name, recipe_name) end
    for _, output in ipairs(productive_output_identities) do
      append_index(by_productive_output_identity, identity_key(output.type, output.name), recipe_name)
    end
    for _, ingredient_name in ipairs(ingredient_names) do append_index(by_ingredient, ingredient_name, recipe_name) end
    for _, ingredient in ipairs(ingredients) do
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
    schema = ACTIVE_SCHEMA,
    record_type = ACTIVE_RECORD_TYPE,
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

-- Build the established schema-2 index only for an explicit supported
-- boundary. The active owner retains no identities alias arrays, so this is
-- where those legacy fields and their shared entry references are recreated.
local function legacy_entries(entries)
  local values, identities = {}, {}
  for position, entry in ipairs(entries or {}) do
    local copied = deepcopy(entry)
    values[position] = copied
    identities[position] = copied
  end
  return values, identities
end

local function legacy_fact(active)
  local ingredients, ingredient_identities = legacy_entries(active.ingredients)
  local results, result_identities = legacy_entries(active.results)
  return {
    schema = SCHEMA,
    name = active.name,
    variants = deepcopy(active.variants),
    categories = deepcopy(active.categories),
    ingredients = ingredients,
    ingredient_names = deepcopy(active.ingredient_names),
    ingredient_identities = ingredient_identities,
    results = results,
    result_names = deepcopy(active.result_names),
    result_identities = result_identities,
    productive_result_names = deepcopy(active.productive_result_names),
    productive_result_identities = deepcopy(active.productive_result_identities),
    main_product = active.main_product,
    hidden = active.hidden,
    enabled_without_research = active.enabled_without_research,
    parameter = active.parameter,
    maximum_productivity = active.maximum_productivity,
    declared_maximum_productivity = active.declared_maximum_productivity,
    effective_maximum_productivity = active.effective_maximum_productivity,
    allow_productivity = active.allow_productivity,
    declared_allow_productivity = active.declared_allow_productivity,
    effective_allow_productivity = active.effective_allow_productivity,
    allow_quality = active.allow_quality,
    declared_allow_quality = active.declared_allow_quality,
    effective_allow_quality = active.effective_allow_quality,
    surface_conditions = deepcopy(active.surface_conditions),
    source_class = active.source_class
  }
end

local function legacy_index(active)
  local facts = {}
  for recipe_name, fact in pairs(active.facts) do facts[recipe_name] = legacy_fact(fact) end
  return {
    schema = SCHEMA,
    facts = facts,
    names = deepcopy(active.names),
    by_output = deepcopy(active.by_output),
    by_output_identity = deepcopy(active.by_output_identity),
    by_productive_output = deepcopy(active.by_productive_output),
    by_productive_output_identity = deepcopy(active.by_productive_output_identity),
    by_ingredient = deepcopy(active.by_ingredient),
    by_ingredient_identity = deepcopy(active.by_ingredient_identity),
    by_category = deepcopy(active.by_category)
  }
end

-- relationships historically borrowed these three map tables from the recipe
-- index and normalized them in place. Keep that observable lifetime inside
-- the owner: the active derived maps and an already-requested legacy Context
-- record undergo the same sort/deduplication before relationships publishes.
-- Facts and typed aggregate entries remain untouched.
local RELATIONSHIP_NORMALIZED_FIELDS = {
  "by_productive_output",
  "by_ingredient",
  "by_category"
}

local function sort_and_deduplicate_index(index, fields)
  local changed = false
  for _, field in ipairs(fields) do
    for key, values in pairs(index[field] or {}) do
      table.sort(values)
      local unique, previous = {}, nil
      for _, value in ipairs(values) do
        if value ~= previous then table.insert(unique, value) end
        previous = value
      end
      if #unique ~= #values then
        index[field][key] = unique
        changed = true
      end
    end
  end
  return changed
end

-- The established default/manual CompilerContext export includes the legacy
-- recipe index. Keep that detached schema-2 value only when its supported
-- export boundary was selected up front; the player active-only path retains
-- only the private owner record above.
local function publish_context_index_state(context, active)
  if context:legacy_compiler_export_requested() then
    local legacy = legacy_index(active)
    if context:has_state("recipe_index") then
      context:replace_epoch("recipe_index", legacy, context:state_epoch("recipe_index"))
    else
      context:set_state("recipe_index", legacy)
    end
    return
  end
  -- Existing Context-local consumers bind the recipe-index epoch. Preserve
  -- that scalar invalidation contract without retaining the mutable index in
  -- Context state: false is only a sentinel, never a usable recipe record.
  if context:has_state("recipe_index") then
    context:replace_epoch("recipe_index", false, context:state_epoch("recipe_index"))
  else
    context:set_state("recipe_index", false)
  end
end

-- Recipe facts are a snapshot, not a live view of data.raw.  A writer that
-- changes recipes after this module has been queried must replace the source
-- through replace_source().  That single operation advances the Context
-- epoch and gives all epoch-aware consumers an unambiguous invalidation point.
local function source_prototypes(context)
  return context:state_view("recipe_source", function()
    return data_raw.prototypes("recipe")
  end)
end

local function source_epoch(context)
  source_prototypes(context)
  return context:state_epoch("recipe_source") or 1
end

local function owned_index_state(context)
  return owned_indexes[context]
end

local function owned_index_epoch(context)
  local state = owned_index_state(context)
  return state and state.epoch or nil
end

local function rebuild(context)
  telemetry.start_phase("snapshot")
  local metrics = context:state_view("recipe_index_metrics", function() return {scan_count = 0} end)
  metrics.scan_count = metrics.scan_count + 1
  local canonical = build_index(source_prototypes(context))
  telemetry.count("recipe_index_scans", 1)
  telemetry.count("recipes", #canonical.names)
  telemetry.finish_phase("snapshot")
  local prior = owned_index_state(context)
  owned_indexes[context] = {
    index = canonical,
    recipe_source_epoch = source_epoch(context),
    epoch = (prior and prior.epoch or 0) + 1
  }
  publish_context_index_state(context, canonical)
  return canonical
end

local function build()
  local context = compiler_context.current()
  local cached = owned_index_state(context)
  local source = source_epoch(context)
  if cached and cached.recipe_source_epoch == source then return cached.index end
  return rebuild(context)
end

-- The full recipe index and the compiler snapshot's recipes domain share the
-- same owned facts/names/schema fields.  Keep only their scalar digests and
-- byte count under the Context epoch: no canonical text or mutable index
-- reference escapes into this cache.  The projection helper validates every
-- field of the complete index, so the full digest retains its established
-- identity while the later snapshot need not traverse the shared facts again.
local function new_fingerprint_material(context, index)
  -- Legacy digest bytes remain exact, but this materialization is export-only:
  -- ordinary active compilation binds active_input_identity() below.
  local legacy = legacy_index(index)
  local full, recipe_domain, recipe_domain_bytes = fingerprint.of_map_with_projection(
    legacy, RECIPE_DOMAIN_FIELDS)
  return {
    recipe_source_epoch = source_epoch(context),
    recipe_index_epoch = owned_index_epoch(context),
    full = full,
    recipe_domain = recipe_domain,
    recipe_domain_bytes = recipe_domain_bytes
  }
end

local function fingerprint_material(context)
  local index = build()
  local source = source_epoch(context)
  local cached = context:state_view("recipe_index_fingerprint_material")
  -- The historical generic digest was cached only by the recipe source state.
  -- relationships can later normalize shared derived maps in place without
  -- changing that cached scalar. Preserve that legacy observation; callers
  -- without a prior material receive the then-current schema-2 export.
  if cached and cached.recipe_source_epoch == source then
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

local function active_input_identity_material(context, index)
  local identity = {
    schema = ACTIVE_INPUT_SCHEMA,
    record_type = "RecipeNormalizedInput",
    contract = ACTIVE_INPUT_CONTRACT,
    recipe_index_schema = index.schema,
    recipe_index_record_type = index.record_type,
    index_derivation_revision = INDEX_DERIVATION_REVISION,
    normalized_fact_domain_fingerprint = fingerprint.of({
      schema = index.schema,
      record_type = index.record_type,
      names = index.names,
      facts = index.facts
    })
  }
  -- For a duplicate virtual source key the normalized fact domain cannot
  -- identify every consumed discovery map. Bind the exact legacy schema-2
  -- complete-index digest only in that exceptional shape; this preserves the
  -- established complete identity without trusting table identity.
  if exceptional_complete_index_identity[index] then
    -- Do not reuse the historical generic-digest cache here. Relationship
    -- normalization can change the owner-derived maps without a source change;
    -- the versioned active identity must bind those current consumed values.
    identity.exceptional_complete_index_fingerprint = new_fingerprint_material(context, index).full
  end
  return {
    recipe_source_epoch = source_epoch(context),
    recipe_index_epoch = owned_index_epoch(context),
    identity = identity
  }
end

-- The ordinary compiler records a versioned identity of every normalized
-- recipe fact it can consume. It deliberately excludes only index maps that
-- build_index deterministically derives from those facts; the derivation
-- revision binds that algorithm. Generic snapshot/export paths keep using
-- fingerprint(), whose legacy full-index digest remains unchanged.
function M.active_input_identity()
  local context = compiler_context.current()
  local index = build()
  local source = source_epoch(context)
  local index_epoch = owned_index_epoch(context)
  local cached = context:state_view("recipe_active_input_identity")
  if cached and cached.recipe_source_epoch == source and cached.recipe_index_epoch == index_epoch then
    return deepcopy(cached.identity)
  end
  local material = active_input_identity_material(context, index)
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
  return legacy_index(build_index(recipe_prototypes))
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
  context:replace_epoch("recipe_source", recipe_prototypes, current_epoch)
  local next_epoch = context:state_epoch("recipe_source")

  -- Rebuild the direct index immediately so callers holding no other cache
  -- never observe a stale recipe snapshot.  Downstream caches key themselves
  -- to source_epoch() and refresh lazily on their next query.
  if owned_index_state(context) then rebuild(context) end
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
      active_input_identity_material(context, build()),
      context:state_epoch("recipe_active_input_identity")
    )
  end
  return next_epoch
end

function M.source_epoch()
  return source_epoch(compiler_context.current())
end

function M.index_epoch()
  build()
  return owned_index_epoch(compiler_context.current())
end

function M.normalize_relationship_indexes()
  local context = compiler_context.current()
  local active = build()
  local changed = sort_and_deduplicate_index(active, RELATIONSHIP_NORMALIZED_FIELDS)
  if changed then
    -- Active identity includes exceptional full-map state. Advance the owner
    -- epoch so a later identity is never reused after the maps it binds change.
    owned_index_state(context).epoch = owned_index_epoch(context) + 1
  end
  -- A default/manual Context has already materialized its supported schema-2
  -- export. Preserve the former shared-map observation without leaking the
  -- active owner itself through Context state.
  local legacy = context:state_view("recipe_index")
  if type(legacy) == "table" then
    sort_and_deduplicate_index(legacy, RELATIONSHIP_NORMALIZED_FIELDS)
  end
  return changed
end

-- Narrow scalar owner queries avoid constructing an ActiveRecipeFact facade
-- for hot decision paths.  The callback receives no recipe table, so it
-- cannot become another escape route for retained mutable fact state.
function M.has_typed_result(recipe_name, entry_type, result_name, visit, visit_context)
  if type(recipe_name) ~= "string" or type(entry_type) ~= "string" or type(result_name) ~= "string" then
    return false
  end
  local fact = build().facts[recipe_name]
  if not fact then return false end
  for _, result in ipairs(fact.results or {}) do
    if visit and visit(visit_context) == false then return false end
    if result.type == entry_type and result.name == result_name then return true end
  end
  return false
end

function M.is_enabled_without_research(recipe_name)
  if type(recipe_name) ~= "string" then return false end
  local fact = build().facts[recipe_name]
  return fact ~= nil and fact.enabled_without_research == true
end

function M.get(recipe_name)
  local fact = build().facts[recipe_name]
  if fact then telemetry.count("recipe_fact_copies", 1) end
  -- get() is a defensive public read boundary, so retain the exact schema-2
  -- fact rather than exposing ActiveRecipeFact1.
  return fact and deepcopy(legacy_fact(fact)) or nil
end

-- Internal compiler views avoid repeated deep copies during one immutable
-- data-final-fixes planning pass. Callers must treat returned tables as
-- read-only.
function M.view(recipe_name)
  return active_view(build().facts[recipe_name])
end

function M.index_view()
  return active_view(build())
end

function M.is_active_index(index)
  return active_proxy_sources[index] == build()
end

-- Relationship construction intentionally mutates/sorts three derived maps.
-- It receives only a new owned copy from the authoritative active index.
local COPYABLE_ACTIVE_INDEX_FIELDS = {
  by_productive_output = true,
  by_ingredient = true,
  by_category = true
}
function M.copy_active_index_field(field)
  if not COPYABLE_ACTIVE_INDEX_FIELDS[field] then
    error("Unsupported active recipe index copy field: " .. tostring(field), 2)
  end
  return deepcopy(build()[field])
end

-- Relationships publishes copied surface conditions. It cannot retain a
-- nested active view because Factorio's native deepcopy implementation need
-- not honor __pairs; expand this narrow map inside the owner instead.
function M.copy_surface_conditions_by_recipe()
  local out = {}
  for recipe_name, fact in pairs(build().facts) do
    if fact.surface_conditions then out[recipe_name] = deepcopy(fact.surface_conditions) end
  end
  return out
end

function M.for_each(callback)
  if type(callback) ~= "function" then error("recipe_facts.for_each expects a callback", 2) end
  local index = build()
  for _, recipe_name in ipairs(index.names) do callback(recipe_name, active_view(index.facts[recipe_name])) end
end

function M.summary()
  local index = build()
  return {schema = index.schema, record_type = index.record_type, recipe_count = #index.names}
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
  if index == nil or active_proxy_sources[index] ~= build() then return nil end
  local material = fingerprint_material(context)
  if material.recipe_source_epoch ~= source_epoch(context)
    or material.recipe_index_epoch ~= owned_index_epoch(context) then
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
  return active_view(build().by_output[name] or {})
end

-- Exact type/name query for consumers that cannot safely use the historical
-- name-only convenience index (notably recipe-route feasibility).
function M.recipes_by_output_identity_view(entry_type, name)
  return active_view(build().by_output_identity[identity_key(entry_type, name)] or {})
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

function M.recipes_by_output_identity(entry_type, name)
  return deepcopy(build().by_output_identity[identity_key(entry_type, name)] or {})
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
  -- snapshot() is the explicit generic schema-2 export boundary. Preserve
  -- the established returned-copy isolation (including its non-aliased
  -- aggregate entry copies) from the former deepcopy(index) implementation.
  return deepcopy(legacy_index(index))
end

function M.scan_count()
  build()
  return compiler_context.current():state_view("recipe_index_metrics").scan_count
end

return M
