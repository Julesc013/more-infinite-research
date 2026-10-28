-- This preflight intentionally repeats the independent F200 Base row facts
-- used by the published source fixture.  It is never derived from save state.
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

local fixture = mods["mir-fixture-mir5-f200-legacy-cap"]
local f200 = mods.base == "2.0.77" and mods["more-infinite-research"] == "5.0.20000"
  and (fixture == "0.2.0" or fixture == "0.8.0")
local f210 = mods.base == "2.1.23" and mods["more-infinite-research"] == "5.0.21000"
  and (fixture == "0.5.0" or fixture == "0.6.0" or fixture == "0.7.0")
assert((f200 or f210) and mods["space-age"] == nil, "unexpected F200/F210 successor fixture closure")
if f210 then
  for _, name in ipairs({"elevated-rails", "quality", "recycler"}) do
    assert(mods[name] == nil, "F210 Base successor carries Space Age companion: " .. name)
  end
end
local technology = assert(data.raw.technology[NAME], "successor gear technology is absent")
assert(technology.type == "technology" and technology.name == NAME and technology.level == 1
  and technology.upgrade == true and technology.max_level == "infinite"
  and technology.visible_when_disabled == nil and technology.hidden == nil,
  "successor gear identity, progression, or fresh presentation changed")
-- The disabled intermediate deliberately selects false. The other stages
-- accept only the native omitted-true default or an explicit true boolean.
local enabled = technology.enabled
if enabled == nil then enabled = true end
assert(type(enabled) == "boolean" and enabled == (fixture ~= "0.6.0"),
  "successor gear enabled state differs from selected fixture stage")
names(technology.prerequisites, SCIENCE, "successor gear prerequisites")
local unit = assert(technology.unit, "successor gear unit is absent")
assert(unit.count == nil and unit.count_formula == "8000*2^(L-1)" and unit.time == 60,
  "successor gear cost or time changed")
assert(type(unit.ingredients) == "table" and #unit.ingredients == #SCIENCE,
  "successor gear science count changed")
for index, science in ipairs(SCIENCE) do
  local ingredient = unit.ingredients[index]
  assert(type(ingredient) == "table" and ingredient[1] == science and ingredient[2] == 1
    and ingredient[3] == nil, "successor gear science changed at " .. tostring(index))
end
assert(type(technology.effects) == "table" and #technology.effects == 1
  and technology.effects[1].type == "change-recipe-productivity"
  and technology.effects[1].recipe == "iron-gear-wheel"
  and technology.effects[1].change == 0.01,
  "successor gear 1% fixture-selected effect changed")
unit.count, unit.count_formula, unit.time = nil, "1", 1
