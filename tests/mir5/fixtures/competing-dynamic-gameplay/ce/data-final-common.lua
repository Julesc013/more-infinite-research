-- Shared exact-row preflight and disposable acceleration for every CE transition stage.
-- Exact independent CE 0.2.20 F200 Space Age source row; mutate only
-- disposable count/time after this complete named row preflight.
local function names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, label .. " count changed")
  for index, wanted in ipairs(expected) do assert(actual[index] == wanted, label .. " changed at " .. tostring(index)) end
end
local function effects(actual, expected)
  assert(type(actual) == "table" and #actual == #expected, "CE effects count changed")
  for index, recipe in ipairs(expected) do
    local effect = actual[index]
    assert(effect.type == "change-recipe-productivity" and effect.recipe == recipe and effect.change == 0.1,
      "CE effect changed at " .. tostring(index))
  end
end
assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77" and mods["crafting-efficiency-2"] == "0.2.20"
  and (mods["more-infinite-research"] == "4.7.20002" or mods["more-infinite-research"] == "5.0.20000"), "unexpected CE fixture closure")
local value = assert(data.raw.technology["ce-iron-gear-wheel-19"], "captured CE target is absent")
assert(value.type == "technology" and value.name == "ce-iron-gear-wheel-19" and value.level == nil
  and value.max_level == "infinite" and value.enabled == nil and value.visible_when_disabled == nil
  and value.hidden == nil and value.upgrade == true and value.icon == "__base__/graphics/icons/iron-gear-wheel.png"
  and value.localised_name[1] == "technology-name.technology-productivity"
  and value.localised_name[2] == "Iron gear wheel productivity", "captured CE identity/presentation changed")
names(value.prerequisites, {"ce-iron-gear-wheel-14", "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"}, "CE prerequisites")
effects(value.effects, {"iron-gear-wheel", "casting-iron-gear-wheel"})
local unit = assert(value.unit, "CE unit is absent")
assert(unit.count == nil and unit.count_formula == "1200 * 1.5 * l" and unit.time == 45, "CE cost/time changed")
assert(type(unit.ingredients) == "table" and #unit.ingredients == 6, "CE science count changed")
for _, name in ipairs({"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"}) do
  local found = false
  for _, ingredient in ipairs(unit.ingredients) do if ingredient[1] == name and ingredient[2] == 1 and ingredient[3] == nil then found = true end end
  assert(found, "CE science changed: " .. name)
end
unit.count, unit.count_formula, unit.time = nil, "1", 1

return true
