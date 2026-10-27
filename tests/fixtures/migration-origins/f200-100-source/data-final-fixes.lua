if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "1.0.0"
    or mods["mir-fixture-mir5-migration-origin-f200-100-source"] ~= "0.1.0" then
  error("[mir5-migration-origin-f200-100-source] source closure differs")
end

local direct = assert(data.raw.technology["recipe-prod-research_gears-1"],
  "[mir5-migration-origin-f200-100-source] source gear technology is absent")
assert(direct.name == "recipe-prod-research_gears-1" and direct.level == 1
  and direct.upgrade == true and direct.max_level == "infinite" and direct.enabled ~= false,
  "[mir5-migration-origin-f200-100-source] source gear identity differs")

local unit = assert(direct.unit,
  "[mir5-migration-origin-f200-100-source] source gear unit is absent")
local expected = {
  {"automation-science-pack", 1},
  {"chemical-science-pack", 1},
  {"logistic-science-pack", 1},
  {"production-science-pack", 1}
}
assert(unit.count_formula == "8000 * 2^(L-1)" and unit.time == 60
  and type(unit.ingredients) == "table" and #unit.ingredients == #expected,
  "[mir5-migration-origin-f200-100-source] source gear unit differs")
for index, ingredient in ipairs(expected) do
  local actual = unit.ingredients[index]
  assert(type(actual) == "table" and actual[1] == ingredient[1] and actual[2] == ingredient[2],
    "[mir5-migration-origin-f200-100-source] source gear science differs")
end

local gear_effects = 0
for _, effect in ipairs(direct.effects or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == "iron-gear-wheel"
      and effect.change == .10 then
    gear_effects = gear_effects + 1
  end
end
assert(gear_effects == 1,
  "[mir5-migration-origin-f200-100-source] source gear productivity effect differs")

-- Fixture-only acceleration follows every source assertion. It retains the
-- selected technology, source science and source effect unchanged.
unit.count_formula = nil
unit.count = 1
unit.time = 1
