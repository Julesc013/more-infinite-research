-- Shared exact-row preflight and disposable acceleration for every PR transition stage.
-- Exact independent ProductivityResearch 1.3.2 F200 Space Age source row.
-- It deliberately proves the captured empty prerequisite set before changing
-- only count/time for a disposable native lab.
local function effects(actual, expected)
  assert(type(actual) == "table" and #actual == #expected, "PR effects count changed")
  for index, recipe in ipairs(expected) do
    local effect = actual[index]
    assert(effect.type == "change-recipe-productivity" and effect.recipe == recipe and effect.change == 0.1,
      "PR effect changed at " .. tostring(index))
  end
end
assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77" and mods.ProductivityResearch == "1.3.2"
  and (mods["more-infinite-research"] == "4.7.20002" or mods["more-infinite-research"] == "5.0.20000"), "unexpected PR fixture closure")
local value = assert(data.raw.technology["sem-prfe_iron-gear-wheel-productivity-1"], "captured PR target is absent")
assert(value.type == "technology" and value.name == "sem-prfe_iron-gear-wheel-productivity-1" and value.level == nil
  and value.max_level == "infinite" and value.enabled == nil and value.visible_when_disabled == nil
  and value.hidden == true and value.hidden_in_factoriopedia == true and value.upgrade == true
  and value.prerequisites == nil, "captured PR identity/empty prerequisites changed")
assert(type(value.icons) == "table" and #value.icons == 2
  and value.icons[1].icon == "__base__/graphics/icons/iron-gear-wheel.png"
  and value.icons[2].icon == "__core__/graphics/icons/technology/effect-constant/effect-constant-recipe-productivity.png"
  and value.icons[2].icon_size == 64, "captured PR icons changed")
assert(value.localised_name[1] == "technology-name.sem-prfe_productivity", "captured PR locale changed")
effects(value.effects, {"iron-gear-wheel", "casting-iron-gear-wheel"})
local unit = assert(value.unit, "PR unit is absent")
assert(unit.count == nil and unit.count_formula == "1.25^(L-1)*1000" and unit.time == 15, "PR cost/time changed")
assert(type(unit.ingredients) == "table" and #unit.ingredients == 1 and unit.ingredients[1][1] == "automation-science-pack"
  and unit.ingredients[1][2] == 1 and unit.ingredients[1][3] == nil, "PR science changed")
unit.count, unit.count_formula, unit.time = nil, "1", 1

return true
