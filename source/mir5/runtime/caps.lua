-- Absolute-cap reconciliation for already-admitted native technologies.
--
-- The caller owns durable state and passes it explicitly as:
--   owned_disabled[force.index][technology_name] = {
--     disabled = true,
--     visible_when_disabled = false
--   }
-- Each field records a state this module actually changed. `disabled` is the
-- sole authority for re-enabling a technology later; visibility can be owned
-- independently for a technology that was already disabled by another mod.
-- This module deliberately has no settings, event, prototype, or Generator
-- dependency.  The caller supplies a small limits map where 0 means unlimited.
local M = {}

local function positive_integer(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value > 0 and value == math.floor(value)
end

local function cap(value)
  if value == 0 then return 0 end
  if positive_integer(value) then return value end
  return false
end

local function checked_limits(limits)
  if type(limits) ~= "table" then error("MIR caps limits must be a table", 3) end
  local result = {}
  for name, value in pairs(limits) do
    if type(name) ~= "string" or name == "" then
      error("MIR caps limits must use nonempty technology names", 3)
    end
    local value_cap = cap(value)
    if value_cap == false then
      error("MIR caps limits must be nonnegative integers", 3)
    end
    result[name] = value_cap
  end
  return result
end

local function valid_level(technology)
  return technology and positive_integer(technology.level) and technology.level or nil
end

local function filter_queue(force, limits)
  local queue = force.research_queue
  local current = force.current_research
  local current_name = current and current.name or nil
  local current_limit = current_name and limits[current_name]
  local current_level = current_name and force.technologies
    and valid_level(force.technologies[current_name]) or nil
  local current_over_cap = current_limit and current_limit > 0
    and current_level and current_level > current_limit
  if queue == nil then return false, nil, current_over_cap and current_name or nil end

  local next_level, filtered, removed = {}, {}, 0
  for _, queued in ipairs(queue) do
    local name = queued and queued.name
    local limit = name and limits[name]
    local technology = name and force.technologies and force.technologies[name]
    local level = name and (next_level[name] or valid_level(technology)) or nil

    if limit and limit > 0 and level and level > limit then
      removed = removed + 1
    else
      filtered[#filtered + 1] = queued
      if limit and limit > 0 and level then next_level[name] = level + 1 end
    end
  end

  if removed == 0 then return false, nil, current_over_cap and current_name or nil end

  -- Factorio's queue setter owns current-research cancellation when the
  -- current entry was removed.  Reapply progress only when that exact current
  -- technology remains current, so valid fractional progress is preserved and
  -- removed research does not leak progress into another queue entry.
  local progress = current and force.research_progress or nil
  force.research_queue = filtered
  local retained = force.current_research
  if current_name and retained and retained.name == current_name and progress ~= nil then
    force.research_progress = progress
  end
  local current_retained = current_name and retained and retained.name == current_name
  local removed_current = nil
  if current_name and not current_retained then removed_current = current_name end
  local unresolved_current = nil
  if current_over_cap and current_retained then unresolved_current = current_name end
  return true, removed_current, unresolved_current
end

local function ensure_record(owned_disabled, force_index, owned, name)
  owned = owned or {}
  local record = owned[name]
  if type(record) ~= "table" then
    record = {}
    owned[name] = record
  end
  owned_disabled[force_index] = owned
  return owned, record
end

-- Reconcile one force against admitted absolute caps.
--
-- `limits` maps technology names to nonnegative integer caps.  A zero cap is
-- unlimited. `owned_disabled` is a caller-owned per-force map.  The function
-- never writes level or researched, and only rewrites research_queue when it
-- removes an above-cap entry.  It returns the ownership map and a compact
-- result for event owners that want diagnostics. `unresolved_current` exposes
-- an over-cap current technology that the supplied queue did not remove;
-- callers must not guess a different native cancellation API from this module.
function M.reconcile(force, limits, owned_disabled)
  local caps = checked_limits(limits)
  if type(owned_disabled) ~= "table" then
    error("MIR caps owned_disabled must be a table", 2)
  end
  if not force or force.valid == false or not force.technologies then
    return owned_disabled, {queue_changed = false, removed_current = nil, unresolved_current = nil}
  end
  if force.index == nil then error("MIR caps force must have an index", 2) end

  local queue_changed, removed_current, unresolved_current = filter_queue(force, caps)
  local owned = owned_disabled[force.index]

  for name, limit in pairs(caps) do
    local technology = force.technologies[name]
    local level = valid_level(technology)
    if technology and limit > 0 and level and level > limit then
      local record = owned and owned[name]
      if technology.visible_when_disabled ~= true then
        owned, record = ensure_record(owned_disabled, force.index, owned, name)
        if record.visible_when_disabled == nil then
          record.visible_when_disabled = technology.visible_when_disabled == true
        end
        technology.visible_when_disabled = true
      end
      if technology.enabled then
        owned, record = ensure_record(owned_disabled, force.index, owned, name)
        record.disabled = true
        technology.enabled = false
      end
    elseif technology and owned and type(owned[name]) == "table" then
      local record = owned[name]
      -- An explicit MIR record proves this module performed the prior
      -- enabled-to-disabled transition. Pre-disabled foreign technologies
      -- never gain this record and therefore remain disabled on relaxation.
      if record.visible_when_disabled ~= nil then
        technology.visible_when_disabled = record.visible_when_disabled
      end
      if record.disabled == true then technology.enabled = true end
      owned[name] = nil
    end
  end

  if owned and next(owned) == nil then owned_disabled[force.index] = nil end
  return owned_disabled, {queue_changed = queue_changed, removed_current = removed_current,
    unresolved_current = unresolved_current}
end

return M
