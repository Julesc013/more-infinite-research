-- Fixture-owned continuity probe retained across prototype-cap saves.
data:extend({{
  type = "technology",
  name = "mir5-ba-continuity-queue-probe",
  icon = "__base__/graphics/technology/automation.png",
  icon_size = 256,
  prerequisites = {"automation"},
  unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}},
  effects = {},
}})
