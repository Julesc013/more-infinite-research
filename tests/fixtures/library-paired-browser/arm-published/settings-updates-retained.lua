local selector = data.raw["string-setting"] and data.raw["string-setting"]["mir5-library-paired-browser-arm"]
local retained = data.raw["bool-setting"] and data.raw["bool-setting"]["mir5-library-paired-browser-retained-refresh"]
assert(selector and selector.setting_type == "startup" and selector.default_value == "mir5", "published retained selector differs")
assert(retained and retained.setting_type == "startup" and retained.default_value == false, "retained refresh selector differs")
selector.default_value = "published"
retained.default_value = true
