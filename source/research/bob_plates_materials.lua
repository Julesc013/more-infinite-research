-- Explicit F210 Bob Plates material and ordinary-product data.  This module
-- names only the captured individual Bob Plates routes; selection, raw
-- admission, and prototype publication remain outside this data module.
local CORE = require("research.bob_core_materials")

local M = {}

local CORE_KEYS = {
  "research_material_bronze",
  "research_material_copper_tungsten",
  "research_material_gunmetal",
  "research_material_invar",
  "research_material_lead",
  "research_material_nitinol",
  "research_material_tin",
}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR Bob Plates definition contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, nested in pairs(value) do out[key] = copy(nested, seen) end
  seen[value] = nil
  return out
end

local CORE_BY_KEY = {}
for _, definition in ipairs(CORE) do CORE_BY_KEY[definition.key] = definition end

local function route(recipe, ingredients, results, owner, enabled, allow_productivity)
  return {
    recipe = recipe, ingredients = ingredients, results = results, owner = owner,
    enabled = enabled, allow_productivity = allow_productivity,
    maximum_productivity = "omitted",
  }
end

local function item(name, amount) return {type="item", name=name, amount=amount} end
local function fluid(name, amount) return {type="fluid", name=name, amount=amount} end

local function stages(key, early_science, early_prerequisites, continuation_science, continuation_prerequisites)
  return {
    early = {
      id = "recipe-prod-" .. key .. "-1", max_level = 3, order = "p[" .. key .. "]",
      science = early_science, prerequisites = early_prerequisites,
    },
    continuation = {
      id = "recipe-prod-" .. key .. "-4", first_level = 4,
      predecessor_count = 800, previous_count = 400, max_level = "infinite",
      order = "p[" .. key .. "__continuation]", science = continuation_science,
      prerequisites = continuation_prerequisites,
      show_levels_info = false, visible_when_disabled = true,
    },
  }
end

local function definition(key, item_name, icon, icon_size, routes, stage_data)
  return {
    key = key, item = item_name, icon = icon, icon_size = icon_size,
    productivity_ceiling = 3, routes = routes,
    early = stage_data.early, continuation = stage_data.continuation,
  }
end

local function base_delta(key, routes, early_science, early_prerequisites, continuation_science, continuation_prerequisites)
  return {
    routes = routes,
    stages = stages(key, early_science, early_prerequisites, continuation_science, continuation_prerequisites),
  }
end

-- Each body below is an authored delta over the same seven named definitions
-- as research.bob_core_materials.  Base deliberately keeps its captured
-- utility-science tails rather than reusing Space Age's vectors.
local BASE_CORE_DELTAS = {
  research_material_bronze = base_delta("research_material_bronze", {
    route("bob-bronze-alloy", {item("copper-plate", 3), item("bob-tin-plate", 2)}, {item("bob-bronze-alloy", 5)}, "bob-alloy-processing", false, true),
  }, {"automation-science-pack"}, {"automation-science-pack", "bob-alloy-processing"}, {"automation-science-pack", "utility-science-pack"},
  {"automation-science-pack", "bob-alloy-processing", "recipe-prod-research_material_bronze-1", "utility-science-pack"}),
  research_material_copper_tungsten = base_delta("research_material_copper_tungsten", {
    route("bob-copper-tungsten-alloy", {item("copper-plate", 2), item("bob-powdered-tungsten", 3)}, {item("bob-copper-tungsten-alloy", 5)}, "bob-tungsten-processing", false, true),
  }, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
  {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "bob-tungsten-processing"}, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"},
  {"automation-science-pack", "bob-tungsten-processing", "chemical-science-pack", "logistic-science-pack", "production-science-pack", "recipe-prod-research_material_copper_tungsten-1", "utility-science-pack"}),
  research_material_gunmetal = base_delta("research_material_gunmetal", {
    route("bob-gunmetal-alloy", {item("copper-plate", 8), item("bob-tin-plate", 1), item("bob-zinc-plate", 1)}, {item("bob-gunmetal-alloy", 10)}, "bob-zinc-processing", false, true),
  }, {"automation-science-pack", "logistic-science-pack"}, {"automation-science-pack", "logistic-science-pack", "bob-zinc-processing"}, {"automation-science-pack", "logistic-science-pack", "utility-science-pack"},
  {"automation-science-pack", "bob-zinc-processing", "logistic-science-pack", "recipe-prod-research_material_gunmetal-1", "utility-science-pack"}),
  research_material_invar = base_delta("research_material_invar", {
    route("bob-invar-alloy", {item("bob-nickel-plate", 2), item("iron-plate", 3)}, {item("bob-invar-alloy", 5)}, "bob-invar-processing", false, true),
  }, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "bob-invar-processing"}, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack"},
  {"automation-science-pack", "bob-invar-processing", "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_invar-1", "utility-science-pack"}),
  research_material_lead = base_delta("research_material_lead", {
    route("bob-lead-plate", {item("bob-lead-ore", 1)}, {item("bob-lead-plate", 1)}, nil, nil, true),
    route("bob-lead-plate-2", {item("bob-lead-oxide", 2), item("carbon", 1)}, {item("bob-lead-plate", 2)}, "bob-lead-processing", false, true),
  }, {"automation-science-pack", "logistic-science-pack"}, {"automation-science-pack", "logistic-science-pack", "bob-lead-processing"}, {"automation-science-pack", "logistic-science-pack", "utility-science-pack"},
  {"automation-science-pack", "bob-lead-processing", "logistic-science-pack", "recipe-prod-research_material_lead-1", "utility-science-pack"}),
  research_material_nitinol = base_delta("research_material_nitinol", {
    route("bob-nitinol-alloy", {item("bob-nickel-plate", 3), item("bob-titanium-plate", 2)}, {item("bob-nitinol-alloy", 5)}, "bob-nitinol-processing", false, true),
  }, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "bob-nitinol-processing"}, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"},
  {"automation-science-pack", "bob-nitinol-processing", "chemical-science-pack", "logistic-science-pack", "production-science-pack", "recipe-prod-research_material_nitinol-1", "utility-science-pack"}),
  research_material_tin = base_delta("research_material_tin", {
    route("bob-tin-plate", {item("bob-tin-ore", 1)}, {item("bob-tin-plate", 1)}, nil, nil, true),
  }, {"automation-science-pack"}, {"automation-science-pack"}, {"automation-science-pack", "utility-science-pack"},
  {"automation-science-pack", "recipe-prod-research_material_tin-1", "utility-science-pack"}),
}

local BASE_ADDITIONS = {
  definition("research_material_aluminium", "bob-aluminium-plate", "__bobplates__/graphics/icons/plate/aluminium-plate.png", 64, {
    route("bob-aluminium-plate", {item("bob-alumina", 2), item("carbon", 1)}, {item("bob-aluminium-plate", 2)}, "bob-aluminium-processing", false, true),
  }, stages("research_material_aluminium", {"automation-science-pack", "logistic-science-pack"}, {"automation-science-pack", "logistic-science-pack", "bob-aluminium-processing"},
    {"automation-science-pack", "logistic-science-pack", "utility-science-pack"}, {"automation-science-pack", "bob-aluminium-processing", "logistic-science-pack", "recipe-prod-research_material_aluminium-1", "utility-science-pack"})),
  definition("research_material_brass", "bob-brass-alloy", "__bobplates__/graphics/icons/plate/brass-plate.png", 64, {
    route("bob-brass-alloy", {item("copper-plate", 3), item("bob-zinc-plate", 2)}, {item("bob-brass-alloy", 5)}, "bob-brass-processing", false, true),
  }, stages("research_material_brass", {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "bob-brass-processing"},
    {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack"}, {"automation-science-pack", "bob-brass-processing", "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_brass-1", "utility-science-pack"})),
  definition("research_material_cobalt_steel", "bob-cobalt-steel-alloy", "__bobplates__/graphics/icons/plate/cobalt-steel-plate.png", 32, {
    route("bob-cobalt-steel-alloy", {item("iron-plate", 14), item("bob-cobalt-plate", 1)}, {item("bob-cobalt-steel-alloy", 10)}, "bob-cobalt-processing", false, true),
  }, stages("research_material_cobalt_steel", {"automation-science-pack", "logistic-science-pack"}, {"automation-science-pack", "logistic-science-pack", "bob-cobalt-processing"},
    {"automation-science-pack", "logistic-science-pack", "utility-science-pack"}, {"automation-science-pack", "bob-cobalt-processing", "logistic-science-pack", "recipe-prod-research_material_cobalt_steel-1", "utility-science-pack"})),
  definition("research_material_gold", "bob-gold-plate", "__bobplates__/graphics/icons/plate/gold-plate.png", 64, {
    route("bob-gold-plate", {item("bob-gold-ore", 1), fluid("bob-chlorine", 3)}, {item("bob-gold-plate", 1)}, "bob-gold-processing", false, true),
  }, stages("research_material_gold", {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "bob-gold-processing"},
    {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack"}, {"automation-science-pack", "bob-gold-processing", "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_gold-1", "utility-science-pack"})),
  definition("research_material_silver", "bob-silver-plate", "__bobplates__/graphics/icons/plate/silver-plate.png", 32, {
    route("bob-silver-plate", {item("bob-silver-ore", 1)}, {item("bob-silver-plate", 1)}, "bob-lead-processing", false, true),
  }, stages("research_material_silver", {"automation-science-pack", "logistic-science-pack"}, {"automation-science-pack", "logistic-science-pack", "bob-lead-processing"},
    {"automation-science-pack", "logistic-science-pack", "utility-science-pack"}, {"automation-science-pack", "bob-lead-processing", "logistic-science-pack", "recipe-prod-research_material_silver-1", "utility-science-pack"})),
  definition("research_material_titanium", "bob-titanium-plate", "__bobplates__/graphics/icons/plate/titanium-plate.png", 32, {
    route("bob-titanium-plate", {item("bob-calcium-chloride", 2), item("carbon", 1), item("bob-rutile-ore", 2)}, {item("bob-titanium-plate", 2)}, "bob-titanium-processing", false, true),
  }, stages("research_material_titanium", {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "bob-titanium-processing"},
    {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack"}, {"automation-science-pack", "bob-titanium-processing", "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_titanium-1", "utility-science-pack"})),
  definition("research_material_zinc", "bob-zinc-plate", "__bobplates__/graphics/icons/plate/zinc-plate.png", 32, {
    route("bob-zinc-plate", {item("bob-zinc-ore", 1), fluid("sulfuric-acid", 10)}, {item("bob-zinc-plate", 1)}, "bob-zinc-processing", false, true),
  }, stages("research_material_zinc", {"automation-science-pack", "logistic-science-pack"}, {"automation-science-pack", "logistic-science-pack", "bob-zinc-processing"},
    {"automation-science-pack", "logistic-science-pack", "utility-science-pack"}, {"automation-science-pack", "bob-zinc-processing", "logistic-science-pack", "recipe-prod-research_material_zinc-1", "utility-science-pack"})),
}

local SA_GOLD = definition("research_material_gold", "bob-gold-plate", "__bobplates__/graphics/icons/plate/gold-plate.png", 64, {
  route("bob-gold-plate", {item("bob-gold-ore", 1), fluid("bob-chlorine", 3)}, {item("bob-gold-plate", 1)}, "bob-gold-processing", false, true),
}, stages("research_material_gold", {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}, {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "bob-gold-processing"},
  {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack"}, {"automation-science-pack", "bob-gold-processing", "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_gold-1", "space-science-pack"}))

local function product(key, item_name, icon, icon_size, effects, routes, localised_name)
  return {
    key = key, family = key, kind = "productivity",
    science = "science_automation_logistic_chemical_production",
    exact_prerequisites = true,
    prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    effects = effects, routes = routes, item = item_name, icon = icon, icon_size = icon_size,
    overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
    localised_name = localised_name,
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    order = "p[" .. key .. "]",
    tuning = {base_cost=8000, effect_percent=10, enabled=true, growth_factor=2, linear_increment=0, max_level=0, research_time=60},
    setting_order = "b-100-" .. key:gsub("research_", "") .. "-productivity-stream-" .. key .. "-",
  }
end

local BASE_PRODUCTS = {
  product("research_carbon", "carbon", "__bobplates__/graphics/icons/carbon.png", 32,
    {{recipe="bob-carbon-from-wood", scale=1}, {recipe="carbon", scale=1}}, {
      route("bob-carbon-from-wood", {item("wood", 1)}, {item("carbon", 1)}, "bob-chemical-processing-1", false, "default"),
      route("carbon", {fluid("water", 5), item("coal", 1)}, {item("carbon", 2)}, "bob-chemical-processing-1", false, true),
    }, {"technology-name.more-infinite-research.research_carbon", {"item-name.carbon"}}),
  product("research_lithium", "lithium-plate", "__base__/graphics/technology/mining-productivity.png", 256,
    {{recipe="bob-deuterium-fuel-reprocessing", scale=1}, {recipe="lithium-plate", scale=1}}, {
      route("bob-deuterium-fuel-reprocessing", {item("bob-depleted-deuterium-fuel-cell", 10)}, {
        {type="item", name="bob-empty-nuclear-fuel-cell", amount=10, ignored_by_productivity=10, ignored_by_stats=10},
        {type="item", name="lithium-plate", amount=1, independent_probability=0.1},
        {type="item", name="bob-fusion-catalyst", amount=1},
      }, "bob-deuterium-fuel-reprocessing", false, true),
      route("lithium-plate", {item("bob-lithium-chloride", 1)}, {item("lithium-plate", 1)}, "bob-lithium-processing", false, true),
    }, {"technology-name.more-infinite-research.research_lithium", {"technology-name.lithium-processing"}}),
  product("research_tungsten", "tungsten-plate", "__bobplates__/graphics/icons/plate/tungsten-plate.png", 32,
    {{recipe="tungsten-carbide", scale=1}, {recipe="tungsten-plate", scale=1}}, {
      route("tungsten-carbide", {item("carbon", 1), item("bob-powdered-tungsten", 1)}, {item("tungsten-carbide", 2)}, "bob-tungsten-processing", false, true),
      route("tungsten-plate", {item("bob-nickel-plate", 1), item("bob-powdered-tungsten", 4)}, {item("tungsten-plate", 5)}, "bob-tungsten-processing", false, true),
    }, {"technology-name.more-infinite-research.research_tungsten", {"item-name.tungsten-plate"}}),
}

local function base_definitions()
  local output = {}
  for _, key in ipairs(CORE_KEYS) do
    -- Keep assert separate: Lua returns every argument of assert when it is
    -- the final call argument, which would otherwise pass its diagnostic
    -- string into copy() as the cycle-map parameter.
    local core_definition = assert(CORE_BY_KEY[key], "MIR Bob Core definition is missing " .. key)
    local definition = copy(core_definition)
    local delta = BASE_CORE_DELTAS[key]
    definition.routes, definition.early, definition.continuation = copy(delta.routes), copy(delta.stages.early), copy(delta.stages.continuation)
    output[#output + 1] = definition
  end
  for _, addition in ipairs(BASE_ADDITIONS) do output[#output + 1] = copy(addition) end
  return output
end

local function shared_core_definition(key)
  local core_definition = assert(CORE_BY_KEY[key], "MIR Bob Core definition is missing " .. key)
  local definition = copy(core_definition)
  -- Bob Core's renderer body intentionally omits this native recipe field
  -- because it does not consume it.  The Bob Plates direct-route admission
  -- does consume the captured F210 value, so carry it on this separate copy.
  for _, route_definition in ipairs(definition.routes) do
    route_definition.allow_productivity = true
  end
  return definition
end

function M.material_definitions(profile)
  if profile == "base" then return base_definitions() end
  if profile == "space-age" then
    local output = {}
    for _, key in ipairs(CORE_KEYS) do output[#output + 1] = shared_core_definition(key) end
    output[#output + 1] = copy(SA_GOLD)
    return output
  end
  return {}
end

function M.product_definitions(profile)
  if profile ~= "base" then return {} end
  local output = {}
  for index, definition in ipairs(BASE_PRODUCTS) do output[index] = copy(definition) end
  return output
end

return M
