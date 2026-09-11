local recipe_name = "bob-gold-plate"
local technology_name = "recipe-prod-research_material_gold-1"
local setting_name = "ips-max-level-research_material_gold"
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")
local function fail(message) error("[mir-a06-bob-gold-qualification] " .. message) end
local function has(values, wanted) for _, value in ipairs(values or {}) do if value == wanted then return true end end return false end
local function sorted(values) table.sort(values); return values end
local function names(entries)
  local result = {}
  for _, entry in ipairs(entries or {}) do result[#result + 1] = entry.name or entry[1] end
  return sorted(result)
end
local function exact(values, expected, label)
  if #values ~= #expected then fail(label .. " count differs") end
  for index, value in ipairs(values) do if value ~= expected[index] then fail(label .. " differs") end end
end
local function empty(values) return type(values) == "table" and next(values) == nil end
local observed_fact, observed_risk, route_admitted, route_reason
compiler_context.with_active(compiler_context.new(), function()
  observed_fact = recipe_facts.view(recipe_name)
  observed_risk = recipe_risk_facts.view(recipe_name)
  route_admitted, route_reason = recipe_matching.material_route_is_acyclic(observed_fact)
end)
if not observed_fact or not observed_risk or #(observed_fact.variants or {}) ~= 1 then fail("canonical Gold recipe observation is absent or variant-mismatched") end
local observed_variant = observed_fact.variants[1]
if observed_fact.name ~= recipe_name or observed_fact.source_class ~= "ordinary" or observed_fact.hidden
  or observed_fact.allow_productivity ~= true or observed_fact.declared_allow_productivity ~= true
  or observed_fact.effective_allow_productivity ~= true or tonumber(observed_fact.effective_maximum_productivity) ~= 3.0 then
  fail("canonical Gold permission, visibility, or maximum-productivity fact differs")
end
if observed_risk.schema ~= 1 or observed_risk.recipe ~= recipe_name
  or observed_risk.risk_fingerprint ~= "mir32-0bcf48a0" or not empty(observed_risk.hard_flags)
  or not empty(observed_risk.review_flags) or not empty(observed_risk.shared_input_output)
  or observed_risk.evidence_confidence ~= 1 then fail("canonical Gold risk evidence differs") end
if route_admitted ~= true or route_reason ~= "no-recipe-return-path" then fail("canonical Gold route is not admitted by the ordinary acyclic guard") end
if #(observed_variant.ingredients or {}) ~= 2 or #(observed_variant.results or {}) ~= 1
  or observed_variant.allow_productivity ~= true or observed_variant.declared_allow_productivity ~= true
  or observed_variant.effective_allow_productivity ~= true or tonumber(observed_variant.effective_maximum_productivity) ~= 3.0 then
  fail("canonical Gold normalized IO or permission cardinality differs")
end
local normalized_ingredients, normalized_results = {}, {}
for _, entry in ipairs(observed_variant.ingredients) do normalized_ingredients[entry.name] = entry end
for _, entry in ipairs(observed_variant.results) do normalized_results[entry.name] = entry end
local ore, chlorine, plate = normalized_ingredients["bob-gold-ore"], normalized_ingredients["bob-chlorine"], normalized_results[recipe_name]
if not ore or not chlorine or not plate or ore.type ~= "item" or ore.name ~= "bob-gold-ore" or ore.amount ~= 1
  or chlorine.type ~= "fluid" or chlorine.name ~= "bob-chlorine" or chlorine.amount ~= 3
  or plate.type ~= "item" or plate.name ~= recipe_name or plate.amount ~= 1 then fail("canonical Gold normalized IO differs") end
log("[mir-a06-bob-gold-qualification] CANONICAL risk=" .. observed_risk.risk_fingerprint .. " hard=" .. table.concat(observed_risk.hard_flags, ",") .. " review=" .. table.concat(observed_risk.review_flags, ",") .. " shared=" .. table.concat(observed_risk.shared_input_output, ",") .. " confidence=" .. tostring(observed_risk.evidence_confidence) .. " source=" .. observed_fact.source_class .. " hidden=" .. tostring(observed_fact.hidden) .. " declared-productivity=" .. tostring(observed_fact.declared_allow_productivity) .. " effective-productivity=" .. tostring(observed_fact.effective_allow_productivity) .. " maximum-productivity=" .. tostring(observed_fact.effective_maximum_productivity))
log("[mir-a06-bob-gold-qualification] ADMISSION mechanism=ordinary-acyclic-route reason=" .. route_reason)
for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do if mods[name] then fail("Bob-only fixture refuses " .. name) end end
local recipe = data.raw.recipe[recipe_name]
if not recipe or recipe.normal or recipe.expensive or #recipe.categories ~= 1 or recipe.categories[1] ~= "bob-chemical-furnace" then fail("exact final Gold recipe form differs") end
if recipe.allow_productivity ~= true or recipe.auto_recycle ~= false or #recipe.ingredients ~= 2 or #recipe.results ~= 1 then fail("exact final Gold cardinality or permission differs") end
local ingredients = {}
for _, entry in ipairs(recipe.ingredients) do ingredients[entry.name or entry[1]] = entry.amount or entry[2] end
if ingredients["bob-gold-ore"] ~= 1 or ingredients["bob-chlorine"] ~= 3 then fail("exact final Gold ingredients differ") end
local product = recipe.results[1]
if (product.name or product[1]) ~= recipe_name or (product.amount or product[2]) ~= 1 then fail("exact final Gold output differs") end
local machine = data.raw["assembling-machine"]["bob-electric-chemical-furnace"]
if not machine or not has(machine.crafting_categories, "bob-chemical-furnace") or not machine.energy_source or machine.energy_source.type ~= "electric" then fail("Gold machine capability differs") end
local technology = data.raw.technology[technology_name]
if not technology then fail("Gold technology is absent") end
exact(sorted(technology.prerequisites or {}), {"automation-science-pack", "bob-gold-processing", "chemical-science-pack", "logistic-science-pack"}, "Gold prerequisites")
exact(names(technology.unit and technology.unit.ingredients), {"automation-science-pack", "chemical-science-pack", "logistic-science-pack"}, "Gold science ingredients")
local lab = data.raw.lab and data.raw.lab.lab
if not lab or not has(lab.inputs, "automation-science-pack") or not has(lab.inputs, "chemical-science-pack") or not has(lab.inputs, "logistic-science-pack") then fail("base lab does not accept exact Gold science") end
local owner_count, change = 0, nil
for owner_name, candidate in pairs(data.raw.technology) do
  for _, effect in ipairs(candidate.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owner_count = owner_count + 1
      if owner_name ~= technology_name or effect.change ~= 0.02 then fail("Gold productivity owner/change differs") end
      change = effect.change
    end
  end
end
if owner_count ~= 1 then fail("Gold requires exactly one productivity owner") end
local direct = settings.startup[setting_name]
local profile = settings.startup["mir-settings-profile-import"]
if not direct or direct.value ~= 2 or not profile or type(profile.value) ~= "string" then fail("Gold cap transport is absent") end
local decoded, decode_error = profile_codec.decode(profile.value)
if not decoded or not decoded.settings or decoded.settings[setting_name] ~= 3 then fail("Gold MIRSET1 cap differs: " .. tostring(decode_error)) end
if startup_settings.raw(setting_name) ~= 2 or startup_settings.get(setting_name) ~= 3 then fail("Gold raw/effective cap resolver differs") end
log("[mir-a06-bob-gold-qualification] DATA recipe=" .. recipe_name .. " machine=bob-electric-chemical-furnace category=bob-chemical-furnace owner=" .. owner_count .. " change=" .. change .. " prerequisites=automation-science-pack,bob-gold-processing,chemical-science-pack,logistic-science-pack science=automation-science-pack,chemical-science-pack,logistic-science-pack lab=lab raw=2 imported=3 effective=3")
