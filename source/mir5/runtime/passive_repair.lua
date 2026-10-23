-- Passive repair is an opt-in, event-driven wall/gate repair queue. The
-- bootstrap owns Factorio registration; this module receives every native
-- object, resolved config and direct saved bucket explicitly.
local M = {}

M.quiet_ticks = 600
M.repair_interval_ticks = 60
M.repair_amount = 1
M.maximum_pending = 256
M.per_tick_budget = 8

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function positive_integer(value)
  return finite_number(value) and value > 0 and value == math.floor(value)
end

local function checked_config(config)
  if type(config) ~= "table" or type(config.enabled) ~= "boolean" then
    error("MIR passive repair config.enabled must be boolean", 3)
  end
  return config.enabled
end

local function tick_for(game, event)
  local tick = event and event.tick
  if finite_number(tick) then return tick end
  tick = game and game.tick
  return finite_number(tick) and tick or nil
end

local function empty_state(state)
  if type(state) ~= "table" then return state end
  state.queue, state.members, state.scheduled = {}, {}, false
  return state
end

-- The historical bucket had no schema: queue is ordered unit numbers, members
-- maps each number to its live LuaEntity reference and timing/identity fields,
-- and scheduled mirrors the conditional 60-tick subscription.
local function ensure_state(state)
  local value = type(state) == "table" and state or {}
  if type(value.queue) ~= "table" then value.queue = {} end
  if type(value.members) ~= "table" then value.members = {} end
  if type(value.scheduled) ~= "boolean" then value.scheduled = false end
  return value
end

local function valid_force(force)
  return force and force.valid ~= false
end

local function is_player_or_reciprocal_friend(game, force)
  local player = game and game.forces and game.forces.player
  if not valid_force(force) or not valid_force(player) then return false end
  if force.index == player.index then return true end
  local ok, forward, reverse = pcall(function()
    return force.get_friend(player), player.get_friend(force)
  end)
  return ok and forward == true and reverse == true
end

local function entity_identity(game, entity)
  if not entity or entity.valid ~= true or (entity.type ~= "wall" and entity.type ~= "gate") then return nil end
  local ok, id, force, surface = pcall(function()
    return entity.unit_number, entity.force, entity.surface
  end)
  if not ok or not positive_integer(id) or not valid_force(force) or not surface
    or not positive_integer(force.index) or not positive_integer(surface.index)
    or force.name == "enemy" or force.name == "neutral"
    or not is_player_or_reciprocal_friend(game, force) then return nil end
  return id, force.index, surface.index
end

local function maximum_health(entity)
  local ok, value = pcall(function() return entity.max_health end)
  return ok and finite_number(value) and value > 0 and value or nil
end

local function current_health(entity)
  local ok, value = pcall(function() return entity.health end)
  return ok and finite_number(value) and value or nil
end

local function incomplete(entity, maximum)
  local health = current_health(entity)
  return health and health > 0 and health < maximum, health
end

local function valid_member(row)
  return type(row) == "table" and positive_integer(row.force_index)
    and positive_integer(row.surface_index) and finite_number(row.quiet_until)
    and finite_number(row.next_repair_tick)
end

local function entity_for(game, row, id)
  if not valid_member(row) then return nil end
  local entity = row.entity
  local actual_id, force_index, surface_index = entity_identity(game, entity)
  if actual_id ~= id or force_index ~= row.force_index or surface_index ~= row.surface_index then return nil end
  return entity
end

local function remove_queued_id(queue, id)
  for index, queued_id in ipairs(queue) do
    if queued_id == id then table.remove(queue, index); return end
  end
end

local function schedule_facts(state, facts)
  local needs_schedule = #state.queue > 0
  state.scheduled = needs_schedule
  facts.needs_schedule = needs_schedule
  return state, facts
end

local function pending(state)
  return type(state) == "table" and type(state.queue) == "table" and #state.queue > 0
end

-- An explicit configuration boundary clears the old queue while disabled.
-- No state is allocated for a disabled feature that has no historical bucket.
function M.reconcile(config, state)
  local enabled = checked_config(config)
  if not enabled then
    return empty_state(state), {active = false, needs_schedule = false, cleared = type(state) == "table"}
  end
  if type(state) ~= "table" then return nil, {active = true, needs_schedule = false} end
  local value = ensure_state(state)
  return schedule_facts(value, {active = true, cleared = false})
end

-- Read-only load decision for the registration owner. It deliberately does
-- not normalize or create state, because on_load must not mutate save data.
function M.on_load(config, state)
  local enabled = checked_config(config)
  local queued = type(state) == "table" and type(state.queue) == "table" and #state.queue > 0
  return {active = enabled, needs_schedule = enabled and queued}
end

function M.on_entity_damaged(game, config, state, event)
  local enabled = checked_config(config)
  if not enabled then
    return empty_state(state), {active = false, accepted = false, needs_schedule = false}
  end
  local entity = event and event.entity
  local id, force_index, surface_index = entity_identity(game, entity)
  if not id then return state, {active = true, accepted = false, needs_schedule = pending(state)} end
  local maximum = maximum_health(entity)
  local damaged = maximum and incomplete(entity, maximum)
  if not damaged then return state, {active = true, accepted = false, needs_schedule = pending(state)} end
  local now = tick_for(game, event)
  if now == nil then return state, {active = true, accepted = false, needs_schedule = pending(state)} end

  local value = ensure_state(state)
  local row = value.members[id]
  if row then
    if row.force_index ~= force_index or row.surface_index ~= surface_index then
      value.members[id] = nil
      remove_queued_id(value.queue, id)
      return schedule_facts(value, {active = true, accepted = false, removed_stale = true})
    end
    row.quiet_until, row.next_repair_tick = now + M.quiet_ticks, now + M.quiet_ticks
    return schedule_facts(value, {active = true, accepted = true, postponed = true})
  end

  if #value.queue >= M.maximum_pending then
    return schedule_facts(value, {active = true, accepted = false, capacity_reached = true})
  end
  value.members[id] = {
    entity = entity,
    force_index = force_index,
    surface_index = surface_index,
    quiet_until = now + M.quiet_ticks,
    next_repair_tick = now + M.quiet_ticks
  }
  value.queue[#value.queue + 1] = id
  return schedule_facts(value, {active = true, accepted = true, postponed = false})
end

function M.on_nth_tick(game, config, state, event)
  local enabled = checked_config(config)
  if not enabled then
    return empty_state(state), {active = false, processed = 0, repaired = 0, needs_schedule = false}
  end
  if type(state) ~= "table" or type(state.queue) ~= "table" or type(state.members) ~= "table" then
    return state, {active = true, processed = 0, repaired = 0, needs_schedule = false}
  end
  local now = tick_for(game, event)
  if now == nil then return schedule_facts(state, {active = true, processed = 0, repaired = 0}) end

  local processed, repaired, dropped = 0, 0, 0
  local budget = math.min(M.per_tick_budget, #state.queue)
  for _ = 1, budget do
    local id = table.remove(state.queue, 1)
    local row = state.members[id]
    local entity = entity_for(game, row, id)
    local maximum = entity and maximum_health(entity)
    local unfinished, health = false, nil
    if entity and maximum then unfinished, health = incomplete(entity, maximum) end
    if entity and maximum and unfinished then
      if now >= row.quiet_until and now >= row.next_repair_tick then
        local target = math.min(maximum, health + M.repair_amount)
        local wrote = pcall(function() entity.health = target end)
        if wrote then
          repaired = repaired + 1
          row.next_repair_tick = now + M.repair_interval_ticks
        else
          entity = nil
        end
        if wrote then unfinished = incomplete(entity, maximum) end
      end
      if entity and unfinished then
        state.queue[#state.queue + 1] = id
      else
        state.members[id] = nil
        if not entity then dropped = dropped + 1 end
      end
    else
      state.members[id] = nil
      dropped = dropped + 1
    end
    processed = processed + 1
  end
  return schedule_facts(state, {
    active = true, processed = processed, repaired = repaired, dropped = dropped
  })
end

return M
