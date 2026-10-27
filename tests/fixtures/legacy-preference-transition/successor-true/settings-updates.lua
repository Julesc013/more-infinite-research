local FIXTURE = "mir-fixture-mir5-legacy-preference-transition"
assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77"
  and mods["more-infinite-research"] == "5.0.20000" and mods[FIXTURE] == "0.2.1"
  and mods["plates-n-circuit-productivity"] == "0.0.2"
  and mods.Science_packs_productivity == "0.0.1"
  and mods["bioflux-productivity"] == "0.1.0" and mods["fish-productivity"] == "1.0.0",
  "unexpected legacy-preference fixture closure")
local setting = assert(data.raw["bool-setting"] and data.raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"],
  "MIR competing preference setting is absent")
setting.default_value = true
