local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")

local bronze = {
  key = "bronze",
  recipe = "bob-bronze-alloy",
  technology = "recipe-prod-research_material_bronze-1",
  machine = "bob-electric-mixing-furnace",
  machine_type = "assembling-machine",
  category = "bob-mixing-furnace",
  risk = "mir32-e44a5d1a",
  ingredients = {
    {type = "item", name = "copper-plate", amount = 3},
    {type = "item", name = "bob-tin-plate", amount = 2}
  },
  result = {type = "item", name = "bob-bronze-alloy", amount = 5},
  science = {"automation-science-pack"}
}
local routes = {
  bronze,
  {
    key = "gunmetal",
    recipe = "bob-gunmetal-alloy",
    technology = "recipe-prod-research_material_gunmetal-1",
    machine = "bob-electric-mixing-furnace",
    machine_type = "assembling-machine",
    category = "bob-mixing-furnace",
    risk = "mir32-7ac4d701",
    ingredients = {
      {type = "item", name = "copper-plate", amount = 8},
      {type = "item", name = "bob-tin-plate", amount = 1},
      {type = "item", name = "bob-zinc-plate", amount = 1}
    },
    result = {type = "item", name = "bob-gunmetal-alloy", amount = 10},
    science = {"automation-science-pack", "logistic-science-pack"}
  },
  {
    key = "invar",
    recipe = "bob-invar-alloy",
    technology = "recipe-prod-research_material_invar-1",
    machine = "bob-electric-mixing-furnace",
    machine_type = "assembling-machine",
    category = "bob-mixing-furnace",
    risk = "mir32-af1ecd3b",
    ingredients = {
      {type = "item", name = "bob-nickel-plate", amount = 2},
      {type = "item", name = "iron-plate", amount = 3}
    },
    result = {type = "item", name = "bob-invar-alloy", amount = 5},
    science = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack"}
  },
  {
    key = "nitinol",
    recipe = "bob-nitinol-alloy",
    technology = "recipe-prod-research_material_nitinol-1",
    machine = "bob-electric-mixing-furnace",
    machine_type = "assembling-machine",
    category = "bob-mixing-furnace",
    risk = "mir32-946acc06",
    ingredients = {
      {type = "item", name = "bob-nickel-plate", amount = 3},
      {type = "item", name = "bob-titanium-plate", amount = 2}
    },
    result = {type = "item", name = "bob-nitinol-alloy", amount = 5},
    science = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack", "production-science-pack"}
  },
  {
    key = "copper-tungsten",
    recipe = "bob-copper-tungsten-alloy",
    technology = "recipe-prod-research_material_copper_tungsten-1",
    machine = "foundry",
    machine_type = "assembling-machine",
    category = "metallurgy",
    risk = "mir32-d92d266f",
    ingredients = {
      {type = "item", name = "bob-powdered-tungsten", amount = 3},
      {type = "fluid", name = "molten-copper", amount = 20}
    },
    result = {type = "item", name = "bob-copper-tungsten-alloy", amount = 5},
    science = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack", "metallurgic-science-pack", "production-science-pack", "space-science-pack"}
  }
}
local guard = {
  recipe = "bob-brass-alloy",
  technology = "recipe-prod-research_material_brass-1",
  risk = "mir32-99ebf44b",
  ingredients = {
    {type = "item", name = "copper-plate", amount = 3},
    {type = "item", name = "bob-zinc-plate", amount = 2}
  },
  result = {type = "item", name = "bob-brass-alloy", amount = 5}
}

local function fail(message)
  error("[mir-a06-bob-ordinary-alloys-qualification] " .. message)
end

local function exact(actual, expected, label)
  if #actual ~= #expected then fail(label .. " count differs") end
  for index, value in ipairs(actual) do
    if value ~= expected[index] then fail(label .. " differs at " .. index) end
  end
end

local function sorted_names(entries)
  local result = {}
  for _, entry in ipairs(entries or {}) do
    result[#result + 1] = entry.name or entry[1]
  end
  table.sort(result)
  return result
end

local function contains(values, wanted)
  for _, value in ipairs(values or {}) do
    if value == wanted then return true end
  end
  return false
end

local function empty(values)
  return type(values) == "table" and next(values) == nil
end

local function entry_key(entry)
  return (entry.type or "item") .. ":" .. (entry.name or entry[1])
end

local function assert_entries(actual, expected, label, normalized)
  if type(actual) ~= "table" or #actual ~= #expected then
    fail(label .. " cardinality differs")
  end
  local observed, wanted = {}, {}
  for _, entry in ipairs(actual) do
    if type(entry) ~= "table" then fail(label .. " entry is malformed") end
    if normalized and (entry.probability ~= 1 or entry.independent_probability ~= 1) then
      fail(label .. " normalized probability differs")
    end
    observed[entry_key(entry)] = entry.amount or entry[2]
  end
  for _, entry in ipairs(expected) do
    wanted[entry.type .. ":" .. entry.name] = entry.amount
  end
  for key, amount in pairs(wanted) do
    if observed[key] ~= amount then fail(label .. " entry differs " .. key) end
  end
  for key in pairs(observed) do
    if wanted[key] == nil then fail(label .. " has unexpected entry " .. key) end
  end
end

local function assert_common_fact(fact, risk, route)
  if not fact or not risk or fact.name ~= route.recipe or fact.source_class ~= "ordinary" or fact.hidden
    or fact.allow_productivity ~= true or fact.declared_allow_productivity ~= true
    or fact.effective_allow_productivity ~= true or tonumber(fact.effective_maximum_productivity) ~= 3.0
    or #(fact.variants or {}) ~= 1 then
    fail(route.key .. " canonical fact differs")
  end
  if risk.schema ~= 1 or risk.recipe ~= route.recipe or risk.risk_fingerprint ~= route.risk
    or risk.evidence_confidence ~= 1 or not empty(risk.hard_flags) or not empty(risk.review_flags)
    or not empty(risk.shared_input_output) then
    fail(route.key .. " risk certificate differs")
  end
  local variant = fact.variants[1]
  if variant.allow_productivity ~= true or variant.declared_allow_productivity ~= true
    or variant.effective_allow_productivity ~= true or tonumber(variant.effective_maximum_productivity) ~= 3.0 then
    fail(route.key .. " canonical variant permission differs")
  end
  assert_entries(variant.ingredients, route.ingredients, route.key .. " canonical ingredients", true)
  assert_entries(variant.results, {route.result}, route.key .. " canonical results", true)
end

local function assert_raw_recipe(route)
  local recipe = data.raw.recipe[route.recipe]
  if not recipe or recipe.normal or recipe.expensive or #(recipe.categories or {}) ~= 1
    or recipe.categories[1] ~= route.category or recipe.allow_productivity ~= true or recipe.auto_recycle ~= false then
    fail(route.key .. " final raw recipe form differs")
  end
  assert_entries(recipe.ingredients, route.ingredients, route.key .. " raw ingredients", false)
  assert_entries(recipe.results, {route.result}, route.key .. " raw results", false)
end

local function effect_count(recipe, technology)
  local count, change = 0, nil
  for owner_name, candidate in pairs(data.raw.technology) do
    for _, effect in ipairs(candidate.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe then
        count = count + 1
        if owner_name ~= technology or effect.change ~= 0.02 then
          fail(recipe .. " owner/change differs")
        end
        change = effect.change
      end
    end
  end
  return count, change
end

local facts, risks, admitted, reasons = {}, {}, {}, {}
compiler_context.with_active(compiler_context.new(), function()
  for _, route in ipairs(routes) do
    facts[route.key] = recipe_facts.view(route.recipe)
    risks[route.key] = recipe_risk_facts.view(route.recipe)
    admitted[route.key], reasons[route.key] = recipe_matching.material_route_is_acyclic(facts[route.key])
  end
  facts.brass = recipe_facts.view(guard.recipe)
  risks.brass = recipe_risk_facts.view(guard.recipe)
  admitted.brass, reasons.brass = recipe_matching.material_route_is_acyclic(facts.brass)
end)

for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do
  if mods[name] then fail("Bob-only fixture refuses " .. name) end
end

local lab = data.raw.lab and data.raw.lab.lab
if not lab then fail("base lab is absent") end

for _, route in ipairs(routes) do
  assert_common_fact(facts[route.key], risks[route.key], route)
  if admitted[route.key] ~= true or reasons[route.key] ~= "no-recipe-return-path" then
    fail(route.key .. " ordinary route is not admitted")
  end
  assert_raw_recipe(route)
  local machine = data.raw[route.machine_type] and data.raw[route.machine_type][route.machine]
  if not machine or not contains(machine.crafting_categories, route.category)
    or not machine.energy_source or machine.energy_source.type ~= "electric" then
    fail(route.key .. " machine capability differs")
  end
  local technology = data.raw.technology[route.technology]
  if not technology then fail(route.key .. " technology is absent") end
  exact(sorted_names(technology.prerequisites), {}, route.key .. " prerequisites")
  exact(sorted_names(technology.unit and technology.unit.ingredients), route.science, route.key .. " science")
  for _, science in ipairs(route.science) do
    if not contains(lab.inputs, science) then fail(route.key .. " lab science differs " .. science) end
  end
  local owners, change = effect_count(route.recipe, route.technology)
  if owners ~= 1 then fail(route.key .. " exact owner count differs") end
  if route.key == "bronze" then
    log("[mir-a06-bob-ordinary-alloys-qualification] ADMISSION mechanism=ordinary-acyclic-route reason=no-recipe-return-path")
    log("[mir-a06-bob-ordinary-alloys-qualification] DATA recipe=" .. route.recipe .. " machine=" .. route.machine .. " category=" .. route.category .. " owner=" .. owners .. " change=" .. change .. " prerequisites=- science=" .. table.concat(route.science, ",") .. " lab=lab raw=2 imported=3 effective=3")
  end
end

assert_common_fact(facts.brass, risks.brass, {
  key = "brass",
  recipe = guard.recipe,
  risk = guard.risk,
  ingredients = guard.ingredients,
  result = guard.result
})
if admitted.brass ~= false or reasons.brass ~= "potential-return-path:copper-plate" then
  fail("Brass exact negative guard differs")
end
assert_raw_recipe({
  key = "brass",
  recipe = guard.recipe,
  category = "bob-mixing-furnace",
  ingredients = guard.ingredients,
  result = guard.result
})
if data.raw.technology[guard.technology] then fail("withheld Brass technology was emitted") end
local brass_owners = effect_count(guard.recipe, guard.technology)
if brass_owners ~= 0 then fail("withheld Brass gained a productivity owner") end

local setting_name = "ips-max-level-research_material_bronze"
local direct, profile = settings.startup[setting_name], settings.startup["mir-settings-profile-import"]
if not direct or direct.value ~= 2 or not profile or type(profile.value) ~= "string" then
  fail("Bronze cap transport is absent")
end
local decoded, decode_error = profile_codec.decode(profile.value)
if not decoded or not decoded.settings or decoded.settings[setting_name] ~= 3 then
  fail("Bronze MIRSET1 cap differs: " .. tostring(decode_error))
end
if startup_settings.raw(setting_name) ~= 2 or startup_settings.get(setting_name) ~= 3 then
  fail("Bronze raw/effective cap resolver differs")
end

log("[mir-a06-bob-ordinary-alloys-qualification] MATRIX admitted=bronze,gunmetal,invar,nitinol,copper-tungsten brass=withheld:potential-return-path:copper-plate brass-owner-effects=0")
