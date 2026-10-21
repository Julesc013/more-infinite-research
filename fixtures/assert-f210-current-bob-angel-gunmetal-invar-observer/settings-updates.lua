-- This observer uses the existing phase-aware generation reporting switch.
-- It does not modify recipe, technology, effect, or force state.
local setting = data.raw["bool-setting"]["mir-debug-generation-report"]
assert(setting, "Gunmetal/Invar observer requires the existing generation-report setting")
setting.default_value = true
