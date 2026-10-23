-- Independent Factorio 2.0.77 Base worker-tail facts. This fixture does not
-- derive the row from a candidate; after the full native preflight it changes
-- only the disposable count/formula/time fields.
local NAME = "worker-robots-speed-6"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "space-science-pack",
}

local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, name in ipairs(expected) do
    assert(actual[index] == name, label .. " changed at " .. tostring(index))
  end
end

assert(mods.base == "2.0.77" and mods["more-infinite-research"] == "4.7.20002"
  and mods["space-age"] == nil, "unexpected F200 published fixture closure")
local technology = assert(data.raw.technology[NAME], "published native worker tail is absent")
assert(technology.type == "technology" and technology.name == NAME and technology.level == nil
  and technology.upgrade == true and technology.max_level == "infinite"
  and technology.enabled == nil and technology.visible_when_disabled == true and technology.hidden == nil,
  "published native worker identity or progression changed")
names(technology.prerequisites, {"worker-robots-speed-5", "space-science-pack"},
  "published native worker prerequisites")
local unit = assert(technology.unit, "published native worker unit is absent")
assert(unit.count == nil and unit.count_formula == "2^(L-6)*1000" and unit.time == 60,
  "published native worker cost or time changed")
assert(type(unit.ingredients) == "table" and #unit.ingredients == #SCIENCE,
  "published native worker science count changed")
for index, science in ipairs(SCIENCE) do
  local ingredient = unit.ingredients[index]
  assert(type(ingredient) == "table" and ingredient[1] == science and ingredient[2] == 1
    and ingredient[3] == nil, "published native worker science changed at " .. tostring(index))
end
assert(type(technology.effects) == "table" and #technology.effects == 1
  and technology.effects[1].type == "worker-robot-speed"
  and technology.effects[1].modifier == 0.65,
  "published native worker effect changed")

unit.count, unit.count_formula, unit.time = nil, "1", 1
