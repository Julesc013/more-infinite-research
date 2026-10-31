-- Guarded retirement of MIR's one spoilage contribution.  Both the active
-- Space Age body and the base-only removal bridge use this small pure helper;
-- it never owns storage or registers control callbacks.
local M = {}

local MIN_MODIFIER = 0.01
local MAX_MODIFIER = 100
local EPSILON = 0.000001

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function positive_number(value)
  return finite_number(value) and value > 0
end

function M.clamp(value)
  if value ~= value or value <= MIN_MODIFIER then return MIN_MODIFIER end
  if value >= MAX_MODIFIER then return MAX_MODIFIER end
  return value
end

function M.nearly_equal(left, right)
  return finite_number(left) and finite_number(right) and math.abs(left - right) <= EPSILON
end

local function usable_state(state)
  if type(state) ~= "table" then return nil end
  if not positive_number(state.baseline) or not positive_number(state.applied_multiplier)
    or not finite_number(state.last_applied_value) then return nil end
  return state
end

-- Retire a contribution after the caller has already read the documented
-- native property.  The direct write intentionally has the same failure
-- behaviour as active reconciliation; the removal bridge uses try_retire
-- below when that native property may no longer exist.
function M.retire(settings, current, state, reason)
  local prior = usable_state(state)
  if not prior then
    return nil, {
      active = false, restored = false, external_write_ambiguous = false,
      reason = reason
    }
  end

  local ambiguous = not M.nearly_equal(current, prior.last_applied_value)
  if not ambiguous then settings.spoil_time_modifier = M.clamp(prior.baseline) end
  return nil, {
    active = false,
    restored = not ambiguous,
    external_write_ambiguous = ambiguous,
    reason = reason
  }
end

local function unavailable(state, reason)
  return state, {
    active = false,
    restored = false,
    external_write_ambiguous = false,
    unavailable_native_property = true,
    reason = reason
  }
end

-- Space Age can be removed before this control chunk is loaded again.  In a
-- base-only stage, do not discard a valid contribution or overwrite anything
-- unless the native property is still readable and the guarded restore is
-- executable.  Retaining it lets a later re-addition reconcile from the
-- exact saved contribution.
function M.try_retire(game, state, reason)
  local readable, settings, current = pcall(function()
    local difficulty = game and game.difficulty_settings
    if difficulty == nil then return nil, nil end
    return difficulty, difficulty.spoil_time_modifier
  end)
  if not readable or settings == nil or not finite_number(current) then
    return unavailable(state, reason)
  end

  local retired, next_state, facts = pcall(M.retire, settings, current, state, reason)
  if not retired then return unavailable(state, reason) end
  return next_state, facts
end

return M
