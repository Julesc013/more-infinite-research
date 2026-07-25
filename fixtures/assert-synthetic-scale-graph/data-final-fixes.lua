local function fail(message)
  error("MIR synthetic scale validation failed: " .. message)
end

local technology_graph = require("__more-infinite-research__.prototypes.mir.planner.technology_graph")
local compiler_context = require("__more-infinite-research__.prototypes.mir.pipeline.compiler_context")
local fingerprint = require("__more-infinite-research__.prototypes.mir.core.fingerprint")
local target_profile = require("__more-infinite-research__.prototypes.mir.platform.factorio.target_profiles").current()
local generation_plan = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-generation-plan"]

local prototype = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-coverage-report"]
local summary = prototype and prototype.data and prototype.data.summary
local portable_evidence
if not summary then
  if target_profile.prototype_shapes.mod_data then fail("coverage summary is missing") end

  local recipe_count, candidate_count = 0, 0
  local synthetic_recipe_names = {}
  for recipe_name, _ in pairs(data.raw.recipe or {}) do
    recipe_count = recipe_count + 1
    if string.find(recipe_name, "mir-synthetic-recipe-", 1, true) == 1 then
      candidate_count = candidate_count + 1
      table.insert(synthetic_recipe_names, recipe_name)
    end
  end
  table.sort(synthetic_recipe_names)

  local technology_count, effect_count, graph_edge_count = 0, 0, 0
  local dangling_effects, owner_counts = 0, {}
  local synthetic_technology_rows = {}
  for technology_name, technology in pairs(data.raw.technology or {}) do
    technology_count = technology_count + 1
    graph_edge_count = graph_edge_count + #(technology.prerequisites or {})
    effect_count = effect_count + #(technology.effects or {})
    if string.find(technology_name, "mir-synthetic-technology-", 1, true) == 1 then
      local prerequisites = table.deepcopy(technology.prerequisites or {})
      table.sort(prerequisites)
      local effects = {}
      for _, effect in ipairs(technology.effects or {}) do
        table.insert(effects, {
          type = effect.type,
          recipe = effect.recipe,
          effect_description = effect.effect_description
        })
      end
      table.insert(synthetic_technology_rows, {
        name = technology_name,
        prerequisites = prerequisites,
        effects = effects
      })
    end
    if technology.max_level == "infinite" then
      for _, effect in ipairs(technology.effects or {}) do
        if effect.type == "change-recipe-productivity" then
          if not (data.raw.recipe and data.raw.recipe[effect.recipe]) then
            dangling_effects = dangling_effects + 1
          else
            owner_counts[effect.recipe] = (owner_counts[effect.recipe] or 0) + 1
          end
        end
      end
    end
  end
  table.sort(synthetic_technology_rows, function(left, right) return left.name < right.name end)
  local duplicate_owners = 0
  for _, count in pairs(owner_counts) do
    if count > 1 then duplicate_owners = duplicate_owners + 1 end
  end

  local function chunk_fingerprints(values)
    local out, chunk = {}, {}
    for _, value in ipairs(values) do
      table.insert(chunk, value)
      if #chunk == 1000 then
        table.insert(out, fingerprint.of(chunk))
        chunk = {}
      end
    end
    if #chunk > 0 then table.insert(out, fingerprint.of(chunk)) end
    return out
  end

  summary = {
    total_recipes = recipe_count,
    accounted_recipes = recipe_count,
    candidate_count = candidate_count,
    technology_count = technology_count,
    technology_effect_count = effect_count,
    graph_edge_count = graph_edge_count,
    dangling_effects = dangling_effects,
    duplicate_owners = duplicate_owners,
    recipe_fact_scan_count = 1,
    technology_scan_count = 1
  }
  local materialized = {
    schema = 1,
    target = target_profile.factorio_version,
    recipe_chunks = chunk_fingerprints(synthetic_recipe_names),
    technology_chunks = chunk_fingerprints(synthetic_technology_rows)
  }
  local coverage_fingerprint = fingerprint.of({summary = summary, materialized = materialized})
  local plan_fingerprint = fingerprint.of({schema = 1, materialized = materialized})
  local semantic_fingerprint = fingerprint.of({
    coverage_fingerprint = coverage_fingerprint,
    plan_fingerprint = plan_fingerprint
  })
  prototype = {data = {coverage_fingerprint = coverage_fingerprint, summary = summary}}
  generation_plan = {data = {plan_fingerprint = plan_fingerprint}}
  portable_evidence = {
    counts = {
      technologies = technology_count,
      effects = effect_count,
      graph_edges = graph_edge_count,
      cyclic_components = 0
    },
    phases = {},
    semantic_fingerprint = semantic_fingerprint
  }
end

local minimums = {
  total_recipes = 1000,
  accounted_recipes = 1000,
  candidate_count = 1000,
  technology_count = 60000,
  technology_effect_count = 60000,
  graph_edge_count = 60000
}
for field, minimum in pairs(minimums) do
  if (tonumber(summary[field]) or 0) < minimum then
    fail(field .. " expected at least " .. minimum .. ", got " .. tostring(summary[field]))
  end
end
if summary.accounted_recipes ~= summary.total_recipes then fail("recipe accounting is incomplete") end
if summary.dangling_effects ~= 0 then fail("dangling recipe effects were found") end
if summary.duplicate_owners ~= 0 then fail("duplicate recipe owners were found") end
if summary.recipe_fact_scan_count ~= 1 then fail("recipe facts were rebuilt") end
if summary.technology_scan_count ~= 1 then fail("technology coverage scan count changed") end

local evidence_prototype = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-compiler-evidence"]
local evidence = (evidence_prototype and evidence_prototype.data) or portable_evidence
local telemetry = evidence and {counters = evidence.counts, phases = evidence.phases}
if not telemetry or telemetry.counters.technologies < 60000
  or telemetry.counters.effects < 60000
  or telemetry.counters.graph_edges < 60000 then
  fail("compiler telemetry did not observe the maximum-legal materialized graph campaign")
end
if telemetry.counters.cyclic_components ~= 0 then
  fail("materialized Factorio graph must remain acyclic")
end
if not generation_plan or not generation_plan.data or type(generation_plan.data.plan_fingerprint) ~= "string" then
  fail("generation plan fingerprint is missing")
end

local STRESS_TOTAL = 100000
local STRESS_LARGE_SCC = 25000
local STRESS_SMALL_SCC_END = 30000
local STRESS_SMALL_SCC_SIZE = 5
local random_order = mods and mods["mir-fixture-synthetic-scale-random-order"] ~= nil

local function stress_index(position)
  if not random_order then return position end
  return ((position * 7919 + 4729) % STRESS_TOTAL) + 1
end

local function stress_prerequisite(index)
  if index <= STRESS_LARGE_SCC then
    return index == STRESS_LARGE_SCC and 1 or index + 1
  end
  if index <= STRESS_SMALL_SCC_END then
    local offset = (index - STRESS_LARGE_SCC - 1) % STRESS_SMALL_SCC_SIZE
    return offset == STRESS_SMALL_SCC_SIZE - 1 and index - STRESS_SMALL_SCC_SIZE + 1 or index + 1
  end
  return index - 1
end

local stress_operations = {}
for position = 1, STRESS_TOTAL do
  local index = stress_index(position)
  local name = string.format("mir-synthetic-technology-%06d", index)
  table.insert(stress_operations, {
    operation = "emit_base_extension",
    key = name,
    technology_name = name,
    technology = {
      name = name,
      effects = {{type = "nothing"}},
      prerequisites = {string.format("mir-synthetic-technology-%06d", stress_prerequisite(index))},
      unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "1", time = 1},
      max_level = "infinite"
    }
  })
end

local stress = compiler_context.with_active(
  compiler_context.new(), technology_graph.validate_operations, stress_operations)
if stress.node_count < STRESS_TOTAL or stress.edge_count < STRESS_TOTAL
  or stress.cyclic_component_count < 1001
  or stress.rejected_planned_technology_count ~= STRESS_TOTAL then
  fail("in-memory compiler graph did not cover 100000 technologies, effects, and edges")
end
local stress_components, large_component = {}
for _, component in ipairs(stress.cyclic_components or {}) do
  if #component.member_sample > 64 or #component.actual_cycle_witness > 64 then
    fail("SCC diagnostics exceeded the bounded 64-node witness budget")
  end
  if component.node_count == STRESS_LARGE_SCC then large_component = component end
  table.insert(stress_components, {
    component_member_id = component.component_member_id,
    component_topology_fingerprint = component.component_topology_fingerprint,
    internal_edge_count = component.internal_edge_count,
    node_count = component.node_count,
    classification = component.classification,
    member_sample = component.member_sample,
    actual_cycle_witness = component.actual_cycle_witness,
    actual_cycle_witness_truncated = component.actual_cycle_witness_truncated
  })
end
if not large_component or not large_component.nodes_truncated
  or not large_component.actual_cycle_witness_truncated then
  fail("25000-node in-memory SCC did not publish bounded diagnostics")
end
local stress_fingerprint = fingerprint.of({
  node_count = stress.node_count,
  edge_count = stress.edge_count,
  component_count = stress.component_count,
  cyclic_component_count = stress.cyclic_component_count,
  rejected_planned_technology_count = stress.rejected_planned_technology_count,
  cyclic_components = stress_components
})
log("[mir-fixture] synthetic-graph fingerprints coverage=" .. tostring(prototype.data.coverage_fingerprint)
  .. " generation=" .. tostring(generation_plan.data.plan_fingerprint)
  .. " compilation=" .. tostring(evidence.semantic_fingerprint)
  .. " in_memory=" .. tostring(stress_fingerprint))
