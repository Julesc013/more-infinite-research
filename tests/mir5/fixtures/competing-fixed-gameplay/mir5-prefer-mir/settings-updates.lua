-- Fixture-only stage selection. Production settings remain authoritative.
assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77"
  and mods["more-infinite-research"] == "5.0.20000"
  and mods["plates-n-circuit-productivity"] == "0.0.2"
  and mods.Science_packs_productivity == "0.0.1"
  and mods["bioflux-productivity"] == "0.1.0"
  and mods["fish-productivity"] == "1.0.0", "unexpected fixed-provider fixture closure")
local setting = assert(data.raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"], "MIR preference setting is absent")
assert(type(setting.default_value) == "boolean", "MIR preference default is malformed")
setting.default_value = true