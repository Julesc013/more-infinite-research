-- Fixture-only preference selection for the staged native save chain.
assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77"
  and mods["crafting-efficiency-2"] == "0.2.20", "unexpected dynamic fixture closure")
local setting = assert(data.raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"], "MIR preference setting is absent")
assert(type(setting.default_value) == "boolean", "MIR preference default is malformed")
setting.default_value = true
