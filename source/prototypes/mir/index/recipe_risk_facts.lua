local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local relationships = require("prototypes.mir.index.relationships")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local telemetry = require("prototypes.mir.report.compiler_telemetry")

local M = {}
local SCHEMA = 1

local REVIEW_PATTERNS = {
  {flag = "cleaning_or_recovery_loop", patterns = {"clean", "recover", "recovery", "wash", "washing", "scrub", "scrubbing"}},
  {flag = "voiding_or_destruction", patterns = {"void", "vent", "flare", "sink", "destroy", "disposal"}},
  {flag = "matter_or_transmutation", patterns = {"matter", "transmut", "conversion", "convert"}},
  {flag = "barrel_or_container_return", patterns = {"barrel", "canister", "container", "capsule", "empty%-", "fill%-"}}
}

local function add(values, seen, value, evidence, evidence_rows)
  if seen[value] then return end
  seen[value] = true
  table.insert(values, value)
  table.insert(evidence_rows, evidence)
end

local function contains_pattern(value, patterns)
  local text = string.lower(value or "")
  for _, pattern in ipairs(patterns or {}) do
    if string.find(text, pattern) then return true end
  end
  return false
end

local function category_set(categories)
  local out = {}
  for _, category in ipairs(categories or {}) do out[category] = true end
  return out
end

local function risk_identity(entry)
  if type(entry) ~= "table" or type(entry.type) ~= "string" or entry.type == ""
    or type(entry.name) ~= "string" or entry.name == "" then
    error("recipe_risk_facts requires canonical typed identities", 3)
  end
  return entry.type .. "\30" .. entry.name
end

local function productive_intersection(fact)
  local ingredients, out = {}, {}
  -- Canonical facts already retain type/name identities. Keep the public
  -- evidence names and fingerprints unchanged for actual shared identities,
  -- while avoiding an item/fluid name collision in the risk disposition.
  if type(fact.ingredient_identities) == "table" and type(fact.productive_result_identities) == "table" then
    local shared = {}
    for _, entry in ipairs(fact.ingredient_identities) do
      ingredients[risk_identity(entry)] = true
    end
    for _, entry in ipairs(fact.productive_result_identities) do
      if ingredients[risk_identity(entry)] then shared[entry.name] = true end
    end
    for name in pairs(shared) do out[#out + 1] = name end
    table.sort(out)
    return out
  end
  -- Historical name-only callers retain their conservative disposition.
  for _, name in ipairs(fact.ingredient_names or {}) do ingredients[name] = true end
  for _, name in ipairs(fact.productive_result_names or {}) do
    if ingredients[name] then table.insert(out, name) end
  end
  table.sort(out)
  return out
end

local function result_is_deterministic(result)
  return tonumber(result.independent_probability or result.probability or 1) == 1
    and result.shared_probability == nil
    and tonumber(result.extra_count_fraction or 0) == 0
    and result.amount_min == nil
    and result.amount_max == nil
    and tonumber(result.catalyst_amount or 0) == 0
    and tonumber(result.ignored_by_productivity or 0) == 0
end

local function placeable_output_risks(fact, indexes)
  local placeable = {}
  for _, name in ipairs(fact.productive_result_names or {}) do
    local item = indexes.items[name]
    if item and item.place_result then placeable[name] = true end
  end
  local placeable_count = 0
  for _ in pairs(placeable) do placeable_count = placeable_count + 1 end
  if placeable_count == 0 then return false, false end

  local ambiguous = placeable_count > 1
  local nondeterministic = false
  for _, variant in ipairs(fact.variants or {}) do
    local matched = 0
    for _, result in ipairs(variant.results or {}) do
      if placeable[result.name] then
        matched = matched + 1
        if not result_is_deterministic(result) then nondeterministic = true end
      end
    end
    if matched ~= 1 or #(variant.results or {}) ~= 1 then ambiguous = true end
  end
  return ambiguous, nondeterministic
end

local function risk_material(row)
  return {
    schema = row.schema,
    recipe = row.recipe,
    hard_flags = row.hard_flags,
    review_flags = row.review_flags,
    evidence = row.evidence,
    shared_input_output = row.shared_input_output,
    evidence_confidence = row.evidence_confidence
  }
end

local function build_row(recipe_name, fact, indexes)
  local hard, review, evidence = {}, {}, {}
  local hard_seen, review_seen = {}, {}
  local categories = category_set(fact.categories)
  local shared = productive_intersection(fact)
  local ambiguous, nondeterministic = placeable_output_risks(fact, indexes)

  if categories.recycling or fact.source_class == "recycling" then
    add(hard, hard_seen, "recycling_loop", "category:recycling", evidence)
  end
  if fact.hidden or fact.source_class == "hidden-internal" then
    add(hard, hard_seen, "hidden_internal", "recipe:hidden", evidence)
  end
  if fact.parameter then add(hard, hard_seen, "parameter_recipe", "recipe:parameter", evidence) end
  if fact.effective_allow_productivity ~= true then
    add(hard, hard_seen, "productivity_disabled", "recipe:effective_allow_productivity=false", evidence)
  end
  if tonumber(fact.effective_maximum_productivity) == 0 then
    add(hard, hard_seen, "zero_productivity_cap", "recipe:effective_maximum_productivity=0", evidence)
  end
  if #shared > 0 then
    add(hard, hard_seen, "catalyst_or_self_return", "productive-input-output-intersection:" .. table.concat(shared, ","), evidence)
  end
  if nondeterministic then
    add(hard, hard_seen, "non_deterministic_output", "placeable-output:nondeterministic", evidence)
  end
  if ambiguous then
    add(hard, hard_seen, "ambiguous_placeable_output", "placeable-output:ambiguous", evidence)
  end

  for _, descriptor in ipairs(REVIEW_PATTERNS) do
    local matched = contains_pattern(recipe_name, descriptor.patterns)
    if not matched then
      for category in pairs(categories) do
        if contains_pattern(category, descriptor.patterns) then matched = true; break end
      end
    end
    if matched then add(review, review_seen, descriptor.flag, "heuristic:name-or-category:" .. descriptor.flag, evidence) end
  end
  if #(fact.productive_result_names or {}) > 1
    and contains_pattern(recipe_name, {"ore", "fragment", "scrap", "core", "resource"}) then
    add(review, review_seen, "multi_output_resource_loop", "shape:multi-output-resource-process", evidence)
  end

  table.sort(hard)
  table.sort(review)
  table.sort(evidence)
  local row = {
    schema = SCHEMA,
    recipe = recipe_name,
    hard_flags = hard,
    review_flags = review,
    evidence = evidence,
    shared_input_output = shared,
    evidence_confidence = #review > 0 and 0.75 or 1.0
  }
  row.risk_fingerprint = fingerprint.of(risk_material(row))
  return row
end

local function build_index(source, indexes)
  local facts, hard_count, review_count = {}, 0, 0
  local names = deepcopy(source.names or {})
  table.sort(names)
  for _, recipe_name in ipairs(names) do
    local row = build_row(recipe_name, source.facts[recipe_name], indexes)
    facts[recipe_name] = row
    if #row.hard_flags > 0 then hard_count = hard_count + 1 end
    if #row.review_flags > 0 then review_count = review_count + 1 end
  end
  local index = {schema = SCHEMA, names = names, facts = facts}
  index.risk_index_fingerprint = fingerprint.of({schema = index.schema, names = index.names, facts = index.facts})
  return index, hard_count, review_count
end

local function materialization()
  local context = compiler_context.current()
  return context:state_view("recipe_risk_materialization", function()
    local source = recipe_facts.index_view()
    local names = deepcopy(source.names or {})
    table.sort(names)
    -- Reuse the Context service boundary for complete external inspection.
    -- Capture the owner function, not a mutable caller-supplied exporter.
    local complete = M.fingerprint
    context:set_service("recipe_risk.materialize_export", function() complete() end)
    return {
      schema = 1, record_type = "RecipeRiskMaterialization", complete = false,
      source = source, relationships = relationships.view("input"),
      index = {schema = SCHEMA, names = names, facts = {}}
    }
  end)
end

local function materialize_row(state, recipe_name)
  local row = state.index.facts[recipe_name]
  if row then return row end
  local fact = state.source.facts[recipe_name]
  if not fact then return nil end
  telemetry.start_phase("recipe_risk_facts")
  row = build_row(recipe_name, fact, state.relationships)
  state.index.facts[recipe_name] = row
  telemetry.count("recipe_risk_facts", 1)
  telemetry.count("recipe_hard_risk_count", #row.hard_flags > 0 and 1 or 0)
  telemetry.count("recipe_review_risk_count", #row.review_flags > 0 and 1 or 0)
  telemetry.finish_phase("recipe_risk_facts")
  return row
end

local function build()
  local state = materialization()
  if not state.complete then
    for _, name in ipairs(state.index.names) do materialize_row(state, name) end
    state.index.risk_index_fingerprint = fingerprint.of({
      schema = state.index.schema, names = state.index.names, facts = state.index.facts
    })
    compiler_context.current():set_state("recipe_risk_index", state.index)
    state.complete = true
  end
  return state.index
end

function M.index_facts(recipe_index, relationship_index)
  if type(recipe_index) ~= "table" or type(recipe_index.facts) ~= "table"
    or type(relationship_index) ~= "table" or type(relationship_index.items) ~= "table" then
    error("recipe_risk_facts.index_facts requires canonical recipe and relationship indexes", 2)
  end
  local index = build_index(recipe_index, relationship_index)
  return deepcopy(index)
end

function M.view(recipe_name)
  return materialize_row(materialization(), recipe_name)
end

-- Ordinary compilation needs a source identity, not the complete diagnostic
-- output inventory. Bind every classifier input: normalized recipe facts,
-- item placeability, the declared review patterns and hard-rule revision.
-- This identity grants no admission; each selected row still runs build_row.
function M.source_fingerprint()
  local state = materialization()
  if not state.source_fingerprint then
    local placeable = {}
    for name, item in pairs(state.relationships.items) do
      if item.place_result then placeable[name] = item.place_result end
    end
    local source = {
      schema = 1, record_type = "RecipeRiskInputs", hard_rule_revision = 1,
      placeable_items = placeable,
      review_patterns = REVIEW_PATTERNS
    }
    -- Explicit generic snapshot/export requests retain the established full
    -- index digest. The active compiler binds the complete normalized input
    -- contract instead, so it need not serialize derived index maps merely to
    -- name its ordinary source inputs.
    if compiler_context.current():legacy_compiler_export_requested() then
      source.recipe_facts = recipe_facts.fingerprint()
    else
      source.recipe_input = recipe_facts.active_input_identity()
    end
    state.source_fingerprint = fingerprint.of(source)
  end
  return state.source_fingerprint
end

function M.get(recipe_name)
  local row = M.view(recipe_name)
  return row and deepcopy(row) or nil
end

function M.snapshot()
  return deepcopy(build())
end

function M.fingerprint()
  return build().risk_index_fingerprint
end

function M.has_hard_flag(row, flag)
  for _, value in ipairs((row and row.hard_flags) or {}) do
    if value == flag then return true end
  end
  return false
end

function M.primary_disposition(row)
  if not row then return "HARD_REJECTED", "recipe_fact_missing" end
  if #row.hard_flags > 0 then return "HARD_REJECTED", row.hard_flags[1] end
  if #row.review_flags > 0 then return "REVIEW_REQUIRED", row.review_flags[1] end
  return "PASS", nil
end

return M
