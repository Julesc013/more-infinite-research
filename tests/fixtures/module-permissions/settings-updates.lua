-- This selects the retained startup setting through the normal settings
-- stage. `forced_value` is intentionally not used: the pinned 2.1.23
-- setting-prototype contract does not expose it, and this fixture selects a
-- disposable profile rather than imposing a player setting.
local name = "mir-unrestricted-modules"
local setting = data.raw["bool-setting"] and data.raw["bool-setting"][name]
if not setting then error("[mir5-module-permissions] missing startup setting " .. name) end
if setting.setting_type ~= "startup" or setting.default_value ~= false then
  error("[mir5-module-permissions] unrestricted-module setting has an unexpected retained contract")
end
setting.default_value = true
