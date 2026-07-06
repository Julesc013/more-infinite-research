local productivity_owners = require("prototypes.compat.productivity-owners")
local schema = require("prototypes.lib.mir.schema")

local R = {}

-- Typed fact contract: RecipeFact, TechnologyFact, MachineFact, LabFact,
-- OwnerFact, and RuleMutationFact. These are boring data snapshots used by
-- diagnostics and future planner gates; they do not mutate prototypes.

local DEFAULT_RECIPE_MAX_PRODUCTIVITY = 3.0

local MACHINE_TYPES = {
  "assembling-machine",
  "furnace",
  "mining-drill",
  "rocket-silo"
}

local function sorted_keys(tbl)
  local keys = {}
  for key, _ in pairs(tbl or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

local function table_count(tbl)
  local count = 0
  for _, _ in pairs(tbl or {}) do count = count + 1 end
  return count
end

local function push_unique(list, seen, value)
  if value and not seen[value] then
    seen[value] = true
    table.insert(list, value)
  end
end

local function sorted_set_values(set)
  local out = {}
  for value, enabled in pairs(set or {}) do
    if enabled then table.insert(out, value) end
  end
  table.sort(out)
  return out
end

local function prototype_name(entry)
  if not entry then return nil end
  if type(entry) == "string" then return entry end
  return entry.name or entry[1]
end

local function prototype_amount(entry)
  if not entry or type(entry) == "string" then return 1 end
  return entry.amount or entry[2] or 1
end

local function scan_recipe_variants(recipe, callback)
  if not recipe then return end
  if type(recipe.normal) == "table" or type(recipe.expensive) == "table" then
    if type(recipe.normal) == "table" then callback(recipe.normal, "normal") end
    if type(recipe.expensive) == "table" then callback(recipe.expensive, "expensive") end
    return
  end
  callback(recipe, "default")
end

local function recipe_categories(recipe)
  if recipe and recipe.categories then return recipe.categories end
  if recipe and recipe.category then return {recipe.category} end
  return {"crafting"}
end

local function recipe_hidden(recipe)
  if not recipe then return false end
  if recipe.hidden then return true end
  if type(recipe.normal) == "table" and recipe.normal.hidden then return true end
  if type(recipe.expensive) == "table" and recipe.expensive.hidden then return true end
  return false
end

local function recipe_enabled(recipe)
  if not recipe then return false end
  if recipe.enabled ~= nil then return recipe.enabled == true end
  if type(recipe.normal) == "table" and recipe.normal.enabled ~= nil then return recipe.normal.enabled == true end
  if type(recipe.expensive) == "table" and recipe.expensive.enabled ~= nil then return recipe.expensive.enabled == true end
  return false
end

local function collect_recipe_io(recipe, field)
  local by_name = {}
  scan_recipe_variants(recipe, function(def)
    local entries = def[field]
    if field == "results" and not entries and def.result then
      entries = {{name = def.result, amount = def.result_count or 1}}
    end
    for _, entry in pairs(entries or {}) do
      local name = prototype_name(entry)
      if name then
        local existing = by_name[name] or 0
        by_name[name] = existing + prototype_amount(entry)
      end
    end
  end)

  local out = {}
  for _, name in ipairs(sorted_keys(by_name)) do
    table.insert(out, {
      name = name,
      amount = by_name[name]
    })
  end
  return out
end

local function main_product(recipe, results)
  if not recipe then return nil end
  if recipe.main_product then return recipe.main_product end
  local found = nil
  scan_recipe_variants(recipe, function(def)
    if def.main_product and not found then found = def.main_product end
    if def.result and not found then found = def.result end
  end)
  if found then return found end
  if #results == 1 then return results[1].name end
  return nil
end

local function collect_unlock_techs()
  local unlocks = {}
  for _, tech_name in ipairs(sorted_keys(data.raw.technology or {})) do
    local tech = data.raw.technology[tech_name]
    for _, effect in ipairs(tech.effects or {}) do
      if effect.type == "unlock-recipe" and effect.recipe then
        unlocks[effect.recipe] = unlocks[effect.recipe] or {}
        table.insert(unlocks[effect.recipe], tech_name)
      end
    end
  end
  return unlocks
end

local function collect_science_packs(tech)
  local out = {}
  local unit = tech and tech.unit
  for _, ingredient in ipairs((unit and unit.ingredients) or {}) do
    local name = prototype_name(ingredient)
    if name then table.insert(out, name) end
  end
  table.sort(out)
  return out
end

local function collect_effect_types(tech)
  local seen = {}
  local out = {}
  for _, effect in ipairs((tech and tech.effects) or {}) do
    push_unique(out, seen, effect.type)
  end
  table.sort(out)
  return out
end

local function collect_categories(source)
  local seen = {}
  local out = {}
  for _, category in ipairs((source and source.crafting_categories) or {}) do
    push_unique(out, seen, category)
  end
  table.sort(out)
  return out
end

local function collect_allowed_effects(source)
  local allowed = source and source.allowed_effects
  if not allowed then return {} end
  if #allowed > 0 then
    local seen = {}
    local out = {}
    for _, effect in ipairs(allowed) do
      push_unique(out, seen, effect)
    end
    table.sort(out)
    return out
  end
  return sorted_set_values(allowed)
end

local function has_allowed_effect(source, effect_name)
  for _, effect in ipairs(collect_allowed_effects(source)) do
    if effect == effect_name then return true end
  end
  return false
end

local function build_recipe_facts(unlocks)
  local facts = {}
  for _, name in ipairs(sorted_keys(data.raw.recipe or {})) do
    local recipe = data.raw.recipe[name]
    local ingredients = collect_recipe_io(recipe, "ingredients")
    local results = collect_recipe_io(recipe, "results")
    local owner_records = productivity_owners.external_recipe_productivity_owner_records(name)
    local owner_names = {}
    for _, owner in ipairs(owner_records) do
      table.insert(owner_names, owner.tech)
    end
    table.sort(owner_names)

    facts[name] = {
      name = name,
      categories = recipe_categories(recipe),
      ingredients = ingredients,
      results = results,
      main_product = main_product(recipe, results),
      allow_productivity = productivity_owners.recipe_allows_productivity(name),
      maximum_productivity = recipe.maximum_productivity,
      allow_quality = recipe.allow_quality,
      hidden = recipe_hidden(recipe),
      enabled = recipe_enabled(recipe),
      unlock_techs = unlocks[name] or {},
      surface_conditions = recipe.surface_conditions,
      owners = owner_names
    }
  end
  return facts
end

local function build_technology_facts()
  local facts = {}
  for _, name in ipairs(sorted_keys(data.raw.technology or {})) do
    local tech = data.raw.technology[name]
    facts[name] = {
      name = name,
      effects = collect_effect_types(tech),
      effect_count = #(tech.effects or {}),
      prerequisites = tech.prerequisites or {},
      science_packs = collect_science_packs(tech),
      count_formula = tech.unit and tech.unit.count_formula,
      max_level = tech.max_level,
      research_trigger = tech.research_trigger,
      hidden = tech.hidden == true,
      enabled = tech.enabled ~= false,
      owners = {}
    }
  end
  return facts
end

local function build_machine_facts()
  local facts = {}
  for _, prototype_type in ipairs(MACHINE_TYPES) do
    for _, name in ipairs(sorted_keys(data.raw[prototype_type] or {})) do
      local machine = data.raw[prototype_type][name]
      facts[prototype_type .. "/" .. name] = {
        name = name,
        prototype_type = prototype_type,
        crafting_categories = collect_categories(machine),
        module_slots = machine.module_slots or 0,
        allowed_effects = collect_allowed_effects(machine),
        base_productivity = machine.base_productivity,
        allowed_module_categories = machine.allowed_module_categories or {},
        surface_conditions = machine.surface_conditions
      }
    end
  end
  return facts
end

local function build_lab_facts()
  local facts = {}
  for _, name in ipairs(sorted_keys(data.raw.lab or {})) do
    local lab = data.raw.lab[name]
    local inputs = {}
    for _, input in ipairs(lab.inputs or {}) do table.insert(inputs, input) end
    table.sort(inputs)
    facts[name] = {
      name = name,
      inputs = inputs,
      module_slots = lab.module_slots or 0,
      allowed_effects = collect_allowed_effects(lab),
      allowed_module_categories = lab.allowed_module_categories or {}
    }
  end
  return facts
end

local function owner_status(tech_name, effect)
  if productivity_owners.is_mir_recipe_productivity_tech(tech_name) then
    return "mir_owned"
  end
  if effect.type == "change-recipe-productivity" then
    return "external_owned_exact"
  end
  return "external_owned_unknown"
end

local function owner_subject(effect)
  if effect.type == "change-recipe-productivity" then
    return "recipe", effect.recipe
  end
  local parts = {}
  for _, field in ipairs(sorted_keys(effect)) do
    local value = effect[field]
    if field ~= "type" and field ~= "modifier" and field ~= "change" and field ~= "icon" and field ~= "icons"
        and (type(value) == "string" or type(value) == "number" or type(value) == "boolean") then
      table.insert(parts, field .. "=" .. tostring(value))
    end
  end
  local subject = effect.type
  if #parts > 0 then subject = subject .. "|" .. table.concat(parts, ",") end
  return "modifier", subject
end

local function build_owner_facts()
  local facts = {}
  for _, tech_name in ipairs(sorted_keys(data.raw.technology or {})) do
    local tech = data.raw.technology[tech_name]
    for _, effect in ipairs(tech.effects or {}) do
      if effect.type and effect.type ~= "unlock-recipe" and effect.type ~= "nothing" then
        local subject_type, subject = owner_subject(effect)
        if subject then
          table.insert(facts, {
            subject_type = subject_type,
            subject = subject,
            effect_type = effect.type,
            change_value = effect.change or effect.modifier,
            technology = tech_name,
            mod_owner = productivity_owners.is_mir_recipe_productivity_tech(tech_name) and "more-infinite-research" or "external",
            infinite = tech.max_level == "infinite",
            finite_lead_in = tech.max_level ~= "infinite",
            exact_overlap = effect.type == "change-recipe-productivity",
            policy = owner_status(tech_name, effect)
          })
        end
      end
    end
  end
  return facts
end

local function build_rule_mutation_facts(recipe_facts, machine_facts, lab_facts)
  local facts = {}

  for _, name in ipairs(sorted_keys(recipe_facts)) do
    local recipe = recipe_facts[name]
    local cap = recipe.maximum_productivity
    if cap ~= nil and (type(cap) ~= "number" or math.abs(cap - DEFAULT_RECIPE_MAX_PRODUCTIVITY) > 0.000000001) then
      table.insert(facts, {
        subject = name,
        subject_type = "recipe",
        field = "maximum_productivity",
        observed_value = tostring(cap),
        expected_baseline = tostring(DEFAULT_RECIPE_MAX_PRODUCTIVITY),
        likely_mutator_mod = "",
        confidence = 1.0
      })
    end
  end

  for _, key in ipairs(sorted_keys(machine_facts)) do
    local machine = machine_facts[key]
    local value = tonumber(machine.base_productivity)
    if value and math.abs(value) > 0.000000001 then
      table.insert(facts, {
        subject = key,
        subject_type = "machine",
        field = "base_productivity",
        observed_value = tostring(machine.base_productivity),
        expected_baseline = "0",
        likely_mutator_mod = "",
        confidence = 0.8
      })
    end
  end

  for _, key in ipairs(sorted_keys(data.raw.beacon or {})) do
    local beacon = data.raw.beacon[key]
    if has_allowed_effect(beacon, "productivity") then
      table.insert(facts, {
        subject = "beacon/" .. key,
        subject_type = "beacon",
        field = "allowed_effects",
        observed_value = "productivity",
        expected_baseline = "no_productivity",
        likely_mutator_mod = "",
        confidence = 0.7
      })
    end
  end

  for _, key in ipairs(sorted_keys(lab_facts)) do
    local lab = lab_facts[key]
    for _, effect in ipairs(lab.allowed_effects or {}) do
      if effect == "productivity" then
        table.insert(facts, {
          subject = "lab/" .. key,
          subject_type = "lab",
          field = "allowed_effects",
          observed_value = "productivity",
          expected_baseline = "no_productivity",
          likely_mutator_mod = "",
          confidence = 0.7
        })
      end
    end
  end

  return facts
end

local RISK_PATTERNS = {
  {flag = "recycling_loop", patterns = {"recycl"}, categories = {recycling = true}},
  {flag = "cleaning_or_recovery_loop", patterns = {"clean", "recover", "recovery", "wash", "washing", "scrub", "scrubbing"}},
  {flag = "voiding_or_destruction", patterns = {"void", "vent", "flare", "sink", "destroy", "disposal"}},
  {flag = "barrel_or_container_return", patterns = {"barrel", "canister", "container", "capsule", "empty%-", "fill%-"}},
  {flag = "matter_or_transmutation", patterns = {"matter", "transmut", "conversion", "convert"}}
}

local function contains_pattern(name, patterns)
  local text = string.lower(name or "")
  for _, pattern in ipairs(patterns or {}) do
    if string.find(text, pattern) then return true end
  end
  return false
end

local function category_set(categories)
  local out = {}
  for _, category in ipairs(categories or {}) do out[category] = true end
  return out
end

local function io_intersection(ingredients, results)
  local ingredient_names = {}
  for _, ingredient in ipairs(ingredients or {}) do ingredient_names[ingredient.name] = true end
  local out = {}
  for _, result in ipairs(results or {}) do
    if ingredient_names[result.name] then table.insert(out, result.name) end
  end
  table.sort(out)
  return out
end

local function build_loop_risk_facts(recipe_facts)
  local facts = {}
  for _, name in ipairs(sorted_keys(recipe_facts)) do
    local recipe = recipe_facts[name]
    local flags = {}
    local seen = {}
    local categories = category_set(recipe.categories)

    for _, risk in ipairs(RISK_PATTERNS) do
      local matched = contains_pattern(name, risk.patterns)
      if not matched and risk.categories then
        for category, _ in pairs(risk.categories) do
          if categories[category] then matched = true end
        end
      end
      if matched then push_unique(flags, seen, risk.flag) end
    end

    local repeated = io_intersection(recipe.ingredients, recipe.results)
    if #repeated > 0 then
      push_unique(flags, seen, "catalyst_or_self_return", nil)
      if #recipe.results == 1 then
        push_unique(flags, seen, "self_producing_recipe", nil)
      end
    end

    if recipe.hidden then
      push_unique(flags, seen, "hidden_internal", nil)
    end

    if #recipe.results > 1 and contains_pattern(name, {"ore", "fragment", "scrap", "core"}) then
      push_unique(flags, seen, "multi_output_resource_loop", nil)
    end

    if #flags > 0 then
      table.insert(facts, {
        subject = name,
        subject_type = "recipe",
        risk_flags = flags,
        shared_inputs_outputs = repeated,
        confidence = 0.75
      })
    end
  end
  return facts
end

function R.labs_for_packs(lab_facts, packs)
  local wanted = {}
  for _, pack in ipairs(packs or {}) do wanted[pack] = true end
  local labs = {}
  for _, name in ipairs(sorted_keys(lab_facts)) do
    local lab = lab_facts[name]
    local accepted = {}
    for _, input in ipairs(lab.inputs or {}) do accepted[input] = true end
    local ok = true
    for pack, _ in pairs(wanted) do
      if not accepted[pack] then
        ok = false
        break
      end
    end
    if ok then table.insert(labs, name) end
  end
  return labs
end

function R.build()
  local unlocks = collect_unlock_techs()
  local recipes = build_recipe_facts(unlocks)
  local technologies = build_technology_facts()
  local machines = build_machine_facts()
  local labs = build_lab_facts()
  local owners = build_owner_facts()
  local rule_mutations = build_rule_mutation_facts(recipes, machines, labs)
  local loop_risks = build_loop_risk_facts(recipes)

  local generated_technologies = 0
  for _, tech_name in ipairs(sorted_keys(technologies)) do
    if productivity_owners.is_mir_recipe_productivity_tech(tech_name) then
      generated_technologies = generated_technologies + 1
    end
  end

  return {
    schema = schema.fact_registry,
    recipes = recipes,
    technologies = technologies,
    machines = machines,
    labs = labs,
    owners = owners,
    rule_mutations = rule_mutations,
    loop_risks = loop_risks,
    summary = {
      recipes = table_count(recipes),
      technologies = table_count(technologies),
      machines = table_count(machines),
      labs = table_count(labs),
      owners = #owners,
      rule_mutations = #rule_mutations,
      loop_risks = #loop_risks,
      generated_technologies = generated_technologies
    }
  }
end

function R.sorted_keys(tbl)
  return sorted_keys(tbl)
end

return R
