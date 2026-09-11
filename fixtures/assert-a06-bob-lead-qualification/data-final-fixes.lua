local admitted_recipe = "bob-lead-plate"
local excluded_recipe = "bob-lead-plate-2"
local technology_name = "recipe-prod-research_material_lead-1"
local setting_name = "ips-max-level-research_material_lead"
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")
local function fail(message) error("[mir-a06-bob-lead-qualification] " .. message) end
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
local admitted_fact, admitted_risk, admitted, admitted_reason
local excluded_fact, excluded_risk, excluded, excluded_reason
compiler_context.with_active(compiler_context.new(), function()
  admitted_fact = recipe_facts.view(admitted_recipe)
  admitted_risk = recipe_risk_facts.view(admitted_recipe)
  admitted, admitted_reason = recipe_matching.material_route_is_acyclic(admitted_fact)
  excluded_fact = recipe_facts.view(excluded_recipe)
  excluded_risk = recipe_risk_facts.view(excluded_recipe)
  excluded, excluded_reason = recipe_matching.material_route_is_acyclic(excluded_fact)
end)
local function assert_canonical(fact, risk, recipe, fingerprint)
  if not fact or not risk or #(fact.variants or {}) ~= 1 then fail("canonical " .. recipe .. " observation is absent or variant-mismatched") end
  if fact.name ~= recipe or fact.source_class ~= "ordinary" or fact.hidden
    or fact.allow_productivity ~= true or fact.declared_allow_productivity ~= true
    or fact.effective_allow_productivity ~= true or tonumber(fact.effective_maximum_productivity) ~= 3.0 then
    fail("canonical " .. recipe .. " permission, visibility, or maximum-productivity fact differs")
  end
  if risk.schema ~= 1 or risk.recipe ~= recipe or risk.risk_fingerprint ~= fingerprint
    or not empty(risk.hard_flags) or not empty(risk.review_flags) or not empty(risk.shared_input_output)
    or risk.evidence_confidence ~= 1 then fail("canonical " .. recipe .. " risk evidence differs") end
  local variant = fact.variants[1]
  if variant.allow_productivity ~= true or variant.declared_allow_productivity ~= true
    or variant.effective_allow_productivity ~= true or tonumber(variant.effective_maximum_productivity) ~= 3.0 then
    fail("canonical " .. recipe .. " variant permission differs")
  end
  return variant
end
local admitted_variant = assert_canonical(admitted_fact, admitted_risk, admitted_recipe, "mir32-1806ec36")
local excluded_variant = assert_canonical(excluded_fact, excluded_risk, excluded_recipe, "mir32-ea26340b")
if admitted ~= true or admitted_reason ~= "no-recipe-return-path" then fail("canonical Lead smelting route is not admitted by the ordinary acyclic guard") end
if excluded ~= false or excluded_reason ~= "potential-return-path:carbon" then fail("canonical Lead alternative is not withheld by the ordinary acyclic guard") end
if #(admitted_variant.ingredients or {}) ~= 1 or #(admitted_variant.results or {}) ~= 1 then fail("canonical admitted Lead normalized IO cardinality differs") end
local admitted_input, admitted_output = admitted_variant.ingredients[1], admitted_variant.results[1]
if admitted_input.type ~= "item" or admitted_input.name ~= "bob-lead-ore" or admitted_input.amount ~= 1
  or admitted_output.type ~= "item" or admitted_output.name ~= admitted_recipe or admitted_output.amount ~= 1 then fail("canonical admitted Lead normalized IO differs") end
if #(excluded_variant.ingredients or {}) ~= 2 or #(excluded_variant.results or {}) ~= 1 then fail("canonical excluded Lead normalized IO cardinality differs") end
local excluded_ingredients = {}
for _, entry in ipairs(excluded_variant.ingredients) do excluded_ingredients[entry.name] = entry end
local excluded_output = excluded_variant.results[1]
if not excluded_ingredients["bob-lead-oxide"] or excluded_ingredients["bob-lead-oxide"].type ~= "item" or excluded_ingredients["bob-lead-oxide"].amount ~= 2
  or not excluded_ingredients.carbon or excluded_ingredients.carbon.type ~= "item" or excluded_ingredients.carbon.amount ~= 1
  or excluded_output.type ~= "item" or excluded_output.name ~= admitted_recipe or excluded_output.amount ~= 2 then fail("canonical excluded Lead normalized IO differs") end
log("[mir-a06-bob-lead-qualification] CANONICAL admitted-recipe=" .. admitted_recipe .. " admitted-risk=" .. admitted_risk.risk_fingerprint .. " admitted-declared-productivity=" .. tostring(admitted_fact.declared_allow_productivity) .. " admitted-effective-productivity=" .. tostring(admitted_fact.effective_allow_productivity) .. " excluded-recipe=" .. excluded_recipe .. " excluded-risk=" .. excluded_risk.risk_fingerprint .. " excluded-declared-productivity=" .. tostring(excluded_fact.declared_allow_productivity) .. " excluded-effective-productivity=" .. tostring(excluded_fact.effective_allow_productivity))
log("[mir-a06-bob-lead-qualification] ADMISSION recipe=" .. admitted_recipe .. " mechanism=ordinary-acyclic-route reason=" .. admitted_reason)
for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do if mods[name] then fail("Bob-only fixture refuses " .. name) end end
local admitted_raw = data.raw.recipe[admitted_recipe]
local excluded_raw = data.raw.recipe[excluded_recipe]
if not admitted_raw or admitted_raw.normal or admitted_raw.expensive or #admitted_raw.categories ~= 1 or admitted_raw.categories[1] ~= "smelting"
  or admitted_raw.allow_productivity ~= true or admitted_raw.auto_recycle ~= false or #admitted_raw.ingredients ~= 1 or #admitted_raw.results ~= 1 then fail("exact final admitted Lead recipe form differs") end
local raw_input, raw_output = admitted_raw.ingredients[1], admitted_raw.results[1]
if (raw_input.name or raw_input[1]) ~= "bob-lead-ore" or (raw_input.amount or raw_input[2]) ~= 1
  or (raw_output.name or raw_output[1]) ~= admitted_recipe or (raw_output.amount or raw_output[2]) ~= 1 then fail("exact final admitted Lead IO differs") end
if not excluded_raw or excluded_raw.normal or excluded_raw.expensive or #excluded_raw.categories ~= 1 or excluded_raw.categories[1] ~= "bob-chemical-furnace"
  or excluded_raw.allow_productivity ~= true or excluded_raw.auto_recycle ~= false or #excluded_raw.ingredients ~= 2 or #excluded_raw.results ~= 1 then fail("exact final excluded Lead recipe form differs") end
local raw_excluded_ingredients = {}
for _, entry in ipairs(excluded_raw.ingredients) do raw_excluded_ingredients[entry.name or entry[1]] = entry.amount or entry[2] end
local raw_excluded_output = excluded_raw.results[1]
if raw_excluded_ingredients["bob-lead-oxide"] ~= 2 or raw_excluded_ingredients.carbon ~= 1
  or (raw_excluded_output.name or raw_excluded_output[1]) ~= admitted_recipe or (raw_excluded_output.amount or raw_excluded_output[2]) ~= 2 then fail("exact final excluded Lead IO differs") end
local furnace = data.raw.furnace["electric-furnace"]
if not furnace or not has(furnace.crafting_categories, "smelting") or not furnace.energy_source or furnace.energy_source.type ~= "electric" then fail("Lead smelting machine capability differs") end
local alternative_machine = data.raw["assembling-machine"]["bob-electric-chemical-furnace"]
if not alternative_machine or not has(alternative_machine.crafting_categories, "bob-chemical-furnace") or not alternative_machine.energy_source or alternative_machine.energy_source.type ~= "electric" then fail("Lead alternative machine capability differs") end
local technology = data.raw.technology[technology_name]
if not technology then fail("Lead technology is absent") end
exact(sorted(technology.prerequisites or {}), {"automation-science-pack", "chemical-science-pack", "logistic-science-pack"}, "Lead prerequisites")
exact(names(technology.unit and technology.unit.ingredients), {"automation-science-pack", "chemical-science-pack", "logistic-science-pack"}, "Lead science ingredients")
local lab = data.raw.lab and data.raw.lab.lab
if not lab or not has(lab.inputs, "automation-science-pack") or not has(lab.inputs, "chemical-science-pack") or not has(lab.inputs, "logistic-science-pack") then fail("base lab does not accept exact Lead science") end
local admitted_owner_count, excluded_owner_count, change = 0, 0, nil
for owner_name, candidate in pairs(data.raw.technology) do
  for _, effect in ipairs(candidate.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == admitted_recipe then
      admitted_owner_count = admitted_owner_count + 1
      if owner_name ~= technology_name or effect.change ~= 0.02 then fail("Lead productivity owner/change differs") end
      change = effect.change
    elseif effect.type == "change-recipe-productivity" and effect.recipe == excluded_recipe then
      excluded_owner_count = excluded_owner_count + 1
    end
  end
end
if admitted_owner_count ~= 1 or excluded_owner_count ~= 0 then fail("Lead admitted/excluded ownership differs") end
log("[mir-a06-bob-lead-qualification] EXCLUSION recipe=" .. excluded_recipe .. " reason=" .. excluded_reason .. " owner-effects=" .. excluded_owner_count)
local direct = settings.startup[setting_name]
local profile = settings.startup["mir-settings-profile-import"]
if not direct or direct.value ~= 2 or not profile or type(profile.value) ~= "string" then fail("Lead cap transport is absent") end
local decoded, decode_error = profile_codec.decode(profile.value)
if not decoded or not decoded.settings or decoded.settings[setting_name] ~= 3 then fail("Lead MIRSET1 cap differs: " .. tostring(decode_error)) end
if startup_settings.raw(setting_name) ~= 2 or startup_settings.get(setting_name) ~= 3 then fail("Lead raw/effective cap resolver differs") end
log("[mir-a06-bob-lead-qualification] DATA recipe=" .. admitted_recipe .. " machine=electric-furnace category=smelting owner=" .. admitted_owner_count .. " change=" .. change .. " prerequisites=automation-science-pack,chemical-science-pack,logistic-science-pack science=automation-science-pack,chemical-science-pack,logistic-science-pack lab=lab raw=2 imported=3 effective=3")
