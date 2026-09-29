-- Package-excluded, read-only observation aid for one exact current F210
-- Bob/Angel tuple. It captures the product's canonical facts without
-- declaring a route or modifying a prototype.
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")
local relationships = require("__more-infinite-research__/prototypes/mir/index/relationships")
local data_raw = require("__more-infinite-research__/prototypes/mir/platform/factorio/data_raw")

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

local function names_line(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[#out + 1] = tostring(value) end
  table.sort(out)
  return #out == 0 and "-" or table.concat(out, ",")
end

local function technology_binding(name)
  local technology = data_raw.technology(name)
  if type(technology) ~= "table" or type(technology.unit) ~= "table" then
    error("MIR F210 current Bob/Angel Tin route observation missing unlock " .. tostring(name))
  end
  local science, prerequisites = {}, {}
  for _, entry in ipairs(technology.unit.ingredients or {}) do
    science[#science + 1] = tostring(entry.name or entry[1]) .. ":" .. tostring(entry.amount or entry[2])
  end
  for _, prerequisite in ipairs(technology.prerequisites or {}) do prerequisites[#prerequisites + 1] = prerequisite end
  return name .. "[" .. names_line(science) .. "][" .. names_line(prerequisites) .. "]"
end

local function entries_line(entries)
  local values = {}
  for _, entry in ipairs(entries or {}) do
    values[#values + 1] = (entry.type or "item") .. ":" .. entry.name .. ":" .. tostring(entry.amount or entry.amount_min or "-")
  end
  table.sort(values)
  return #values == 0 and "-" or table.concat(values, "|")
end

local function expected_productivity_effects(technology_name)
  local technology = data.raw.technology[technology_name]
  if type(technology) ~= "table" then
    error("MIR F210 current Bob/Angel Tin route observation missing generated technology " .. technology_name)
  end
  local expected, seen = {
    ["angels-plate-tin"] = true,
    ["angels-plate-tin-2"] = true
  }, {}
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and expected[effect.recipe] then
      if effect.change ~= 0.02 or seen[effect.recipe] then
        error("MIR F210 current Bob/Angel Tin route observation has invalid generated effect " .. technology_name .. ":" .. tostring(effect.recipe))
      end
      seen[effect.recipe] = true
    elseif effect.type == "change-recipe-productivity" then
      error("MIR F210 current Bob/Angel Tin route observation has unexpected generated effect " .. technology_name .. ":" .. tostring(effect.recipe))
    end
  end
  if not seen["angels-plate-tin"] or not seen["angels-plate-tin-2"] then
    error("MIR F210 current Bob/Angel Tin route observation lacks one generated Angel Tin effect for " .. technology_name)
  end
  return technology
end

local function generated_tin_stage_observation()
  local early_name = "recipe-prod-research_material_tin-1"
  local continuation_name = "recipe-prod-research_material_tin-4"
  local early = expected_productivity_effects(early_name)
  local continuation = expected_productivity_effects(continuation_name)
  if early.max_level ~= 3 then
    error("MIR F210 current Bob/Angel Tin route observation early stage must end at level 3")
  end
  if continuation.max_level ~= "infinite" then
    error("MIR F210 current Bob/Angel Tin route observation continuation must retain its script-managed prototype level domain")
  end
  for _, recipe_name in ipairs({"angels-plate-tin", "angels-plate-tin-2"}) do
    local owners = {}
    for owner_name, technology in pairs(data.raw.technology or {}) do
      for _, effect in ipairs(technology.effects or {}) do
        if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
          owners[#owners + 1] = owner_name .. ":" .. tostring(effect.change)
        end
      end
    end
    table.sort(owners)
    local expected = early_name .. ":0.02," .. continuation_name .. ":0.02"
    if table.concat(owners, ",") ~= expected then
      error("MIR F210 current Bob/Angel Tin route observation owner set differs for " .. recipe_name .. ": " .. table.concat(owners, ","))
    end
  end
  log("[mir-f210-current-ba-tin-observer] GENERATED"
    .. " early=" .. early_name .. ":" .. tostring(early.max_level)
    .. " continuation=" .. continuation_name .. ":" .. tostring(continuation.max_level)
    .. " recipes=angels-plate-tin,angels-plate-tin-2")
end

log("[mir-f210-current-ba-tin-observer] ACTIVE_MODS " .. active_mods_line())
compiler_context.with_active(compiler_context.new(), function()
  local input = relationships.view("input")
  if type(input) ~= "table" then error("MIR F210 current Bob/Angel Tin route observation has no relationship index") end
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
    local owners = (input.technologies_by_recipe_effect or {})[recipe_name] or {}
    local unlocks = {}
    for _, name in ipairs((input.unlocks_by_recipe or {})[recipe_name] or {}) do unlocks[#unlocks + 1] = technology_binding(name) end
    log("[mir-f210-current-ba-tin-observer] BINDING recipe=" .. recipe_name
      .. " owners=" .. names_line(owners)
      .. " unlocks=" .. names_line(unlocks))
  end
  local witness = recipe_facts.view("bob-bronze-alloy")
  if type(witness) ~= "table" or type(witness.variants) ~= "table" or #witness.variants ~= 1 then
    error("MIR F210 current Bob/Angel Tin route observation missing single bob-bronze-alloy witness")
  end
  local variant = witness.variants[1]
  log("[mir-f210-current-ba-tin-observer] WITNESS"
    .. " recipe=bob-bronze-alloy"
    .. " source=" .. scalar(witness.source_class)
    .. " hidden=" .. scalar(witness.hidden)
    .. " enabled_without_research=" .. scalar(witness.enabled_without_research)
    .. " variant_hidden=" .. scalar(variant.hidden)
    .. " variant_enabled=" .. scalar(variant.enabled)
    .. " inputs=" .. entries_line(variant.ingredients)
    .. " results=" .. entries_line(variant.results))
  generated_tin_stage_observation()
end)

log("[mir-f210-current-ba-tin-observer] DATA PASS read-only-finalized-contract-capture")
