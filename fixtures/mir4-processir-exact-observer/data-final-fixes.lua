-- Package-excluded T12 observer. This mod is materialized only under build/ and
-- depends on the exact MIR target archive, so it executes after the terminal
-- compiler. It reads canonical facts; it never writes a prototype.
local config = require("capture_config")
local snapshot_adapter = require("__more-infinite-research__.prototypes.mir.pipeline.compilation_snapshot_adapter")
local recipe_risk_facts = require("__more-infinite-research__.prototypes.mir.index.recipe_risk_facts")
local compiler_context = require("__more-infinite-research__.prototypes.mir.pipeline.compiler_context")

local function sorted_copy(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[#out + 1] = value end
  table.sort(out)
  return out
end

local function contains(values, wanted)
  for _, value in ipairs(values or {}) do if value == wanted then return true end end
  return false
end

local function selector_match(name, fact)
  local text = string.lower(name or "")
  for _, category in ipairs(fact.categories or {}) do text = text .. "\0" .. string.lower(category) end
  for _, entry in ipairs(fact.ingredients or {}) do text = text .. "\0" .. string.lower(entry.name or "") end
  for _, entry in ipairs(fact.results or {}) do text = text .. "\0" .. string.lower(entry.name or "") end
  for _, selector in ipairs(config.selectors or {}) do
    if string.find(text, string.lower(selector), 1, true) then return true end
  end
  return false
end

local function selection_rank(name, fact, risk)
  if #(risk.hard_flags or {}) > 0 then return 1 end
  if #(risk.review_flags or {}) > 0 then return 2 end
  if selector_match(name, fact) then return 3 end
  if fact.source_class == "recycling" then return 4 end
  return 5
end

local function selected_names(recipe_domain, risks)
  local ranked = {}
  for _, name in ipairs(recipe_domain.names or {}) do
    local fact = recipe_domain.facts[name]
    ranked[#ranked + 1] = {name = name, rank = selection_rank(name, fact, risks.facts[name] or {})}
  end
  table.sort(ranked, function(left, right)
    if left.rank ~= right.rank then return left.rank < right.rank end
    return left.name < right.name
  end)
  local out = {}
  for index = 1, math.min(#ranked, config.maximum_processes or 128) do out[index] = ranked[index].name end
  table.sort(out)
  return out, #ranked
end

local function machines_by_category(entities)
  local out = {}
  for name, entity in pairs(entities or {}) do
    for _, category in ipairs(entity.crafting_categories or {}) do
      out[category] = out[category] or {}
      out[category][#out[category] + 1] = name
    end
  end
  for _, names in pairs(out) do table.sort(names) end
  return out
end

local function machines_for(fact, index)
  local seen, out = {}, {}
  for _, category in ipairs(fact.categories or {}) do
    for _, name in ipairs(index[category] or {}) do
      if not seen[name] then seen[name] = true; out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

local function source_identity()
  return {
    status = "unavailable",
    reason = "Factorio's finalized recipe prototype surface does not expose a trustworthy last-writer mod identity. The exact environment closure is retained separately."
  }
end

-- MIR deliberately closes its production CompilerContext before dependent mods
-- run. Establish a fresh observation-only context so every cache is rebuilt
-- from the finalized Factorio surface; no production compiler state is reused.
local snapshot, risks = compiler_context.with_active(compiler_context.new(), function()
  local captured = snapshot_adapter.capture({source_fingerprints = {t12_capture = config.capture_id}})
  return captured, recipe_risk_facts.snapshot()
end)
local recipes = snapshot.fact_domains.recipes
local machine_index = machines_by_category(snapshot.fact_domains.entities)
local names, total = selected_names(recipes, risks)

local header = {
  schema = 1,
  kind = "MIR4ExactProcessIRObserverHeaderV1",
  capture_id = config.capture_id,
  target = config.target,
  scenario_id = config.scenario_id,
  maximum_processes = config.maximum_processes,
  selected_processes = #names,
  total_recipes = total,
  compilation_snapshot_fingerprint = snapshot.snapshot_fingerprint,
  recipe_domain_fingerprint = snapshot.domain_fingerprints.recipes,
  relationship_fingerprint = snapshot.relationship_fingerprint,
  owner_index_fingerprint = snapshot.owner_index_fingerprint,
  graph_input_fingerprint = snapshot.graph_input_fingerprint,
  risk_index_fingerprint = risks.risk_index_fingerprint,
  terminal_fact_authority = true,
  post_finalizer_observation = true,
  package_visible = false,
  mutation_authorized = false
}
log("[MIR4_PROCESSIR_HEADER] " .. helpers.table_to_json(header))

for _, name in ipairs(names) do
  local fact = recipes.facts[name]
  local risk = risks.facts[name]
  local row = {
    schema = 1,
    kind = "MIR4ExactProcessIRObserverRowV1",
    capture_id = config.capture_id,
    recipe = name,
    fact = fact,
    risk = risk,
    unlocks = sorted_copy(snapshot.relationship_indexes.unlocks_by_recipe[name]),
    productivity_owners = sorted_copy(snapshot.relationship_indexes.technologies_by_recipe_effect[name]),
    machines = machines_for(fact, machine_index),
    source_mod = source_identity()
  }
  log("[MIR4_PROCESSIR_ROW] " .. helpers.table_to_json(row))
end

local footer = {
  schema = 1,
  kind = "MIR4ExactProcessIRObserverFooterV1",
  capture_id = config.capture_id,
  emitted_rows = #names,
  complete = true,
  mutation_authorized = false
}
log("[MIR4_PROCESSIR_FOOTER] " .. helpers.table_to_json(footer))
