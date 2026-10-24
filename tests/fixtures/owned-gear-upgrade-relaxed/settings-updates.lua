-- Fixture-only constraints make a saved cap of two reload as zero. The normal
-- profile import is deliberately blank: this scenario observes the raw-startup
-- path and does not overwrite a user's effective import selection.
local maximum_name = "ips-max-level-research_gears"
local import_name = "mir-settings-profile-import"
local maximum = data.raw["int-setting"] and data.raw["int-setting"][maximum_name]
local profile_import = data.raw["string-setting"] and data.raw["string-setting"][import_name]

if maximum == nil or maximum.setting_type ~= "startup" or maximum.minimum_value ~= 0
    or type(maximum.maximum_value) ~= "number" or maximum.maximum_value < 0 then
  error("[mir5-owned-gear-upgrade-relaxed] unexpected gear cap setting constraints")
end
if profile_import == nil or profile_import.setting_type ~= "startup" or profile_import.default_value ~= "" then
  error("[mir5-owned-gear-upgrade-relaxed] expected blank profile import is absent")
end

maximum.minimum_value = -1
maximum.maximum_value = 0
maximum.default_value = 0
