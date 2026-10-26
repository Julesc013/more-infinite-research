-- Source-stage preflight only.  It does not repair or write the historical
-- carrier rows: the native source archive remains the object under test.
local EARLY = "mir-k2-imersite-staged-state-1"
local TAIL = "mir-k2-imersite-continuation-state-4"
local POWDER = "kr-imersite-powder"

assert(mods.base == "2.1.23" and mods.Krastorio2 == "2.1.4"
  and mods["space-exploration"] == "0.7.63" and mods["Krastorio2-spaced-out"] == nil
  and mods["more-infinite-research"] == "4.7.21003"
  and mods["mir-fixture-mir5-k2se-imersite-carrier-retention"] == "0.1.0",
  "unexpected published K2SE Imersite carrier closure")

local function carrier(name, first, formula)
  local value = assert(data.raw.technology[name], "carrier is absent: " .. name)
  assert(value.type == "technology" and value.name == name and value.level == first
    and value.hidden == true and value.upgrade == false and value.enabled ~= false
    and value.max_level == "infinite", "carrier identity changed: " .. name)
  assert(type(value.prerequisites) == "table" and #value.prerequisites == 0,
    "carrier prerequisites changed: " .. name)
  assert(type(value.effects) == "table" and #value.effects == 1
    and value.effects[1].type == "change-recipe-productivity"
    and value.effects[1].recipe == POWDER and value.effects[1].change == 0.02,
    "carrier effect changed: " .. name)
  local unit = assert(value.unit, "carrier unit is absent: " .. name)
  assert(unit.count == nil and unit.count_formula == formula and unit.time == 30,
    "carrier unit changed: " .. name)
  assert(type(unit.ingredients) == "table" and #unit.ingredients > 0,
    "carrier science is absent: " .. name)
end

carrier(EARLY, 1, "200*2^(L-1)")
carrier(TAIL, 4, "1600+200*(L-4)")
