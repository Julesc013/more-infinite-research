-- Spoilage preservation owns only MIR's contribution to the one global
-- LuaDifficultySettings.spoil_time_modifier. The caller supplies the native
-- game object, resolved settings and this module's saved bucket explicitly;
-- this module does not register events, read settings/storage, or import a
-- former runtime implementation.
local contribution = require("runtime.spoilage_contribution")
local M = {}

M.technology_name = "recipe-prod-research_spoilage_preservation-1"

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function positive_number(value)
  return finite_number(value) and value > 0
end

local function modifier(game)
  local settings = game and game.difficulty_settings
  local value = settings and settings.spoil_time_modifier
  if not finite_number(value) then error("MIR spoilage requires a finite spoil_time_modifier", 3) end
  return settings, value
end

local function checked_config(config)
  if type(config) ~= "table" or type(config.enabled) ~= "boolean" then
    error("MIR spoilage config.enabled must be boolean", 3)
  end
  if not config.enabled then return false, nil end
  local percent = config.per_level_percent
  if not finite_number(percent) or percent < 0 then
    error("MIR spoilage config.per_level_percent must be a nonnegative finite number", 3)
  end
  return true, 1 + percent / 100
end

local function eligible_force(force)
  return force and force.valid ~= false and force.name ~= "enemy" and force.name ~= "neutral"
end

local function completed_levels(force)
  if not eligible_force(force) then return 0 end
  local technologies = force.technologies
  local technology = technologies and technologies[M.technology_name]
  local level = technology and technology.level
  if not finite_number(level) then return 0 end
  return math.max(0, math.floor(level) - 1)
end

-- The historical runtime considered the feature present when any force had
-- the technology, but only non-enemy/non-neutral forces contribute levels.
local function force_facts(game)
  if game == nil or game.forces == nil then error("MIR spoilage requires game.forces", 3) end
  local highest, present = 0, false
  for _, force in pairs(game.forces) do
    local technologies = force and force.technologies
    if technologies and technologies[M.technology_name] ~= nil then present = true end
    local completed = completed_levels(force)
    if completed > highest then highest = completed end
  end
  return highest, present
end

local function inactive(settings, current, state, reason)
  return contribution.retire(settings, current, state, reason)
end

-- Reconcile the single global spoilage contribution.
--
-- `game` is a documented game-available LuaGameScript-shaped input with
-- `forces` and `difficulty_settings.spoil_time_modifier`. `config` is a plain
-- resolved table `{enabled = boolean, per_level_percent = nonnegative number}`.
-- `state` is this feature's direct durable bucket, or nil. The result is
-- `(next_state, facts)`: callers store `next_state` only when non-nil and may
-- use `facts.active` to omit research/config callbacks while inactive.
--
-- `external_write_ambiguous` means that the observed global modifier changed
-- since MIR's last write. Rebase preserves the observed aggregate through
-- MIR's previous multiplier, but cannot identify or separate foreign writers.
function M.reconcile(game, config, state)
  local settings, current = modifier(game)
  local enabled, per_level_multiplier = checked_config(config)
  if not enabled then return inactive(settings, current, state, "disabled") end

  local level, present = force_facts(game)
  if not present then return inactive(settings, current, state, "missing-technology") end

  local next_state = state
  if type(next_state) ~= "table" or not positive_number(next_state.baseline)
    or not positive_number(next_state.applied_multiplier)
    or not finite_number(next_state.last_applied_value) then
    next_state = nil
  end
  local ambiguous = false
  if next_state then
    if not contribution.nearly_equal(current, next_state.last_applied_value) then
      -- This is a best-effort aggregate rebase. It deliberately does not
      -- claim ownership of an independent writer's contribution.
      next_state.baseline = contribution.clamp(current / next_state.applied_multiplier)
      ambiguous = true
    end
  else
    next_state = {baseline = contribution.clamp(current)}
  end

  local target = contribution.clamp(next_state.baseline * (per_level_multiplier ^ level))
  settings.spoil_time_modifier = target
  next_state.effective_level = level
  next_state.applied_multiplier = next_state.baseline > 0 and target / next_state.baseline or 1
  next_state.last_applied_value = target

  return next_state, {
    active = true,
    restored = false,
    external_write_ambiguous = ambiguous,
    effective_level = level,
    applied_multiplier = next_state.applied_multiplier,
    value = target
  }
end

return M
