-- One-time recovery for the MIR3.2.0/3.2.1 Space Age discovery defect.
-- It deliberately has no storage: native researched effects remain the only
-- authority, and a repeat configuration event is naturally idempotent.
local target = require("platform.target")

local M = {}

local MOD_NAME = "more-infinite-research"
local AFFECTED_ORIGINS = {
  ["3.2.0"] = true,
  ["3.2.1"] = true,
}

local function iterable_mapping(value)
  local value_type = type(value)
  return value_type == "table" or value_type == "userdata"
end

local function exact_upgrade(event)
  if target.id ~= "f210" or type(target.distribution_version) ~= "string"
      or target.distribution_version == "" then
    return false
  end
  local changes = event and event.mod_changes
  local change = type(changes) == "table" and changes[MOD_NAME] or nil
  return type(change) == "table"
    and AFFECTED_ORIGINS[change.old_version] == true
    and change.new_version == target.distribution_version
end

local function ordered_forces()
  local forces = game and game.forces
  if not iterable_mapping(forces) then return {} end
  local ordered = {}
  for _, force in pairs(forces) do
    if force and force.valid ~= false and type(force.name) == "string" then
      ordered[#ordered + 1] = force
    end
  end
  table.sort(ordered, function(left, right) return left.name < right.name end)
  return ordered
end

local function researched_location_names(force, locations)
  local technologies = force and force.technologies
  if not iterable_mapping(technologies) or not iterable_mapping(locations) then return {} end
  local names, seen = {}, {}
  for _, technology in pairs(technologies) do
    local prototype = technology and technology.researched == true and technology.prototype or nil
    local effects = prototype and prototype.effects or nil
    if type(effects) == "table" then
      for _, effect in pairs(effects) do
        local effect_type = type(effect) == "table" and effect.type or nil
        local location = type(effect) == "table" and effect.space_location or nil
        if effect_type == "unlock-space-location"
            and type(location) == "string" and location ~= ""
            and locations[location] ~= nil and not seen[location] then
          seen[location] = true
          names[#names + 1] = location
        end
      end
    end
  end
  table.sort(names)
  return names
end

local function repair_force(force, locations)
  if type(force.is_space_location_unlocked) ~= "function"
      or type(force.unlock_space_location) ~= "function" then
    return 0
  end
  local repaired = 0
  for _, location in ipairs(researched_location_names(force, locations)) do
    if force.is_space_location_unlocked(location) ~= true then
      force.unlock_space_location(location)
      repaired = repaired + 1
    end
  end
  return repaired
end

-- Root composes this after other lifecycle modifiers. It is intentionally
-- called only from its on_configuration_changed callback, never on init/load.
function M.apply(event)
  if not exact_upgrade(event) then return 0 end
  local locations = prototypes and prototypes.space_location
  if not iterable_mapping(locations) then return 0 end
  local repaired = 0
  for _, force in ipairs(ordered_forces()) do
    repaired = repaired + repair_force(force, locations)
  end
  return repaired
end

M.on_configuration_changed = M.apply

return M
