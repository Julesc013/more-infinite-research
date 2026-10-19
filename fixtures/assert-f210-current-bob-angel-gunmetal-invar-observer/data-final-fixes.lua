-- Package-excluded read-only capture for exact F210 Bob/Angel Gunmetal/Invar.
-- It records finalized facts and never admits a route or mutates a prototype.
local active_mods = {}
for name, version in pairs(mods or {}) do active_mods[#active_mods + 1] = name .. "@" .. version end
table.sort(active_mods)
log("[MIR_ACTIVE_MODS] " .. table.concat(active_mods, "|"))
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")
local relationships = require("__more-infinite-research__/prototypes/mir/index/relationships")
local data_raw = require("__more-infinite-research__/prototypes/mir/platform/factorio/data_raw")

local direct_producers = {
  {family = "gunmetal", role = "recycler", recipe = "bob-gunmetal-alloy-recycling"},
  {family = "gunmetal", role = "hidden-direct-producer", recipe = "bob-gunmetal-alloy"},
  {family = "invar", role = "recycler", recipe = "bob-invar-alloy-recycling"},
  {family = "invar", role = "hidden-direct-producer", recipe = "bob-invar-alloy"}
}

local function line(value)
  if type(serpent) ~= "table" or type(serpent.line) ~= "function" then
    error("[mir-f210-current-ba-gunmetal-invar-observer] serpent.line is unavailable")
  end
  return serpent.line(value, {comment = false, sortkeys = true})
end

local function direct_producer_observation(subject)
  local raw = (data.raw.recipe or {})[subject.recipe]
  local normalized = recipe_facts.view(subject.recipe)
  if type(raw) ~= "table" or type(normalized) ~= "table" then
    error("[mir-f210-current-ba-gunmetal-invar-observer] direct producer fact is absent " .. subject.recipe)
  end
  log("[mir-f210-current-ba-gunmetal-invar-observer] FACT family=" .. subject.family
    .. " role=" .. subject.role .. " recipe=" .. subject.recipe
    .. " raw=" .. line(raw) .. " normalized=" .. line(normalized))
end
local subjects = {
  {family = "gunmetal", technology = "recipe-prod-research_material_gunmetal-1", recipe = "angels-plate-gunmetal"},
  {family = "invar", technology = "recipe-prod-research_material_invar-1", recipe = "angels-plate-invar"}
}

local function scalar(value)
  if value == nil then return "-" end
  local text = tostring(value):gsub("%s+", "_")
  return text == "" and "-" or text
end

local function names_line(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[#out + 1] = scalar(value) end
  table.sort(out)
  return #out == 0 and "-" or table.concat(out, ",")
end

local function science_line(technology)
  if type(technology) ~= "table" or type(technology.unit) ~= "table" then return "-" end
  local values = {}
  for _, entry in ipairs(technology.unit.ingredients or {}) do
    values[#values + 1] = scalar(entry.name or entry[1]) .. ":" .. scalar(entry.amount or entry[2])
  end
  return names_line(values)
end

local function prerequisites_line(technology)
  if type(technology) ~= "table" then return "-" end
  return names_line(technology.prerequisites)
end

local function technology_binding(name)
  local technology = data_raw.technology(name)
  if type(technology) ~= "table" then return scalar(name) .. "[missing]" end
  return scalar(name) .. "[science=" .. science_line(technology) .. ";prerequisites=" .. prerequisites_line(technology) .. "]"
end

local function effect_owners(recipe)
  local owners = {}
  for technology_name, technology in pairs(data.raw.technology or {}) do
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe then
        owners[#owners + 1] = scalar(technology_name) .. ":" .. scalar(effect.change)
      end
    end
  end
  return names_line(owners)
end

local function emission_observation(subject)
  local technology = data.raw.technology[subject.technology]
  local matching, unexpected = 0, 0
  if type(technology) == "table" then
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" then
        if effect.recipe == subject.recipe and effect.change == 0.02 then matching = matching + 1 else unexpected = unexpected + 1 end
      end
    end
  end
  log("[mir-f210-current-ba-gunmetal-invar-observer] EMISSION family=" .. subject.family
    .. " technology=" .. subject.technology
    .. " present=" .. scalar(type(technology) == "table")
    .. " max_level=" .. scalar(type(technology) == "table" and technology.max_level or nil)
    .. " matching_effects=" .. tostring(matching)
    .. " unexpected_productivity_effects=" .. tostring(unexpected)
    .. " recipe_owners=" .. effect_owners(subject.recipe))
end

compiler_context.with_active(compiler_context.new(), function()
  local input = relationships.view("input") or {}
  for _, producer in ipairs(direct_producers) do direct_producer_observation(producer) end
  for _, subject in ipairs(subjects) do
    local fact = recipe_facts.view(subject.recipe)
    local risk = recipe_risk_facts.view(subject.recipe)
    local contract, contract_reason = nil, nil
    if type(fact) == "table" then contract, contract_reason = recipe_matching.relevant_route_fingerprints(fact) end
    local admitted, reason = false, "missing_fact"
    if type(fact) == "table" then admitted, reason = recipe_matching.material_route_is_acyclic(fact) end
    local owners = (input.technologies_by_recipe_effect or {})[subject.recipe] or {}
    local unlocks = {}
    for _, name in ipairs((input.unlocks_by_recipe or {})[subject.recipe] or {}) do unlocks[#unlocks + 1] = technology_binding(name) end
    log("[mir-f210-current-ba-gunmetal-invar-observer] ROUTE family=" .. subject.family
      .. " recipe=" .. subject.recipe
      .. " fact_present=" .. scalar(type(fact) == "table")
      .. " generic=" .. scalar(admitted)
      .. " reason=" .. scalar(reason)
      .. " source=" .. scalar(type(fact) == "table" and fact.source_class or nil)
      .. " hidden=" .. scalar(type(fact) == "table" and fact.hidden or nil)
      .. " declared_productivity=" .. scalar(type(fact) == "table" and fact.declared_allow_productivity or nil)
      .. " effective_productivity=" .. scalar(type(fact) == "table" and fact.effective_allow_productivity or nil)
      .. " maximum_productivity=" .. scalar(type(fact) == "table" and fact.effective_maximum_productivity or nil))
    log("[mir-f210-current-ba-gunmetal-invar-observer] CERTIFICATE family=" .. subject.family
      .. " recipe=" .. subject.recipe
      .. " available=" .. scalar(type(contract) == "table")
      .. " reason=" .. scalar(contract_reason)
      .. " risk=" .. scalar(type(risk) == "table" and risk.risk_fingerprint or nil)
      .. " graph=" .. scalar(type(contract) == "table" and contract.return_graph_fingerprint or nil)
      .. " bindings=" .. scalar(type(contract) == "table" and contract.bindings_fingerprint or nil)
      .. " identities=" .. scalar(type(contract) == "table" and contract.reachable_identity_count or nil)
      .. " recipes=" .. scalar(type(contract) == "table" and contract.relevant_recipe_count or nil)
      .. " producers=" .. scalar(type(contract) == "table" and contract.direct_output_producer_count or nil))
    log("[mir-f210-current-ba-gunmetal-invar-observer] BINDING family=" .. subject.family
      .. " recipe=" .. subject.recipe
      .. " generated_technology=" .. subject.technology
      .. " science=" .. science_line(data_raw.technology(subject.technology))
      .. " prerequisites=" .. prerequisites_line(data_raw.technology(subject.technology))
      .. " effect_owners=" .. names_line(owners)
      .. " unlocks=" .. names_line(unlocks))
    emission_observation(subject)
  end
end)

log("[mir-f210-current-ba-gunmetal-invar-observer] DATA PASS read-only-finalized-fact-capture")
