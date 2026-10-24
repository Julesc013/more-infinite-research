-- Fixture-only preference selection. The production setting remains authoritative;
-- this only makes each staged native save input explicit.
assert(mods.base == "2.0.77" and mods.ExpandedProductivityResearch == "1.3.8", "unexpected EPR fixture closure")
local setting = assert(data.raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"], "MIR preference setting is absent")
assert(setting.default_value == true or setting.default_value == false, "MIR preference default is malformed")
setting.default_value = false
