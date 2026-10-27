local FIXTURE = "mir-fixture-mir5-migration-origin-f200-110-source"
assert(mods.base == "2.1.23" and mods["more-infinite-research"] == "5.0.21000" and mods[FIXTURE] == "0.4.0",
  "[mir5-migration-origin-f200-110-successor] unexpected disabled-module settings closure")

local setting = assert(data.raw["bool-setting"] and data.raw["bool-setting"]["ips-enable-research_modules"],
  "[mir5-migration-origin-f200-110-successor] module startup setting is absent")
assert(setting.type == "bool-setting" and setting.name == "ips-enable-research_modules" and setting.default_value == true,
  "[mir5-migration-origin-f200-110-successor] module startup setting prototype differs")
setting.default_value = false
