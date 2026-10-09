-- This isolated observation stage requests the existing diagnostic setting.
-- It does not change recipes, technologies, effects, or gameplay state.
local setting = data.raw["bool-setting"]["mir-debug-generation-report"]
assert(setting, "MIR Tin observer requires the existing generation-report setting")
setting.default_value = true
