-- Exact, reduced direct-research contracts for the seven released historical
-- target lines. A target body is constructed only when selected; inactive
-- target maps are never materialised at data stage.
local direct = require("research.native_direct_definitions")

local M = {}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR historical direct contract contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function row(key, science, prerequisites)
  return {key=key, science=science, prerequisites=prerequisites}
end

local character = {
  "research_character_crafting_speed", "research_character_mining_speed", "research_character_reach",
  "research_character_walking_speed", "research_inventory_capacity",
}
local all = direct.keys()

local function selected(keys)
  local out = {}
  for index = 1, #keys do out[index] = keys[index] end
  return out
end

local function without(keys, omitted)
  local skip, out = {}, {}
  for index = 1, #omitted do skip[omitted[index]] = true end
  for index = 1, #keys do if not skip[keys[index]] then out[#out + 1] = keys[index] end end
  return out
end

local function append(out, key, science, prerequisites)
  out[#out + 1] = row(key, science, prerequisites)
end

local function old_numeric_rows()
  local rows = {}
  local alien = {"alien-science-pack"}
  local alien_prerequisites = {"alien-technology"}
  for index = 1, #character do append(rows, character[index], alien, alien_prerequisites) end
  append(rows, "research_rocket_shooting_speed",
    {"alien-science-pack", "science-pack-1", "science-pack-2", "science-pack-3"},
    {"advanced-electronics", "alien-technology", "battery", "logistics", "rocketry"})
  append(rows, "research_electric_shooting_speed",
    {"alien-science-pack", "science-pack-1", "science-pack-2", "science-pack-3"},
    {"advanced-electronics", "alien-technology", "battery", "discharge-defense-equipment", "logistics"})
  return rows
end

local function numeric_target(id, factorio_line)
  return {
    id=id, factorio_line=factorio_line, numeric_cost=true, scalar_icon=true, visible_when_disabled=nil,
    settings=without(all, {"research_lab_productivity", "research_robot_battery"}),
    emitted=old_numeric_rows(),
  }
end

local function f015_rows(include_lab)
  local rows = {}
  local character_science = {"high-tech-science-pack", "military-science-pack"}
  local character_prerequisites = {"advanced-electronics-2", "automation-2", "battery", "military-2", "speed-module", "turrets"}
  for index = 1, #character do append(rows, character[index], character_science, character_prerequisites) end
  local shooting_science = {"military-science-pack", "production-science-pack", "science-pack-1", "science-pack-2", "science-pack-3"}
  local shooting_prerequisites = {"advanced-electronics", "advanced-material-processing-2", "electric-engine", "engine", "military-2", "turrets"}
  append(rows, "research_rocket_shooting_speed", shooting_science,
    {"advanced-electronics", "advanced-material-processing-2", "electric-engine", "engine", "military-2", "turrets", "rocketry"})
  append(rows, "research_electric_shooting_speed", shooting_science,
    {"advanced-electronics", "advanced-material-processing-2", "electric-engine", "engine", "military-2", "turrets", "discharge-defense-equipment"})
  append(rows, "research_flamethrower_shooting_speed", shooting_science,
    {"advanced-electronics", "advanced-material-processing-2", "electric-engine", "engine", "military-2", "turrets", "flamethrower"})
  append(rows, "research_robot_battery", {"production-science-pack", "science-pack-1", "science-pack-2", "science-pack-3"},
    {"advanced-electronics", "advanced-material-processing-2", "electric-engine", "engine"})
  if include_lab then
    append(rows, "research_lab_productivity",
      {"high-tech-science-pack", "military-science-pack", "production-science-pack", "science-pack-1", "science-pack-2", "science-pack-3"},
      {"advanced-electronics", "advanced-electronics-2", "advanced-material-processing-2", "automation-2", "battery", "electric-engine", "engine", "military-2", "speed-module", "turrets"})
  end
  return rows
end

local function f015()
  return {
    id="f015", factorio_line="0.15", numeric_cost=false, scalar_icon=false, visible_when_disabled=nil,
    settings=without(all, {"research_lab_productivity"}), emitted=f015_rows(false),
  }
end

local function f016()
  return {
    id="f016", factorio_line="0.16", numeric_cost=false, scalar_icon=false, visible_when_disabled=nil,
    settings=selected(all), emitted=f015_rows(true),
  }
end

local function later_rows(cannon_prerequisite)
  local rows = {}
  local character_science = {"military-science-pack", "utility-science-pack"}
  local character_prerequisites = {"military-science-pack", "utility-science-pack"}
  for index = 1, #character do append(rows, character[index], character_science, character_prerequisites) end
  local shooting_science = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack", "military-science-pack", "production-science-pack"}
  local shooting_prerequisites = {"chemical-science-pack", "logistic-science-pack", "military-science-pack", "production-science-pack"}
  append(rows, "research_cannon_shooting_speed", shooting_science,
    {"chemical-science-pack", "logistic-science-pack", "military-science-pack", "production-science-pack", "weapon-shooting-speed-5", cannon_prerequisite})
  append(rows, "research_rocket_shooting_speed", shooting_science,
    {"chemical-science-pack", "logistic-science-pack", "military-science-pack", "production-science-pack", "rocketry"})
  append(rows, "research_electric_shooting_speed", shooting_science,
    {"chemical-science-pack", "logistic-science-pack", "military-science-pack", "production-science-pack", "discharge-defense-equipment"})
  append(rows, "research_flamethrower_shooting_speed", shooting_science,
    {"chemical-science-pack", "logistic-science-pack", "military-science-pack", "production-science-pack", "flamethrower"})
  append(rows, "research_lab_productivity",
    {"automation-science-pack", "chemical-science-pack", "logistic-science-pack", "military-science-pack", "production-science-pack", "utility-science-pack"},
    {"chemical-science-pack", "logistic-science-pack", "military-science-pack", "production-science-pack", "utility-science-pack"})
  append(rows, "research_robot_battery",
    {"automation-science-pack", "chemical-science-pack", "logistic-science-pack", "production-science-pack"},
    {"chemical-science-pack", "logistic-science-pack", "production-science-pack"})
  return rows
end

local function f017()
  return {id="f017", factorio_line="0.17", numeric_cost=false, scalar_icon=false, visible_when_disabled=false,
    settings=selected(all), emitted=later_rows("tanks")}
end

local function f100()
  return {id="f100", factorio_line="1.0", numeric_cost=false, scalar_icon=false, visible_when_disabled=false,
    settings=selected(all), emitted=later_rows("tanks")}
end

local function f110()
  return {id="f110", factorio_line="1.1", numeric_cost=false, scalar_icon=false, visible_when_disabled=false,
    constant_overlay=true, settings=selected(all), emitted=later_rows("tank")}
end

function M.for_target(target)
  if target == "f013" then return numeric_target("f013", "0.13") end
  if target == "f014" then return numeric_target("f014", "0.14") end
  if target == "f015" then return f015() end
  if target == "f016" then return f016() end
  if target == "f017" then return f017() end
  if target == "f100" then return f100() end
  if target == "f110" then return f110() end
  error("MIR historical direct target is not supported: " .. tostring(target), 2)
end

function M.definition(key)
  return direct.definition(key)
end

return M
