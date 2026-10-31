local name = "mir-max-level-worker-robots-speed"
local setting = data.raw["int-setting"] and data.raw["int-setting"][name]
if setting == nil then error("[mir5-f200-legacy-worker-source] setting is absent: " .. name) end
setting.default_value = 7
