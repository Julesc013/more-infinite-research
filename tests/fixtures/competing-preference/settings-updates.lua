assert(mods.base == "2.0.77" and mods.ExpandedProductivityResearch == "1.3.8",
  "unexpected competing-owner reference closure")
local setting = data.raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"]
assert(setting and setting.default_value == true, "published preference default changed")
setting.default_value = false
