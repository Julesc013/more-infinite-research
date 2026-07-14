local technologies = data.raw.technology or {}

local expected = {
  "recipe-prod-research_cannon_shooting_speed-1",
  "recipe-prod-research_character_crafting_speed-1",
  "recipe-prod-research_character_mining_speed-1",
  "recipe-prod-research_character_reach-1",
  "recipe-prod-research_character_walking_speed-1",
  "recipe-prod-research_electric_shooting_speed-1",
  "recipe-prod-research_flamethrower_shooting_speed-1",
  "recipe-prod-research_inventory_capacity-1",
  "recipe-prod-research_lab_productivity-1",
  "recipe-prod-research_robot_battery-1",
  "recipe-prod-research_rocket_shooting_speed-1"
}

for _, technology_name in ipairs(expected) do
  local technology = technologies[technology_name]
  if not technology or not technology.icons then
    error("MIR validation failed: missing Factorio 1.0 direct-effect technology or icon layers " .. technology_name)
  end
  for _, layer in ipairs(technology.icons) do
    local icon = layer.icon or ""
    if string.find(icon, "__space-age__", 1, true) or string.find(icon, "effect-constant-recipe-productivity", 1, true) then
      error("MIR validation failed: unavailable newer badge on " .. technology_name)
    end
    if string.find(icon, "/constants/", 1, true) then
      error("MIR validation failed: Factorio 1.1 constant badge leaked onto Factorio 1.0 technology " .. technology_name)
    end
  end
end
