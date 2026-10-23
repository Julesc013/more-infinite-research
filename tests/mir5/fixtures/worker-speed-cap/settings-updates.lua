local name = "mir-max-level-worker-robots-speed"
local setting = data.raw["int-setting"] and data.raw["int-setting"][name]
if not setting then error("[mir5-worker-speed-cap] missing startup setting " .. name) end

-- The known 6<-5 tail starts at level six. A cap of seven admits exactly two
-- earned levels before the controller disables next level eight.
-- Clamp the saved unlimited baseline to seven for the configuration scenario.
-- This fixture-only range does not change the player's production setting.
setting.minimum_value, setting.maximum_value, setting.default_value = 7, 8, 7
