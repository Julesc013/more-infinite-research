-- F013/F014 do not have the later startup-setting surface.  This fixture-only
-- acceleration validates the selected direct output before changing its cost
-- and time, and intentionally never changes the observed numeric continuation.
local target = require("target")
if target.science_policy == "all" then
  assert(target.id == "f017" or target.id == "f100" or target.id == "f110",
    "historical all science target differs")

  local red = assert(data.raw.recipe["automation-science-pack"], "historical initial red recipe is absent")
  assert(red.enabled ~= false and red.result == "automation-science-pack" and red.results == nil,
    "historical initial red recipe differs")
  assert(data.raw.technology["automation-science-pack"] == nil,
    "historical initial red owner differs")

  local function assert_unit(name, science)
    local technology = assert(data.raw.technology[name], "historical all science technology is absent")
    local unit = assert(technology.unit, "historical all science unit is absent")
    assert(#unit.ingredients == #science, "historical all science ingredient count differs")
    for index, pack in ipairs(science) do
      local ingredient = unit.ingredients[index]
      assert(ingredient[1] == pack and ingredient[2] == 1,
        "historical all science ingredient differs")
    end
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      assert(prerequisite ~= "automation-science-pack", "historical initial red prerequisite differs")
    end
  end

  assert_unit(target.direct, target.direct_science)
  assert_unit(target.continuation, target.continuation_science)
  return
end

if target.id ~= "f013" and target.id ~= "f014" then return end

local technology = assert(data.raw.technology[target.direct], "missing historical direct probe")
assert(technology.type == "technology" and technology.name == target.direct,
  "historical direct probe identity differs")
assert(technology.level == 1 and technology.upgrade == true and technology.max_level == "infinite",
  "historical direct probe progression differs")
assert(technology.enabled ~= false, "historical direct probe is disabled")

local unit = assert(technology.unit, "historical direct probe has no research unit")
assert(unit.count == 8000 and unit.count_formula == nil and unit.time == 60,
  "historical direct probe cost or time differs")
assert(type(unit.ingredients) == "table" and #unit.ingredients == 1
  and unit.ingredients[1][1] == "alien-science-pack" and unit.ingredients[1][2] == 1,
  "historical direct probe science differs")
assert(type(technology.effects) == "table" and #technology.effects == 1
  and technology.effects[1].type == "character-mining-speed"
  and technology.effects[1].modifier == 0.05,
  "historical direct probe effect differs")

unit.count = 1
unit.time = 1
