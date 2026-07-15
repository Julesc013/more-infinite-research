local modifiers = {
  [1] = 0.15,
  [2] = 0.20,
  [3] = 0.25,
  [4] = 0.35,
  [5] = 0.45,
  [6] = 0.70
}

local technologies = {}
for level = 1, 6 do
  local ingredients = {
    {"science-pack-1", 1},
    {"science-pack-2", 1},
    {"science-pack-3", 1}
  }
  if level >= 3 then
    table.insert(ingredients, {"high-tech-science-pack", 1})
  end
  if level >= 5 then
    table.insert(ingredients, {"production-science-pack", 1})
  end
  if level >= 6 then
    table.insert(ingredients, {"space-science-pack", 1})
  end

  local tech = {
    type = "technology",
    name = "worker-robots-battery-" .. level,
    icon = "__base__/graphics/icons/logistic-robot.png",
    icon_size = 64,
    effects = {
      {type = "worker-robot-battery", modifier = modifiers[level]}
    },
    prerequisites = level == 1 and {"robotics"} or {"worker-robots-battery-" .. (level - 1)},
    unit = {
      count = 50 * level,
      ingredients = ingredients,
      time = level < 3 and 30 or 60
    },
    upgrade = true,
    order = "c-k-b-" .. level
  }

  if level == 6 then
    tech.unit.count = nil
    tech.unit.count_formula = "2^(L-6)*1000"
    tech.max_level = "infinite"
  end

  table.insert(technologies, tech)
end

data:extend(technologies)
