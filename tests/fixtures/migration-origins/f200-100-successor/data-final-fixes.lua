local catalogue = require("__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue")
local fixture = catalogue.fixture

local function target()
  for name, expected in pairs(catalogue.targets) do
    if mods.base == expected.base and mods["more-infinite-research"] == expected.mir
        and mods[fixture] == expected.fixture
        and mods["mir-fixture-mir5-active-mods-observer"] == "0.1.0" then
      return name
    end
  end
  error("[mir5-migration-origin-f200-100-successor] exact target closure differs")
end

local selected = target()
if selected == "f210" then
  assert(mods["space-age"] == nil and mods["elevated-rails"] == nil and mods.quality == nil and mods.recycler == nil,
    "[mir5-migration-origin-f200-100-successor] F210 Base successor has a Space Age companion")
end

local technology = assert(data.raw.technology[catalogue.direct],
  "[mir5-migration-origin-f200-100-successor] candidate gear technology is absent")
assert(technology.type == "technology" and technology.name == catalogue.direct and technology.level == 1
    and technology.upgrade == true and technology.max_level == "infinite" and technology.enabled ~= false,
  "[mir5-migration-origin-f200-100-successor] candidate gear identity differs")

local gear_effects = 0
for _, effect in ipairs(technology.effects or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == catalogue.gear_recipe
      and effect.change == catalogue.expected_gear_delta then
    gear_effects = gear_effects + 1
  end
end
assert(gear_effects == 1,
  "[mir5-migration-origin-f200-100-successor] candidate gear productivity effect differs")
assert(type(technology.unit) == "table" and type(technology.unit.ingredients) == "table"
    and #technology.unit.ingredients > 0,
  "[mir5-migration-origin-f200-100-successor] candidate gear science is absent")

-- This only keeps the real candidate lab bounded. The historical source
-- science/cost remains in its protected save and is never copied into this
-- current-package observer.
technology.unit.count, technology.unit.count_formula, technology.unit.time = 1, nil, 1
