-- Direct 4.6 saves retain detached work while the predecessor fixture reduced
-- its source cost to one. Keep that test cost on the public identity and its
-- JSON carrier before Factorio interprets the saved progress.
-- This companion has no control stage and is never selected for the published
-- 4.7 carrier path.
local EARLY = "recipe-prod-research_material_imersite-1"
local HOLDER = "mir-k2-imersite-staged-state-1"
local POWDER = "kr-imersite-powder"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
}

assert(mods.base == "2.1.23" and mods["Krastorio2-spaced-out"] ~= nil
  and mods["more-infinite-research"] == "5.0.21000"
  and mods["mir-fixture-mir5-k2-imersite-transition"] == "0.3.0",
  "unexpected direct K2 Imersite cost companion closure")

local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, value in ipairs(expected) do
    assert(actual[index] == value, label .. " changed at " .. index)
  end
end

local function effect(technology, label)
  assert(type(technology.effects) == "table" and #technology.effects == 1, label .. " effects changed")
  local value = technology.effects[1]
  assert(value.type == "change-recipe-productivity" and value.recipe == POWDER and value.change == 0.02,
    label .. " effect changed")
end

local function unit(technology, label)
  local value = assert(technology.unit, label .. " unit is absent")
  assert(value.count == nil and value.count_formula == "200*2^(L-1)" and value.time == 30,
    label .. " unit changed")
  assert(type(value.ingredients) == "table" and #value.ingredients == #SCIENCE,
    label .. " science count changed")
  for index, name in ipairs(SCIENCE) do
    local ingredient = value.ingredients[index]
    assert(type(ingredient) == "table" and ingredient[1] == name and ingredient[2] == 1 and ingredient[3] == nil,
      label .. " science changed at " .. index)
  end
end

local early = assert(data.raw.technology[EARLY], "direct cost public early row is absent")
local holder = assert(data.raw.technology[HOLDER], "direct cost JSON early holder is absent")

-- Complete both preflights before either test-only write. The public row and
-- the JSON holder both have the predecessor's original cost shape, and either
-- can be selected by the migration path.
assert(early.type == "technology" and early.name == EARLY and early.level == 1 and early.upgrade == true
  and early.max_level == 3 and early.enabled ~= false and early.hidden ~= true,
  "direct cost public early identity changed")
names(early.prerequisites, {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "kr-quarry-minerals-extraction",
}, "direct cost public early prerequisites")
effect(early, "direct cost public early")
unit(early, "direct cost public early")

assert(holder.type == "technology" and holder.name == HOLDER and holder.level == 1 and holder.upgrade == false
  and holder.hidden == true and holder.enabled == true and holder.max_level == "infinite"
  and type(holder.prerequisites) == "table" and #holder.prerequisites == 0,
  "direct cost JSON early holder identity changed")
effect(holder, "direct cost JSON early holder")
unit(holder, "direct cost JSON early holder")

for _, technology in ipairs({early, holder}) do
  technology.unit.count, technology.unit.count_formula, technology.unit.time = nil, "1", 1
end
