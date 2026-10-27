local fixture = "mir-fixture-mir5-migration-origin-f200-110-source"
local catalogue = require("__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")

if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "1.1.0"
    or mods[fixture] ~= "0.1.0" then
  error("[mir5-migration-origin-f200-110-source] exact settings closure differs")
end

local function fail(message)
  error("[mir5-migration-origin-f200-110-source] " .. message)
end

-- Settings prototypes exist only during the settings stage.  Validate the
-- exact archived defaults here, before the game data stage consumes the
-- effective startup values.
for name, default_value in pairs(catalogue.settings) do
  local setting = data.raw["bool-setting"] and data.raw["bool-setting"][name]
  if setting == nil or setting.type ~= "bool-setting" or setting.name ~= name
      or setting.setting_type ~= "startup" or setting.default_value ~= default_value then
    fail("published setting default differs: " .. name)
  end
end

local setting_count = 0
for name in pairs(data.raw["bool-setting"] or {}) do
  if name:sub(1, 4) == "ips-" then
    if catalogue.settings[name] == nil then fail("unexpected published setting: " .. name) end
    setting_count = setting_count + 1
  end
end
if setting_count ~= 42 then fail("published setting count differs") end
