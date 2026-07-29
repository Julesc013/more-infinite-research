local function fail(message)
  error("MIR synthetic recipe scale validation failed: " .. message)
end

local recipe_facts = require("__more-infinite-research__.prototypes.mir.index.recipe_facts")
local compiler_context = require("__more-infinite-research__.prototypes.mir.pipeline.compiler_context")
local fingerprint = require("__more-infinite-research__.prototypes.mir.core.fingerprint")
local target_profile = require("__more-infinite-research__.prototypes.mir.platform.factorio.target_profiles").current()
local generation_plan = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-generation-plan"]
local prototype = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-coverage-report"]
local summary = prototype and prototype.data and prototype.data.summary
local portable_evidence
if not summary then
  if target_profile.prototype_shapes.mod_data then fail("coverage summary is missing") end

  local portable_index = compiler_context.with_active(
    compiler_context.new(), recipe_facts.index_prototypes, data.raw.recipe or {})
  local synthetic_names = {}
  for _, recipe_name in ipairs(portable_index.names or {}) do
    if string.find(recipe_name, "mir-synthetic-scale-recipe-", 1, true) == 1 then
      table.insert(synthetic_names, recipe_name)
    end
  end

  local dangling_effects, owner_counts = 0, {}
  for _, technology in pairs(data.raw.technology or {}) do
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
  local duplicate_owners = 0
  for _, count in pairs(owner_counts) do
    if count > 1 then duplicate_owners = duplicate_owners + 1 end
  end

  local chunks, chunk = {}, {}
  for _, recipe_name in ipairs(synthetic_names) do
    table.insert(chunk, portable_index.facts[recipe_name])
    if #chunk == 1000 then
      table.insert(chunks, fingerprint.of(chunk))
      chunk = {}
    end
  end
  if #chunk > 0 then table.insert(chunks, fingerprint.of(chunk)) end

  summary = {
    total_recipes = #(portable_index.names or {}),
    accounted_recipes = #(portable_index.names or {}),
    candidate_count = #synthetic_names,
    dangling_effects = dangling_effects,
    duplicate_owners = duplicate_owners,
    recipe_fact_scan_count = 1,
    technology_scan_count = 1
  }
  local materialized = {
    schema = 1,
    target = target_profile.factorio_version,
    recipe_chunks = chunks
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
    counts = {recipes = #(portable_index.names or {}), recipe_index_scans = 1},
    phases = {},
    semantic_fingerprint = semantic_fingerprint
  }
end

local minimums = {
  total_recipes = 1000,
  accounted_recipes = 1000,
  candidate_count = 1000
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
local internal_evidence_prototype = data.raw["mod-data"]
  and data.raw["mod-data"]["more-infinite-research-compiler-evidence-internal"]
local internal_evidence = internal_evidence_prototype and internal_evidence_prototype.data
local telemetry = evidence and {counters = evidence.counts, phases = evidence.phases}
if not telemetry or telemetry.counters.recipes < 1000
  or telemetry.counters.recipe_index_scans ~= 1 then
  fail("compiler telemetry did not observe the high-fanout recipe campaign")
end
if not generation_plan or not generation_plan.data or type(generation_plan.data.plan_fingerprint) ~= "string" then
  fail("generation plan fingerprint is missing")
end
local compiler_output_fingerprint
if internal_evidence and internal_evidence.compiler_result
  and type(internal_evidence.compiler_result.operation_fingerprints) == "table" then
  compiler_output_fingerprint = fingerprint.of(
    internal_evidence.compiler_result.operation_fingerprints)
elseif portable_evidence then
  compiler_output_fingerprint = portable_evidence.semantic_fingerprint
else
  fail("compiler operation fingerprints are missing")
end

local STRESS_TOTAL = 100000
local random_order = mods and mods["mir-fixture-synthetic-scale-random-order"] ~= nil

local function stress_index(position)
  if not random_order then return position end
  return ((position * 7919 + 4729) % STRESS_TOTAL) + 1
end

local stress_prototypes = {}
for position = 1, STRESS_TOTAL do
  local index = stress_index(position)
  local name = string.format("mir-in-memory-recipe-%06d", index)
  stress_prototypes[name] = {
    type = "recipe",
    name = name,
    enabled = true,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{
      type = "item",
      name = index <= 1000 and "mir-synthetic-recipe-machine" or "mir-synthetic-recipe-filler",
      amount = 1
    }},
    allow_productivity = true
  }
end

local stress = compiler_context.with_active(
  compiler_context.new(), recipe_facts.index_prototypes, stress_prototypes)
if #stress.names ~= STRESS_TOTAL
  or #(stress.by_output["mir-synthetic-recipe-machine"] or {}) ~= 1000
  or #(stress.by_output["mir-synthetic-recipe-filler"] or {}) ~= 99000
  or #(stress.by_ingredient["iron-plate"] or {}) ~= STRESS_TOTAL
  or #(stress.by_category.crafting or {}) ~= STRESS_TOTAL then
  fail("in-memory canonical recipe index did not cover all 100000 recipes")
end

local function chunk_fingerprints(values, project)
  local out, chunk = {}, {}
  for _, value in ipairs(values or {}) do
    table.insert(chunk, project and project(value) or value)
    if #chunk == 1000 then
      table.insert(out, fingerprint.of(chunk))
      chunk = {}
    end
  end
  if #chunk > 0 then table.insert(out, fingerprint.of(chunk)) end
  return out
end

local function index_fingerprint(index)
  local keys, rows = {}, {}
  for key, _ in pairs(index or {}) do table.insert(keys, key) end
  table.sort(keys)
  for _, key in ipairs(keys) do
    table.insert(rows, {key = key, chunks = chunk_fingerprints(index[key])})
  end
  return fingerprint.of(rows)
end

local stress_fingerprint = fingerprint.of({
  schema = stress.schema,
  facts = chunk_fingerprints(stress.names, function(name) return stress.facts[name] end),
  by_output = index_fingerprint(stress.by_output),
  by_productive_output = index_fingerprint(stress.by_productive_output),
  by_ingredient = index_fingerprint(stress.by_ingredient),
  by_category = index_fingerprint(stress.by_category)
})
log("[mir-fixture] synthetic-recipes fingerprints coverage=" .. tostring(prototype.data.coverage_fingerprint)
  .. " generation=" .. tostring(generation_plan.data.plan_fingerprint)
  .. " compilation=" .. tostring(compiler_output_fingerprint)
  .. " in_memory=" .. tostring(stress_fingerprint))
