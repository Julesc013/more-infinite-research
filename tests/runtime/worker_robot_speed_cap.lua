-- Exercises the shared native worker-speed admission and the F200
-- settings-derived V3 controller without a save or a second controller.
local cap = 10
local storage_root = {}

package.loaded["prototypes.mir.runtime.state"] = {
  bucket = function(name)
    storage_root[name] = storage_root[name] or {}
    return storage_root[name]
  end
}
package.loaded["prototypes.mir.runtime.startup_settings"] = {
  get = function(name)
    if name == "mir-max-level-worker-robots-speed" then return cap end
    return nil
  end
}
package.loaded["prototypes.mir.streams.registry"] = {
  view = function() return {} end,
  snapshot = function() return {} end
}
package.loaded["prototypes.mir.settings.defaults"] = {base_extensions = {}}
package.loaded["prototypes.mir.platform.factorio.target_line"] = {
  mod_data_supported = function() return false end
}

log = function() end
prototypes = {technology = {}}
game = {forces = {}}

local function check(value, message)
  assert(value, message)
end

local function native_tail()
  return {
    name = "worker-robots-speed-6",
    max_level = 4294967295,
    effects = {{type = "worker-robot-speed", modifier = 0.65}},
    prerequisites = {{name = "worker-robots-speed-5"}}
  }
end

local function force(index, enabled)
  local technology = {
    name = "worker-robots-speed-6",
    level = 10,
    enabled = enabled,
    visible_when_disabled = false
  }
  return {
    valid = true,
    index = index,
    name = "force-" .. tostring(index),
    technologies = {[technology.name] = technology},
    research_queue = {technology, technology},
    worker_robots_speed_modifier = 7.15
  }, technology
end

local controller = require("prototypes.mir.runtime.maximum_level_control")
check(controller.on_load == nil,
  "worker speed cap must not add an on-load mutation or subscription path")

prototypes.technology["worker-robots-speed-6"] = native_tail()
local owned_force, owned = force(1, true)
game.forces = {owned = owned_force}
controller.on_init()
check(#owned_force.research_queue == 1 and owned.enabled == true
    and owned_force.worker_robots_speed_modifier == 7.15,
  "level ten must remain enabled while the level-eleven queue entry is removed")

owned.level = 11
owned_force.worker_robots_speed_modifier = 7.15
controller.on_research_finished({research = {valid = true, force = owned_force,
  name = "worker-robots-speed-6"}})
check(owned.enabled == false and owned_force.worker_robots_speed_modifier == 7.15,
  "the first level above ten must be disabled without changing earned worker-speed bonuses")

cap = 0
controller.on_configuration_changed()
check(owned.enabled == true and owned.visible_when_disabled == false
    and owned.level == 11 and owned_force.worker_robots_speed_modifier == 7.15,
  "default zero must restore only MIR-owned disablement and retain earned levels")

cap = 10
storage_root = {}
local foreign_force, foreign = force(2, false)
foreign.level = 11
game.forces = {foreign = foreign_force}
controller.on_init()
check(foreign.enabled == false,
  "a cap must not claim enablement ownership over an already disabled native technology")
cap = 0
controller.on_configuration_changed()
check(foreign.enabled == false and foreign.visible_when_disabled == false,
  "relaxing the cap must not enable a foreign-disabled native technology")

cap = 10
storage_root = {}
prototypes.technology["worker-robots-speed-6"] = native_tail()
table.insert(prototypes.technology["worker-robots-speed-6"].effects,
  {type = "worker-robot-storage", modifier = 1})
local malformed_force, malformed = force(3, true)
malformed.level = 11
game.forces = {malformed = malformed_force}
controller.on_init()
check(malformed.enabled == true and #malformed_force.research_queue == 2
    and storage_root.maximum_level_control.managed_technologies["worker-robots-speed-6"] == nil,
  "an ambiguous native worker-speed effect binding must be ignored safely")

print("MIR-WORKER-ROBOT-SPEED-CAP-PASS")
