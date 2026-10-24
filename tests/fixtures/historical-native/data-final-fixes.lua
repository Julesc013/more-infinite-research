-- F013/F014 do not have the later startup-setting surface.  This fixture-only
-- acceleration validates the selected direct output before changing its cost
-- and time, and intentionally never changes the observed numeric continuation.
local target = require("target")
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
