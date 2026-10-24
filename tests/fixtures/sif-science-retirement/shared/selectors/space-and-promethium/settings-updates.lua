local setting = assert(data.raw["string-setting"] and data.raw["string-setting"]["mir-science-pack-ingredient-policy"],
  "[mir5-sif-space-and-promethium] MIR policy setting is absent")
assert(setting.setting_type == "startup" and type(setting.allowed_values) == "table",
  "[mir5-sif-space-and-promethium] MIR policy setting contract differs")
local found = false
for _, value in ipairs(setting.allowed_values) do if value == "space-and-promethium" then found = true end end
assert(found, "[mir5-sif-space-and-promethium] authored policy is not allowed")
setting.default_value = "space-and-promethium"
