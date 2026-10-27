local fixture = "mir-fixture-mir5-migration-origin-f200-100-source"
local catalogue = require("__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue")

local target = false
for name, expected in pairs(catalogue.targets) do
  if mods.base == expected.base and mods["more-infinite-research"] == expected.mir
      and mods[fixture] == expected.fixture
      and mods["mir-fixture-mir5-active-mods-observer"] == "0.1.0" then
    target = name
  end
end
assert(target ~= false, "[mir5-migration-origin-f200-100-successor] settings target closure differs")

local setting = assert(data.raw["bool-setting"] and data.raw["bool-setting"][catalogue.breeding_setting],
  "[mir5-migration-origin-f200-100-successor] current breeding setting is absent")
assert(setting.setting_type == "startup" and setting.default_value == true,
  "[mir5-migration-origin-f200-100-successor] current breeding setting default differs")

-- The protected MIR1 save records an effective false value that was created
-- by its source fixture's settings stage.  This wrapper supplies that exact
-- false startup input for the bounded successor load; it does not claim a
-- user-authored override survives a later default change.
setting.default_value = false
