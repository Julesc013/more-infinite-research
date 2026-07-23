local function fail(message)
  error("MIR synthetic recipe scale validation failed: " .. message)
end

local recipe_facts = require("__more-infinite-research__.prototypes.mir.index.recipe_facts")
local compiler_context = require("__more-infinite-research__.prototypes.mir.pipeline.compiler_context")
local fingerprint = require("__more-infinite-research__.prototypes.mir.core.fingerprint")
local generation_plan = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-generation-plan"]
local prototype = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-coverage-report"]
local summary = prototype and prototype.data and prototype.data.summary
if not summary then fail("coverage summary is missing") end

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
local evidence = evidence_prototype and evidence_prototype.data
local telemetry = evidence and {counters = evidence.counts, phases = evidence.phases}
if not telemetry or telemetry.counters.recipes < 1000
  or telemetry.counters.recipe_index_scans ~= 1 then
  fail("compiler telemetry did not observe the high-fanout recipe campaign")
end
if not generation_plan or not generation_plan.data or type(generation_plan.data.plan_fingerprint) ~= "string" then
  fail("generation plan fingerprint is missing")
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
  .. " compilation=" .. tostring(evidence.semantic_fingerprint)
  .. " in_memory=" .. tostring(stress_fingerprint))
