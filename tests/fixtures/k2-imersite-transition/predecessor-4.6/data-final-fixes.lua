-- Exact published 4.6 K2SO source row before its 4.7 JSON carrier rename.
-- This disposable seed changes only research count and time after preflight.
local LEGACY = "recipe-prod-research_material_imersite-1"
local POWDER = "kr-imersite-powder"

assert(mods.base == "2.1.23" and mods["Krastorio2-spaced-out"] ~= nil
  and mods["more-infinite-research"] == "4.6.21000", "unexpected K2 Imersite predecessor closure")

local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, value in ipairs(expected) do assert(actual[index] == value, label .. " changed at " .. index) end
end

local function ingredients(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, name in ipairs(expected) do
    local value = actual[index]
    assert(type(value) == "table" and value[1] == name and value[2] == 1 and value[3] == nil,
      label .. " changed at " .. index)
  end
end

local technology = assert(data.raw.technology[LEGACY], "published predecessor Imersite row is absent")
assert(technology.type == "technology" and technology.name == LEGACY and technology.level == 1
  and technology.upgrade == true and technology.max_level == "infinite" and technology.enabled ~= false,
  "published predecessor Imersite identity changed")
assert(type(technology.effects) == "table" and #technology.effects == 1,
  "published predecessor Imersite effects changed")
local effect = technology.effects[1]
assert(effect.type == "change-recipe-productivity" and effect.recipe == POWDER and effect.change == 0.02,
  "published predecessor Imersite powder effect changed")
local unit = assert(technology.unit, "published predecessor Imersite unit is absent")
assert(unit.count == nil and unit.count_formula == "200*2^(L-1)" and unit.time == 30,
  "published predecessor Imersite cost or time changed")
ingredients(unit.ingredients, {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
}, "published predecessor Imersite science")
names(technology.prerequisites, {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "kr-quarry-minerals-extraction",
}, "published predecessor Imersite prerequisites")

technology.unit.count, technology.unit.count_formula, technology.unit.time = nil, "1", 1
