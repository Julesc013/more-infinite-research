-- This disposable fixture accelerates only the one actual gear lab witness.
-- It preflights the exact target input first; it never changes a catalogue
-- state row, recipe effect, setting, or native owner.
local FIXTURE = "mir-fixture-mir5-full-catalogue-upgrade"
local PLAN = require("__mir-fixture-mir5-full-catalogue-upgrade__/catalogue")
local TARGET = PLAN.target
local SOURCE = mods[FIXTURE] == "0.1.0"
local STAGE = SOURCE and "published-4.7" or "mir5"
local MIR = mods["more-infinite-research"]
local function fail(message) error("[mir5-full-catalogue-upgrade] " .. message) end
assert(mods.base == TARGET.version and MIR == (SOURCE and TARGET.published_mir or TARGET.mir5),
  "full catalogue fixture has an unexpected MIR target closure")
local space = mods["space-age"] ~= nil
if space then
  for _, name in ipairs(TARGET.space_age_closure) do
    assert(mods[name] == TARGET.version, "full catalogue fixture Space Age closure differs")
  end
else
  for _, name in ipairs(TARGET.space_age_closure) do
    if mods[name] ~= nil then fail("full catalogue Base fixture unexpectedly has Space Age companions") end
  end
end
local gear = data.raw.technology and data.raw.technology["recipe-prod-research_gears-1"]
if type(gear) ~= "table" or type(gear.unit) ~= "table" or gear.max_level ~= "infinite"
    or gear.unit.count ~= nil or gear.unit.count_formula ~= "8000*2^(L-1)" or gear.unit.time ~= 60 then
  fail("exact gear workload differs before " .. STAGE .. " acceleration")
end
local expected = space and {"casting-iron-gear-wheel", "iron-gear-wheel"} or {"iron-gear-wheel"}
local science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
if type(gear.unit.ingredients) ~= "table" or #gear.unit.ingredients ~= #science then
  fail("exact gear science cardinality differs before " .. STAGE .. " acceleration")
end
for index, name in ipairs(science) do
  local ingredient = gear.unit.ingredients[index]
  if type(ingredient) ~= "table" or ingredient[1] ~= name or ingredient[2] ~= 1 then
    fail("exact gear science differs before " .. STAGE .. " acceleration")
  end
end
if type(gear.effects) ~= "table" or #gear.effects ~= #expected then fail("exact gear effect cardinality differs") end
for index, recipe in ipairs(expected) do
  local effect = gear.effects[index]
  if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity" or effect.recipe ~= recipe
      or effect.change ~= .1 then fail("exact gear effect differs") end
end
gear.unit.count, gear.unit.count_formula, gear.unit.time = nil, "1", 1
