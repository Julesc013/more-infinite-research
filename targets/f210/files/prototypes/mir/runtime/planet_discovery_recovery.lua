local M = {}
M.requires_features = {"scripted_techs"}

local MOD_NAME = "more-infinite-research"
local FIX_VERSION = "3.2.2"
local AFFECTED_VERSIONS = {
  ["3.2.0"] = true,
  ["3.2.1"] = true
}

local function is_affected_upgrade(event)
  local changes = event and event.mod_changes
  local change = changes and changes[MOD_NAME]
  return change
    and AFFECTED_VERSIONS[tostring(change.old_version)]
    and tostring(change.new_version) == FIX_VERSION
end

local function location_exists(name)
  if type(name) ~= "string" or name == "" then return false end
  return prototypes.space_location and prototypes.space_location[name] ~= nil
end

local function researched_location_names(force)
  local names = {}
  local seen = {}
  for _, technology in pairs(force.technologies) do
    if technology.researched then
      for _, effect in pairs((technology.prototype and technology.prototype.effects) or {}) do
        local name = effect.type == "unlock-space-location" and effect.space_location or nil
        if location_exists(name) and not seen[name] then
          seen[name] = true
          table.insert(names, name)
        end
      end
    end
  end
  table.sort(names)
  return names
end

local function repair_force(force)
  local repaired = {}
  for _, name in ipairs(researched_location_names(force)) do
    if not force.is_space_location_unlocked(name) then
      force.unlock_space_location(name)
      table.insert(repaired, name)
    end
  end
  return repaired
end

function M.on_configuration_changed(event)
  if not is_affected_upgrade(event) then return end

  for _, force in pairs(game.forces) do
    local repaired = repair_force(force)
    if #repaired > 0 then
      log("[more-infinite-research] Restored researched space-location discovery for force "
        .. tostring(force.name)
        .. ": "
        .. table.concat(repaired, ", ")
        .. ".")
    end
  end
end

return M