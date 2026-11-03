local mode = assert(data.raw["bool-setting"]["mir5-large-factory-inventory-only"])
assert(mode.type == "bool-setting" and mode.setting_type == "startup" and mode.default_value == false)
mode.default_value = true
