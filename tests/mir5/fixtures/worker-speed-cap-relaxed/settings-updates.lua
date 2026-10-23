local name = "mir-max-level-worker-robots-speed"
local setting = data.raw["int-setting"] and data.raw["int-setting"][name]
if not setting then error("[mir5-worker-speed-cap-relaxed] missing startup setting " .. name) end
-- A separate fixture/profile changes the real registered startup default to
-- the published unlimited sentinel for the save-continuation run.
setting.default_value = 0
