local technology_name = "research-speed-8"

local function fail(message)
  error("MIR base-continuation cap-transition validation failed: " .. message)
end

script.on_init(function()
  local force = game.forces.player
  force.research_all_technologies()
  local technology = force.technologies[technology_name]
  if not technology then fail("missing generated research-speed continuation") end
  technology.level = 10
  force.research_queue = {technology}
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("could not establish current research before lowering cap")
  end
  force.research_progress = 0.42
  storage.mir_base_continuation_cap_transition = {level = technology.level}
end)

script.on_configuration_changed(function()
  storage.mir_base_continuation_cap_transition_pending = true
end)

script.on_event(defines.events.on_tick, function()
  if not storage.mir_base_continuation_cap_transition_pending then return end
  storage.mir_base_continuation_cap_transition_pending = nil
  local force = game.forces.player
  local technology = force.technologies[technology_name]
  if not technology then fail("continuation disappeared after lowering cap below its first level") end
  if technology.prototype.max_level < 4294967295 then fail("prototype became finite") end
  if technology.level ~= storage.mir_base_continuation_cap_transition.level then
    fail("completed levels changed while lowering cap")
  end
  if technology.enabled then fail("technology remained enabled above lowered cap") end
  if force.current_research and force.current_research.name == technology_name then
    fail("invalid current research survived lowered cap")
  end
  for _, queued in ipairs(force.research_queue) do
    if queued.name == technology_name then fail("invalid queued research survived lowered cap") end
  end
  log("[mir-fixture] base continuation survived a cap below its first level without losing completed research")
end)
