local fixture = "mir-fixture-mir5-legacy-boolean-cap"
local gear_name = "recipe-prod-research_gears-1"
local science = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack",
}

assert(mods.base == "2.0.77" and mods["more-infinite-research"] == "4.0.20000"
  and mods[fixture] == "0.1.0" and mods["space-age"] == nil,
  "[mir5-legacy-boolean-cap-source] source closure differs")

local gear = assert(data.raw.technology[gear_name],
  "[mir5-legacy-boolean-cap-source] published gear technology is absent")
assert(gear.type == "technology" and gear.name == gear_name and gear.upgrade == true
  and gear.max_level == "infinite" and gear.enabled ~= false,
  "[mir5-legacy-boolean-cap-source] published gear identity differs")
local unit = assert(gear.unit, "[mir5-legacy-boolean-cap-source] published gear unit is absent")
assert(unit.count == nil and unit.count_formula == "8000*2^(L-1)" and unit.time == 60,
  "[mir5-legacy-boolean-cap-source] published gear workload differs")
assert(type(unit.ingredients) == "table" and #unit.ingredients == #science,
  "[mir5-legacy-boolean-cap-source] published gear science count differs")
for index, name in ipairs(science) do
  local ingredient = unit.ingredients[index]
  assert(type(ingredient) == "table" and ingredient[1] == name and ingredient[2] == 1
    and ingredient[3] == nil,
    "[mir5-legacy-boolean-cap-source] published gear science differs at " .. tostring(index))
end
assert(type(gear.effects) == "table" and #gear.effects == 1
  and gear.effects[1].type == "change-recipe-productivity"
  and gear.effects[1].recipe == "iron-gear-wheel" and gear.effects[1].change == 0.10,
  "[mir5-legacy-boolean-cap-source] published gear productivity effect differs")

unit.count, unit.count_formula, unit.time = 1, nil, 1
