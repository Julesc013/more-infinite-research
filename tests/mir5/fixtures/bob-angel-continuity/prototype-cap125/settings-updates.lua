-- Fixture-only prototype-cap selection. Keep each material family's normal
-- two-percent, unlimited user setting and blank profile import semantics.
local FAMILIES = {
  "research_material_aluminium", "research_material_copper_tungsten", "research_material_gold",
  "research_material_tin", "research_material_titanium",
}

for _, family in ipairs(FAMILIES) do
  local effect = assert(data.raw["double-setting"] and data.raw["double-setting"]["ips-effect-per-level-" .. family],
    family .. " effect setting is absent")
  local cap = assert(data.raw["int-setting"] and data.raw["int-setting"]["ips-max-level-" .. family],
    family .. " cap setting is absent")
  assert(effect.setting_type == "startup" and effect.default_value == 2,
    family .. " effect setting contract changed")
  assert(cap.setting_type == "startup" and cap.minimum_value == 0,
    family .. " cap setting contract changed")
  cap.default_value = 0
end
local imported = assert(data.raw["string-setting"] and data.raw["string-setting"]["mir-settings-profile-import"],
  "profile import setting is absent")
assert(imported.setting_type == "startup" and imported.default_value == "",
  "normal profile import default changed")
local productivity = assert(data.raw["string-setting"] and data.raw["string-setting"]["mir-prototype-productivity-cap"],
  "prototype productivity cap setting is absent")
assert(productivity.setting_type == "startup" and productivity.default_value == "engine-default",
  "prototype productivity cap default changed")
productivity.default_value = "percent-125"
