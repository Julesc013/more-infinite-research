local target = require("target")
local technology = assert(data.raw.technology[target.direct], "missing historical transition direct probe")
assert(technology.type == "technology" and technology.name == target.direct,
  "historical transition direct identity differs")
assert(technology.level == 1 and technology.upgrade == true and technology.max_level == "infinite",
  "historical transition direct progression differs")
assert(technology.enabled ~= false, "historical transition direct is disabled")

local unit = assert(technology.unit, "historical transition direct has no research unit")
local formula_targets = {
  f015 = true, f016 = true, f017 = true, f100 = true, f110 = true,
}
if target.id == "f013" or target.id == "f014" then
  assert(unit.count == 8000 and unit.count_formula == nil and unit.time == 60,
    "historical transition direct numeric cost or time differs")
else
  assert(formula_targets[target.id], "historical transition target cost family differs")
  assert(unit.count_formula == "1*(8000*2^(L-1))" and unit.time == 60,
    "historical transition direct formula cost or time differs")
end
assert(type(unit.ingredients) == "table" and #unit.ingredients == #target.direct_science,
  "historical transition direct science count differs")
for index, name in ipairs(target.direct_science) do
  local ingredient = unit.ingredients[index]
  assert(type(ingredient) == "table" and ingredient[1] == name and ingredient[2] == 1,
    "historical transition direct science differs")
end
assert(type(technology.effects) == "table" and #technology.effects == 1
  and technology.effects[1].type == "character-mining-speed"
  and technology.effects[1].modifier == target.direct_effect,
  "historical transition direct effect differs")

-- Fixture-only acceleration follows the exact row check.  It changes neither
-- identity, level boundary, science nor modifier.
unit.count_formula = nil
unit.count = 1
unit.time = 1
