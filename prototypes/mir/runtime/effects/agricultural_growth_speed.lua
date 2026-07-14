local M = {}
local settings_resolver = require("prototypes.mir.runtime.settings_resolver")
local runtime_state = require("prototypes.mir.runtime.state")

M.technology_name = "recipe-prod-research_agricultural_growth_speed-1"
M.stream_key = "research_agricultural_growth_speed"

local PER_LEVEL = 1.01
local MAX_MULTIPLIER = 10

local function feature_enabled()
  return settings_resolver.stream_enabled(M.stream_key)
end

local function state()
  return runtime_state.bucket("agricultural_growth_speed")
end

local function completed_levels(force)
  if not (force and force.valid) then return 0 end
  local tech = force.technologies[M.technology_name]
  if not tech then return 0 end
  return math.max(0, (tech.level or 1) - 1)
end

local function multiplier_for_force(force)
  if not feature_enabled() then return 1, 0 end
  local level = completed_levels(force)
  if level <= 0 then return 1, 0 end
  return math.min(MAX_MULTIPLIER, PER_LEVEL ^ level), level
end

local function refresh_force_state(log_debug)
  local data = state()
  local enabled = feature_enabled()
  data.force_multipliers = {}
  for force_name, force in pairs(game.forces) do
    if force_name ~= "enemy" and force_name ~= "neutral" then
      local multiplier, level = multiplier_for_force(force)
      data.force_multipliers[force_name] = {
        level = level,
        multiplier = multiplier
      }
    end
  end

  if log_debug then
    log_debug("agricultural growth speed force state refreshed enabled=" .. tostring(enabled))
  end
end

local function read_tick_grown(plant)
  local ok, value = pcall(function() return plant.tick_grown end)
  if ok then return value end
  return nil
end

local function write_tick_grown(plant, value)
  local ok = pcall(function() plant.tick_grown = value end)
  return ok
end

local function accelerate_plant(plant, now, multiplier)
  if not (plant and plant.valid) then return false end
  if multiplier <= 1 then return false end

  local tick_grown = read_tick_grown(plant)
  if not tick_grown then return false end

  local remaining = tick_grown - now
  if remaining <= 1 then return false end

  local new_tick_grown = now + math.max(1, math.floor(remaining / multiplier))
  if new_tick_grown >= tick_grown then return false end

  return write_tick_grown(plant, new_tick_grown)
end

function M.on_init(_, log_debug)
  refresh_force_state(log_debug)
end

function M.on_configuration_changed(_, log_debug)
  refresh_force_state(log_debug)
end

function M.on_research_finished(_, log_debug)
  refresh_force_state(log_debug)
end

function M.on_research_reversed(_, log_debug)
  refresh_force_state(log_debug)
end

function M.on_technology_effects_reset(_, log_debug)
  refresh_force_state(log_debug)
end

function M.on_tower_planted_seed(event, log_debug)
  if not feature_enabled() then return end
  if not (event and event.plant and event.plant.valid) then return end

  local force = nil
  if event.tower and event.tower.valid then
    force = event.tower.force
  elseif event.plant.force and event.plant.force.valid then
    force = event.plant.force
  end

  local multiplier, level = multiplier_for_force(force)
  if level <= 0 or multiplier <= 1 then return end

  local now = event.tick or game.tick
  if accelerate_plant(event.plant, now, multiplier) and log_debug then
    log_debug("agricultural growth speed applied force=" .. tostring(force and force.name or "unknown")
      .. " level=" .. tostring(level)
      .. " multiplier=" .. tostring(multiplier))
  end
end

return M
