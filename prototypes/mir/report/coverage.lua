local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local deepcopy = require("prototypes.mir.core.deepcopy")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")
local family_resolver = require("prototypes.mir.families.resolver")
local fingerprint = require("prototypes.mir.core.fingerprint")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local mod_data = require("prototypes.mir.emit.mod_data")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local adoption = require("prototypes.mir.emit.transactions.productivity_family_adoption")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}

local CATEGORIES = {
  "auto_attached",
  "generated_family_covered",
  "adopted_external",
  "external_exact_owner",
  "safe_skip",
  "unsafe_skip",
  "target_unsupported",
  "ambiguous",
  "unclassified"
}

local function owner_index()
  local by_recipe = {}
  local counts = {technologies = 0, effects = 0, graph_edges = 0, technology_passes = 1}
  for technology_name, technology in pairs(data_raw.prototypes("technology")) do
    counts.technologies = counts.technologies + 1
    counts.graph_edges = counts.graph_edges + #(technology.prerequisites or {})
    for _, effect in ipairs(technology.effects or {}) do
      counts.effects = counts.effects + 1
      if effect.type == "change-recipe-productivity" and effect.recipe then
        by_recipe[effect.recipe] = by_recipe[effect.recipe] or {}
        table.insert(by_recipe[effect.recipe], technology_name)
      end
    end
  end
  for _, owners in pairs(by_recipe) do table.sort(owners) end
  return by_recipe, counts
end

local function family_indexes()
  local snapshot = family_resolver.snapshot()
  local attached, decisions = {}, {}
  for stream_key, rows in pairs(snapshot.attachments or {}) do
    for _, row in ipairs(rows) do attached[row.recipe] = stream_key end
  end
  for _, row in ipairs(snapshot.decisions or {}) do
    decisions[row.recipe] = decisions[row.recipe] or row
    if row.blocker then decisions[row.recipe] = row end
  end
  return attached, decisions, #(snapshot.decisions or {})
end

local function adopted_index()
  local out = {}
  for _, row in ipairs(adoption.snapshot()) do out[row.recipe] = row.owner end
  return out
end

local function base_skip(fact)
  if fact.hidden then return "safe_skip", "hidden_recipe" end
  if fact.parameter then return "safe_skip", "parameter_recipe" end
  if fact.source_class == "recycling" then return "safe_skip", "recycling_recipe" end
  if fact.allow_productivity == false then return "safe_skip", "recipe_productivity_not_allowed" end
  if tonumber(fact.maximum_productivity) == 0 then return "safe_skip", "zero_productivity_cap" end
  return nil, nil
end

local function shared_input_output_state(fact)
  local any_shared = false
  for _, variant in ipairs(fact.variants or {}) do
    local ingredients = {}
    for _, entry in ipairs(variant.ingredients or {}) do ingredients[entry.name] = true end
    for _, entry in ipairs(variant.results or {}) do
      if ingredients[entry.name] then
        any_shared = true
        local maximum = tonumber(entry.amount_max or entry.amount or entry.amount_min) or 1
        local ignored = tonumber(entry.ignored_by_productivity or 0) or 0
        if maximum - ignored > 0 then return "productive" end
      end
    end
  end
  return any_shared and "ignored" or nil
end

local function classify(recipe_name, fact, owners, attached, decisions, adopted)
  if not target_line.feature_enabled("recipe_productivity") then
    return "target_unsupported", "recipe_productivity_unsupported"
  end
  local category, reason = base_skip(fact)
  if category then return category, reason end
  local shared_state = shared_input_output_state(fact)
  if #owners == 0 and shared_state == "productive" then
    return "unsafe_skip", "shared_input_output_loop_risk"
  end
  if #owners == 0 and shared_state == "ignored" then
    return "unsafe_skip", "catalyst_or_nonproductive_return_requires_review"
  end
  if #owners > 1 then return "ambiguous", "multiple_recipe_productivity_owners" end
  if #owners == 1 then
    local owner = owners[1]
    if generated_registry.contains(owner) then
      local stream_key = attached[recipe_name]
      if stream_key and not string.find(stream_key, "^research_auto_") then
        return "auto_attached", "structural_family_attachment"
      end
      if stream_key then return "generated_family_covered", "reviewed_generic_family" end
      return "generated_family_covered", "fixed_stream_coverage"
    end
    if adopted[recipe_name] == owner then return "adopted_external", "planned_external_adoption" end
    return "external_exact_owner", "existing_recipe_productivity_effect"
  end
  local decision = decisions[recipe_name]
  if decision and decision.blocker then return "unsafe_skip", decision.blocker end
  if decision then return "unclassified", "family_candidate_without_materialized_owner" end
  return "unclassified", "no_family_candidate_or_owner"
end

function M.build(context)
  context = context or compiler_context.current()
  local facts = recipe_facts.snapshot()
  local owners_by_recipe, prototype_counts = owner_index()
  local attached, decisions, candidate_count = family_indexes()
  local adopted = adopted_index()
  local rows, counts = {}, {}
  for _, category in ipairs(CATEGORIES) do counts[category] = 0 end
  local visible, eligible, dangling, duplicate = 0, 0, 0, 0

  for _, recipe_name in ipairs(facts.names) do
    local fact = facts.facts[recipe_name]
    local owners = owners_by_recipe[recipe_name] or {}
    if not fact.hidden then visible = visible + 1 end
    local skip_category = base_skip(fact)
    if not skip_category and #owners == 0 and shared_input_output_state(fact) then
      skip_category = "unsafe_skip"
    end
    if not skip_category and target_line.feature_enabled("recipe_productivity") then eligible = eligible + 1 end
    if #owners > 1 then duplicate = duplicate + 1 end
    local category, reason = classify(recipe_name, fact, owners, attached, decisions, adopted)
    counts[category] = counts[category] + 1
    table.insert(rows, {
      schema = 1,
      recipe = recipe_name,
      category = category,
      reason = reason,
      visible = not fact.hidden,
      productivity_eligible = not skip_category and target_line.feature_enabled("recipe_productivity"),
      owners = deepcopy(owners)
    })
  end

  for recipe_name, _ in pairs(owners_by_recipe) do
    if not facts.facts[recipe_name] then dangling = dangling + 1 end
  end

  local summary = {
    total_recipes = #facts.names,
    visible_recipes = visible,
    productivity_eligible_recipes = eligible,
    accounted_recipes = #rows,
    category_counts = counts,
    dangling_effects = dangling,
    duplicate_owners = duplicate,
    candidate_count = candidate_count,
    recipe_fact_scan_count = recipe_facts.scan_count(),
    technology_scan_count = prototype_counts.technology_passes,
    technology_count = prototype_counts.technologies,
    technology_effect_count = prototype_counts.effects,
    graph_edge_count = prototype_counts.graph_edges
  }
  local artifact = {
    schema = 1,
    kind = "mir-coverage-report",
    summary = summary,
    rows = rows
  }
  artifact.fingerprint = fingerprint.of(artifact)
  context:set_state("coverage_report", artifact)
  return deepcopy(artifact)
end

function M.emit(context)
  local artifact = M.build(context)
  diagnostics.coverage({
    key = "recipe_accounting",
    status = "diagnostic",
    reason = "all_recipes_accounted",
    total = tostring(artifact.summary.total_recipes),
    visible = tostring(artifact.summary.visible_recipes),
    eligible = tostring(artifact.summary.productivity_eligible_recipes),
    accounted = tostring(artifact.summary.accounted_recipes),
    dangling_effects = tostring(artifact.summary.dangling_effects),
    duplicate_owners = tostring(artifact.summary.duplicate_owners),
    recipe_count = tostring(artifact.summary.total_recipes),
    technology_count = tostring(artifact.summary.technology_count),
    effect_count = tostring(artifact.summary.technology_effect_count),
    graph_edge_count = tostring(artifact.summary.graph_edge_count),
    candidate_count = tostring(artifact.summary.candidate_count),
    scan_count = tostring(artifact.summary.recipe_fact_scan_count + artifact.summary.technology_scan_count),
    evidence = artifact.fingerprint
  })
  for _, row in ipairs(artifact.rows) do
    diagnostics.coverage_recipe({
      key = row.recipe,
      recipe = row.recipe,
      status = row.category,
      reason = row.reason,
      category = row.category,
      visible = tostring(row.visible),
      productivity_eligible = tostring(row.productivity_eligible),
      owners = table.concat(row.owners, ",")
    })
  end
  return artifact
end

function M.publish(context)
  context = context or compiler_context.current()
  local artifact = context:state_snapshot("coverage_report") or M.build(context)
  return mod_data.emit_coverage(artifact)
end

function M.latest_artifact(context)
  context = context or compiler_context.current()
  return context:state_snapshot("coverage_report")
end

return M
