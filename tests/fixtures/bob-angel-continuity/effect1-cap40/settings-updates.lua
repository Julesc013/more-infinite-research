-- Fixture-only startup defaults exercise the per-family useful-cap path.
-- They modify no player state and leave profile import blank.
local FAMILIES = {
  "research_material_aluminium", "research_material_copper_tungsten", "research_material_gold",
  "research_material_tin", "research_material_titanium",
}
for _, family in ipairs(FAMILIES) do
  local effect_setting = assert(data.raw["double-setting"] and data.raw["double-setting"]["ips-effect-per-level-" .. family], family .. " effect setting is absent")
  local cap_setting = assert(data.raw["int-setting"] and data.raw["int-setting"]["ips-max-level-" .. family], family .. " cap setting is absent")
  assert(effect_setting.setting_type == "startup" and cap_setting.setting_type == "startup" and cap_setting.minimum_value == 0,
    family .. " startup setting contract changed")
  effect_setting.default_value = 1
  cap_setting.default_value = 40
end
local profile_import = assert(data.raw["string-setting"] and data.raw["string-setting"]["mir-settings-profile-import"], "blank profile import setting is absent")
assert(profile_import.setting_type == "startup" and profile_import.default_value == "", "normal profile import default changed")
