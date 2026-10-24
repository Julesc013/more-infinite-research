-- Fixture-only stage selection. Production settings remain authoritative.
assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77"
  and mods["more-infinite-research"] == "5.0.20000"
  and mods["plates-n-circuit-productivity"] == nil
  and mods.Science_packs_productivity == nil
  and mods["bioflux-productivity"] == nil
  and mods["fish-productivity"] == nil, "unexpected fixed-provider removal fixture closure")
local setting = assert(data.raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"], "MIR preference setting is absent")
assert(type(setting.default_value) == "boolean", "MIR preference default is malformed")
setting.default_value = false
