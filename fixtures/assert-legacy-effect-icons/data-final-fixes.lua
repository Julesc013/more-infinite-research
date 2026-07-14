local technologies = data.raw.technology or {}

local expected = {
  ["recipe-prod-research_cannon_shooting_speed-1"] = "constant-speed.png",
  ["recipe-prod-research_character_crafting_speed-1"] = "constant-speed.png",
  ["recipe-prod-research_character_mining_speed-1"] = "constant-mining.png",
  ["recipe-prod-research_character_reach-1"] = "constant-range.png",
  ["recipe-prod-research_character_walking_speed-1"] = "constant-movement-speed.png",
  ["recipe-prod-research_electric_shooting_speed-1"] = "constant-speed.png",
  ["recipe-prod-research_flamethrower_shooting_speed-1"] = "constant-speed.png",
  ["recipe-prod-research_inventory_capacity-1"] = "constant-capacity.png",
  ["recipe-prod-research_lab_productivity-1"] = "constant-mining-productivity.png",
  ["recipe-prod-research_robot_battery-1"] = "constant-battery.png",
  ["recipe-prod-research_rocket_shooting_speed-1"] = "constant-speed.png"
}

for technology_name, badge_name in pairs(expected) do
  local technology = technologies[technology_name]
  if not technology or not technology.icons then
    error("MIR validation failed: missing legacy direct-effect technology or icon layers " .. technology_name)
  end
  local found = false
  for _, layer in ipairs(technology.icons) do
    local icon = layer.icon or ""
    if string.find(icon, "__space-age__", 1, true) or string.find(icon, "effect-constant-recipe-productivity", 1, true) then
      error("MIR validation failed: unavailable newer badge on " .. technology_name)
    end
    if string.find(icon, "/constants/" .. badge_name, 1, true) then found = true end
  end
  if not found then error("MIR validation failed: missing target-era badge on " .. technology_name) end
end
