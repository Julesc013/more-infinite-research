local PREFIX = "[MIR5_MIGRATION_ORIGIN_EARLY_OFFSET] "
local FOREIGN = "mir5-migration-origin-f200-100-foreign"
local DETACHED = "mir5-migration-origin-f200-100-detached"

local function value(force)
  if force == nil or force.valid == false then return "null" end
  local offset = force.manual_mining_speed_modifier
  if type(offset) ~= "number" then return "null" end
  return string.format("%.17g", offset)
end

local function observe(event)
  local forces = game.forces
  log(PREFIX .. "{\"event\":\"" .. event .. "\",\"player\":" .. value(forces.player)
    .. ",\"foreign\":" .. value(forces[FOREIGN])
    .. ",\"detached\":" .. value(forces[DETACHED]) .. "}")
end

script.on_init(function() observe("init") end)
script.on_configuration_changed(function() observe("configuration-changed") end)
