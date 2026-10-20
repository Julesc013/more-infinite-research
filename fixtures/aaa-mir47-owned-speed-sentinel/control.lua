local interface_name = "aaa-mir47-owned-speed-sentinel"
local source_mir_version = "4.6.21000"
local target_mir_version = "4.7.21000"
local owned_delta = 0.125
local epsilon = 0.000001

local function fail(message)
  error("MIR owned speed sentinel failed: " .. message, 2)
end

local function close(left, right)
  return type(left) == "number" and type(right) == "number"
    and math.abs(left - right) <= epsilon
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local function current_state()
  storage.mir47_owned_speed_sentinel = storage.mir47_owned_speed_sentinel or {
    schema = 1,
    phase = "source",
    records = {},
    configuration_changed_events = 0
  }
  return storage.mir47_owned_speed_sentinel
end

local function force_for(name)
  local force = type(name) == "string" and game.forces[name] or nil
  if not force then fail("unknown force: " .. tostring(name)) end
  return force
end

local function records_in_order(state)
  local names = {}
  for name in pairs(state.records) do names[#names + 1] = name end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do out[#out + 1] = state.records[name] end
  return out
end

local function assert_source_identity()
  if script.active_mods["more-infinite-research"] ~= source_mir_version then
    fail("source MIR identity differs: " .. tostring(script.active_mods["more-infinite-research"]))
  end
end

local function capture(force_name)
  assert_source_identity()
  local state = current_state()
  if state.phase ~= "source" then fail("source capture is closed") end
  if state.records[force_name] then fail("force is already captured: " .. force_name) end
  local force = force_for(force_name)
  local baseline = force.character_running_speed_modifier
  if type(baseline) ~= "number" then fail("force speed is unavailable: " .. force_name) end
  force.character_running_speed_modifier = baseline + owned_delta
  local source_total = force.character_running_speed_modifier
  if not close(source_total, baseline + owned_delta) then
    fail("source contribution was not applied exactly: " .. force_name)
  end
  local record = {
    force_name = force_name,
    force_index = force.index,
    baseline = baseline,
    delta = owned_delta,
    source_total = source_total
  }
  state.records[force_name] = record
  log("[mir-owned-speed-sentinel] source-captured force=" .. force_name
    .. " baseline=" .. tostring(baseline) .. " delta=" .. tostring(owned_delta))
  return copy(record)
end

local function seal_source(force_names)
  assert_source_identity()
  local state = current_state()
  if state.phase ~= "source" then fail("source capture is already sealed") end
  if type(force_names) ~= "table" or #force_names == 0 then fail("expected source force list is invalid") end
  local expected = {}
  for _, name in ipairs(force_names) do
    if type(name) ~= "string" or expected[name] then fail("source force list is not unique") end
    expected[name] = true
  end
  local count = 0
  for name in pairs(state.records) do
    count = count + 1
    if not expected[name] then fail("unexpected captured source force: " .. name) end
  end
  if count ~= #force_names then fail("source force capture is incomplete") end
  state.phase = "captured"
  state.source_mir_version = source_mir_version
  state.target_mir_version = nil
  log("[mir-owned-speed-sentinel] source-sealed forces=" .. tostring(count))
  return copy(state)
end

local function snapshot()
  return copy(current_state())
end

remote.add_interface(interface_name, {
  capture = capture,
  seal_source = seal_source,
  snapshot = snapshot
})

script.on_configuration_changed(function()
  local state = current_state()
  state.configuration_changed_events = (state.configuration_changed_events or 0) + 1
  if state.phase == "restored" then
    for _, record in ipairs(records_in_order(state)) do
      local current = force_for(record.force_name).character_running_speed_modifier
      if not close(current, record.restored_total) then
        fail("owned contribution changed after restoration for " .. record.force_name)
      end
    end
    log("[mir-owned-speed-sentinel] target-repeat-verified event="
      .. tostring(state.configuration_changed_events))
    return
  end
  if state.phase ~= "captured" then fail("target transition lacks a sealed source record") end
  if script.active_mods["more-infinite-research"] ~= target_mir_version then
    fail("target MIR identity differs: " .. tostring(script.active_mods["more-infinite-research"]))
  end

  -- Validate every force before writing any. The companion never assigns an
  -- aggregate total: it adds only its recorded contribution to the exact
  -- source baseline that the engine exposed after prototype migration.
  for _, record in ipairs(records_in_order(state)) do
    local force = force_for(record.force_name)
    if force.index ~= record.force_index then fail("force identity changed: " .. record.force_name) end
    local current = force.character_running_speed_modifier
    if close(current, record.source_total) then
      fail("engine retained the owned contribution; refusing to add it twice for " .. record.force_name)
    end
    if not close(current, record.baseline) then
      fail("target baseline differs; refusing to invent prior state for " .. record.force_name)
    end
    record.before_target = current
  end
  for _, record in ipairs(records_in_order(state)) do
    local force = force_for(record.force_name)
    force.character_running_speed_modifier = force.character_running_speed_modifier + record.delta
    if not close(force.character_running_speed_modifier, record.source_total) then
      fail("target contribution was not restored exactly for " .. record.force_name)
    end
    record.restored_total = force.character_running_speed_modifier
  end
  state.phase = "restored"
  state.target_mir_version = target_mir_version
  log("[mir-owned-speed-sentinel] target-restored event="
    .. tostring(state.configuration_changed_events) .. " forces=" .. tostring(#records_in_order(state)))
end)
