-- Package-excluded, read-only observation aid for one exact current F210
-- Bob/Angel tuple. It captures the product's canonical facts without
-- declaring a route or modifying a prototype.
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")

local routes = {
  "bob-tin-plate",
  "angels-plate-tin",
  "angels-plate-tin-2"
}

local function scalar(value)
  if value == nil then return "-" end
  if type(value) == "boolean" then return value and "true" or "false" end
  return tostring(value)
end

local function active_mods_line()
  local values = {}
  for name, version in pairs(mods or {}) do
    values[#values + 1] = name .. "=" .. tostring(version)
  end
  table.sort(values)
  return table.concat(values, ",")
end

local function entries_line(entries)
  local values = {}
  for _, entry in ipairs(entries or {}) do
    values[#values + 1] = (entry.type or "item") .. ":" .. entry.name .. ":" .. tostring(entry.amount or entry.amount_min or "-")
  end
  table.sort(values)
  return #values == 0 and "-" or table.concat(values, "|")
end

log("[mir-f210-current-ba-tin-observer] ACTIVE_MODS " .. active_mods_line())
compiler_context.with_active(compiler_context.new(), function()
  for _, recipe_name in ipairs(routes) do
    local fact = recipe_facts.view(recipe_name)
    local risk = recipe_risk_facts.view(recipe_name)
    if type(fact) ~= "table" or type(risk) ~= "table" then
      error("MIR F210 current Bob/Angel Tin route observation missing finalized fact " .. recipe_name)
    end
    local admitted, reason = recipe_matching.material_route_is_acyclic(fact)
    local contract, contract_reason = recipe_matching.relevant_route_fingerprints(fact)
    if type(contract) ~= "table" then
      error("MIR F210 current Bob/Angel Tin route observation lacks exact contract " .. recipe_name .. " reason=" .. tostring(contract_reason))
    end
    local variant = fact.variants and fact.variants[1] or {}
    log("[mir-f210-current-ba-tin-observer] ROUTE"
      .. " recipe=" .. recipe_name
      .. " generic=" .. scalar(admitted)
      .. " reason=" .. scalar(reason)
      .. " source=" .. scalar(fact.source_class)
      .. " hidden=" .. scalar(fact.hidden)
      .. " declared_productivity=" .. scalar(fact.declared_allow_productivity)
      .. " effective_productivity=" .. scalar(fact.effective_allow_productivity)
      .. " maximum_productivity=" .. scalar(fact.effective_maximum_productivity)
      .. " risk=" .. scalar(risk.risk_fingerprint)
      .. " graph=" .. scalar(contract.return_graph_fingerprint)
      .. " bindings=" .. scalar(contract.bindings_fingerprint)
      .. " identities=" .. scalar(contract.reachable_identity_count)
      .. " recipes=" .. scalar(contract.relevant_recipe_count)
      .. " producers=" .. scalar(contract.direct_output_producer_count)
      .. " inputs=" .. entries_line(variant.ingredients)
      .. " results=" .. entries_line(variant.results))
  end
end)

log("[mir-f210-current-ba-tin-observer] DATA PASS read-only-finalized-contract-capture")