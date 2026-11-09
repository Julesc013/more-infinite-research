-- Data-only disposable stimulus. Real worker technologies are untouched.
local lab = table.deepcopy(data.raw.lab.lab)
lab.name = "mir-ferrum-lab"
lab.energy_source = {type = "void"}
lab.researching_speed = 1001
-- Ferrum itself must append robotics science once in its final lab patch.
lab.inputs = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "space-science-pack", "electromagnetic-science-pack"}
local rows = {lab}
for _, name in ipairs({"mir-ferrum-sentinel", "mir-ferrum-detached", "mir-ferrum-count-control-6"}) do
  rows[#rows + 1] = {type = "technology", name = name, icon = "__base__/graphics/technology/automation.png",
    icon_size = 256, effects = {}, prerequisites = {},
    enabled = name ~= "mir-ferrum-count-control-6", hidden = name == "mir-ferrum-count-control-6",
    unit = {count = 1000, time = 60, ingredients = {{"automation-science-pack", 1}}}}
end
local calibration = rows[#rows]
calibration.unit.count, calibration.unit.count_formula = nil, "1518.75"
data:extend(rows)
