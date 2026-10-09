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
-- Keep this exact fail-closed mirror of recipe_matching.REVIEWED_ENTRY_FIELDS
-- local: recipe_matching does not expose its certificate-only predicate. Any
-- new normalized field appears in an observed entry and is rejected here until
-- this qualification is deliberately reviewed.
local REVIEWED_ENTRY_FIELDS = {
  "type", "name", "amount", "amount_min", "amount_max", "probability",
  "independent_probability", "declared_probability", "declared_independent_probability",
  "shared_probability", "extra_count_fraction", "catalyst_amount",
  "ignored_by_productivity", "ignored_by_stats", "temperature",
  "minimum_temperature", "maximum_temperature", "fluidbox_index",
  "percent_spoiled", "always_fresh", "reset_freshness_on_craft",
  "quality_min", "quality_max", "quality_change", "affected_by_quality"
}
local REVIEWED_ENTRY_FIELD_SET = {}
for _, field in ipairs(REVIEWED_ENTRY_FIELDS) do REVIEWED_ENTRY_FIELD_SET[field] = true end
local RAW_ENTRY_FIELDS = {type = true, name = true, amount = true}
local function dense_array(values)
  if type(values) ~= "table" then return false end
  local count = 0
  for index in pairs(values) do
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then return false end
    count = count + 1
  end
  return count == #values
end
local function normalized_probability(entry, field)
  return tonumber(entry[field] == nil and 1 or entry[field])
end
local function reviewed_entry_value(entry, field)
  if field == "probability" or field == "independent_probability" then return normalized_probability(entry, field) end
  return entry[field]
end
local function positive_fixed_amount(value)
  local number = tonumber(value)
  return number ~= nil and number == number and number ~= math.huge and number ~= -math.huge and number > 0
end
local function zero_or_nil(value) return value == nil or (type(value) == "number" and value == 0) end
local function ordinary_deterministic_entry(entry)
  return positive_fixed_amount(entry.amount)
    and normalized_probability(entry, "probability") == 1
    and normalized_probability(entry, "independent_probability") == 1
    and (entry.declared_probability == nil or entry.declared_probability == 1)
    and (entry.declared_independent_probability == nil or entry.declared_independent_probability == 1)
    and entry.shared_probability == nil
    and entry.amount_min == nil and entry.amount_max == nil
    and zero_or_nil(entry.extra_count_fraction) and zero_or_nil(entry.catalyst_amount)
    and zero_or_nil(entry.ignored_by_productivity) and zero_or_nil(entry.ignored_by_stats)
end
local function assert_normalized_entry(entry, expected, label)
  if type(entry) ~= "table" or type(expected) ~= "table" then fail(label .. " is not a normalized entry") end
  for field in pairs(entry) do if not REVIEWED_ENTRY_FIELD_SET[field] then fail(label .. " has unreviewed normalized field " .. tostring(field)) end end
  for field in pairs(expected) do if not REVIEWED_ENTRY_FIELD_SET[field] then fail(label .. " expected contract has unreviewed field " .. tostring(field)) end end
  if not ordinary_deterministic_entry(entry) or not ordinary_deterministic_entry(expected) then fail(label .. " is not ordinary deterministic IO") end
  for _, field in ipairs(REVIEWED_ENTRY_FIELDS) do
    if reviewed_entry_value(entry, field) ~= reviewed_entry_value(expected, field) then fail(label .. " normalized " .. field .. " differs") end
  end
  if type(entry.type) ~= "string" or entry.type == "" or type(entry.name) ~= "string" or entry.name == "" then fail(label .. " lacks concrete type/name") end
end
local function assert_normalized_entries(entries, expected, label)
  if not dense_array(entries) or not dense_array(expected) or #entries ~= #expected then fail(label .. " normalized cardinality differs") end
  for index, entry in ipairs(entries) do assert_normalized_entry(entry, expected[index], label .. "[" .. index .. "]") end
end
local function assert_raw_entry(entry, expected, label)
  if type(entry) ~= "table" or type(expected) ~= "table" then fail(label .. " is not a raw prototype entry") end
  for field in pairs(entry) do if not RAW_ENTRY_FIELDS[field] then fail(label .. " raw prototype field differs " .. tostring(field)) end end
  for _, field in ipairs({"type", "name", "amount"}) do if entry[field] ~= expected[field] then fail(label .. " raw " .. field .. " differs") end end
end
local function assert_raw_entries(entries, expected, label)
  if not dense_array(entries) or not dense_array(expected) or #entries ~= #expected then fail(label .. " raw cardinality differs") end
  for index, entry in ipairs(entries) do assert_raw_entry(entry, expected[index], label .. "[" .. index .. "]") end
end
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
assert_normalized_entries(admitted_variant.ingredients, {{type = "item", name = "bob-lead-ore", amount = 1, probability = 1, independent_probability = 1}}, "admitted Lead ingredients")
assert_normalized_entries(admitted_variant.results, {{type = "item", name = admitted_recipe, amount = 1, probability = 1, independent_probability = 1}}, "admitted Lead results")
assert_normalized_entries(excluded_variant.ingredients, {{type = "item", name = "bob-lead-oxide", amount = 2, probability = 1, independent_probability = 1}, {type = "item", name = "carbon", amount = 1, probability = 1, independent_probability = 1}}, "excluded Lead ingredients")
assert_normalized_entries(excluded_variant.results, {{type = "item", name = admitted_recipe, amount = 2, probability = 1, independent_probability = 1}}, "excluded Lead results")
log("[mir-a06-bob-lead-qualification] CANONICAL admitted-recipe=" .. admitted_recipe .. " admitted-risk=" .. admitted_risk.risk_fingerprint .. " admitted-declared-productivity=" .. tostring(admitted_fact.declared_allow_productivity) .. " admitted-effective-productivity=" .. tostring(admitted_fact.effective_allow_productivity) .. " excluded-recipe=" .. excluded_recipe .. " excluded-risk=" .. excluded_risk.risk_fingerprint .. " excluded-declared-productivity=" .. tostring(excluded_fact.declared_allow_productivity) .. " excluded-effective-productivity=" .. tostring(excluded_fact.effective_allow_productivity))
log("[mir-a06-bob-lead-qualification] ADMISSION recipe=" .. admitted_recipe .. " mechanism=ordinary-acyclic-route reason=" .. admitted_reason)
for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do if mods[name] then fail("Bob-only fixture refuses " .. name) end end
local admitted_raw = data.raw.recipe[admitted_recipe]
local excluded_raw = data.raw.recipe[excluded_recipe]
if not admitted_raw or admitted_raw.normal or admitted_raw.expensive or #admitted_raw.categories ~= 1 or admitted_raw.categories[1] ~= "smelting"
  or admitted_raw.allow_productivity ~= true or admitted_raw.auto_recycle ~= false or #admitted_raw.ingredients ~= 1 or #admitted_raw.results ~= 1 then fail("exact final admitted Lead recipe form differs") end
assert_raw_entries(admitted_raw.ingredients, {{type = "item", name = "bob-lead-ore", amount = 1}}, "admitted Lead raw ingredients")
assert_raw_entries(admitted_raw.results, {{type = "item", name = admitted_recipe, amount = 1}}, "admitted Lead raw results")
if not excluded_raw or excluded_raw.normal or excluded_raw.expensive or #excluded_raw.categories ~= 1 or excluded_raw.categories[1] ~= "bob-chemical-furnace"
  or excluded_raw.allow_productivity ~= true or excluded_raw.auto_recycle ~= false or #excluded_raw.ingredients ~= 2 or #excluded_raw.results ~= 1 then fail("exact final excluded Lead recipe form differs") end
assert_raw_entries(excluded_raw.ingredients, {{type = "item", name = "bob-lead-oxide", amount = 2}, {type = "item", name = "carbon", amount = 1}}, "excluded Lead raw ingredients")
assert_raw_entries(excluded_raw.results, {{type = "item", name = admitted_recipe, amount = 2}}, "excluded Lead raw results")
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
