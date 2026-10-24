-- This disposable fixture accelerates only the one actual gear lab witness.
-- It preflights the exact published F200 input first; it never changes a
-- catalogue state row, recipe effect, setting, or native owner.
local STAGE, MIR = 'mir5', '5.0.20000'
local function fail(message) error("[mir5-full-catalogue-upgrade] " .. message) end
assert(mods.base == "2.0.77" and mods["more-infinite-research"] == MIR,
  "full catalogue fixture has an unexpected MIR F200 closure")
local space = mods["space-age"] ~= nil
if space then
  assert(mods["space-age"] == "2.0.77" and mods["elevated-rails"] == "2.0.77" and mods.quality == "2.0.77",
    "full catalogue fixture Space Age closure differs")
elseif mods["elevated-rails"] ~= nil or mods.quality ~= nil then
  fail("full catalogue Base fixture unexpectedly has Space Age companions")
end
local gear = data.raw.technology and data.raw.technology["recipe-prod-research_gears-1"]
if type(gear) ~= "table" or type(gear.unit) ~= "table" or gear.max_level ~= "infinite"
    or gear.unit.count ~= nil or gear.unit.count_formula ~= "8000*2^(L-1)" or gear.unit.time ~= 60 then
  fail("exact gear workload differs before " .. STAGE .. " acceleration")
end
local expected = space and {"casting-iron-gear-wheel", "iron-gear-wheel"} or {"iron-gear-wheel"}
if type(gear.effects) ~= "table" or #gear.effects ~= #expected then fail("exact gear effect cardinality differs") end
for index, recipe in ipairs(expected) do
  local effect = gear.effects[index]
  if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity" or effect.recipe ~= recipe
      or effect.change ~= .1 then fail("exact gear effect differs") end
end
gear.unit.count, gear.unit.count_formula, gear.unit.time = nil, "1", 1
