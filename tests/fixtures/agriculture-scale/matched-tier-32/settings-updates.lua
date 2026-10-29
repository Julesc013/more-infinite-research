local tier = assert(data.raw["int-setting"] and data.raw["int-setting"]["mir5-agriculture-scale-tier"],
  "agriculture matched fixture tier is absent")
assert(tier.setting_type == "startup" and tier.default_value == 1,
  "agriculture matched fixture tier definition differs")
tier.default_value = 32
