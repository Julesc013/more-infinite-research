local FIXTURE = "mir-fixture-mir5-migration-origin-f200-110-source"
assert(mods.base == "2.1.23" and mods["more-infinite-research"] == "5.0.21000" and mods[FIXTURE] == "0.4.0",
  "[mir5-migration-origin-f200-110-successor] unexpected source-default settings closure")

local values = {
  ["ips-require-space-gate"] = {current = false, published = true},
  ["ips-enable-research_inventory_capacity"] = {current = true, published = false},
}
for name, expected in pairs(values) do
  local setting = assert(data.raw["bool-setting"] and data.raw["bool-setting"][name],
    "[mir5-migration-origin-f200-110-successor] startup setting is absent: " .. name)
  assert(setting.type == "bool-setting" and setting.name == name and setting.default_value == expected.current,
    "[mir5-migration-origin-f200-110-successor] startup setting prototype differs: " .. name)
end
for name, expected in pairs(values) do
  local setting = data.raw["bool-setting"][name]
  setting.default_value = expected.published
end
