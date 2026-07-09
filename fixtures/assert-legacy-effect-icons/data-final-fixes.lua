local techs = data.raw.technology or {}

local effect_constant_prefix = "__core__/graphics/icons/technology/effect-constant/"

local forbidden_overlay_icons = {
  ["__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"] = true,
  ["__core__/graphics/icons/technology/effect-constant/effect-constant-recipe-productivity.png"] = true
}

local expected_overlays = {
  ["recipe-prod-research_cannon_shooting_speed-1"] = "__core__/graphics/icons/technology/constants/constant-speed.png",
  ["recipe-prod-research_character_crafting_speed-1"] = "__core__/graphics/icons/technology/constants/constant-speed.png",
  ["recipe-prod-research_character_mining_speed-1"] = "__core__/graphics/icons/technology/constants/constant-mining.png",
  ["recipe-prod-research_character_reach-1"] = "__core__/graphics/icons/technology/constants/constant-range.png",
  ["recipe-prod-research_character_walking_speed-1"] = "__core__/graphics/icons/technology/constants/constant-movement-speed.png",
  ["recipe-prod-research_electric_shooting_speed-1"] = "__core__/graphics/icons/technology/constants/constant-speed.png",
  ["recipe-prod-research_flamethrower_shooting_speed-1"] = "__core__/graphics/icons/technology/constants/constant-speed.png",
  ["recipe-prod-research_inventory_capacity-1"] = "__core__/graphics/icons/technology/constants/constant-capacity.png",
  ["recipe-prod-research_lab_productivity-1"] = "__core__/graphics/icons/technology/constants/constant-mining-productivity.png",
  ["recipe-prod-research_robot_battery-1"] = "__core__/graphics/icons/technology/constants/constant-battery.png",
  ["recipe-prod-research_rocket_shooting_speed-1"] = "__core__/graphics/icons/technology/constants/constant-speed.png"
}

local function fail(message)
  error("MIR validation failed: " .. message)
end

local function is_space_age_icon(icon)
  return type(icon) == "string" and string.find(icon, "__space-age__", 1, true) ~= nil
end

local function is_effect_constant_icon(icon)
  return type(icon) == "string" and string.find(icon, effect_constant_prefix, 1, true) == 1
end

local function is_expected_overlay_layer(layer, expected_icon)
  return layer.icon == expected_icon
    and layer.icon_size == 128
    and layer.shift
    and layer.shift[1] == 100
    and layer.shift[2] == 100
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
    if forbidden_overlay_icons[layer.icon] then
      fail("generated Factorio 1.1 technology " .. tech_name .. " uses unavailable newer badge icon " .. layer.icon .. ".")
    end
    if is_effect_constant_icon(layer.icon) then
      fail("generated Factorio 1.1 technology " .. tech_name .. " uses smaller effect-row sprite " .. layer.icon .. " as a technology tile badge.")
    end
    if is_space_age_icon(layer.icon) then
      fail("generated Factorio 1.1 technology " .. tech_name .. " uses newer Space Age icon " .. layer.icon .. ".")
    end
    if is_expected_overlay_layer(layer, expected_icon) then
      found_expected_overlay = true
    end
  end

  if not found_expected_overlay then
    fail("generated Factorio 1.1 technology " .. tech_name .. " is missing expected high-resolution target-era overlay " .. expected_icon .. ".")
  end
end

for tech_name, expected_icon in pairs(expected_overlays) do
  assert_expected_overlay(tech_name, expected_icon)
end
