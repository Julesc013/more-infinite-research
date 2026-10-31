-- Eleven delivered direct-research identities shared by the modern and
-- reduced historical target adapters. These are authored semantic rows, not
-- captured TechnologyPrototype output or a discovery catalogue.
local M = {}

local ORDER = {
  "research_cannon_shooting_speed",
  "research_character_crafting_speed",
  "research_character_mining_speed",
  "research_character_reach",
  "research_character_walking_speed",
  "research_electric_shooting_speed",
  "research_flamethrower_shooting_speed",
  "research_inventory_capacity",
  "research_lab_productivity",
  "research_robot_battery",
  "research_rocket_shooting_speed",
}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR direct research declaration contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function direct(key, effect, icon_candidates, icon, icon_size, overlay, localised_name, localised_description,
  base_cost, effect_percent, growth_factor, research_time, setting_order, modern_science, modern_prerequisites)
  return {
    key = key,
    family = key,
    kind = "direct",
    effects = effect,
    icon_candidates = icon_candidates,
    modern = {
      science = modern_science,
      prerequisites = modern_prerequisites,
      icon = icon,
      icon_size = icon_size,
      overlay = overlay,
      localised_name = localised_name,
      localised_description = localised_description,
    },
    defaults = {
      base_cost = base_cost,
      effect_percent = effect_percent,
      enabled = true,
      growth_factor = growth_factor,
      linear_increment = 0,
      max_level = 0,
      research_time = research_time,
    },
    order = "p[" .. key .. "]",
    setting_order = setting_order,
  }
end

local DEFINITIONS = {
  research_cannon_shooting_speed = direct(
    "research_cannon_shooting_speed",
    {{type="gun-speed", ammo_category="cannon-shell", raw=false, scale=1}},
    {{technology="weapon-shooting-speed-3"}, {technology="physical-projectile-damage-2"}, {item="cannon-shell"}},
    "__base__/graphics/technology/weapon-shooting-speed-2.png", 256,
    "__core__/graphics/icons/technology/constants/constant-speed.png",
    {"technology-name.more-infinite-research.research_cannon_shooting_speed"},
    {"technology-description.more-infinite-research.direct_effect"},
    60, 10, 1.5, 60, "b-100-cannon-shooting-speed-stream-research_cannon_shooting_speed-",
    "science_automation_logistic_chemical_production_military", {"weapon-shooting-speed-5", "tank"}),
  research_character_crafting_speed = direct(
    "research_character_crafting_speed",
    {{type="character-crafting-speed", raw=false, scale=1}},
    {{technology="automation-3"}, {technology="automation-2"}, {item="repair-pack"}},
    "__base__/graphics/technology/automation-3.png", 256,
    "__core__/graphics/icons/technology/constants/constant-speed.png",
    {"technology-name.more-infinite-research.research_character_crafting_speed"},
    {"technology-description.more-infinite-research.direct_effect"},
    8000, 5, 2, 60, "b-100-character-crafting-speed-stream-research_character_crafting_speed-",
    "science_utility_military", {}),
  research_character_mining_speed = direct(
    "research_character_mining_speed",
    {{type="character-mining-speed", raw=false, scale=1}},
    {{technology="steel-axe"}, {item="steel-axe"}},
    "__base__/graphics/technology/steel-axe.png", 256,
    "__core__/graphics/icons/technology/constants/constant-mining.png",
    {"technology-name.more-infinite-research.research_character_mining_speed", {"technology-name.steel-axe"}},
    {"technology-description.more-infinite-research.direct_effect"},
    8000, 5, 2, 60, "b-100-character-mining-speed-stream-research_character_mining_speed-",
    "science_utility_military", {}),
  research_character_reach = direct(
    "research_character_reach",
    {{type="character-reach-distance", raw=true, scale=1}, {type="character-build-distance", raw=true, scale=1},
      {type="character-resource-reach-distance", raw=true, scale=1}, {type="character-item-drop-distance", raw=true, scale=1}},
    {{technology="steel-axe"}, {item="steel-axe"}},
    "__base__/graphics/technology/steel-axe.png", 256,
    "__core__/graphics/icons/technology/constants/constant-range.png",
    {"technology-name.more-infinite-research.research_character_reach", {"technology-name.steel-axe"}},
    {"technology-description.more-infinite-research.direct_effect"},
    8000, 10, 2, 60, "b-050-character-reach-bonus-stream-research_character_reach-",
    "science_utility_military", {}),
  research_character_walking_speed = direct(
    "research_character_walking_speed",
    {{type="character-running-speed", raw=false, scale=1}},
    {{technology="exoskeleton-equipment"}, {item="exoskeleton-equipment"}},
    "__base__/graphics/technology/exoskeleton-equipment.png", 256,
    "__core__/graphics/icons/technology/constants/constant-movement-speed.png",
    {"technology-name.more-infinite-research.research_character_walking_speed", {"technology-name.exoskeleton-equipment"}},
    {"technology-description.more-infinite-research.direct_effect"},
    8000, 5, 2, 60, "b-100-character-walking-speed-stream-research_character_walking_speed-",
    "science_utility_military", {}),
  research_electric_shooting_speed = direct(
    "research_electric_shooting_speed",
    {{type="gun-speed", ammo_category="electric", raw=false, scale=1}},
    {{technology="electric-weapons-damage-1", required_mod="space-age"}, {technology="discharge-defense-equipment"}},
    "__base__/graphics/technology/discharge-defense-equipment.png", 256,
    "__core__/graphics/icons/technology/constants/constant-speed.png",
    {"technology-name.more-infinite-research.research_electric_shooting_speed"},
    {"technology-description.more-infinite-research.electric_shooting_speed"},
    60, 10, 1.5, 60, "b-100-electric-shooting-speed-stream-research_electric_shooting_speed-",
    "science_automation_logistic_chemical_production_military", {"discharge-defense-equipment"}),
  research_flamethrower_shooting_speed = direct(
    "research_flamethrower_shooting_speed",
    {{type="gun-speed", ammo_category="flamethrower", raw=false, scale=1}},
    {{technology="flamethrower"}, {item="flamethrower"}},
    "__base__/graphics/technology/flamethrower.png", 256,
    "__core__/graphics/icons/technology/constants/constant-speed.png",
    {"technology-name.more-infinite-research.research_flamethrower_shooting_speed", {"technology-name.flamethrower"}},
    {"technology-description.more-infinite-research.flamethrower_shooting_speed"},
    60, 10, 1.5, 60, "b-100-flamethrower-shooting-speed-stream-research_flamethrower_shooting_speed-",
    "science_automation_logistic_chemical_production_military", {"flamethrower"}),
  research_inventory_capacity = direct(
    "research_inventory_capacity",
    {{type="character-inventory-slots-bonus", raw=true, scale=1}, {type="character-logistic-trash-slots", raw=true, scale=1}},
    {{technology="toolbelt"}, {item="toolbelt"}},
    "__base__/graphics/technology/toolbelt.png", 256,
    "__core__/graphics/icons/technology/constants/constant-capacity.png",
    {"technology-name.more-infinite-research.research_inventory_capacity", {"technology-name.toolbelt"}},
    {"technology-description.more-infinite-research.direct_effect"},
    8000, 1, 1.1, 60, "b-100-character-inventory-slots-stream-research_inventory_capacity-",
    "science_utility_military", {}),
  research_lab_productivity = direct(
    "research_lab_productivity",
    {{type="laboratory-productivity", raw=false, scale=1}},
    {{technology="research-productivity", required_mod="space-age"}, {technology="military-science-pack"},
      {technology="mining-productivity-4"}, {technology="mining-productivity-3"}, {technology="mining-productivity-1"}},
    "__base__/graphics/technology/military-science-pack.png", 256,
    "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
    {"technology-name.more-infinite-research.research_lab_productivity"},
    {"technology-description.more-infinite-research.lab_productivity"},
    1000, 10, 1.2, 120, "b-050-research-productivity-stream-research_lab_productivity-",
    "science_automation_logistic_military_chemical_production_utility", {}),
  research_robot_battery = direct(
    "research_robot_battery",
    {{type="worker-robot-battery", raw=false, scale=1}},
    {{technology="logistic-robotics"}, {item="logistic-robotics"}},
    "__base__/graphics/technology/logistic-robotics.png", 256,
    "__core__/graphics/icons/technology/constants/constant-battery.png",
    {"technology-name.more-infinite-research.research_robot_battery", {"technology-name.logistic-robotics"}},
    {"technology-description.more-infinite-research.direct_effect"},
    8000, 10, 1.2, 60, "b-100-worker-robot-battery-stream-research_robot_battery-",
    "science_automation_logistic_chemical_production", {}),
  research_rocket_shooting_speed = direct(
    "research_rocket_shooting_speed",
    {{type="gun-speed", ammo_category="rocket", raw=false, scale=1}},
    {{technology="rocketry"}, {item="rocketry"}},
    "__base__/graphics/technology/rocketry.png", 256,
    "__core__/graphics/icons/technology/constants/constant-speed.png",
    {"technology-name.more-infinite-research.research_rocket_shooting_speed", {"technology-name.rocketry"}},
    {"technology-description.more-infinite-research.direct_effect"},
    60, 10, 1.5, 60, "b-100-rocket-shooting-speed-stream-research_rocket_shooting_speed-",
    "science_automation_logistic_chemical_production_military", {"rocketry"}),
}


-- Factorio 1.1 used its own laboratory-productivity constant. All other
-- delivered direct-family constant assets retain their ordinary names.
local LEGACY_OVERLAYS = {
  research_cannon_shooting_speed = "__core__/graphics/icons/technology/constants/constant-speed.png",
  research_character_crafting_speed = "__core__/graphics/icons/technology/constants/constant-speed.png",
  research_character_mining_speed = "__core__/graphics/icons/technology/constants/constant-mining.png",
  research_character_reach = "__core__/graphics/icons/technology/constants/constant-range.png",
  research_character_walking_speed = "__core__/graphics/icons/technology/constants/constant-movement-speed.png",
  research_electric_shooting_speed = "__core__/graphics/icons/technology/constants/constant-speed.png",
  research_flamethrower_shooting_speed = "__core__/graphics/icons/technology/constants/constant-speed.png",
  research_inventory_capacity = "__core__/graphics/icons/technology/constants/constant-capacity.png",
  research_lab_productivity = "__core__/graphics/icons/technology/constants/constant-mining-productivity.png",
  research_robot_battery = "__core__/graphics/icons/technology/constants/constant-battery.png",
  research_rocket_shooting_speed = "__core__/graphics/icons/technology/constants/constant-speed.png",
}

function M.keys()
  return copy(ORDER)
end

function M.definition(key)
  local definition = DEFINITIONS[key]
  if not definition then error("MIR unknown direct research family " .. tostring(key), 2) end
  return copy(definition)
end

-- Exact F210 base catalogue projection. The compatibility catalogue retains
-- only the direct identities here; construction stays in research.modern.
function M.legacy_overlay(key)
  local overlay = LEGACY_OVERLAYS[key]
  if not overlay then error("MIR direct research has no legacy overlay for " .. tostring(key), 2) end
  return overlay
end

function M.modern(key)
  local definition = M.definition(key)
  local modern = definition.modern
  return {
    key = definition.key,
    family = definition.family,
    kind = definition.kind,
    science = modern.science,
    prerequisites = copy(modern.prerequisites),
    effects = copy(definition.effects),
    icon = modern.icon,
    icon_size = modern.icon_size,
    overlay = modern.overlay,
    localised_name = copy(modern.localised_name),
    localised_description = copy(modern.localised_description),
    order = definition.order,
    tuning = copy(definition.defaults),
    setting_order = definition.setting_order,
  }
end

return M
