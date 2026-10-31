-- The fixture selects the opt-in controller in the native settings stage.  It
-- does not add or force a setting; runtime reads settings.startup only.
local setting = data.raw["bool-setting"] and data.raw["bool-setting"]["mir-enable-passive-repair"]
if type(setting) ~= "table" or setting.default_value ~= false then
  error("[mir5-repair-stress] passive-repair startup setting is absent or changed")
end
setting.default_value = true
