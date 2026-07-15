local prototypes = {}

if not (data.raw["recipe-category"] and data.raw["recipe-category"].recycling) then
  table.insert(prototypes, {type = "recipe-category", name = "recycling"})
end

local function clone_entity(prototype_type, source_name, name, result)
  local source = data.raw[prototype_type] and data.raw[prototype_type][source_name]
  if not source then return end
  local entity = table.deepcopy(source)
  entity.name = name
  entity.minable = {mining_time = 0.1, result = result}
  entity.next_upgrade = nil
  table.insert(prototypes, entity)
end

local function add_item(name, icon, subgroup, place_result)
  table.insert(prototypes, {
    type = "item",
    name = name,
    icon = icon,
    icon_size = 64,
    subgroup = subgroup,
    order = "mir-semantic-" .. name,
    place_result = place_result,
    stack_size = 50
  })
end

local function add_recipe(name, result, ingredient, options)
  options = options or {}
  table.insert(prototypes, {
    type = "recipe",
    name = name,
    categories = {options.category or "crafting"},
    enabled = true,
    ingredients = {{type = "item", name = ingredient or "iron-plate", amount = 1}},
    results = {{type = "item", name = result, amount = 1}},
    allow_productivity = options.allow_productivity ~= false
  })
end

if data.raw["loader-1x1"] and data.raw["loader-1x1"]["loader-1x1"] then
  clone_entity("loader-1x1", "loader-1x1", "opaque-transfer-node", "opaque-transfer-node")
else
  clone_entity("loader", "loader", "opaque-transfer-node", "opaque-transfer-node")
end
add_item("opaque-transfer-node", "__base__/graphics/icons/transport-belt.png", "belt", "opaque-transfer-node")
add_recipe("assemble-alpha", "opaque-transfer-node", "transport-belt")

clone_entity("mining-drill", "electric-mining-drill", "opaque-extractor", "opaque-extractor")
add_item("opaque-extractor", "__base__/graphics/icons/electric-mining-drill.png", "extraction-machine", "opaque-extractor")
add_recipe("assemble-beta", "opaque-extractor", "electric-mining-drill")

clone_entity("furnace", "stone-furnace", "opaque-smelter", "opaque-smelter")
add_item("opaque-smelter", "__base__/graphics/icons/stone-furnace.png", "smelting-machine", "opaque-smelter")
add_recipe("assemble-gamma", "opaque-smelter", "stone-furnace")

clone_entity("accumulator", "accumulator", "opaque-charge-bank", "opaque-charge-bank")
add_item("opaque-charge-bank", "__base__/graphics/icons/accumulator.png", "energy", "opaque-charge-bank")
add_recipe("assemble-delta", "opaque-charge-bank", "battery")

clone_entity("inserter", "inserter", "opaque-hand", "opaque-hand")
add_item("opaque-hand", "__base__/graphics/icons/inserter.png", "inserter", "opaque-hand")
add_recipe("assemble-epsilon", "opaque-hand", "iron-gear-wheel")

clone_entity("lab", "lab", "opaque-research-device", "opaque-research-device")
add_item("opaque-research-device", "__base__/graphics/icons/lab.png", "production-machine", "opaque-research-device")
add_recipe("assemble-zeta", "opaque-research-device", "electronic-circuit")

clone_entity("assembling-machine", "assembling-machine-2", "opaque-fabrication-device", "opaque-fabrication-device")
add_item("opaque-fabrication-device", "__base__/graphics/icons/assembling-machine-2.png", "production-machine", "opaque-fabrication-device")
add_recipe("assemble-theta", "opaque-fabrication-device", "electronic-circuit")

table.insert(prototypes, {
  type = "item",
  name = "opaque-pack-component",
  icon = "__base__/graphics/icons/iron-gear-wheel.png",
  icon_size = 64,
  subgroup = "intermediate-product",
  order = "mir-semantic-pack-component",
  stack_size = 100
})
add_recipe("pack-only-recipe", "opaque-pack-component", "iron-gear-wheel")

clone_entity("assembling-machine", "assembling-machine-1", "opaque-hard-false-machine", "opaque-hard-false-machine")
add_item("opaque-hard-false-machine", "__base__/graphics/icons/assembling-machine-1.png", "production-machine", "opaque-hard-false-machine")
add_recipe("pack-hard-productivity-false", "opaque-hard-false-machine", "iron-plate", {allow_productivity = false})

clone_entity("assembling-machine", "assembling-machine-1", "opaque-recycling-machine", "opaque-recycling-machine")
add_item("opaque-recycling-machine", "__base__/graphics/icons/assembling-machine-1.png", "production-machine", "opaque-recycling-machine")
add_recipe("pack-hard-recycling", "opaque-recycling-machine", "iron-plate", {category = "recycling"})

local source_module = data.raw.module and data.raw.module["speed-module"]
if source_module then
  local module = table.deepcopy(source_module)
  module.name = "opaque-enhancer"
  module.tier = 4
  module.order = "mir-semantic-opaque-enhancer"
  table.insert(prototypes, module)
  add_recipe("assemble-eta", "opaque-enhancer", "speed-module")
end

table.insert(prototypes, {
  type = "technology",
  name = "mir-fixture-finite-family-owner",
  icon = "__base__/graphics/technology/automation.png",
  icon_size = 256,
  max_level = 1,
  effects = {{type = "change-recipe-productivity", recipe = "assemble-alpha", change = 0.1}},
  prerequisites = {"automation"},
  unit = {count = 10, time = 5, ingredients = {{"automation-science-pack", 1}}}
})

table.insert(prototypes, {
  type = "mod-data",
  name = "more-infinite-research-compatibility-pack",
  data = {packs = {
    ["semantic-family-fixture"] = {
      schema = 2,
      id = "semantic-family-fixture",
      applicability = {mods = {{id = "mir-fixture-semantic-family-attach", version = "= 0.1.0"}}},
      aliases = {},
      exact = {includes = {
        {recipe = "pack-hard-productivity-false", family = "assembling-machine-manufacturing"},
        {recipe = "pack-hard-recycling", family = "assembling-machine-manufacturing"}
      }, excludes = {}},
      family_hints = {},
      science_roles = {},
      owner_claims = {},
      risk_overrides = {},
      family_authorizations = {{
        family = "assembling-machine-manufacturing",
        stream = "research_auto_assembling_machine",
        action = "generate",
        evidence = {"semantic-family-attach"},
        claim_boundary = "fixture-only"
      }},
      candidate_seeds = {{
        recipe = "pack-only-recipe",
        item = "opaque-pack-component",
        family = "logistics-manufacturing",
        stream = "research_belts",
        change = 0.01,
        evidence = {"semantic-family-attach"}
      }},
      targets = {factorio_lines = {"2.1"}},
      evidence = {fixtures = {"semantic-family-attach"}, real_mod = {}},
      claim = {level = "fixture-only", public = false}
    }
  }}
})

data:extend(prototypes)
