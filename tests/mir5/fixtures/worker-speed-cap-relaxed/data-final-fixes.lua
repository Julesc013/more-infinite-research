local setting = data.raw["int-setting"] and data.raw["int-setting"]["mir-max-level-worker-robots-speed"]
if not setting or setting.default_value ~= 0 then
  error("[mir5-worker-speed-cap-relaxed] unlimited startup sentinel differs")
end
-- Keep the fixture's unrelated current research identity during the upgrade.
data:extend({{
  type = "technology", name = "mir5-worker-speed-cap-probe",
  icon = "__base__/graphics/technology/automation-1.png", icon_size = 256,
  prerequisites = {"automation-science-pack"},
  unit = {count = 100, time = 1, ingredients = {{"automation-science-pack", 1}}},
  effects = {}
}})
