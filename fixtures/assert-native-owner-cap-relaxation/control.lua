local technology_name = "processing-unit-productivity"

local function fail(message)
  error("MIR native-owner cap-relaxation validation failed: " .. message)
end

script.on_init(function()
  local force = game.forces.player
  force.research_all_technologies()
  local technology = force.technologies[technology_name]
  technology.level = 3
  force.research_queue = {technology}
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("could not establish valid current research below the initial cap")
  end
  force.research_progress = 0.42
  storage.mir_native_owner_cap_relaxation = {
    level = technology.level,
    progress = force.research_progress
  }
end)

script.on_configuration_changed(function()
  storage.mir_native_owner_cap_relaxation_pending = true
end)

script.on_event(defines.events.on_tick, function()
  if not storage.mir_native_owner_cap_relaxation_pending then return end
  storage.mir_native_owner_cap_relaxation_pending = nil
  local force = game.forces.player
  local technology = force.technologies[technology_name]
  local before = storage.mir_native_owner_cap_relaxation
  if technology.level ~= before.level then fail("valid current research level changed") end
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("valid current research was cancelled while relaxing the cap")
  end
  if math.abs(force.research_progress - before.progress) > 0.0000001 then
    fail("valid fractional progress changed while relaxing the cap")
  end
  if not technology.enabled then fail("technology remained disabled after relaxing the cap") end

  force.research_queue = nil
  if force.current_research then force.cancel_current_research() end
  technology.level = 6
  if not force.add_research(technology) then
    fail("a level above the old cap did not become researchable")
  end
  local changed = settings.startup["ips-max-level-research_processing_unit"].value
  log("[mir-fixture] native-owner relaxed cap retained valid progress and restored future levels changed="
    .. tostring(changed))
end)
