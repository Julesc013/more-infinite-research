-- Passive repair is opt-in and host-driven. Requiring this module registers no
-- Factorio handlers; the host explicitly calls register and lifecycle hooks.
local startup_settings = require("prototypes.mir.runtime.startup_settings")
local runtime_state = require("prototypes.mir.platform.factorio.runtime_state")

local M = {}

M.setting_name = "mir-enable-passive-repair"
M.requires_features = {"scripted_techs"}
M.quiet_ticks = 600
M.repair_interval_ticks = 60
M.repair_amount = 1
M.maximum_pending = 256
M.per_tick_budget = 8

local function finite_number(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function current_tick(event)
  if event and finite_number(event.tick) then return event.tick end
  if game and finite_number(game.tick) then return game.tick end
  return 0
end

local function enabled()
  return startup_settings.get(M.setting_name) == true
end

local function state_root()
  local ok, root = pcall(runtime_state.root)
  if not ok or type(root) ~= "table" then return nil end
  return root
end

local function state(create)
  local root = state_root()
  if not root then return nil end
  local namespace = root.mir
  if type(namespace) ~= "table" then
    if not create then return nil end
    namespace = {}
    root.mir = namespace
  end
  local value = namespace.passive_repair
  if type(value) ~= "table" then
    if not create then return nil end
    value = {}
    namespace.passive_repair = value
  end
  if create then
    if type(value.queue) ~= "table" then value.queue = {} end
    if type(value.members) ~= "table" then value.members = {} end
    if type(value.scheduled) ~= "boolean" then value.scheduled = false end
  end
  return value
end

-- on_load uses this read-only path. It never creates `mir` or a repair bucket.
local function peek_state()
  return state(false)
end

local function readable_function(object, name)
  local ok, value = pcall(function() return object and object[name] end)
  return ok and type(value) == "function"
end

local function damage_event_id()
  local ok, value = pcall(function() return defines and defines.events and defines.events.on_entity_damaged end)
  return ok and value or nil
end

local damaged_entity_filters = {
  {filter = "type", type = "wall"},
  {filter = "type", type = "gate"}
}

local function host_supported()
  return readable_function(script, "on_event")
    and readable_function(script, "on_nth_tick")
    and damage_event_id() ~= nil
end

local function set_subscription(active)
  if not host_supported() then return false end
  script.on_nth_tick(M.repair_interval_ticks, active and M.on_nth_tick or nil)
  return true
end

local function schedule(data, active)
  if data.scheduled == active then return end
  data.scheduled = active
  set_subscription(active)
end

local function player_or_reciprocal_ally(force)
  if not (force and game and game.forces and game.forces.player) then return false end
  local player = game.forces.player
  if force.index == player.index then return true end
  local ok, allied = pcall(function()
    return force.get_friend(player) == true and player.get_friend(force) == true
  end)
  return ok and allied == true
end

local function entity_identity(entity)
  if not (entity and entity.valid and (entity.type == "wall" or entity.type == "gate")) then return nil end
  local id = entity.unit_number
  local force_object = entity.force
  local force = force_object and force_object.index
  local surface = entity.surface and entity.surface.index
  if not (finite_number(id) and id > 0 and finite_number(force) and finite_number(surface))
    or force_object.name == "enemy" or force_object.name == "neutral"
    or not player_or_reciprocal_ally(force_object) then return nil end
  return id, force, surface
end

local function valid_member(row)
  return type(row) == "table"
    and finite_number(row.force_index)
    and finite_number(row.surface_index)
    and finite_number(row.quiet_until)
    and finite_number(row.next_repair_tick)
end

local function entity_for(row, id)
  if not valid_member(row) then return nil end
  local entity = row.entity
  local actual_id, force_index, surface_index = entity_identity(entity)
  if actual_id ~= id or force_index ~= row.force_index or surface_index ~= row.surface_index then return nil end
  return entity
end

local function maximum_health(entity)
  local prototype = entity and entity.prototype
  if not prototype then return nil end
  local ok, value = pcall(function() return prototype.get_max_health(entity.quality) end)
  if ok and finite_number(value) and value > 0 then return value end
  return nil
end

local function incomplete(entity, maximum)
  return finite_number(entity.health) and entity.health > 0 and entity.health < maximum
end

local function clear(data)
  data.queue = {}
  data.members = {}
  schedule(data, false)
end

function M.on_entity_damaged(event)
  if not enabled() then return false end
  local entity = event and event.entity
  local id, force_index, surface_index = entity_identity(entity)
  if not id then return false end
  local maximum = maximum_health(entity)
  if not maximum or not incomplete(entity, maximum) then return false end
  local data = state(true)
  if not data then return false end

  local now = current_tick(event)
  local row = data.members[id]
  if row then
    if row.force_index ~= force_index or row.surface_index ~= surface_index then
      data.members[id] = nil
      for index, queued_id in ipairs(data.queue) do
        if queued_id == id then table.remove(data.queue, index); break end
      end
      schedule(data, #data.queue > 0)
      return false
    end
    row.quiet_until = now + M.quiet_ticks
    row.next_repair_tick = row.quiet_until
    return true
  end

  if #data.queue >= M.maximum_pending then return false end
  data.members[id] = {
    entity = entity,
    force_index = force_index,
    surface_index = surface_index,
    quiet_until = now + M.quiet_ticks,
    next_repair_tick = now + M.quiet_ticks
  }
  data.queue[#data.queue + 1] = id
  schedule(data, true)
  return true
end

function M.on_nth_tick(event)
  local data = peek_state()
  if not data or type(data.queue) ~= "table" or type(data.members) ~= "table" then return 0 end
  if not enabled() then
    clear(data)
    return 0
  end

  local now = current_tick(event)
  local processed = 0
  local budget = math.min(M.per_tick_budget, #data.queue)
  for _ = 1, budget do
    local id = table.remove(data.queue, 1)
    local row = data.members[id]
    local entity = entity_for(row, id)
    local maximum = entity and maximum_health(entity)
    if entity and maximum and incomplete(entity, maximum) then
      if now >= row.quiet_until and now >= row.next_repair_tick then
        entity.health = math.min(maximum, entity.health + M.repair_amount)
        row.next_repair_tick = now + M.repair_interval_ticks
      end
      if incomplete(entity, maximum) then
        data.queue[#data.queue + 1] = id
      else
        data.members[id] = nil
      end
    else
      data.members[id] = nil
    end
    processed = processed + 1
  end
  schedule(data, #data.queue > 0)
  return processed
end

function M.on_init(_)
  local data = peek_state()
  if data and type(data.queue) == "table" then schedule(data, enabled() and #data.queue > 0) end
end

function M.on_configuration_changed(_)
  M.register()
  local data = peek_state()
  if not data or type(data.queue) ~= "table" or type(data.members) ~= "table" then return end
  if not enabled() then
    clear(data)
  else
    schedule(data, #data.queue > 0)
  end
end

function M.on_load()
  local data = peek_state()
  if data and type(data.queue) == "table" and enabled() and #data.queue > 0 then set_subscription(true) end
end

function M.register()
  if not host_supported() then return false end
  if enabled() then
    script.on_event(defines.events.on_entity_damaged, M.on_entity_damaged, damaged_entity_filters)
  else
    script.on_event(defines.events.on_entity_damaged, nil)
  end
  return true
end

return M
