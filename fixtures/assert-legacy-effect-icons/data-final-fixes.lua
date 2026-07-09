local techs = data.raw.technology or {}

local forbidden_icon_prefixes = {
  "__core__/graphics/icons/technology/constants/",
  "__core__/graphics/icons/technology/effect-constant/",
  "__space-age__/"
}

local expected_overlay_sources = {
  ["recipe-prod-research_cannon_shooting_speed-1"] = {
    "speed-module-3", "speed-module-2", "speed-module"
  },
  ["recipe-prod-research_character_crafting_speed-1"] = {
    "speed-module-3", "speed-module-2", "speed-module"
  },
  ["recipe-prod-research_character_mining_speed-1"] = {
    "speed-module-3", "speed-module-2", "speed-module"
  },
  ["recipe-prod-research_character_reach-1"] = {
    "artillery-shell-range-1"
  },
  ["recipe-prod-research_character_walking_speed-1"] = {
    "speed-module-3", "speed-module-2", "speed-module"
  },
  ["recipe-prod-research_electric_shooting_speed-1"] = {
    "speed-module-3", "speed-module-2", "speed-module"
  },
  ["recipe-prod-research_flamethrower_shooting_speed-1"] = {
    "speed-module-3", "speed-module-2", "speed-module"
  },
  ["recipe-prod-research_inventory_capacity-1"] = {
    "toolbelt", "inserter-capacity-bonus-7", "inserter-capacity-bonus-1"
  },
  ["recipe-prod-research_lab_productivity-1"] = {
    "mining-productivity-4", "mining-productivity-3", "mining-productivity-1"
  },
  ["recipe-prod-research_robot_battery-1"] = {
    "battery", "battery-equipment", "logistic-robotics"
  },
  ["recipe-prod-research_rocket_shooting_speed-1"] = {
    "speed-module-3", "speed-module-2", "speed-module"
  }
}

local function fail(message)
  error("MIR validation failed: " .. message)
end

local function has_prefix(value, prefix)
  return type(value) == "string" and string.find(value, prefix, 1, true) == 1
end

local function icon_paths_for_technology_names(names)
  local paths = {}
  for _, tech_name in ipairs(names or {}) do
    local tech = techs[tech_name]
    if tech then
      for _, layer in ipairs(tech.icons or {}) do
        if layer.icon then paths[layer.icon] = true end
      end
      if tech.icon then paths[tech.icon] = true end
    end
  end
  return paths
end

local function is_expected_overlay_layer(layer, expected_paths)
  return layer.icon
    and expected_paths[layer.icon]
    and layer.scale == 0.42
    and layer.shift
    and layer.shift[1] == 44
    and layer.shift[2] == 44
end

local function assert_expected_overlay(tech_name, expected_sources)
  local tech = techs[tech_name]
  if not tech then
    fail("missing generated old-line direct-effect technology " .. tech_name .. ".")
  end

  local expected_paths = icon_paths_for_technology_names(expected_sources)
  if not next(expected_paths) then
    fail("missing old-line overlay source technology for " .. tech_name .. ".")
  end

  if not tech.icons or #tech.icons < 2 then
    fail("generated old-line direct-effect technology " .. tech_name .. " has no visible tile badge overlay.")
  end

  local found_expected_overlay = false
  for _, layer in ipairs(tech.icons or {}) do
    for _, prefix in ipairs(forbidden_icon_prefixes) do
      if has_prefix(layer.icon, prefix) then
        fail("generated old-line technology " .. tech_name .. " uses unavailable newer badge icon " .. layer.icon .. ".")
      end
    end
    if is_expected_overlay_layer(layer, expected_paths) then
      found_expected_overlay = true
    end
  end

  if not found_expected_overlay then
    fail("generated old-line technology " .. tech_name .. " is missing expected target-era tile badge art.")
  end
end

for tech_name, expected_sources in pairs(expected_overlay_sources) do
  assert_expected_overlay(tech_name, expected_sources)
end
