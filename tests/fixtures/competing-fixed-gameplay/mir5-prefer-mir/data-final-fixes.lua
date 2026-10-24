-- Capture all foreign rows before validating the true-preference MIR breeding row.
require("foreign-data")
local bioflux = require("full-bioflux-data")
local NAME = "recipe-prod-research_breeding-1"
local INGREDIENTS = {
  {"automation-science-pack", 1}, {"logistic-science-pack", 1},
  {"chemical-science-pack", 1}, {"production-science-pack", 1},
  {"agricultural-science-pack", 1}, {"cryogenic-science-pack", 1},
}
local PREREQUISITES = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "agricultural-science-pack", "cryogenic-science-pack",
}
local EFFECTS = {"biter-egg", "fish-breeding", "pentapod-egg"}
local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, wanted in ipairs(expected) do assert(actual[index] == wanted, label .. " changed at " .. tostring(index)) end
end
assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77" and mods["more-infinite-research"] == "5.0.20000"
  and mods["plates-n-circuit-productivity"] == "0.0.2" and mods.Science_packs_productivity == "0.0.1"
  and mods["bioflux-productivity"] == "0.1.0" and mods["fish-productivity"] == "1.0.0", "unexpected preferred breeding closure")
local value = assert(data.raw.technology[NAME], "captured preferred MIR breeding row is absent")
assert(value.type == "technology" and value.name == NAME and value.level == 1 and value.max_level == "infinite"
  and value.upgrade == true and value.enabled == nil and value.visible_when_disabled == nil and value.hidden == nil,
  "captured preferred MIR breeding identity changed")
names(value.prerequisites, PREREQUISITES, "captured preferred MIR breeding prerequisites")
assert(type(value.effects) == "table" and #value.effects == #EFFECTS, "captured preferred MIR breeding effects count changed")
for index, recipe in ipairs(EFFECTS) do
  local effect = value.effects[index]
  assert(effect.type == "change-recipe-productivity" and effect.recipe == recipe and effect.change == 0.1,
    "captured preferred MIR breeding effect changed at " .. tostring(index))
end
local unit = assert(value.unit, "captured preferred MIR breeding unit is absent")
assert(unit.count == nil and unit.count_formula == "8000*2^(L-1)" and unit.time == 60,
  "captured preferred MIR breeding cost/time changed")
assert(type(unit.ingredients) == "table" and #unit.ingredients == #INGREDIENTS, "captured preferred MIR breeding science count changed")
for index, expected in ipairs(INGREDIENTS) do
  local item = unit.ingredients[index]
  assert(type(item) == "table" and item[1] == expected[1] and item[2] == expected[2] and item[3] == nil,
    "captured preferred MIR breeding science changed at " .. tostring(index))
end
unit.count, unit.count_formula, unit.time = nil, "1", 1
local full = bioflux.assert_row(assert(data.raw.technology[bioflux.name],
  "captured preferred MIR bioflux row is absent"), nil, "captured preferred MIR bioflux")
bioflux.accelerate(full)
