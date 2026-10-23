-- Fixture-only acceleration for the five retained F200 Bob/Angel material
-- families. These literal expectations come from the independent 4.7.2
-- captured inventory, with only the reviewed MIR5 tail cap (infinite) changed.
-- Validate every semantic field before changing any count formula or time.
local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"
local rows = {
  {
    key = "research_material_aluminium", item = "bob-aluminium-plate",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-aluminium.png",
    early = {name = "recipe-prod-research_material_aluminium-1", order = "p[research_material_aluminium]",
      science = {"automation-science-pack", "logistic-science-pack"},
      prerequisites = {"automation-science-pack", "logistic-science-pack", "angels-aluminium-smelting-1", "angels-aluminium-casting-2"}},
    tail = {name = "recipe-prod-research_material_aluminium-4", order = "p[research_material_aluminium__continuation]",
      science = {"automation-science-pack", "logistic-science-pack", "utility-science-pack"},
      prerequisites = {"angels-aluminium-casting-2", "angels-aluminium-smelting-1", "automation-science-pack", "logistic-science-pack", "recipe-prod-research_material_aluminium-1", "utility-science-pack"}},
    recipes = {"angels-plate-aluminium", "angels-plate-aluminium-2"},
  },
  {
    key = "research_material_copper_tungsten", item = "bob-copper-tungsten-alloy",
    icon = "__bobplates__/graphics/icons/plate/copper-tungsten-plate.png",
    early = {name = "recipe-prod-research_material_copper_tungsten-1", order = "p[research_material_copper_tungsten]",
      science = {"automation-science-pack", "logistic-science-pack"},
      prerequisites = {"automation-science-pack", "logistic-science-pack", "angels-tungsten-smelting-1"}},
    tail = {name = "recipe-prod-research_material_copper_tungsten-4", order = "p[research_material_copper_tungsten__continuation]",
      science = {"automation-science-pack", "logistic-science-pack", "utility-science-pack"},
      prerequisites = {"angels-tungsten-smelting-1", "automation-science-pack", "logistic-science-pack", "recipe-prod-research_material_copper_tungsten-1", "utility-science-pack"}},
    recipes = {"bob-copper-tungsten-alloy"},
  },
  {
    key = "research_material_gold", item = "bob-gold-plate",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-gold.png",
    early = {name = "recipe-prod-research_material_gold-1", order = "p[research_material_gold]",
      science = {"automation-science-pack", "logistic-science-pack"},
      prerequisites = {"automation-science-pack", "logistic-science-pack", "angels-gold-smelting-1", "angels-gold-casting-2"}},
    tail = {name = "recipe-prod-research_material_gold-4", order = "p[research_material_gold__continuation]",
      science = {"automation-science-pack", "logistic-science-pack", "utility-science-pack"},
      prerequisites = {"angels-gold-casting-2", "angels-gold-smelting-1", "automation-science-pack", "logistic-science-pack", "recipe-prod-research_material_gold-1", "utility-science-pack"}},
    recipes = {"angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"},
  },
  {
    key = "research_material_tin", item = "bob-tin-plate",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-tin.png",
    early = {name = "recipe-prod-research_material_tin-1", order = "p[research_material_tin]",
      science = {"automation-science-pack"},
      prerequisites = {"automation-science-pack", "angels-tin-smelting-1", "angels-tin-casting-2"}},
    tail = {name = "recipe-prod-research_material_tin-4", order = "p[research_material_tin__continuation]",
      science = {"automation-science-pack", "utility-science-pack"},
      prerequisites = {"angels-tin-casting-2", "angels-tin-smelting-1", "automation-science-pack", "recipe-prod-research_material_tin-1", "utility-science-pack"}},
    recipes = {"angels-plate-tin", "angels-plate-tin-2"},
  },
  {
    key = "research_material_titanium", item = "bob-titanium-plate",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-titanium.png",
    early = {name = "recipe-prod-research_material_titanium-1", order = "p[research_material_titanium]",
      science = {"automation-science-pack", "logistic-science-pack"},
      prerequisites = {"automation-science-pack", "logistic-science-pack", "angels-titanium-smelting-1", "angels-titanium-casting-2"}},
    tail = {name = "recipe-prod-research_material_titanium-4", order = "p[research_material_titanium__continuation]",
      science = {"automation-science-pack", "logistic-science-pack", "utility-science-pack"},
      prerequisites = {"angels-titanium-casting-2", "angels-titanium-smelting-1", "automation-science-pack", "logistic-science-pack", "recipe-prod-research_material_titanium-1", "utility-science-pack"}},
    recipes = {"angels-plate-titanium", "angels-plate-titanium-2"},
  },
}

local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, name in ipairs(expected) do assert(actual[index] == name, label .. " changed at " .. tostring(index)) end
end

local function localised(actual, item, label)
  assert(type(actual) == "table" and actual[1] == "" and type(actual[2]) == "table"
    and actual[2][1] == "description.productivity-bonus" and actual[3] == ": "
    and type(actual[4]) == "table" and actual[4][1] == "item-name." .. item and actual[5] == nil,
    label .. " localised name changed")
end

local function effects(actual, recipes, label)
  assert(type(actual) == "table" and #actual == #recipes, label .. " effects count changed")
  for index, recipe in ipairs(recipes) do
    local effect = actual[index]
    assert(type(effect) == "table" and effect.type == "change-recipe-productivity"
      and effect.recipe == recipe and effect.change == 0.02, label .. " effect changed at " .. tostring(index))
  end
end

local function row(family, stage, tail)
  local technology = assert(data.raw.technology[stage.name], stage.name .. " is absent")
  local level, maximum, formula = tail and 4 or 1, tail and "infinite" or 3,
    tail and "1600+200*(L-4)" or "200*2^(L-1)"
  assert(technology.type == "technology" and technology.name == stage.name and technology.level == level
    and technology.upgrade == true and technology.max_level == maximum and technology.order == stage.order
    and technology.enabled ~= false and technology.hidden == nil, stage.name .. " identity or progression changed")
  names(technology.prerequisites, stage.prerequisites, stage.name .. " prerequisites")
  localised(technology.localised_name, family.item, stage.name)
  assert(type(technology.localised_description) == "table"
    and technology.localised_description[1] == "technology-description.more-infinite-research.recipe_productivity"
    and technology.localised_description[2] == nil, stage.name .. " localised description changed")
  assert(type(technology.icons) == "table" and #technology.icons == 2
    and technology.icons[1].icon == family.icon and technology.icons[1].icon_size == 32
    and technology.icons[2].icon == OVERLAY and technology.icons[2].icon_size == 128
    and technology.icons[2].scale == 0.5 and type(technology.icons[2].shift) == "table"
    and technology.icons[2].shift[1] == 50 and technology.icons[2].shift[2] == 50
    and technology.icons[2].floating == true, stage.name .. " icons changed")
  local unit = assert(technology.unit, stage.name .. " unit is absent")
  assert(unit.count == nil and unit.count_formula == formula and unit.time == 30,
    stage.name .. " default tuning changed")
  assert(type(unit.ingredients) == "table" and #unit.ingredients == #stage.science,
    stage.name .. " science count changed")
  for index, science in ipairs(stage.science) do
    local ingredient = unit.ingredients[index]
    assert(type(ingredient) == "table" and ingredient[1] == science and ingredient[2] == 1
      and ingredient[3] == nil, stage.name .. " science changed at " .. tostring(index))
  end
  effects(technology.effects, family.recipes, stage.name)
  return technology
end

assert(mods.base == "2.0.77" and mods["more-infinite-research"] == "5.0.20000"
  and mods["space-age"] == nil and mods.bobtech == nil, "unexpected F200 Bob/Angel fixture closure")

local technologies = {}
for _, family in ipairs(rows) do
  technologies[#technologies + 1] = row(family, family.early, false)
  technologies[#technologies + 1] = row(family, family.tail, true)
end

-- The MIR data-final override has already resolved the selected startup
-- policy. Verify every named native route before the disposable technology
-- count/time acceleration below.
local REQUIRED_RECIPE_CAPS = {
  "angels-plate-aluminium", "angels-plate-aluminium-2", "bob-copper-tungsten-alloy",
  "angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2",
  "angels-plate-tin", "angels-plate-tin-2", "angels-plate-titanium", "angels-plate-titanium-2",
}
for _, name in ipairs(REQUIRED_RECIPE_CAPS) do
  local recipe = assert(data.raw.recipe and data.raw.recipe[name], "named recipe is absent: " .. name)
  assert(recipe.maximum_productivity == 4, "named recipe productivity cap changed: " .. name)
end

-- All ten defaults were checked before the first write. The native fixture
-- changes only disposable count/time, leaving output identity/effects intact.
for _, technology in ipairs(technologies) do
  technology.unit.count = nil
  technology.unit.count_formula = "1"
  technology.unit.time = 1
end
