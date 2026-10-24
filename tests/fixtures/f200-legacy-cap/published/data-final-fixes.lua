-- Independent F200 Base facts from spec/mir5/inventory/modern-f200-470.json.
-- The fixture-selected 1% setting is the only deliberate effect difference;
-- do not accelerate a changed production row.
local NAME = "recipe-prod-research_gears-1"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack",
}

local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, name in ipairs(expected) do
    assert(actual[index] == name, label .. " changed at " .. tostring(index))
  end
end

assert(mods.base == "2.0.77" and mods["more-infinite-research"] == "4.7.20002"
  and mods["space-age"] == nil, "unexpected F200 published fixture closure")
local technology = assert(data.raw.technology[NAME], "published gear technology is absent")
assert(technology.type == "technology" and technology.name == NAME and technology.level == 1
  and technology.upgrade == true and technology.max_level == "infinite"
  and technology.enabled ~= false and technology.visible_when_disabled == true and technology.hidden == nil,
  "published gear identity, progression, or cap presentation changed")
names(technology.prerequisites, SCIENCE, "published gear prerequisites")
local unit = assert(technology.unit, "published gear unit is absent")
assert(unit.count == nil and unit.count_formula == "8000*2^(L-1)" and unit.time == 60,
  "published gear cost or time changed")
assert(type(unit.ingredients) == "table" and #unit.ingredients == #SCIENCE,
  "published gear science count changed")
for index, science in ipairs(SCIENCE) do
  local ingredient = unit.ingredients[index]
  assert(type(ingredient) == "table" and ingredient[1] == science and ingredient[2] == 1
    and ingredient[3] == nil, "published gear science changed at " .. tostring(index))
end
assert(type(technology.effects) == "table" and #technology.effects == 1
  and technology.effects[1].type == "change-recipe-productivity"
  and technology.effects[1].recipe == "iron-gear-wheel"
  and technology.effects[1].change == 0.01,
  "published gear 1% fixture-selected effect changed")

-- This is the complete disposable mutation.  Do not change science, effects,
-- prerequisites, or cap presentation in a native continuity fixture.
unit.count, unit.count_formula, unit.time = nil, "1", 1
