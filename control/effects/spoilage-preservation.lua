local M = {}

M.technology_name = "recipe-prod-research_spoilage_preservation-1"
M.setting_name = "ips-enable-research_spoilage_preservation"

local MIN_MODIFIER = 0.01
local MAX_MODIFIER = 100
local PER_LEVEL = 1.01
local EPSILON = 0.000001

local function feature_enabled()
  local setting = settings.startup[M.setting_name]
  return setting and setting.value == true
end

local function state()
  storage.mir = storage.mir or {}
  storage.mir.spoilage_preservation = storage.mir.spoilage_preservation or {}
  return storage.mir.spoilage_preservation
end

local function clamp(value)
  if value < MIN_MODIFIER then return MIN_MODIFIER end
  if value > MAX_MODIFIER then return MAX_MODIFIER end
  return value
end

local function nearly_equal(a, b)
  return math.abs((a or 0) - (b or 0)) <= EPSILON
end

local function completed_levels(force)
  if not (force and force.valid) then return 0 end
  local tech = force.technologies[M.technology_name]
  if not tech then return 0 end
  return math.max(0, (tech.level or 1) - 1)
end

local function effective_level()
  local highest = 0
  for force_name, force in pairs(game.forces) do
    if force_name ~= "enemy" and force_name ~= "neutral" then
      highest = math.max(highest, completed_levels(force))
    end
  end
  return highest
end

local function technology_exists_for_any_force()
  for _, force in pairs(game.forces) do
    if force.technologies[M.technology_name] then return true end
  end
  return false
end

local function capture_or_rebase_baseline(data)
  local current = game.difficulty_settings.spoil_time_modifier
  if not data.baseline then
    data.baseline = current
    data.applied_multiplier = 1
    data.last_applied_value = current
    return
  end

  if data.last_applied_value and not nearly_equal(current, data.last_applied_value) then
    local previous_multiplier = data.applied_multiplier or 1
    if previous_multiplier <= 0 then previous_multiplier = 1 end
    data.baseline = clamp(current / previous_multiplier)
  end
end

local function restore(data, log_debug, reason)
  if not data.baseline then return end

  local current = game.difficulty_settings.spoil_time_modifier
  if not data.last_applied_value or nearly_equal(current, data.last_applied_value) then
    game.difficulty_settings.spoil_time_modifier = clamp(data.baseline)
    current = game.difficulty_settings.spoil_time_modifier
  else
    data.baseline = current
  end

  data.applied_multiplier = 1
  data.last_applied_value = current
  if log_debug then log_debug("spoilage preservation restored or stopped applying: " .. tostring(reason or "unknown")) end
end

local function apply(log_debug)
  local data = state()
  if not feature_enabled() or not technology_exists_for_any_force() then
    restore(data, log_debug, "disabled_or_missing_technology")
    return
  end

  capture_or_rebase_baseline(data)

  local level = effective_level()
  local multiplier = math.min(MAX_MODIFIER, PER_LEVEL ^ level)
  local target = clamp((data.baseline or 1) * multiplier)
  game.difficulty_settings.spoil_time_modifier = target

  data.effective_level = level
  data.applied_multiplier = multiplier
  data.last_applied_value = target

  if log_debug then
    log_debug("spoilage preservation applied level=" .. tostring(level)
      .. " multiplier=" .. tostring(multiplier)
      .. " value=" .. tostring(target))
  end
end

function M.on_init(_, log_debug)
  apply(log_debug)
end

function M.on_configuration_changed(_, log_debug)
  apply(log_debug)
end

function M.on_research_finished(_, log_debug)
  apply(log_debug)
end

function M.on_research_reversed(_, log_debug)
  apply(log_debug)
end

function M.on_technology_effects_reset(_, log_debug)
  apply(log_debug)
end

return M
