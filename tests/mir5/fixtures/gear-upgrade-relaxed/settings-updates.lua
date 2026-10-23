-- This successor fixture shares the published seed fixture's mod identity.
-- Constraining the native prototype to exactly zero makes the saved 4.7 cap
-- value ineligible without changing player settings at runtime. The ordinary
-- MIR profile import remains blank here: a nonblank valid import has its
-- documented precedence and is deliberately outside this raw-default case.
local max_name = "ips-max-level-research_gears"
local import_name = "mir-settings-profile-import"
local maximum = data.raw["int-setting"] and data.raw["int-setting"][max_name]
local profile_import = data.raw["string-setting"] and data.raw["string-setting"][import_name]

if maximum == nil then error("[mir5-gear-upgrade-relaxed] gear maximum setting is absent") end
if maximum.setting_type ~= "startup" or maximum.minimum_value ~= 0
    or type(maximum.maximum_value) ~= "number" or maximum.maximum_value < 0 then
  error("[mir5-gear-upgrade-relaxed] gear maximum setting has unexpected constraints")
end
if profile_import == nil or profile_import.setting_type ~= "startup"
    or profile_import.default_value ~= "" then
  error("[mir5-gear-upgrade-relaxed] expected blank normal profile import is absent")
end

maximum.minimum_value = 0
maximum.maximum_value = 0
maximum.default_value = 0
