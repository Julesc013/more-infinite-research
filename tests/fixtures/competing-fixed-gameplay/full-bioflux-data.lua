-- Exact independently captured F200 Space Age MIR bioflux row.  The three
-- successor stages share this narrow preflight so fixture-only acceleration
-- cannot alter the false-preference retained-effect contract.
local M = {
  name = "recipe-prod-research_bioflux-1",
  prerequisites = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "agricultural-science-pack",
  },
  ingredients = {
    {"automation-science-pack", 1}, {"logistic-science-pack", 1},
    {"chemical-science-pack", 1}, {"production-science-pack", 1},
    {"agricultural-science-pack", 1},
  },
}

local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, wanted in ipairs(expected) do
    assert(actual[index] == wanted, label .. " changed at " .. tostring(index))
  end
end

function M.assert_row(value, enabled, label)
  assert(type(value) == "table" and value.type == "technology" and value.name == M.name
    and value.level == 1 and value.max_level == "infinite" and value.upgrade == true
    and value.enabled == enabled and value.visible_when_disabled == nil and value.hidden == nil,
    label .. " identity changed")
  names(value.prerequisites, M.prerequisites, label .. " prerequisites")
  assert(type(value.effects) == "table" and #value.effects == 1, label .. " effects count changed")
  local effect = value.effects[1]
  assert(effect.type == "change-recipe-productivity" and effect.recipe == "bioflux" and effect.change == 0.1,
    label .. " effect changed")
  local unit = assert(value.unit, label .. " unit is absent")
  assert(unit.count == nil and unit.count_formula == "8000*2^(L-1)" and unit.time == 60,
    label .. " cost/time changed")
  assert(type(unit.ingredients) == "table" and #unit.ingredients == #M.ingredients,
    label .. " science count changed")
  for index, expected in ipairs(M.ingredients) do
    local item = unit.ingredients[index]
    assert(type(item) == "table" and item[1] == expected[1] and item[2] == expected[2] and item[3] == nil,
      label .. " science changed at " .. tostring(index))
  end
  return value
end

function M.accelerate(value)
  value.unit.count, value.unit.count_formula, value.unit.time = nil, "1", 1
end

return M
