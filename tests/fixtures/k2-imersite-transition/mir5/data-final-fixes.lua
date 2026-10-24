-- Exact MIR5 K2SO Imersite definitions before the disposable successor lab.
local EARLY = "recipe-prod-research_material_imersite-1"
local TAIL = "recipe-prod-research_material_imersite-4"
local HOLDER = "mir-k2-imersite-staged-state-1"
local CARRIER = "mir-k2-imersite-continuation-state-4"
local POWDER = "kr-imersite-powder"

assert(mods.base == "2.1.23" and mods["Krastorio2-spaced-out"] ~= nil
  and mods["more-infinite-research"] == "5.0.21000", "unexpected MIR5 K2 Imersite closure")

local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, value in ipairs(expected) do assert(actual[index] == value, label .. " changed at " .. index) end
end

local function effect(technology, label)
  assert(type(technology.effects) == "table" and #technology.effects == 1, label .. " effects changed")
  local value = technology.effects[1]
  assert(value.type == "change-recipe-productivity" and value.recipe == POWDER and value.change == 0.02,
    label .. " powder effect changed")
end

local function unit(technology, formula, science, label)
  local value = assert(technology.unit, label .. " unit is absent")
  assert(value.count == nil and value.count_formula == formula and value.time == 30,
    label .. " cost or time changed")
  assert(type(value.ingredients) == "table" and #value.ingredients == #science, label .. " science count changed")
  for index, item in ipairs(science) do
    local actual = value.ingredients[index]
    assert(type(actual) == "table" and actual[1] == item and actual[2] == 1 and actual[3] == nil,
      label .. " science changed at " .. index)
  end
end

local early = assert(data.raw.technology[EARLY], "MIR5 Imersite early row is absent")
local tail = assert(data.raw.technology[TAIL], "MIR5 re-added Imersite continuation is absent")
assert(early.type == "technology" and early.name == EARLY and early.level == 1 and early.upgrade == true
  and early.max_level == 3 and early.enabled ~= false, "MIR5 Imersite early identity changed")
assert(tail.type == "technology" and tail.name == TAIL and tail.level == 4 and tail.upgrade == true
  and tail.max_level == "infinite" and tail.enabled ~= false and tail.visible_when_disabled == true
  and tail.show_levels_info == false, "MIR5 Imersite continuation identity changed")
names(early.prerequisites, {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "kr-quarry-minerals-extraction",
}, "MIR5 Imersite early prerequisites")
names(tail.prerequisites, {
  "kr-quarry-minerals-extraction", "production-science-pack", EARLY, "space-science-pack",
}, "MIR5 Imersite continuation prerequisites")
effect(early, "MIR5 Imersite early")
effect(tail, "MIR5 Imersite continuation")
unit(early, "200*2^(L-1)", {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
}, "MIR5 Imersite early")
unit(tail, "1600+200*(L-4)", {"production-science-pack", "space-science-pack"},
  "MIR5 Imersite continuation")

for _, row in ipairs({
  {HOLDER, 1, "200*2^(L-1)", {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}},
  {CARRIER, 4, "1600+200*(L-4)", {"production-science-pack", "space-science-pack"}},
}) do
  local technology = assert(data.raw.technology[row[1]], "MIR5 Imersite carrier is absent: " .. row[1])
  assert(technology.type == "technology" and technology.name == row[1] and technology.level == row[2]
    and technology.hidden == true and technology.upgrade == false and technology.enabled == true
    and technology.max_level == "infinite" and type(technology.prerequisites) == "table" and #technology.prerequisites == 0,
    "MIR5 Imersite carrier identity changed: " .. row[1])
  effect(technology, "MIR5 Imersite carrier " .. row[1])
  unit(technology, row[3], row[4], "MIR5 Imersite carrier " .. row[1])
end

-- The source state has already earned its first tail level. Only the
-- destination continuation gets a one-count/one-second fixture mutation.
tail.unit.count, tail.unit.count_formula, tail.unit.time = nil, "1", 1
