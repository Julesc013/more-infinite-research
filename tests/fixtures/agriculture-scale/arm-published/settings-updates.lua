local tier = assert(data.raw["int-setting"] and data.raw["int-setting"]["mir5-agriculture-scale-tier"],
  "agriculture paired fixture core setting is absent")
assert(tier.setting_type == "startup" and tier.default_value == 1,
  "agriculture paired arm requires the fixed single-tower tier")
