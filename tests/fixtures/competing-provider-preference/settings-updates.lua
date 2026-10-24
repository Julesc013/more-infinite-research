assert(mods.base == "2.0.77" and mods["more-infinite-research"] == "4.7.20002",
  "provider preference observer requires the exact published F200 arm")
local option = assert(data.raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"],
  "published competing-provider preference is absent")
assert(option.setting_type == "startup" and option.default_value == true,
  "published competing-provider preference shape changed")
option.default_value = false
