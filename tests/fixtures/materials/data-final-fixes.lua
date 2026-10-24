-- Fixture-only acceleration.  These checks first prove that the three named
-- K2SO rows retain their default identities, science, prerequisites and
-- effects.  Only their count formula and time change below, so this fixture
-- never qualifies ordinary material tuning.
local rows = {
  {
    name = "recipe-prod-research_material_rare_metals-1",
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
    prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "kr-rare-metal-processing", "kr-enriched-ores"},
    recipes = {"kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"},
  },
  {
    name = "recipe-prod-research_material_silicon-1",
    science = {"automation-science-pack", "logistic-science-pack"},
    prerequisites = {"automation-science-pack", "logistic-science-pack", "kr-silicon-processing"},
    recipes = {"kr-silicon"},
  },
  {
    name = "recipe-prod-research_material_glass-1",
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
    prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "kr-stone-processing"},
    recipes = {"kr-glass"},
  },
}

local function assert_names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, name in ipairs(expected) do
    assert(actual[index] == name, label .. " changed at " .. tostring(index))
  end
end

local function assert_row(expected)
  local technology = assert(data.raw.technology[expected.name], expected.name .. " is absent")
  assert(technology.type == "technology" and technology.name == expected.name,
    expected.name .. " identity changed")
  assert(technology.level == 1 and technology.upgrade == true and technology.max_level == 3,
    expected.name .. " finite progression changed")
  assert(technology.enabled ~= false, expected.name .. " is disabled")
  assert_names(technology.prerequisites, expected.prerequisites, expected.name .. " prerequisites")

  local unit = assert(technology.unit, expected.name .. " unit is absent")
  assert(unit.count == nil and unit.count_formula == "200*2^(L-1)" and unit.time == 30,
    expected.name .. " default cost or time changed")
  assert(type(unit.ingredients) == "table" and #unit.ingredients == #expected.science,
    expected.name .. " science count changed")
  for index, science in ipairs(expected.science) do
    local ingredient = unit.ingredients[index]
    assert(type(ingredient) == "table" and ingredient[1] == science and ingredient[2] == 1,
      expected.name .. " science changed at " .. tostring(index))
  end

  assert(type(technology.effects) == "table" and #technology.effects == #expected.recipes,
    expected.name .. " effects changed")
  for index, recipe in ipairs(expected.recipes) do
    local effect = technology.effects[index]
    assert(type(effect) == "table" and effect.type == "change-recipe-productivity"
      and effect.recipe == recipe and effect.change == 0.02,
      expected.name .. " effect changed at " .. tostring(index))
  end
  return technology
end

-- Validate the whole submitted fixture family before touching any row.  A
-- later bad row must not leave an earlier one accelerated.
local technologies = {}
for index, expected in ipairs(rows) do technologies[index] = assert_row(expected) end

for index = 1, #technologies do
  local unit = technologies[index].unit
  unit.count_formula = "1"
  unit.count = nil
  unit.time = 1
end
