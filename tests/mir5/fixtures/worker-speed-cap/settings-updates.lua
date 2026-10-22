local name = "mir-max-level-worker-robots-speed"
local setting = data.raw["int-setting"] and data.raw["int-setting"][name]
if not setting then error("[mir5-worker-speed-cap] missing startup setting " .. name) end

-- The known 6<-5 tail starts at level six. A cap of seven admits exactly two
-- earned levels before the controller disables next level eight.
setting.default_value = 7
