if settings.startup["mir-max-level-worker-robots-speed"].value ~= 0 then
  error("[mir5-worker-speed-precap] expected unlimited baseline")
end
data:extend({{
  type = "technology", name = "mir5-worker-speed-cap-probe",
  icon = "__base__/graphics/technology/automation-1.png", icon_size = 256,
  prerequisites = {"automation-science-pack"},
  unit = {count = 100, time = 1, ingredients = {{"automation-science-pack", 1}}},
  effects = {}
}})
