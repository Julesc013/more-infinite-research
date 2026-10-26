-- Private F210 Bob-core gameplay preflight. The fourteen named MIR rows and
-- five physical alloy routes are independently captured published 4.7.2
-- facts for the exact no-Angel Bob closure. Only research count/time and a
-- fixture-owned clone of the named native machine are accelerated.
local families = {
  {
    key="research_material_tin", recipe="bob-tin-plate",
    early={name="recipe-prod-research_material_tin-1", order="p[research_material_tin]",
      science={"automation-science-pack"}, prerequisites={"automation-science-pack"}},
    tail={name="recipe-prod-research_material_tin-4", order="p[research_material_tin__continuation]",
      science={"automation-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "recipe-prod-research_material_tin-1", "space-science-pack"}},
  },
  {
    key="research_material_lead", recipe="bob-lead-plate",
    early={name="recipe-prod-research_material_lead-1", order="p[research_material_lead]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
      prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}},
    tail={name="recipe-prod-research_material_lead-4", order="p[research_material_lead__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_lead-1", "space-science-pack"}},
  },
  {
    key="research_material_bronze", recipe="bob-bronze-alloy",
    early={name="recipe-prod-research_material_bronze-1", order="p[research_material_bronze]",
      science={"automation-science-pack"}, prerequisites={"automation-science-pack", "bob-alloy-processing"}},
    tail={name="recipe-prod-research_material_bronze-4", order="p[research_material_bronze__continuation]",
      science={"automation-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "bob-alloy-processing", "recipe-prod-research_material_bronze-1", "space-science-pack"}},
  },
  {
    key="research_material_gunmetal", recipe="bob-gunmetal-alloy",
    early={name="recipe-prod-research_material_gunmetal-1", order="p[research_material_gunmetal]",
      science={"automation-science-pack", "logistic-science-pack"}, prerequisites={"automation-science-pack", "logistic-science-pack", "bob-zinc-processing"}},
    tail={name="recipe-prod-research_material_gunmetal-4", order="p[research_material_gunmetal__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "bob-zinc-processing", "logistic-science-pack", "recipe-prod-research_material_gunmetal-1", "space-science-pack"}},
  },
  {
    key="research_material_invar", recipe="bob-invar-alloy",
    early={name="recipe-prod-research_material_invar-1", order="p[research_material_invar]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}, prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "bob-invar-processing"}},
    tail={name="recipe-prod-research_material_invar-4", order="p[research_material_invar__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "bob-invar-processing", "chemical-science-pack", "logistic-science-pack", "recipe-prod-research_material_invar-1", "space-science-pack"}},
  },
  {
    key="research_material_nitinol", recipe="bob-nitinol-alloy",
    early={name="recipe-prod-research_material_nitinol-1", order="p[research_material_nitinol]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}, prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "bob-nitinol-processing"}},
    tail={name="recipe-prod-research_material_nitinol-4", order="p[research_material_nitinol__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack"},
      prerequisites={"automation-science-pack", "bob-nitinol-processing", "chemical-science-pack", "logistic-science-pack", "production-science-pack", "recipe-prod-research_material_nitinol-1", "space-science-pack"}},
  },
  {
    key="research_material_copper_tungsten", recipe="bob-copper-tungsten-alloy",
    early={name="recipe-prod-research_material_copper_tungsten-1", order="p[research_material_copper_tungsten]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack", "metallurgic-science-pack"}, prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack", "metallurgic-science-pack", "bob-tungsten-processing"}},
    tail={name="recipe-prod-research_material_copper_tungsten-4", order="p[research_material_copper_tungsten__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack", "metallurgic-science-pack"},
      prerequisites={"automation-science-pack", "bob-tungsten-processing", "chemical-science-pack", "logistic-science-pack", "metallurgic-science-pack", "production-science-pack", "recipe-prod-research_material_copper_tungsten-1", "space-science-pack"}},
  },
}

-- These five rows are a deliberately finite physical-output witness. Their
-- inputs/results and owners are in bob-core-f210-captured-facts.json; their
-- categories and native times are checked against the exact bobplates_3.0.2
-- archive (SHA256 0C9A...B691862D), without using candidate output. Space
-- Age changes Copper Tungsten from its archive's mixing/item branch into the
-- captured metallurgy/molten-copper branch, so it uses a separate foundry
-- clone whose inherent productivity is preserved below.
local physical_routes = {
  {
    recipe="bob-bronze-alloy", owner="bob-alloy-processing", energy=16, machine="mixing",
    inherent_productivity=0,
    categories={"bob-mixing-furnace"},
    ingredients={{type="item", name="copper-plate", amount=3}, {type="item", name="bob-tin-plate", amount=2}},
    results={{type="item", name="bob-bronze-alloy", amount=5}},
  },
  {
    recipe="bob-gunmetal-alloy", owner="bob-zinc-processing", energy=32, machine="mixing",
    inherent_productivity=0,
    categories={"bob-mixing-furnace"},
    ingredients={{type="item", name="copper-plate", amount=8}, {type="item", name="bob-tin-plate", amount=1}, {type="item", name="bob-zinc-plate", amount=1}},
    results={{type="item", name="bob-gunmetal-alloy", amount=10}},
  },
  {
    recipe="bob-invar-alloy", owner="bob-invar-processing", energy=16, machine="mixing",
    inherent_productivity=0,
    categories={"bob-mixing-furnace"},
    ingredients={{type="item", name="bob-nickel-plate", amount=2}, {type="item", name="iron-plate", amount=3}},
    results={{type="item", name="bob-invar-alloy", amount=5}},
  },
  {
    recipe="bob-nitinol-alloy", owner="bob-nitinol-processing", energy=16, machine="mixing",
    inherent_productivity=0,
    categories={"bob-mixing-furnace"},
    ingredients={{type="item", name="bob-nickel-plate", amount=3}, {type="item", name="bob-titanium-plate", amount=2}},
    results={{type="item", name="bob-nitinol-alloy", amount=5}},
  },
  {
    recipe="bob-copper-tungsten-alloy", owner="bob-tungsten-processing", energy=16, machine="metallurgy",
    inherent_productivity=0.5,
    categories={"metallurgy"},
    ingredients={{type="item", name="bob-powdered-tungsten", amount=3}, {type="fluid", name="molten-copper", amount=20}},
    results={{type="item", name="bob-copper-tungsten-alloy", amount=5}},
  },
}
local MIXING_SOURCE_MACHINE = "bob-electric-mixing-furnace"
local MIXING_FIXTURE_MACHINE = "mir5-bob-core-alloy-witness-furnace"
local METALLURGY_SOURCE_MACHINE = "foundry"
local METALLURGY_FIXTURE_MACHINE = "mir5-bob-core-alloy-witness-foundry"
local FIXTURE_SPEED = 200

local function assert_names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, name in ipairs(expected) do
    assert(actual[index] == name, label .. " changed at " .. tostring(index))
  end
end

local function entry_name(value) return type(value) == "table" and (value.name or value[1]) or nil end
local function entry_amount(value) return type(value) == "table" and (value.amount or value[2]) or nil end

local function assert_entries(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, wanted in ipairs(expected) do
    local value = actual[index]
    assert(type(value) == "table" and (value.type or "item") == wanted.type
      and entry_name(value) == wanted.name and entry_amount(value) == wanted.amount
      and value.temperature == wanted.temperature
      and value.minimum_temperature == wanted.minimum_temperature
      and value.maximum_temperature == wanted.maximum_temperature
      and value.amount_min == nil and value.amount_max == nil
      and (value.probability == nil or value.probability == 1)
      and (value.independent_probability == nil or value.independent_probability == 1)
      and (value.extra_count_fraction == nil or value.extra_count_fraction == 0)
      and (value.ignored_by_productivity == nil or value.ignored_by_productivity == 0)
      and (value.ignored_by_stats == nil or value.ignored_by_stats == 0),
      label .. " changed at " .. tostring(index))
  end
end

local function assert_owner(raw, route)
  local owner = assert(raw.technology[route.owner], route.owner .. " is absent")
  local matches = 0
  for _, effect in ipairs(owner.effects or {}) do
    if effect.recipe == route.recipe then
      assert(effect.type == "unlock-recipe", route.owner .. " ownership effect changed")
      matches = matches + 1
    end
  end
  assert(matches == 1, route.owner .. " no longer owns " .. route.recipe)
end

local function assert_physical_route(raw, route)
  local value = assert(raw.recipe[route.recipe], route.recipe .. " is absent")
  assert(value.type == "recipe" and value.name == route.recipe and value.enabled == false
    and value.allow_productivity == true and value.maximum_productivity == nil
    and value.energy_required == route.energy, route.recipe .. " route flags changed")
  assert_names(value.categories, route.categories, route.recipe .. " categories")
  assert_entries(value.ingredients, route.ingredients, route.recipe .. " ingredients")
  assert_entries(value.results, route.results, route.recipe .. " results")
  assert_owner(raw, route)
end

local function fixture_clone(source, name)
  local fixture = table.deepcopy(source)
  fixture.name = name
  fixture.minable = nil
  fixture.next_upgrade = nil
  fixture.crafting_speed = FIXTURE_SPEED
  fixture.module_slots = 0
  return fixture
end

local function assert_mixing_machine(raw)
  local source = assert(raw["assembling-machine"][MIXING_SOURCE_MACHINE], "captured alloy machine is absent")
  assert(source.type == "assembling-machine" and source.name == MIXING_SOURCE_MACHINE
    and source.crafting_speed == 2 and source.module_slots == 2,
    "captured alloy machine identity changed")
  assert_names(source.crafting_categories, {"smelting", "bob-mixing-furnace"},
    "captured alloy machine categories")
  return fixture_clone(source, MIXING_FIXTURE_MACHINE)
end

local function assert_metallurgy_machine(raw)
  local source = assert(raw["assembling-machine"][METALLURGY_SOURCE_MACHINE], "captured metallurgy machine is absent")
  assert(source.type == "assembling-machine" and source.name == METALLURGY_SOURCE_MACHINE
    and source.crafting_speed == 4 and source.module_slots == 4
    and source.fluid_boxes_off_when_no_fluid_recipe == true,
    "captured metallurgy machine identity changed")
  assert_names(source.crafting_categories, {"metallurgy"}, "captured metallurgy machine categories")
  local receiver = source.effect_receiver
  assert(type(receiver) == "table" and type(receiver.base_effect) == "table"
    and receiver.base_effect.productivity == 0.5,
    "captured metallurgy machine productivity changed")
  local fluid_boxes = source.fluid_boxes
  assert(type(fluid_boxes) == "table" and #fluid_boxes == 4,
    "captured metallurgy machine fluid boxes changed")
  for index, expected in ipairs({
    {production_type="input", volume=1000}, {production_type="input", volume=1000},
    {production_type="output", volume=100}, {production_type="output", volume=100},
  }) do
    local fluid_box = fluid_boxes[index]
    assert(type(fluid_box) == "table" and fluid_box.production_type == expected.production_type
      and fluid_box.volume == expected.volume,
      "captured metallurgy machine fluid box changed at " .. tostring(index))
  end
  return fixture_clone(source, METALLURGY_FIXTURE_MACHINE)
end

local function assert_stage(family, stage, finite)
  local value = assert(data.raw.technology[stage.name], stage.name .. " is absent")
  assert(value.type == "technology" and value.name == stage.name and value.order == stage.order,
    stage.name .. " identity changed")
  assert(value.level == (finite and 1 or 4) and value.upgrade == true
      and value.max_level == (finite and 3 or "infinite"), stage.name .. " progression changed")
  assert(value.enabled ~= false, stage.name .. " is disabled")
  if finite then
    assert(value.show_levels_info == nil and value.visible_when_disabled == nil,
      stage.name .. " finite presentation changed")
  else
    assert(value.show_levels_info == false and value.visible_when_disabled == true,
      stage.name .. " continuation presentation changed")
  end
  assert_names(value.prerequisites, stage.prerequisites, stage.name .. " prerequisites")
  local unit = assert(value.unit, stage.name .. " unit is absent")
  local formula = finite and "200*2^(L-1)" or "1600+200*(L-4)"
  assert(unit.count == nil and unit.count_formula == formula and unit.time == 30,
    stage.name .. " ordinary cost or time changed")
  assert(type(unit.ingredients) == "table" and #unit.ingredients == #stage.science,
    stage.name .. " science count changed")
  for index, name in ipairs(stage.science) do
    local ingredient = unit.ingredients[index]
    assert(type(ingredient) == "table" and (ingredient.name or ingredient[1]) == name
      and (ingredient.amount or ingredient[2]) == 1, stage.name .. " science changed at " .. tostring(index))
  end
  assert(type(value.effects) == "table" and #value.effects == 1, stage.name .. " effects changed")
  local effect = value.effects[1]
  assert(type(effect) == "table" and effect.type == "change-recipe-productivity"
      and effect.recipe == family.recipe and effect.change == 0.02, stage.name .. " effect changed")
  return value
end

local raw = data.raw
assert(type(raw) == "table" and type(raw.technology) == "table" and type(raw.recipe) == "table"
  and type(raw["assembling-machine"]) == "table", "named Bob-core raw prototypes are unavailable")
for _, route in ipairs(physical_routes) do assert_physical_route(raw, route) end
local rows = {}
for _, family in ipairs(families) do
  rows[#rows + 1] = assert_stage(family, family.early, true)
  rows[#rows + 1] = assert_stage(family, family.tail, false)
end
local mixing_fixture_machine = assert_mixing_machine(raw)
local metallurgy_fixture_machine = assert_metallurgy_machine(raw)
-- Every preflight above has passed. The clone only shortens this disposable
-- witness; it leaves named upstream recipes and ordinary player tuning intact.
data:extend({mixing_fixture_machine, metallurgy_fixture_machine})
for _, value in ipairs(rows) do
  value.unit.count_formula, value.unit.count, value.unit.time = nil, 1, 1
end
