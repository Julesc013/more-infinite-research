local agriculture = assert(data.raw.technology["recipe-prod-research_agricultural_growth_speed-1"],
  "agriculture scale requires MIR agricultural growth research")
local tier_setting = assert(settings.startup["mir5-agriculture-scale-tier"],
  "agriculture scale tier setting is absent")
local tier = tier_setting.value
assert(tier == 1 or tier == 32 or tier == 128, "agriculture scale tier is not an authored fixed tier")

local expected_science = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
  "cryogenic-science-pack", "military-science-pack", "utility-science-pack",
  "space-science-pack", "metallurgic-science-pack", "promethium-science-pack"
}

assert(agriculture.enabled ~= false and agriculture.level == 1 and agriculture.max_level == "infinite"
  and agriculture.upgrade == true, "agriculture scale requires an enabled infinite agriculture definition")
assert(agriculture.unit and agriculture.unit.count_formula == "40000*1.5^(L-1)"
  and agriculture.unit.count == nil and agriculture.unit.time == 90,
  "agriculture scale default agricultural research tuning differs")
assert(#(agriculture.effects or {}) == 1 and agriculture.effects[1].type == "nothing"
  and agriculture.effects[1].effect_description and agriculture.effects[1].effect_description[2] == "1",
  "agriculture scale agricultural effect contract differs")
assert(#(agriculture.unit.ingredients or {}) == #expected_science,
  "agriculture scale all-official science vector cardinality differs")
for index, name in ipairs(expected_science) do
  local ingredient = agriculture.unit.ingredients[index]
  local actual_name, actual_amount = ingredient and (ingredient.name or ingredient[1]),
    ingredient and (ingredient.amount or ingredient[2])
  assert(actual_name == name and actual_amount == 1,
    "agriculture scale all-official science vector differs at " .. index)
end
local gate_count = 0
for _, prerequisite in ipairs(agriculture.prerequisites or {}) do
  if prerequisite == "promethium-science-pack" then gate_count = gate_count + 1 end
end
assert(gate_count == 1, "agriculture scale requires the all-official promethium gate")

local yumako = assert(data.raw.capsule and data.raw.capsule.yumako,
  "agriculture scale requires the native yumako item")
assert(yumako.spoil_ticks == 216000 and yumako.spoil_result == "spoilage",
  "agriculture scale native yumako spoilage contract differs")

-- Only the already-validated test-world prototype is accelerated. The selected
-- research effect, native plant timer, native tower event, and spoilable item
-- remain untouched.
agriculture.unit.count_formula, agriculture.unit.count, agriculture.unit.time = nil, 1, 1
