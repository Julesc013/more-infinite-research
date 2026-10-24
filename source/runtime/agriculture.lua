-- Agricultural growth speed changes only the plant supplied by a native
-- on_tower_planted_seed event. Callers provide resolved configuration, native
-- game/event values and this feature's direct saved bucket; this module has no
-- event registration, settings/storage access, imports, or plant scans.
local M = {}

M.technology_name = "recipe-prod-research_agricultural_growth_speed-1"

local MAX_MULTIPLIER = 10

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function checked_config(config)
  if type(config) ~= "table" or type(config.enabled) ~= "boolean" then
    error("MIR agriculture config.enabled must be boolean", 3)
  end
  if not config.enabled then return false, nil end
  local percent = config.per_level_percent
  if not finite_number(percent) or percent < 0 then
    error("MIR agriculture config.per_level_percent must be a nonnegative finite number", 3)
  end
  return true, 1 + percent / 100
end

local function valid_force(force)
  return force and force.valid ~= false
end

local function completed_levels(force)
  if not valid_force(force) then return 0 end
  local technologies = force.technologies
  local technology = technologies and technologies[M.technology_name]
  local level = technology and technology.level
  if not finite_number(level) then return 0 end
  return math.max(0, math.floor(level) - 1)
end

local function multiplier_for_force(force, per_level_multiplier)
  local level = completed_levels(force)
  if level <= 0 then return 1, 0 end
  return math.min(MAX_MULTIPLIER, per_level_multiplier ^ level), level
end

local function force_name(key, force)
  local name = force and force.name
  if type(name) == "string" and name ~= "" then return name end
  return type(key) == "string" and key ~= "" and key or nil
end

-- Preserve the historical unversioned bucket's one useful field without
-- making its snapshot authoritative for application. The event always reads
-- the actual tower/plant force so research reversal takes effect immediately.
function M.refresh(game, config, state)
  local enabled, per_level_multiplier = checked_config(config)
  if not enabled then
    if type(state) == "table" then state.force_multipliers = {} end
    return state, {active = false, refreshed = false}
  end
  if game == nil or game.forces == nil then error("MIR agriculture requires game.forces", 2) end

  local next_state = type(state) == "table" and state or {}
  local snapshots = {}
  for key, force in pairs(game.forces) do
    local name = force_name(key, force)
    if name and name ~= "enemy" and name ~= "neutral" then
      local multiplier, level = multiplier_for_force(force, per_level_multiplier)
      snapshots[name] = {level = level, multiplier = multiplier}
    end
  end
  next_state.force_multipliers = snapshots
  return next_state, {active = true, refreshed = true}
end

local function read_tick_grown(plant)
  local ok, value = pcall(function() return plant.tick_grown end)
  if not ok or not finite_number(value) then return nil end
  return value
end

local function write_tick_grown(plant, value)
  local ok = pcall(function() plant.tick_grown = value end)
  return ok
end

local function event_force(event, plant)
  local tower = event.tower
  if tower and tower.valid ~= false and valid_force(tower.force) then return tower.force end
  local force = plant.force
  return valid_force(force) and force or nil
end

local function event_tick(game, event)
  local tick = event.tick
  if finite_number(tick) then return tick end
  tick = game and game.tick
  return finite_number(tick) and tick or nil
end

-- Apply the recovered native event mutation. `state` is accepted to make the
-- caller's ownership explicit but is not consulted for gameplay: the saved
-- historical force snapshot can be stale after a reversal, while the event's
-- current tower/plant force is authoritative.
function M.on_tower_planted_seed(game, config, state, event)
  local enabled, per_level_multiplier = checked_config(config)
  if not enabled then return state, {active = false, applied = false, reason = "disabled"} end
  if type(event) ~= "table" or event.plant == nil then
    return state, {active = true, applied = false, reason = "invalid-event"}
  end
  local plant = event.plant
  if plant.valid == false then return state, {active = true, applied = false, reason = "invalid-plant"} end

  local force = event_force(event, plant)
  local multiplier, level = multiplier_for_force(force, per_level_multiplier)
  if level <= 0 then return state, {active = true, applied = false, reason = "missing-research"} end
  if multiplier <= 1 then return state, {active = true, applied = false, reason = "unit-multiplier"} end

  local now = event_tick(game, event)
  if now == nil then return state, {active = true, applied = false, reason = "invalid-tick"} end
  local tick_grown = read_tick_grown(plant)
  if tick_grown == nil then return state, {active = true, applied = false, reason = "tick-grown-unreadable"} end
  local remaining = tick_grown - now
  if remaining <= 1 then return state, {active = true, applied = false, reason = "already-growing"} end

  local target = now + math.max(1, math.floor(remaining / multiplier))
  if target >= tick_grown then return state, {active = true, applied = false, reason = "no-acceleration"} end
  if not write_tick_grown(plant, target) then
    return state, {active = true, applied = false, reason = "tick-grown-write-failed"}
  end
  return state, {
    active = true, applied = true, level = level, multiplier = multiplier,
    tick_grown = target
  }
end

return M
