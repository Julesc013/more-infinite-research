local techs = data.raw.technology or {}

local core_constant_prefix = "__core__/graphics/icons/technology/constants/"

local expected_overlays = {
  ["recipe-prod-research_cannon_shooting_speed-1"] = "__base__/graphics/technology/speed-module-3.png",
  ["recipe-prod-research_character_crafting_speed-1"] = "__base__/graphics/technology/speed-module-3.png",
  ["recipe-prod-research_character_mining_speed-1"] = "__base__/graphics/technology/mining-productivity.png",
  ["recipe-prod-research_character_reach-1"] = "__base__/graphics/technology/artillery-range.png",
  ["recipe-prod-research_character_walking_speed-1"] = "__base__/graphics/technology/exoskeleton-equipment.png",
  ["recipe-prod-research_electric_shooting_speed-1"] = "__base__/graphics/technology/speed-module-3.png",
  ["recipe-prod-research_flamethrower_shooting_speed-1"] = "__base__/graphics/technology/speed-module-3.png",
  ["recipe-prod-research_inventory_capacity-1"] = "__base__/graphics/technology/inserter-capacity.png",
  ["recipe-prod-research_lab_productivity-1"] = "__base__/graphics/technology/productivity-module-3.png",
  ["recipe-prod-research_robot_battery-1"] = "__base__/graphics/technology/battery-equipment.png",
  ["recipe-prod-research_rocket_shooting_speed-1"] = "__base__/graphics/technology/speed-module-3.png"
}

local function fail(message)
  error("MIR validation failed: " .. message)
end

local function is_core_constant_icon(icon)
  return type(icon) == "string" and string.find(icon, core_constant_prefix, 1, true) == 1
end

local function is_space_age_icon(icon)
  return type(icon) == "string" and string.find(icon, "__space-age__", 1, true) ~= nil
end

local function assert_expected_overlay(tech_name, expected_icon)
  local tech = techs[tech_name]
  if not tech then
    fail("missing generated Factorio 1.1 direct-effect technology " .. tech_name .. ".")
  end

  if not tech.icons or #tech.icons < 2 then
    fail("generated Factorio 1.1 direct-effect technology " .. tech_name .. " has no badge overlay.")
  end

  local found_expected_overlay = false
  for _, layer in ipairs(tech.icons or {}) do
    if is_core_constant_icon(layer.icon) then
      fail("generated Factorio 1.1 technology " .. tech_name .. " uses newer core constant icon " .. layer.icon .. ".")
    end
    if is_space_age_icon(layer.icon) then
      fail("generated Factorio 1.1 technology " .. tech_name .. " uses newer Space Age icon " .. layer.icon .. ".")
    end
    if layer.icon == expected_icon and layer.scale ~= nil and layer.shift ~= nil then
      found_expected_overlay = true
    end
  end

  if not found_expected_overlay then
    fail("generated Factorio 1.1 technology " .. tech_name .. " is missing expected target-era overlay " .. expected_icon .. ".")
  end
end

for tech_name, expected_icon in pairs(expected_overlays) do
  assert_expected_overlay(tech_name, expected_icon)
end
