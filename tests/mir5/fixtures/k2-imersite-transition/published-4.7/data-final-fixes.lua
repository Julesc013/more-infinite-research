-- Published 4.7.2 must retain the JSON-renamed tail as a hidden carrier when
-- its configured cap withholds the public continuation. This fixture observes
-- the exact carrier source; it never changes a published prototype.
local EARLY = "recipe-prod-research_material_imersite-1"
local TAIL = "recipe-prod-research_material_imersite-4"
local HOLDER = "mir-k2-imersite-staged-state-1"
local CARRIER = "mir-k2-imersite-continuation-state-4"
local POWDER = "kr-imersite-powder"

assert(mods.base == "2.1.23" and mods["Krastorio2-spaced-out"] ~= nil
  and mods["more-infinite-research"] == "4.7.21002", "unexpected published K2 Imersite closure")

local function effect(technology, label)
  assert(type(technology.effects) == "table" and #technology.effects == 1, label .. " effects changed")
  local value = technology.effects[1]
  assert(value.type == "change-recipe-productivity" and value.recipe == POWDER and value.change == 0.02,
    label .. " powder effect changed")
end

local function unit(technology, formula, science, label)
  local value = assert(technology.unit, label .. " unit is absent")
  assert(value.count == nil and value.count_formula == formula and value.time == 30,
    label .. " unit changed")
  assert(type(value.ingredients) == "table" and #value.ingredients == #science, label .. " science count changed")
  for index, name in ipairs(science) do
    local ingredient = value.ingredients[index]
    assert(type(ingredient) == "table" and ingredient[1] == name and ingredient[2] == 1 and ingredient[3] == nil,
      label .. " science changed at " .. index)
  end
end

local function holder(technology, first, formula, science, label)
  assert(technology.type == "technology" and technology.name == label and technology.level == first
    and technology.hidden == true and technology.upgrade == false and technology.enabled ~= false
    and technology.max_level == "infinite", label .. " carrier identity changed")
  effect(technology, label)
  unit(technology, formula, science, label .. " carrier")
  assert(type(technology.prerequisites) == "table" and #technology.prerequisites == 0,
    label .. " carrier prerequisites changed")
end

local early = assert(data.raw.technology[EARLY], "published Imersite early row is absent")
assert(early.type == "technology" and early.name == EARLY and early.level == 1 and early.upgrade == true
  and early.max_level == 3 and early.enabled ~= false, "published Imersite early identity changed")
effect(early, "published Imersite early")
assert(data.raw.technology[TAIL] == nil, "published bounded Imersite continuation was not withheld")
holder(assert(data.raw.technology[HOLDER], "published staged holder is absent"), 1,
  "200*2^(L-1)", {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
  HOLDER)
holder(assert(data.raw.technology[CARRIER], "published continuation holder is absent"), 4,
  "1600+200*(L-4)", {"production-science-pack", "space-science-pack"}, CARRIER)
