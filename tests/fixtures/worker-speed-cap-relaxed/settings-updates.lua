local name = "mir-max-level-worker-robots-speed"
local setting = data.raw["int-setting"] and data.raw["int-setting"][name]
if not setting then error("[mir5-worker-speed-cap-relaxed] missing startup setting " .. name) end
-- Fixture-only constraints clamp the saved positive cap to the unlimited
-- sentinel. A default change alone does not replace a saved startup value.
assert(setting.minimum_value == 0)
setting.minimum_value, setting.maximum_value, setting.default_value = -1, 0, 0
