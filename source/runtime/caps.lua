-- Absolute-cap reconciliation for already-admitted native technologies.
--
-- The caller owns durable state and passes it explicitly as:
--   owned_disabled[force.index][technology_name] = {
--     disabled = true,
--     visible_when_disabled = false
--   }
-- `disabled=true` records MIR's enablement-restoration right; false preserves
-- the first foreign-disabled baseline. Visibility records the prior value
-- only when MIR changes it and can be owned independently of enablement.
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

local function assert_retained_queue(force, expected)
  local actual = force.research_queue
  if type(actual) ~= "table" then error("MIR native queue readback unavailable", 3) end
  if #actual ~= #expected then error("MIR native queue dropped unselected research", 3) end
  for index, technology in ipairs(expected) do
    if not actual[index] or actual[index].name ~= technology.name then
      error("MIR native queue changed unselected research order", 3)
    end
  end
end

local function same_research(technology, name, level)
  return technology and technology.name == name and level ~= nil and valid_level(technology) == level
end

local function assert_current_head(current, queue)
  local first = queue[1]
  if (current and current.name or nil) ~= (first and first.name or nil) then
    error("MIR inconsistent native current/queue frame after cap rewrite", 3)
  end
end

local function valid_progress(progress)
  return type(progress) == "number" and progress >= 0 and progress <= 1
end

local function same_progress(actual, expected)
  return valid_progress(actual) and math.abs(actual - expected) <= 0.000000001
end

local function suspended_progress(technology)
  local progress = technology.saved_progress
  if not valid_progress(progress) or progress >= 1 then
    error("MIR cannot observe suspended research progress: " .. technology.name, 3)
  end
  return progress
end

local function observe_suspended_work(queue, excluded)
  -- Only Factorio 2.x packages use this runtime. Each queued technology has
  -- one native saved fraction even when its identity occurs several times.
  local rows, seen = {}, {}
  for _, technology in ipairs(queue) do
    local name = technology.name
    if name ~= excluded and not seen[name] then
      local level = valid_level(technology)
      if not level then error("MIR cannot observe queued research level: " .. name, 3) end
      rows[#rows + 1] = {technology=technology, name=name, level=level,
        progress=suspended_progress(technology)}
      seen[name] = true
    end
  end
  return rows
end

local function assert_suspended_work(force, rows, previous_current)
  local active = force.current_research
  for _, row in ipairs(rows) do
    local saved = suspended_progress(row.technology)
    local kept = same_progress(saved, row.progress)
    if active and active.name == row.name and row.name ~= previous_current then
      -- A newly selected follower may have started with its saved fraction,
      -- or its paid work may still be parked while active work is zero.
      local progress = force.research_progress
      kept = (kept and same_progress(progress, 0))
        or (same_progress(progress, row.progress) and (kept or same_progress(saved, 0)))
    end
    if not kept or not same_research(row.technology, row.name, row.level) then
      error("MIR native queue changed suspended research work: " .. row.name, 3)
    end
  end
end

local function filter_queue(force, limits, unavailable)
  local queue = force.research_queue
  local current = force.current_research
  local current_name = current and current.name or nil
  local current_limit = current_name and limits[current_name]
  local current_level = valid_level(current)
  local current_over_cap = current_limit and current_limit > 0
    and current_level and current_level > current_limit
  local current_unavailable = current_name and unavailable and unavailable[current_name] == true
  local current_disallowed = current_over_cap or current_unavailable
  if queue == nil then return false, nil, current_disallowed and current_name or nil end

  local next_level, filtered, removed = {}, {}, 0
  for _, queued in ipairs(queue) do
    local name = queued and queued.name
    local limit = name and limits[name]
    local technology = name and force.technologies and force.technologies[name]
    local level = name and (next_level[name] or valid_level(technology)) or nil

    if (unavailable and unavailable[name] == true)
        or (limit and limit > 0 and level and level > limit) then
      removed = removed + 1
    else
      filtered[#filtered + 1] = queued
      if limit and limit > 0 and level then next_level[name] = level + 1 end
    end
  end

  if removed == 0 then return false, nil, current_disallowed and current_name or nil end

  -- Factorio's queue setter owns current-research cancellation when the
  -- current entry was removed.  Reapply progress only when that exact current
  -- technology remains current, so valid fractional progress is preserved and
  -- removed research does not leak progress into another queue entry.
  local progress = current and force.research_progress or nil
  local head_retained = current_name and queue[1] and queue[1].name == current_name
    and filtered[1] and filtered[1].name == current_name
  if head_retained and (not current_level or not valid_progress(progress)) then
    error("MIR cannot observe retained current research work: " .. current_name, 3)
  end
  local progress_to_suspend
  if current_disallowed then
    -- Native cancellation can park a single fraction on this level.
    -- Validate that the observed paid work fits before changing the queue.
    if not queue[1] or queue[1].name ~= current_name or not current_level
        or not valid_progress(progress) or progress >= 1 then
      error("MIR cannot preserve disallowed current research progress: " .. current_name, 3)
    end
    local saved = suspended_progress(current)
    if progress ~= 0 and saved ~= 0 and not same_progress(saved, progress) then
      error("MIR cannot replace distinct suspended research work: " .. current_name, 3)
    end
    progress_to_suspend = progress ~= 0 and progress or saved
  end
  local excluded = not head_retained and current_name or nil
  local suspended = observe_suspended_work(queue, excluded)
  force.research_queue = filtered
  -- The native setter may silently reject an unresearchable remainder. Do
  -- not report that as preserved foreign/eligible queue state on either path.
  assert_retained_queue(force, filtered)
  local retained = force.current_research
  local current_retained = current_name and retained and retained.name == current_name
  if (head_retained or current_retained) and not same_research(retained, current_name, current_level) then
    error("MIR native queue changed current research: " .. current_name, 3)
  end
  -- A completion may arrive during an intermediate frame. A rewrite still
  -- has to produce a settled queue before any old progress can be reused.
  assert_current_head(retained, filtered)
  local removed_current = nil
  if current_name and not current_retained then removed_current = current_name end
  if current_retained and progress ~= nil then
    force.research_progress = progress
    if not same_research(force.current_research, current_name, current_level)
        or not same_progress(force.research_progress, progress) then
      error("MIR native force did not retain current research progress: " .. current_name, 3)
    end
    assert_retained_queue(force, filtered)
  elseif progress_to_suspend ~= nil then
    local saved = suspended_progress(current)
    if current_unavailable and not same_progress(saved, progress_to_suspend) then
      -- The unavailable-row route may explicitly park its invested work.
      -- Confirm the old level and protect the newly selected research.
      if not same_research(current, current_name, current_level) then
        error("MIR native queue changed the level of suspended research: " .. current_name, 3)
      end
      local next_name = retained and retained.name
      local next_level = retained and valid_level(retained)
      local next_progress = retained and force.research_progress
      if retained and (not next_level or not valid_progress(next_progress)) then
        error("MIR cannot observe current research before suspending: " .. next_name, 3)
      end
      current.saved_progress = progress_to_suspend
      saved = suspended_progress(current)
      local active = force.current_research
      if (retained and (not same_research(active, next_name, next_level)
          or not same_progress(force.research_progress, next_progress))) or (not retained and active) then
        error("MIR native force changed current research while suspending: " .. current_name, 3)
      end
      assert_retained_queue(force, filtered)
    end
    if not same_research(current, current_name, current_level)
        or not same_progress(saved, progress_to_suspend) then
      error("MIR native technology did not retain suspended research progress: " .. current_name, 3)
    end
  end
  assert_suspended_work(force, suspended, current_name)
  local unresolved_current = nil
  if current_disallowed and current_retained then unresolved_current = current_name end
  return true, removed_current, unresolved_current
end

-- Remove only the caller's unavailable authored rows. Levels, completed
-- effects, detached work and the remaining native queue are not MIR-owned.
-- No queued intentions are copied into persistent state or restored later.
function M.remove_unavailable_from_queue(force, unavailable)
  if type(unavailable) ~= "table" then error("MIR unavailable research must be a name set", 2) end
  for name, value in pairs(unavailable) do
    if type(name) ~= "string" or name == "" or value ~= true then
      error("MIR unavailable research must name exact technologies", 2)
    end
  end
  if not force or force.valid == false or not force.technologies or next(unavailable) == nil then
    return {queue_changed = false, removed_current = nil, unresolved_current = nil}
  end
  local changed, removed, unresolved = filter_queue(force, {}, unavailable)
  if unresolved then error("MIR native queue did not cancel unavailable current research: " .. unresolved, 2) end
  return {queue_changed = changed, removed_current = removed, unresolved_current = unresolved}
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
-- `imported_reenabled` is an optional configuration-local map of exact newly
-- imported record identities. It authorizes only this new enabled -> disabled
-- write, never replacing an existing negative or persisting the proof itself.
-- Discovery Tree updates enablement before MIR's event handler. A boolean
-- sixth argument selects that integration: true is a fresh upstream update,
-- false preserves the last observation on events upstream does not handle.
-- Nil retains the ordinary cap ownership contract.
function M.reconcile(force, limits, owned_disabled, targets, imported_reenabled, discovery_observed)
  local caps = checked_limits(limits)
  if type(owned_disabled) ~= "table" then
    error("MIR caps owned_disabled must be a table", 2)
  end
  if not force or force.valid == false or not force.technologies then
    return owned_disabled, {queue_changed = false, removed_current = nil, unresolved_current = nil}
  end
  if force.index == nil then error("MIR caps force must have an index", 2) end

  local selected = caps
  if targets ~= nil then
    if type(targets) ~= "table" then error("MIR caps targets must be a table or nil", 2) end
    selected = {}
    for name, value in pairs(targets) do
      if type(name) ~= "string" or value ~= true or caps[name] == nil then
        error("MIR caps targets must name supplied limits", 2)
      end
      selected[name] = caps[name]
    end
  end

  -- Research callbacks pass one admitted family.  Filter only that sparse
  -- selection too: rewriting another family's queue entry here would turn a
  -- named research event into a broad reconciliation.
  local queue_changed, removed_current, unresolved_current = filter_queue(force, selected)
  local owned = owned_disabled[force.index]

  for name, limit in pairs(selected) do
    local technology = force.technologies[name]
    local level = valid_level(technology)
    if technology and limit > 0 and level and level > limit then
      local record = owned and owned[name]
      local previously_observed = type(record) == "table"
      owned, record = ensure_record(owned_disabled, force.index, owned, name)
      if discovery_observed ~= nil and (discovery_observed or record.discovery_enabled == nil) then
        record.discovery_enabled = technology.enabled == true
      end
      if record.disabled == nil then
        -- A visibility-only row normally retains its foreign baseline.
        -- Record the first baseline once: native resets/reconfiguration can
        -- re-enable this row while the same finite cap is still in force.
        -- The configuration owner may identify an exact newly imported row
        -- whose validated positive proof accompanied this live re-enablement.
        -- Bind that transient exception to its table identity and this actual
        -- new write; existing negatives and ordinary visibility rows win.
        local first_import_write = type(imported_reenabled) == "table"
          and imported_reenabled[name] == record
        record.disabled = technology.enabled == true and (not previously_observed or first_import_write)
      end
      if discovery_observed ~= nil and record.visible_when_disabled ~= nil then
        -- Undo only MIR's earlier visibility write when this integration is
        -- enabled. Discovery Tree owns when ordinary research is revealed.
        technology.visible_when_disabled = record.visible_when_disabled
        record.visible_when_disabled = nil
      elseif discovery_observed == nil and technology.visible_when_disabled ~= true then
        if record.visible_when_disabled == nil then
          record.visible_when_disabled = technology.visible_when_disabled == true
        end
        technology.visible_when_disabled = true
      end
      if technology.enabled then technology.enabled = false end
    elseif technology and owned and type(owned[name]) == "table" then
      local record = owned[name]
      -- Only disabled=true grants an enablement-restoration right. False
      -- retains the observed foreign baseline across native re-enablement;
      -- later reconciliations must never turn it into a MIR-owned transition.
      if record.visible_when_disabled ~= nil then
        technology.visible_when_disabled = record.visible_when_disabled
      end
      if discovery_observed ~= nil then
        -- The just-updated native state is authoritative. Do not reveal a
        -- technology while releasing MIR's old cap ledger.
      elseif record.discovery_enabled ~= nil then
        -- After upstream removal, restore only the last actually observed
        -- available state that MIR capped. Never reveal an unknown hidden row.
        if record.discovery_enabled == true and technology.enabled ~= true then technology.enabled = true end
      elseif record.disabled == true and technology.enabled ~= true then technology.enabled = true
      elseif record.disabled == false and technology.enabled ~= false then technology.enabled = false end
      owned[name] = nil
    end
  end

  if owned and next(owned) == nil then owned_disabled[force.index] = nil end
  return owned_disabled, {queue_changed = queue_changed, removed_current = removed_current,
    unresolved_current = unresolved_current}
end

return M
