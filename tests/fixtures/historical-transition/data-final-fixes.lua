local target = require("target")
local technology = assert(data.raw.technology[target.direct], "missing historical transition direct probe")
assert(technology.type == "technology" and technology.name == target.direct,
  "historical transition direct identity differs")
assert(technology.level == 1 and technology.upgrade == true and technology.max_level == "infinite",
  "historical transition direct progression differs")
assert(technology.enabled ~= false, "historical transition direct is disabled")

local unit = assert(technology.unit, "historical transition direct has no research unit")
local function display(value)
  if value == nil then return "nil" end
  return tostring(value)
end
local science, effects = {}, {}
for index, ingredient in ipairs(unit.ingredients or {}) do
  if type(ingredient) == "table" then
    science[index] = display(ingredient[1]) .. ":" .. display(ingredient[2])
  else
    science[index] = "invalid:" .. display(ingredient)
  end
end
for index, effect in ipairs(technology.effects or {}) do
  if type(effect) == "table" then
    effects[index] = display(effect.type) .. ":modifier=" .. display(effect.modifier)
      .. ":recipe=" .. display(effect.recipe) .. ":change=" .. display(effect.change)
  else
    effects[index] = "invalid:" .. display(effect)
  end
end
log("[MIR5_HISTORICAL_TRANSITION_PREFLIGHT] target=" .. display(target.id)
  .. " count=" .. display(unit.count) .. " count_formula=" .. display(unit.count_formula)
  .. " time=" .. display(unit.time) .. " science=" .. table.concat(science, ",")
  .. " effects=" .. table.concat(effects, ","))
local formula_targets = {
  f015 = true, f016 = true, f017 = true, f018 = true, f100 = true, f110 = true,
}
if target.id == "f013" or target.id == "f014" then
  assert(unit.count == 8000 and unit.count_formula == nil and unit.time == 60,
    "historical transition direct numeric cost or time differs")
else
  assert(formula_targets[target.id], "historical transition target cost family differs")
  local formulas
  if target.id == "f018" then
    -- Published MIR 1.8.0 emitted this source-authored expression with its
    -- spaces; MIR5's reduced constructor has its separately retained ABI.
    formulas = {published = "8000 * 2^(L-1)", mir5 = "1*(8000*2^(L-1))"}
  else
    formulas = {published = "8000*2^(L-1)", mir5 = "1*(8000*2^(L-1))"}
  end
  local expected_formula = formulas[target.stage]
  assert(expected_formula ~= nil and unit.count_formula == expected_formula and unit.time == 60,
    "historical transition direct formula cost or time differs")
end
assert(type(unit.ingredients) == "table" and #unit.ingredients == #target.direct_science,
  "historical transition direct science count differs")
local expected_science, actual_science = {}, {}
for _, name in ipairs(target.direct_science) do
  expected_science[name] = (expected_science[name] or 0) + 1
end
for _, ingredient in ipairs(unit.ingredients) do
  assert(type(ingredient) == "table" and type(ingredient[1]) == "string" and ingredient[2] == 1,
    "historical transition direct science differs")
  actual_science[ingredient[1]] = (actual_science[ingredient[1]] or 0) + 1
end
for name, count in pairs(expected_science) do
  assert(actual_science[name] == count, "historical transition direct science differs")
end
for name, count in pairs(actual_science) do
  assert(expected_science[name] == count, "historical transition direct science differs")
end
assert(type(technology.effects) == "table" and #technology.effects == 1
  and technology.effects[1].type == "character-mining-speed"
  and technology.effects[1].modifier == target.direct_effect,
  "historical transition direct effect differs")

-- Fixture-only acceleration follows the exact row check.  It changes neither
-- identity, level boundary, science nor modifier.
unit.count_formula = nil
unit.count = 1
unit.time = 1
