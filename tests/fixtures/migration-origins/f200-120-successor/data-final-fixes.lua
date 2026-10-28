local catalogue = require("__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")

local selected = nil
for name, target in pairs(catalogue.targets) do
  if mods.base == target.base and mods["more-infinite-research"] == target.mir
      and mods[catalogue.fixture] == target.fixture
      and mods["mir-fixture-mir5-active-mods-observer"] == "0.1.0" then
    selected = name
  end
end
assert(selected ~= nil, "[mir5-migration-origin-f200-120-successor] exact target closure differs")
if selected == "f210" then
  assert(mods["space-age"] == nil and mods["elevated-rails"] == nil and mods.quality == nil and mods.recycler == nil,
    "[mir5-migration-origin-f200-120-successor] direct F210 Base successor excludes Space Age")
end

local function signature(effects)
  local rows = {}
  for _, effect in ipairs(effects or {}) do
    if effect.type ~= "gun-speed" or type(effect.ammo_category) ~= "string" or type(effect.modifier) ~= "number" then
      return nil
    end
    rows[#rows + 1] = effect.type .. "|" .. effect.ammo_category .. "|" .. string.format("%.17g", effect.modifier)
  end
  table.sort(rows)
  return table.concat(rows, ",")
end

local function expected_signature(effects)
  return signature(effects)
end

local function require_direct(name, effects)
  local value = assert(data.raw.technology[name], "[mir5-migration-origin-f200-120-successor] candidate technology is absent: " .. name)
  assert(value.type == "technology" and value.name == name and value.level == 1 and value.upgrade == true
      and value.max_level == "infinite" and value.enabled ~= false,
    "[mir5-migration-origin-f200-120-successor] candidate direct identity differs: " .. name)
  assert(signature(value.effects) == expected_signature(effects),
    "[mir5-migration-origin-f200-120-successor] candidate split gun effects differ: " .. name)
  return value
end

local rocket = require_direct(catalogue.source_combined, catalogue.split_effects.rocket)
require_direct(catalogue.cannon, catalogue.split_effects.cannon)
for name, expected in pairs(catalogue.current_runtime) do
  local value = assert(data.raw.technology[name], "[mir5-migration-origin-f200-120-successor] current finite owner is absent: " .. name)
  assert(value.type == "technology" and value.name == name and value.upgrade == true
      and signature(value.effects) == expected_signature(expected.effects),
    "[mir5-migration-origin-f200-120-successor] current finite vector differs: " .. name)
end

local gear = assert(data.raw.technology[catalogue.direct],
  "[mir5-migration-origin-f200-120-successor] candidate gear technology is absent")
local matches = 0
for _, effect in ipairs(gear.effects or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == catalogue.gear_recipe and effect.change == catalogue.expected_gear_delta then
    matches = matches + 1
  end
end
assert(matches == 1 and type(gear.unit) == "table" and type(gear.unit.ingredients) == "table" and #gear.unit.ingredients > 0,
  "[mir5-migration-origin-f200-120-successor] candidate gear effect or science differs")
gear.unit.count, gear.unit.count_formula, gear.unit.time = 1, nil, 1
