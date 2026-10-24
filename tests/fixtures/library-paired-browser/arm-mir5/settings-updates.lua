local arm = assert(data.raw["string-setting"] and data.raw["string-setting"]["mir5-library-paired-browser-arm"],
  "paired Library fixture selector is absent")
assert(arm.setting_type == "startup" and arm.default_value == "mir5",
  "MIR 5 paired Library selector requires the shared default")
arm.default_value = "mir5"
