local recipe_name = "bob-aluminium-plate"
local technology_name = "recipe-prod-research_material_aluminium-1"
local setting_name = "ips-max-level-research_material_aluminium"
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")

local function fail(message) error("[mir-a06-bob-aluminium-qualification] " .. message) end
local function sorted(values) table.sort(values); return values end
local function names(entries)
  local result = {}
  for _, entry in ipairs(entries or {}) do result[#result + 1] = entry.name or entry[1] end
  return sorted(result)
end
local function contains(values, expected)
  for _, value in ipairs(values or {}) do if value == expected then return true end end
  return false
end
local function exact(values, expected, label)
  if #values ~= #expected then fail(label .. " count differs") end
  for index, value in ipairs(values) do if value ~= expected[index] then fail(label .. " differs") end end
end
local function empty(values) return type(values) == "table" and next(values) == nil end

-- Package-excluded post-finalizer observer: record the canonical fact consumed
-- by the existing reviewed-forward-route contract before asserting admission.
local function observed_entry(entry)
  local fields = {"type", "name", "amount", "amount_min", "amount_max", "probability", "independent_probability", "declared_probability", "declared_independent_probability", "shared_probability", "extra_count_fraction", "catalyst_amount", "ignored_by_productivity", "ignored_by_stats", "temperature", "minimum_temperature", "maximum_temperature", "fluidbox_index", "percent_spoiled", "always_fresh", "reset_freshness_on_craft", "quality_min", "quality_max", "quality_change", "affected_by_quality"}
  local values = {}
  for _, field in ipairs(fields) do values[#values + 1] = field .. "=" .. (entry[field] == nil and "nil" or tostring(entry[field])) end
  return table.concat(values, ";")
end
local observed_fact, observed_risk
compiler_context.with_active(compiler_context.new(), function()
  observed_fact = recipe_facts.view(recipe_name)
  observed_risk = recipe_risk_facts.view(recipe_name)
end)
if not observed_fact or not observed_risk or #(observed_fact.variants or {}) ~= 1 then fail("canonical Aluminium recipe observation is absent or variant-mismatched") end
local observed_variant = observed_fact.variants[1]
if observed_fact.name ~= recipe_name or observed_fact.source_class ~= "ordinary" or observed_fact.hidden
  or observed_fact.allow_productivity ~= true or observed_fact.declared_allow_productivity ~= true
  or observed_fact.effective_allow_productivity ~= true or tonumber(observed_fact.effective_maximum_productivity) ~= 3.0 then
  fail("canonical Aluminium permission, visibility, or maximum-productivity fact differs")
end
if observed_risk.schema ~= 1 or observed_risk.recipe ~= recipe_name
  or observed_risk.risk_fingerprint ~= "mir32-fd133af7"
  or not empty(observed_risk.hard_flags)
  or not empty(observed_risk.review_flags)
  or not empty(observed_risk.shared_input_output)
  or observed_risk.evidence_confidence ~= 1 then
  fail("canonical Aluminium risk evidence differs")
end
if #(observed_variant.ingredients or {}) ~= 2 or #(observed_variant.results or {}) ~= 1 then
  fail("canonical Aluminium normalized IO cardinality differs")
end
if observed_variant.allow_productivity ~= true or observed_variant.declared_allow_productivity ~= true
  or observed_variant.effective_allow_productivity ~= true or tonumber(observed_variant.effective_maximum_productivity) ~= 3.0 then
  fail("canonical Aluminium variant permission or maximum-productivity fact differs")
end
if observed_entry(observed_variant.ingredients[1]) ~= observed_entry({type = "item", name = "bob-alumina", amount = 2, probability = 1, independent_probability = 1})
  or observed_entry(observed_variant.ingredients[2]) ~= observed_entry({type = "item", name = "carbon", amount = 1, probability = 1, independent_probability = 1})
  or observed_entry(observed_variant.results[1]) ~= observed_entry({type = "item", name = "bob-aluminium-plate", amount = 2, probability = 1, independent_probability = 1}) then
  fail("canonical Aluminium normalized IO differs")
end
log("[mir-a06-bob-aluminium-qualification] CANONICAL risk=" .. observed_risk.risk_fingerprint
  .. " hard=" .. table.concat(observed_risk.hard_flags, ",") .. " review=" .. table.concat(observed_risk.review_flags, ",")
  .. " shared=" .. table.concat(observed_risk.shared_input_output, ",") .. " confidence=" .. tostring(observed_risk.evidence_confidence)
  .. " source=" .. observed_fact.source_class .. " hidden=" .. tostring(observed_fact.hidden)
  .. " declared-productivity=" .. tostring(observed_fact.declared_allow_productivity)
  .. " effective-productivity=" .. tostring(observed_fact.effective_allow_productivity)
  .. " maximum-productivity=" .. tostring(observed_fact.effective_maximum_productivity)
  .. " ingredient=" .. observed_entry(observed_variant.ingredients[1]) .. "|" .. observed_entry(observed_variant.ingredients[2])
  .. " result=" .. observed_entry(observed_variant.results[1]))

for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do if mods[name] then fail("Bob-only fixture refuses " .. name) end end
local recipe = data.raw.recipe[recipe_name]
if not recipe or #recipe.categories ~= 1 or recipe.categories[1] ~= "bob-electrolysis" or recipe.normal or recipe.expensive then fail("exact final Aluminium recipe form differs") end
if #recipe.ingredients ~= 2 or #recipe.results ~= 1 then fail("exact final Aluminium ingredient/result cardinality differs") end
local ingredients = {}
for _, entry in ipairs(recipe.ingredients) do ingredients[entry.name or entry[1]] = entry.amount or entry[2] end
if ingredients["bob-alumina"] ~= 2 or ingredients["carbon"] ~= 1 then fail("exact final Aluminium ingredients differ") end
local product = recipe.results[1]
if (product.name or product[1]) ~= recipe_name or (product.amount or product[2]) ~= 2 then fail("exact final Aluminium output differs") end
if recipe.allow_productivity ~= true or recipe.auto_recycle ~= false then fail("Aluminium productivity permission/recycling differs") end
local machine = data.raw["assembling-machine"] and data.raw["assembling-machine"]["bob-electrolyser"]
if not machine or not contains(machine.crafting_categories, "bob-electrolysis") or not machine.energy_source or machine.energy_source.type ~= "electric" then fail("bob-electrolyser capability differs") end

local technology = data.raw.technology[technology_name]
if not technology then fail("Aluminium technology is absent") end
exact(sorted(technology.prerequisites or {}), {"automation-science-pack", "bob-aluminium-processing", "logistic-science-pack"}, "Aluminium prerequisites")
exact(names(technology.unit and technology.unit.ingredients), {"automation-science-pack", "logistic-science-pack"}, "Aluminium science ingredients")
local lab = data.raw.lab and data.raw.lab.lab
if not lab or not contains(lab.inputs, "automation-science-pack") or not contains(lab.inputs, "logistic-science-pack") then fail("base lab does not accept exact Aluminium science") end
local owner_count, change = 0, nil
for owner_name, candidate in pairs(data.raw.technology) do
  for _, effect in ipairs(candidate.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owner_count = owner_count + 1
      if owner_name ~= technology_name or effect.change ~= 0.02 then fail("Aluminium productivity owner/change differs") end
      change = effect.change
    end
  end
end
if owner_count ~= 1 then fail("Aluminium requires exactly one productivity owner") end
local direct = settings.startup[setting_name]
local profile = settings.startup["mir-settings-profile-import"]
if not direct or direct.value ~= 2 or not profile or type(profile.value) ~= "string" then fail("Aluminium cap transport is absent") end
local decoded, decode_error = profile_codec.decode(profile.value)
if not decoded or not decoded.settings or decoded.settings[setting_name] ~= 3 then fail("Aluminium MIRSET1 cap differs: " .. tostring(decode_error)) end
if startup_settings.raw(setting_name) ~= 2 or startup_settings.get(setting_name) ~= 3 then fail("Aluminium raw/effective cap resolver differs") end
log("[mir-a06-bob-aluminium-qualification] DATA recipe=" .. recipe_name .. " machine=bob-electrolyser category=bob-electrolysis owner=" .. owner_count .. " change=" .. change .. " prerequisites=automation-science-pack,bob-aluminium-processing,logistic-science-pack science=automation-science-pack,logistic-science-pack lab=lab raw=2 imported=3 effective=3")
