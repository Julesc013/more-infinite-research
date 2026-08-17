local streams = {
  {key = "research_processing_unit", owner = "processing-unit-productivity"},
  {key = "research_plastic", owner = "plastic-bar-productivity"},
  {key = "research_low_density_structure", owner = "low-density-structure-productivity"},
  {key = "research_rocket_fuel", owner = "rocket-fuel-productivity"},
  {key = "research_steel", owner = "steel-plate-productivity"}
}

local function fail(message)
  error("MIR native-owner cap-transition validation failed: " .. message)
end

local function affected(name)
  for _, row in ipairs(streams) do
    if row.owner == name then return true end
  end
  return false
end

script.on_init(function()
  local force = game.forces.player
  force.research_all_technologies()
  local queue = {}
  local levels = {}
  for _, row in ipairs(streams) do
    local technology = force.technologies[row.owner]
    if not technology then fail("missing native owner " .. row.owner) end
    technology.level = 8
    levels[row.owner] = technology.level
    table.insert(queue, technology)
  end
  force.research_queue = queue
  if not force.current_research or not affected(force.current_research.name) then
    fail("could not establish affected current research before lowering the cap")
  end
  if #force.research_queue ~= #streams then
    fail("could not establish the five-owner research queue before lowering the cap")
  end
  for _, row in ipairs(streams) do
    if force.technologies[row.owner].level ~= 8 then
      fail(row.owner .. " did not retain source level 8 before lowering the cap")
    end
  end
  force.research_progress = 0.42
  storage.mir_native_owner_cap_transition = {
    levels = levels,
    current = force.current_research.name,
    progress = force.research_progress
  }
  log("[mir-fixture] native-owner above-cap transition source prepared current="
    .. force.current_research.name .. " queue=" .. tostring(#force.research_queue))
end)

script.on_configuration_changed(function()
  storage.mir_native_owner_cap_transition_pending = true
end)

script.on_event(defines.events.on_tick, function()
  if not storage.mir_native_owner_cap_transition_pending then return end
  storage.mir_native_owner_cap_transition_pending = nil
  local state = storage.mir_native_owner_cap_transition
  if not state then fail("source transition state did not survive configuration change") end
  local force = game.forces.player
  for _, row in ipairs(streams) do
    local technology = force.technologies[row.owner]
    if not technology then fail("missing native owner after configuration change " .. row.owner) end
    if technology.prototype.max_level < 4294967295 then
      fail(row.owner .. " final runtime prototype maximum was "
        .. tostring(technology.prototype.max_level) .. ", expected infinite for lossless capping")
    end
    if technology.level ~= state.levels[row.owner] then
      fail(row.owner .. " completed level changed while lowering the cap; before="
        .. tostring(state.levels[row.owner]) .. " after=" .. tostring(technology.level))
    end
    if technology.enabled then
      fail(row.owner .. " remained enabled above the lowered cap")
    end
  end

  if force.current_research and affected(force.current_research.name) then
    fail("invalid current research survived lowered cap: " .. force.current_research.name)
  end
  for _, technology in ipairs(force.research_queue) do
    if affected(technology.name) then
      fail("invalid queued research survived lowered cap: " .. technology.name)
    end
  end
  log("[mir-fixture] native-owner lowered cap retained completed levels and removed invalid current/queued research")
end)
