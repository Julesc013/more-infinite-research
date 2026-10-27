local catalogue = require("__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")

local selected = nil
for name, expected in pairs(catalogue.targets) do
  if mods.base == expected.base and mods["more-infinite-research"] == expected.mir
      and mods[catalogue.fixture] == expected.fixture
      and mods["mir-fixture-mir5-active-mods-observer"] == "0.1.0" then
    selected = name
  end
end
assert(selected ~= nil, "[mir5-migration-origin-f200-110-successor] exact target closure differs")
if selected == "f210" or selected == "f210_source_defaults" then
  assert(mods["space-age"] == nil and mods["elevated-rails"] == nil and mods.quality == nil and mods.recycler == nil,
    "[mir5-migration-origin-f200-110-successor] F210 direct source successor excludes the separate planet-repair route")
end

if selected == "f200_source_defaults" or selected == "f210_source_defaults" then
  for name, expected in pairs(catalogue.settings) do
    local value = settings and settings.startup and settings.startup[name]
    local actual = value and value.value
    assert(actual == expected,
      "[mir5-migration-origin-f200-110-successor] effective startup setting differs: " .. name
        .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

local direct = assert(data.raw.technology[catalogue.direct],
  "[mir5-migration-origin-f200-110-successor] candidate direct technology is absent")
assert(direct.type == "technology" and direct.name == catalogue.direct and direct.level == 1
    and direct.upgrade == true and direct.max_level == "infinite" and direct.enabled ~= false,
  "[mir5-migration-origin-f200-110-successor] candidate direct identity differs")
local gear = 0
for _, effect in ipairs(direct.effects or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == catalogue.gear_recipe
      and effect.change == catalogue.expected_gear_delta then gear = gear + 1 end
end
assert(gear == 1 and type(direct.unit) == "table" and type(direct.unit.ingredients) == "table"
    and #direct.unit.ingredients > 0,
  "[mir5-migration-origin-f200-110-successor] candidate direct science or gear effect differs")

-- The protected source has its own historical cost/time. Accelerate only the
-- one new candidate lab after validating the candidate's native definition.
direct.unit.count, direct.unit.count_formula, direct.unit.time = 1, nil, 1
