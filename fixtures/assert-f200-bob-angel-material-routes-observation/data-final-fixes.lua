-- Package-excluded observation aid. It intentionally reads only finalized
-- compiler facts so exact certificates can be authored from one F200 load.
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")

local subjects = {
  {stream = "research_material_aluminium", item = "bob-aluminium-plate", recipes = {"bob-aluminium-plate", "angels-plate-aluminium", "angels-plate-aluminium-2"}},
  {stream = "research_material_gold", item = "bob-gold-plate", recipes = {"bob-gold-plate"}},
  {stream = "research_material_lead", item = "bob-lead-plate", recipes = {"bob-lead-plate", "bob-lead-plate-2"}},
  {stream = "research_material_nickel", item = "bob-nickel-plate", recipes = {"bob-nickel-plate"}},
  {stream = "research_material_platinum", item = "bob-platinum-plate", recipes = {"bob-platinum-plate"}},
  {stream = "research_material_silver", item = "bob-silver-plate", recipes = {"bob-silver-plate"}},
  {stream = "research_material_tin", item = "bob-tin-plate", recipes = {"bob-tin-plate"}},
  {stream = "research_material_titanium", item = "bob-titanium-plate", recipes = {"bob-titanium-plate"}},
  {stream = "research_material_copper_tungsten", item = "bob-copper-tungsten-alloy", recipes = {"bob-copper-tungsten-alloy"}},
  {stream = "research_material_zinc", item = "bob-zinc-plate", recipes = {"bob-zinc-plate"}},
  {stream = "research_material_bronze", item = "bob-bronze-alloy", recipes = {"bob-bronze-alloy"}},
  {stream = "research_material_brass", item = "bob-brass-alloy", recipes = {"bob-brass-alloy"}},
  {stream = "research_material_gunmetal", item = "bob-gunmetal-alloy", recipes = {"bob-gunmetal-alloy"}},
  {stream = "research_material_invar", item = "bob-invar-alloy", recipes = {"bob-invar-alloy"}},
  {stream = "research_material_cobalt_steel", item = "bob-cobalt-steel-alloy", recipes = {"bob-cobalt-steel-alloy"}},
  {stream = "research_material_nitinol", item = "bob-nitinol-alloy", recipes = {"bob-nitinol-alloy"}}
}

local entry_fields = {
  "type", "name", "amount", "amount_min", "amount_max", "probability",
  "independent_probability", "catalyst_amount", "temperature", "minimum_temperature",
  "maximum_temperature", "fluidbox_index", "ignored_by_stats", "ignored_by_productivity",
  "always_fresh", "quality", "quality_change", "percent_spoiled", "extra_count_fraction"
}

local function scalar(value)
  if value == nil then return "-" end
  if type(value) == "boolean" then return value and "true" or "false" end
  return tostring(value)
end

local function entry_line(entry)
  local fields = {}
  for _, field in ipairs(entry_fields) do
    if entry[field] ~= nil then fields[#fields + 1] = field .. "=" .. scalar(entry[field]) end
  end
  return table.concat(fields, ";")
end

local function entries_line(entries)
  local lines = {}
  for _, entry in ipairs(entries or {}) do lines[#lines + 1] = entry_line(entry) end
  table.sort(lines)
  return #lines == 0 and "-" or table.concat(lines, "|")
end

local function names_line(values)
  local names = {}
  for _, value in ipairs(values or {}) do names[#names + 1] = tostring(value) end
  table.sort(names)
  return #names == 0 and "-" or table.concat(names, ",")
end

local function active_mods_line()
  local names = {}
  for name, version in pairs((script and script.active_mods) or mods or {}) do
    names[#names + 1] = name .. "=" .. tostring(version)
  end
  table.sort(names)
  return table.concat(names, ",")
end

local function effect_owners(recipe_name)
  local owners = {}
  for technology_name, technology in pairs(data.raw.technology or {}) do
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
        owners[#owners + 1] = technology_name .. ":" .. scalar(effect.change)
      end
    end
  end
  table.sort(owners)
  return #owners == 0 and "-" or table.concat(owners, ",")
end

log("[mir-f200-material-routes] PROFILE active_mods=" .. active_mods_line())
compiler_context.with_active(compiler_context.new(), function()
  for _, subject in ipairs(subjects) do
    local declared = {}
    for _, recipe_name in ipairs(subject.recipes) do
      declared[recipe_name] = true
      local fact = recipe_facts.view(recipe_name)
      local risk = recipe_risk_facts.view(recipe_name)
      if not fact then
        log("[mir-f200-material-routes] ROUTE stream=" .. subject.stream .. " recipe=" .. recipe_name .. " state=absent")
      else
        local admitted, reason = recipe_matching.material_route_is_acyclic(fact)
        local variant = fact.variants and fact.variants[1] or {}
        log("[mir-f200-material-routes] ROUTE"
          .. " stream=" .. subject.stream
          .. " recipe=" .. recipe_name
          .. " admitted=" .. scalar(admitted)
          .. " reason=" .. scalar(reason)
          .. " source=" .. scalar(fact.source_class)
          .. " hidden=" .. scalar(fact.hidden)
          .. " declared_productivity=" .. scalar(fact.declared_allow_productivity)
          .. " effective_productivity=" .. scalar(fact.effective_allow_productivity)
          .. " maximum_productivity=" .. scalar(fact.effective_maximum_productivity)
          .. " variants=" .. scalar(#(fact.variants or {}))
          .. " ingredients=" .. entries_line(variant.ingredients)
          .. " results=" .. entries_line(variant.results)
          .. " risk=" .. scalar(risk and risk.risk_fingerprint)
          .. " hard=" .. names_line(risk and risk.hard_flags)
          .. " review=" .. names_line(risk and risk.review_flags)
          .. " shared=" .. names_line(risk and risk.shared_input_output)
          .. " owners=" .. effect_owners(recipe_name))
      end
    end
    -- The stable declaration can intentionally name only one ecosystem's
    -- route. List every finalized producer of its output as discovery data;
    -- the report does not promote those routes or change their eligibility.
    for _, recipe_name in ipairs(recipe_facts.recipes_by_output_identity_view("item", subject.item)) do
      if not declared[recipe_name] then
        local fact = recipe_facts.view(recipe_name)
        local risk = recipe_risk_facts.view(recipe_name)
        local admitted, reason = recipe_matching.material_route_is_acyclic(fact)
        local variant = fact and fact.variants and fact.variants[1] or {}
        log("[mir-f200-material-routes] PRODUCER"
          .. " stream=" .. subject.stream
          .. " item=" .. subject.item
          .. " recipe=" .. recipe_name
          .. " admitted=" .. scalar(admitted)
          .. " reason=" .. scalar(reason)
          .. " source=" .. scalar(fact and fact.source_class)
          .. " hidden=" .. scalar(fact and fact.hidden)
          .. " declared_productivity=" .. scalar(fact and fact.declared_allow_productivity)
          .. " effective_productivity=" .. scalar(fact and fact.effective_allow_productivity)
          .. " maximum_productivity=" .. scalar(fact and fact.effective_maximum_productivity)
          .. " variants=" .. scalar(fact and #(fact.variants or {}))
          .. " ingredients=" .. entries_line(variant.ingredients)
          .. " results=" .. entries_line(variant.results)
          .. " risk=" .. scalar(risk and risk.risk_fingerprint)
          .. " hard=" .. names_line(risk and risk.hard_flags)
          .. " review=" .. names_line(risk and risk.review_flags)
          .. " shared=" .. names_line(risk and risk.shared_input_output)
          .. " owners=" .. effect_owners(recipe_name))
      end
    end
  end
end)

-- The current exact F200 Bob/Angel profile has thirteen ordinary finished
-- materials. Assert the emitted recipe effects, rather than inferring delivery
-- from a declaration or from a recipe merely existing in data.raw.
local expected_effects = {
  aluminium = {"angels-plate-aluminium", "angels-plate-aluminium-2"},
  gold = {"angels-plate-gold", "angels-plate-gold-2"},
  lead = {"angels-plate-lead", "angels-plate-lead-2"},
  tin = {"angels-plate-tin", "angels-plate-tin-2"},
  titanium = {"angels-plate-titanium", "angels-plate-titanium-2"},
  copper_tungsten = {"bob-copper-tungsten-alloy"},
  zinc = {"angels-plate-zinc", "angels-plate-zinc-2"},
  bronze = {"angels-plate-bronze"},
  brass = {"angels-plate-brass"},
  gunmetal = {"angels-plate-gunmetal"},
  invar = {"angels-plate-invar"},
  cobalt_steel = {"angels-plate-cobalt-steel"},
  nitinol = {"angels-plate-nitinol"}
}
for key, expected in pairs(expected_effects) do
  local name = "recipe-prod-research_material_" .. key .. "-1"
  local technology = data.raw.technology[name]
  if not technology then error("MIR F200 material missing technology " .. name) end
  local actual = {}
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" then
      actual[#actual + 1] = effect.recipe .. ":" .. tostring(effect.change)
    end
  end
  for index, recipe_name in ipairs(expected) do expected[index] = recipe_name .. ":0.02" end
  table.sort(actual)
  table.sort(expected)
  if table.concat(actual, ",") ~= table.concat(expected, ",") then
    error("MIR F200 material effects differ for " .. name .. " expected="
      .. table.concat(expected, ",") .. " actual=" .. table.concat(actual, ","))
  end
end
for _, key in ipairs({"nickel", "platinum", "silver"}) do
  if data.raw.technology["recipe-prod-research_material_" .. key .. "-1"] then
    error("MIR F200 material unexpectedly emitted " .. key)
  end
end
log("[mir-f200-material-routes] PASS emitted=13 absent=3")
