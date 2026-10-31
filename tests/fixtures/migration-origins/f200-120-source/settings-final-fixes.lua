local FIXTURE = "mir-fixture-mir5-migration-origin-f200-120-source"
local catalogue = require("__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")

if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "1.2.0"
    or mods[FIXTURE] ~= "0.1.0" then
  error("[mir5-migration-origin-f200-120-source] exact settings closure differs")
end

local function fail(message)
  error("[mir5-migration-origin-f200-120-source] " .. message)
end

for name, expected in pairs(catalogue.settings) do
  local setting = data.raw[expected.kind] and data.raw[expected.kind][name]
  if setting == nil or setting.type ~= expected.kind or setting.name ~= name
      or setting.setting_type ~= "startup" or setting.default_value ~= expected.default_value then
    fail("published setting default differs: " .. name)
  end
end

local counts = {}
for kind, values in pairs(data.raw) do
  for name in pairs(values or {}) do
    if type(name) == "string" and name:sub(1, 4) == "ips-" then
      local expected = catalogue.settings[name]
      if expected == nil or expected.kind ~= kind then fail("unexpected published setting: " .. name) end
      counts[kind] = (counts[kind] or 0) + 1
    end
  end
end
for kind, expected in pairs(catalogue.setting_counts) do
  if counts[kind] ~= expected then fail("published setting count differs: " .. kind) end
end
