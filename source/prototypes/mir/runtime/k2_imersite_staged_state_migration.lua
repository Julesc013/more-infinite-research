-- State-preserving upgrade from the released Imersite identities to finite
-- levels 1--3 plus the level-4 continuation.
--
-- Factorio applies JSON technology renames before control.lua.  A source
-- released with only the old infinite -1 technology therefore needs one
-- hidden carrier.  Saves already staged by earlier releases need two: JSON
-- otherwise clears the old -4 queue/current progress when the recreated -1
-- prerequisite becomes false.  The two distinct carrier prefixes avoid
-- Factorio's invalid "infinite followed by level" name-chain rule.
--
-- This is deliberately a narrow compatibility handoff.  Carrier rows are
-- emitted through the ordinary design/executor path; reconciliation runs in
-- the existing productivity-family adoption lifecycle before cap control.
-- It creates no research path, scheduler, solver, or force-wide effect reset.
local state_alias = require("prototypes.mir.domain.research.k2_imersite_staged_state")

local M = {}

local LEGACY = state_alias.legacy_technology
local CONTINUATION = state_alias.continuation_technology
local EARLY_HOLDER = state_alias.early.technology_name
local CONTINUATION_HOLDER = state_alias.continuation.technology_name
local POWDER = state_alias.powder_recipe
local LAST_LEGACY_LEVEL = 3
local FIRST_CONTINUATION_LEVEL = LAST_LEGACY_LEVEL + 1
local STATE_SCHEMA = 3

local function queue_names(force)
  local out = {}
  for _, technology in ipairs(force.research_queue or {}) do out[#out + 1] = technology.name end
  return out
end

local function same_names(left, right)
  if #left ~= #right then return false end
  for index, value in ipairs(left) do if value ~= right[index] then return false end end
  return true
end

local function current_name(force)
  local technology = force.current_research
  return technology and technology.name or nil
end

local function future_level(value)
  return value == "infinite" or (type(value) == "number" and value > LAST_LEGACY_LEVEL)
end

local function has_exact_powder_effect(technology)
  local matches, other = 0, false
  for _, effect in pairs((technology and technology.prototype and technology.prototype.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == POWDER
        and effect.change == 0.02 then
      matches = matches + 1
    elseif effect.type == "change-recipe-productivity" and effect.recipe == POWDER then
      other = true
    end
  end
  return matches == 1 and not other
end

local function has_prerequisite(technology, name)
  for _, prerequisite in pairs((technology and technology.prototype and technology.prototype.prerequisites) or {}) do
    if prerequisite.name == name then return true end
  end
  return false
end

local function valid_holder(holder, definition)
  return holder and holder.prototype and holder.prototype.hidden == true
    and future_level(holder.prototype.max_level) and has_exact_powder_effect(holder)
    and state_alias.matches_runtime_carrier_shape(definition, holder)
end

local function finite_legacy(legacy)
  return legacy and legacy.prototype and legacy.prototype.max_level == LAST_LEGACY_LEVEL
    and has_exact_powder_effect(legacy)
end

local function valid_continuation(legacy, continuation)
  return finite_legacy(legacy) and continuation and continuation.prototype
    and future_level(continuation.prototype.max_level)
    and has_prerequisite(continuation, LEGACY) and has_exact_powder_effect(continuation)
end

local function valid_infinite_legacy(legacy)
  return legacy and legacy.prototype and future_level(legacy.prototype.max_level)
    and has_exact_powder_effect(legacy)
end

local function holder_default_level(definition)
  return definition == state_alias.continuation and FIRST_CONTINUATION_LEVEL or 1
end

local function holder_snapshot(technology)
  return {
    level = technology and technology.level or nil,
    researched = technology and technology.researched == true or false,
    saved_progress = technology and technology.saved_progress or 0
  }
end

local function queued_or_current(force, name)
  for _, queued in ipairs(queue_names(force)) do if queued == name then return true end end
  return current_name(force) == name
end

local function holder_snapshot_active(force, definition, snapshot)
  return snapshot.researched == true or snapshot.level ~= holder_default_level(definition)
    or (snapshot.saved_progress or 0) ~= 0
    or queued_or_current(force, definition.technology_name)
end

local function queue_objects(force, names)
  local out = {}
  for _, name in ipairs(names or {}) do
    local technology = force.technologies[name]
    if not technology then return nil, name end
    out[#out + 1] = technology
  end
  return out
end

local function set_queue(force, names)
  local queue, missing = queue_objects(force, names)
  if not queue then return false, missing end
  local ok, err = pcall(function() force.research_queue = queue end)
  if not ok then return false, tostring(err) end
  return true
end

local function set_state(technology, level, researched, saved_progress)
  -- Native setter evidence: setting researched=false after level resets earned
  -- progress.  Restore the state in the opposite order.  These setters update
  -- effects themselves, so a force-wide reset would be redundant and unsafe.
  technology.researched = researched == true
  technology.level = level
  technology.saved_progress = saved_progress or 0
end

local function technology_snapshot(technology)
  return {
    level = technology.level,
    researched = technology.researched == true,
    saved_progress = technology.saved_progress or 0,
    enabled = technology.enabled,
    visible_when_disabled = technology.visible_when_disabled
  }
end

local function restore_technology_snapshot(technology, snapshot)
  set_state(technology, snapshot.level, snapshot.researched, snapshot.saved_progress)
  technology.enabled = snapshot.enabled
  technology.visible_when_disabled = snapshot.visible_when_disabled
end

local function clear_holder(holder, definition)
  set_state(holder, holder_default_level(definition), false, 0)
  holder.enabled = false
  holder.visible_when_disabled = false
end

local function source_version(event)
  local change = event and event.mod_changes and event.mod_changes["more-infinite-research"]
  return change and change.old_version or nil
end

local function migration_event(event)
  local old_version = source_version(event)
  return type(old_version) == "string" and old_version ~= ""
end

local function source_record(force, early, continuation, event)
  return {
    schema = STATE_SCHEMA,
    force_index = force.index,
    source_version = source_version(event),
    source = "json-two-holders-v1",
    phase = "captured",
    early = holder_snapshot(early),
    continuation = holder_snapshot(continuation),
    queue_before = queue_names(force),
    current_before = current_name(force),
    progress_before = force.research_progress or 0
  }
end

local function valid_record(record, force)
  return type(record) == "table" and record.schema == STATE_SCHEMA
    and record.force_index == force.index and record.source == "json-two-holders-v1"
    and type(record.source_version) == "string" and record.source_version ~= ""
    and type(record.phase) == "string" and type(record.early) == "table"
    and type(record.continuation) == "table"
end

local function stage_target_for_early_level(level)
  return level <= LAST_LEGACY_LEVEL and LEGACY or CONTINUATION
end

local function map_stage_queue(record)
  local mapped, current, early_level = {}, nil, record.early.level
  for _, name in ipairs(record.queue_before or {}) do
    local target = name
    if name == EARLY_HOLDER then
      target = stage_target_for_early_level(early_level)
      early_level = early_level + 1
    elseif name == CONTINUATION_HOLDER then
      target = CONTINUATION
    end
    mapped[#mapped + 1] = target
    if current == nil and name == record.current_before then current = target end
  end
  if current == nil and record.current_before == EARLY_HOLDER then
    current = stage_target_for_early_level(record.early.level)
  elseif current == nil and record.current_before == CONTINUATION_HOLDER then
    current = CONTINUATION
  elseif current == nil then
    current = record.current_before
  end
  return mapped, current
end

local function map_infinite_queue(record)
  local mapped, current = {}, nil
  for _, name in ipairs(record.queue_before or {}) do
    local target = (name == EARLY_HOLDER or name == CONTINUATION_HOLDER) and LEGACY or name
    mapped[#mapped + 1] = target
    if current == nil and name == record.current_before then current = target end
  end
  if current == nil and (record.current_before == EARLY_HOLDER
      or record.current_before == CONTINUATION_HOLDER) then
    current = LEGACY
  elseif current == nil then
    current = record.current_before
  end
  return mapped, current
end

local function map_without_continuation(record)
  local active, current, early_level = {}, nil, record.early.level
  for _, name in ipairs(record.queue_before or {}) do
    local target = name
    if name == EARLY_HOLDER then
      target = stage_target_for_early_level(early_level)
      early_level = early_level + 1
    elseif name == CONTINUATION_HOLDER then
      target = nil
    end
    if target == CONTINUATION then target = nil end
    if target then active[#active + 1] = target end
    if current == nil and name == record.current_before then current = target end
  end
  if current == nil and record.current_before == EARLY_HOLDER then
    current = stage_target_for_early_level(record.early.level)
    if current == CONTINUATION then current = nil end
  elseif current == nil and record.current_before == CONTINUATION_HOLDER then
    current = nil
  elseif current == nil then
    current = record.current_before
  end
  return active, current
end

local function contains_name(names, name)
  for _, value in ipairs(names or {}) do if value == name then return true end end
  return false
end

local function restore_queue_and_progress(force, names, expected_current, progress)
  -- Assigning research_queue is an engine mutation.  Do not clear a carrier
  -- unless Factorio readback proves it retained the complete mapped queue and
  -- the intended active technology.  If the migrated current target vanished,
  -- the engine must instead select the first surviving queue entry with zero
  -- carried fractional work.
  if expected_current and not contains_name(names, expected_current) then
    return false, "mapped-current-not-queued:" .. tostring(expected_current)
  end
  local actual_current = expected_current or names[1]
  local actual_progress = expected_current and (progress or 0) or 0
  local queue_ok, queue_error = set_queue(force, names)
  if not queue_ok then return false, "queue-target-unavailable:" .. tostring(queue_error) end
  if not same_names(queue_names(force), names) then return false, "queue-readback-mismatch" end
  if current_name(force) ~= actual_current then
    return false, "current-readback-mismatch:" .. tostring(current_name(force))
  end
  force.research_progress = actual_progress
  if force.research_progress ~= actual_progress then return false, "progress-readback-mismatch" end
  return true
end

local function force_checkpoint(force, technologies)
  local values = {}
  for name, technology in pairs(technologies) do
    if technology then values[name] = technology_snapshot(technology) end
  end
  return {
    technologies = values,
    queue = queue_names(force),
    current = current_name(force),
    progress = force.research_progress or 0
  }
end

local function restore_checkpoint(force, technologies, checkpoint)
  for name, snapshot in pairs(checkpoint.technologies) do
    local technology = technologies[name]
    if not technology then return false, "rollback-technology-missing:" .. tostring(name) end
    restore_technology_snapshot(technology, snapshot)
  end
  local queue_ok, queue_error = set_queue(force, checkpoint.queue)
  if not queue_ok then return false, "rollback-queue-unavailable:" .. tostring(queue_error) end
  if not same_names(queue_names(force), checkpoint.queue) then return false, "rollback-queue-readback-mismatch" end
  if current_name(force) ~= checkpoint.current then
    return false, "rollback-current-readback-mismatch:" .. tostring(current_name(force))
  end
  force.research_progress = checkpoint.progress
  if force.research_progress ~= checkpoint.progress then return false, "rollback-progress-readback-mismatch" end
  return true
end

local function early_destination(record)
  if record.early.level <= LAST_LEGACY_LEVEL then return record.early end
  return {level = LAST_LEGACY_LEVEL, researched = true, saved_progress = 0}
end

local function continuation_source(record)
  if holder_snapshot_active({research_queue = {}, current_research = nil}, state_alias.continuation,
      record.continuation) then
    return record.continuation
  end
  if record.early.level > LAST_LEGACY_LEVEL then
    return {level = record.early.level, researched = false, saved_progress = record.early.saved_progress}
  end
  return {level = FIRST_CONTINUATION_LEVEL, researched = false, saved_progress = 0}
end

-- The snapshot helper above is intentionally independent of a force after
-- capture.  Queue/current carrier activity is represented in the record and
-- handled by map_stage_queue; this predicate only classifies numeric state.
local function continuation_numeric_state(record)
  return record.continuation.researched == true
    or record.continuation.level ~= FIRST_CONTINUATION_LEVEL
    or (record.continuation.saved_progress or 0) ~= 0
end

local function staged_source_is_consistent(record)
  -- A queued/earned continuation requires the first finite stage to be
  -- complete.  Do not manufacture that prerequisite from a corrupted save.
  if continuation_numeric_state(record) then return record.early.level >= FIRST_CONTINUATION_LEVEL end
  for _, name in ipairs(record.queue_before or {}) do
    if name == CONTINUATION_HOLDER then return record.early.level >= FIRST_CONTINUATION_LEVEL end
  end
  return true
end

local function clear_both(early, continuation)
  clear_holder(early, state_alias.early)
  clear_holder(continuation, state_alias.continuation)
end

local function restore_staged(force, legacy, continuation, early_holder, continuation_holder, record)
  if not staged_source_is_consistent(record) then return false, "continuation-with-incomplete-legacy-state" end
  set_state(legacy, early_destination(record).level, early_destination(record).researched,
    early_destination(record).saved_progress)
  local tail = continuation_source(record)
  set_state(continuation, tail.level, tail.researched, tail.saved_progress)
  legacy.enabled, legacy.visible_when_disabled = true, false
  continuation.enabled, continuation.visible_when_disabled = true, false
  local queue, current = map_stage_queue(record)
  local ok, err = restore_queue_and_progress(force, queue, current, record.progress_before)
  if not ok then return false, err end
  clear_both(early_holder, continuation_holder)
  record.phase = "completed-staged"
  return true
end

local function restore_infinite_legacy(force, legacy, early_holder, continuation_holder, record)
  if not staged_source_is_consistent(record) then return false, "continuation-with-incomplete-legacy-state" end
  local source = continuation_source(record)
  if not continuation_numeric_state(record) and record.early.level <= LAST_LEGACY_LEVEL then
    source = record.early
  end
  set_state(legacy, source.level, source.researched, source.saved_progress)
  legacy.enabled, legacy.visible_when_disabled = true, false
  local queue, current = map_infinite_queue(record)
  local ok, err = restore_queue_and_progress(force, queue, current, record.progress_before)
  if not ok then return false, err end
  clear_both(early_holder, continuation_holder)
  record.phase = "completed-infinite-legacy"
  return true
end

local function retain_tail_without_continuation(force, legacy, early_holder, continuation_holder, record)
  if not staged_source_is_consistent(record) then return false, "continuation-with-incomplete-legacy-state" end
  local early = early_destination(record)
  set_state(legacy, early.level, early.researched, early.saved_progress)
  legacy.enabled, legacy.visible_when_disabled = true, false

  local tail = continuation_source(record)
  local queue, current = map_without_continuation(record)
  local ok, err = restore_queue_and_progress(force, queue, current, record.progress_before)
  if not ok then return false, err end
  clear_holder(early_holder, state_alias.early)

  local has_tail = continuation_numeric_state(record) or record.early.level > LAST_LEGACY_LEVEL
  for _, name in ipairs(record.queue_before or {}) do
    if name == CONTINUATION_HOLDER then has_tail = true end
    if name == EARLY_HOLDER and record.early.level > LAST_LEGACY_LEVEL then has_tail = true end
  end
  if has_tail then
    -- Keep the exact later-stage state hidden, disabled and unqueued. Its
    -- earned powder effect remains active so the finite stage plus this held
    -- tail equals the predecessor's earned total while the cap/profile has no
    -- public continuation. A future valid continuation consumes it once; the
    -- holder never becomes a player-visible research path.
    set_state(continuation_holder, tail.level, tail.researched, tail.saved_progress)
    continuation_holder.enabled, continuation_holder.visible_when_disabled = false, false
    record.tail = {level = tail.level, researched = tail.researched, saved_progress = tail.saved_progress}
    record.phase = "tail-held-no-continuation"
    record.queue_after_removal = queue_names(force)
    record.current_after_removal = current_name(force)
  else
    clear_holder(continuation_holder, state_alias.continuation)
    record.phase = "completed-finite-only"
  end
  return true
end

local function converge_held_tail_unchecked(force, legacy, continuation, early_holder, continuation_holder, record)
  if not valid_continuation(legacy, continuation) or type(record.tail) ~= "table" then return false end
  if not same_names(queue_names(force), record.queue_after_removal or {})
      or current_name(force) ~= record.current_after_removal then
    -- Preserve player changes made while the continuation was unavailable.
    -- Restore owned earned state without replaying an obsolete queue.
    set_state(continuation, record.tail.level, record.tail.researched, record.tail.saved_progress)
    continuation.enabled, continuation.visible_when_disabled = true, false
    clear_both(early_holder, continuation_holder)
    record.phase = "completed-tail-converged-player-queue-changed"
    return true
  end
  set_state(continuation, record.tail.level, record.tail.researched, record.tail.saved_progress)
  continuation.enabled, continuation.visible_when_disabled = true, false
  local queue, current = map_stage_queue(record)
  local ok, err = restore_queue_and_progress(force, queue, current, record.progress_before)
  if not ok then return false, err end
  clear_both(early_holder, continuation_holder)
  record.phase = "completed-tail-converged"
  return true
end

local function converge_held_tail(force, legacy, continuation, early_holder, continuation_holder, record)
  local technologies = {
    [LEGACY] = legacy,
    [CONTINUATION] = continuation,
    [EARLY_HOLDER] = early_holder,
    [CONTINUATION_HOLDER] = continuation_holder
  }
  local checkpoint = force_checkpoint(force, technologies)
  local ok, error_text = converge_held_tail_unchecked(
    force, legacy, continuation, early_holder, continuation_holder, record)
  if ok then return true end
  local rollback_ok, rollback_error = restore_checkpoint(force, technologies, checkpoint)
  if rollback_ok then
    record.phase = "tail-held-no-continuation"
    record.last_error = error_text
  else
    record.phase = "holder-retained-rollback-failed"
    record.last_error = tostring(error_text) .. ";" .. tostring(rollback_error)
  end
  return false, error_text
end

local function destination_kind(legacy, continuation)
  if valid_continuation(legacy, continuation) then return "staged" end
  if finite_legacy(legacy) then return "finite-only" end
  if valid_infinite_legacy(legacy) then return "infinite-legacy" end
  return nil
end

local function remove_carrier_queue(record)
  local active, current = {}, nil
  for _, name in ipairs(record.queue_before or {}) do
    local target = name
    if name == EARLY_HOLDER or name == CONTINUATION_HOLDER then target = nil end
    if target then active[#active + 1] = target end
    if current == nil and name == record.current_before then current = target end
  end
  if current == nil and record.current_before ~= EARLY_HOLDER
      and record.current_before ~= CONTINUATION_HOLDER then
    current = record.current_before
  end
  return active, current
end

local function hold_unmatched_profile(force, early_holder, continuation_holder, record)
  -- The public destination does not currently establish a valid staging or
  -- infinite contract.  Hide both state carriers and remove only their owned
  -- queue entries.  The snapshots and original queue remain in the record for
  -- a later valid configuration, but hidden carriers never become research.
  local queue, current = remove_carrier_queue(record)
  local ok, err = restore_queue_and_progress(force, queue, current, record.progress_before)
  if not ok then return false, err end
  set_state(early_holder, record.early.level, record.early.researched, record.early.saved_progress)
  set_state(continuation_holder, record.continuation.level, record.continuation.researched,
    record.continuation.saved_progress)
  early_holder.enabled, early_holder.visible_when_disabled = false, false
  continuation_holder.enabled, continuation_holder.visible_when_disabled = false, false
  record.queue_after_removal = queue_names(force)
  record.current_after_removal = current_name(force)
  record.phase = "holder-held-unmatched-profile"
  return true
end

local function restore_held_state_without_queue(force, legacy, continuation, early_holder, continuation_holder, record)
  -- The player changed the remaining queue while the destination was absent.
  -- Restore owned earned state only; never replay the old carrier queue over
  -- an intentional later player queue.  The original fractional queue work is
  -- retained in record for audit but cannot be applied to an unrelated active
  -- technology.
  local kind = destination_kind(legacy, continuation)
  if kind == "staged" then
    if not staged_source_is_consistent(record) then return false, "continuation-with-incomplete-legacy-state" end
    local early = early_destination(record)
    local tail = continuation_source(record)
    set_state(legacy, early.level, early.researched, early.saved_progress)
    set_state(continuation, tail.level, tail.researched, tail.saved_progress)
    legacy.enabled, legacy.visible_when_disabled = true, false
    continuation.enabled, continuation.visible_when_disabled = true, false
    clear_both(early_holder, continuation_holder)
    record.phase = "completed-unmatched-profile-player-queue-changed"
    return true
  elseif kind == "finite-only" then
    if not staged_source_is_consistent(record) then return false, "continuation-with-incomplete-legacy-state" end
    local early = early_destination(record)
    set_state(legacy, early.level, early.researched, early.saved_progress)
    legacy.enabled, legacy.visible_when_disabled = true, false
    local tail = continuation_source(record)
    local has_tail = continuation_numeric_state(record) or record.early.level > LAST_LEGACY_LEVEL
    if has_tail then
      set_state(continuation_holder, tail.level, tail.researched, tail.saved_progress)
      continuation_holder.enabled, continuation_holder.visible_when_disabled = false, false
      clear_holder(early_holder, state_alias.early)
      record.tail = {level = tail.level, researched = tail.researched, saved_progress = tail.saved_progress}
      record.phase = "tail-held-no-continuation"
    else
      clear_both(early_holder, continuation_holder)
      record.phase = "completed-finite-only-player-queue-changed"
    end
    return true
  elseif kind == "infinite-legacy" then
    if not staged_source_is_consistent(record) then return false, "continuation-with-incomplete-legacy-state" end
    local source = continuation_source(record)
    if not continuation_numeric_state(record) and record.early.level <= LAST_LEGACY_LEVEL then
      source = record.early
    end
    set_state(legacy, source.level, source.researched, source.saved_progress)
    legacy.enabled, legacy.visible_when_disabled = true, false
    clear_both(early_holder, continuation_holder)
    record.phase = "completed-unmatched-infinite-player-queue-changed"
    return true
  end
  return false, "no-validated-destination"
end

local apply_destination_transactionally

local function converge_held_unmatched_profile(force, legacy, continuation, early_holder, continuation_holder, record)
  local queue_unchanged = same_names(queue_names(force), record.queue_after_removal or {})
    and current_name(force) == record.current_after_removal
  if queue_unchanged then
    return apply_destination_transactionally(force, legacy, continuation, early_holder, continuation_holder, record)
  end
  local technologies = {
    [LEGACY] = legacy,
    [CONTINUATION] = continuation,
    [EARLY_HOLDER] = early_holder,
    [CONTINUATION_HOLDER] = continuation_holder
  }
  local checkpoint = force_checkpoint(force, technologies)
  local ok, error_text = restore_held_state_without_queue(
    force, legacy, continuation, early_holder, continuation_holder, record)
  if ok then return true end
  local rollback_ok, rollback_error = restore_checkpoint(force, technologies, checkpoint)
  if rollback_ok then
    record.phase = "holder-held-unmatched-profile"
    record.last_error = error_text
  else
    record.phase = "holder-retained-rollback-failed"
    record.last_error = tostring(error_text) .. ";" .. tostring(rollback_error)
  end
  return false, error_text
end

local function apply_destination(force, legacy, continuation, early_holder, continuation_holder, record)
  local kind = destination_kind(legacy, continuation)
  if kind == "staged" then
    return restore_staged(force, legacy, continuation, early_holder, continuation_holder, record)
  elseif kind == "finite-only" then
    return retain_tail_without_continuation(force, legacy, early_holder, continuation_holder, record)
  elseif kind == "infinite-legacy" then
    return restore_infinite_legacy(force, legacy, early_holder, continuation_holder, record)
  end
  return hold_unmatched_profile(force, early_holder, continuation_holder, record)
end

apply_destination_transactionally = function(force, legacy, continuation, early_holder, continuation_holder, record)
  local technologies = {
    [LEGACY] = legacy,
    [CONTINUATION] = continuation,
    [EARLY_HOLDER] = early_holder,
    [CONTINUATION_HOLDER] = continuation_holder
  }
  local checkpoint = force_checkpoint(force, technologies)
  local ok, error_text = apply_destination(force, legacy, continuation, early_holder, continuation_holder, record)
  if ok then return true end

  -- A failed queue/current readback must leave the carriers intact.  Returning
  -- a retryable retained record is safer than silently keeping destination
  -- state plus carrier state, which would double the same earned effect.
  local rollback_ok, rollback_error = restore_checkpoint(force, technologies, checkpoint)
  if rollback_ok then
    record.phase = "holder-retained-retryable"
    record.last_error = error_text
  else
    record.phase = "holder-retained-rollback-failed"
    record.last_error = tostring(error_text) .. ";" .. tostring(rollback_error)
  end
  return false, error_text
end

local function valid_carriers(early_holder, continuation_holder)
  return valid_holder(early_holder, state_alias.early)
    and valid_holder(continuation_holder, state_alias.continuation)
end

local function default_empty_holders(force, early_holder, continuation_holder)
  return valid_carriers(early_holder, continuation_holder)
    and not holder_snapshot_active(force, state_alias.early, holder_snapshot(early_holder))
    and not holder_snapshot_active(force, state_alias.continuation, holder_snapshot(continuation_holder))
end

local function cleanup_fresh_force(force, records)
  if not force or records[force.index] ~= nil then return end
  local early_holder = force.technologies[EARLY_HOLDER]
  local continuation_holder = force.technologies[CONTINUATION_HOLDER]
  -- Fresh/default carrier rows have never represented predecessor state.  They
  -- must be disabled, but an unexpected active carrier remains untouched for
  -- a later explicit configuration reconciliation rather than being erased.
  if default_empty_holders(force, early_holder, continuation_holder) then
    clear_both(early_holder, continuation_holder)
  end
end

-- Called by productivity_family_adoption before maximum_level_control. State
-- lives in that established owner, so a later cap relaxation can converge a
-- retained tail without a second handler or additive replay.
function M.reconcile(event, adoption_state)
  adoption_state.k2_imersite_staged_migration = adoption_state.k2_imersite_staged_migration or {}
  local records = adoption_state.k2_imersite_staged_migration
  for _, force in pairs(game.forces) do
    local legacy = force.technologies[LEGACY]
    local continuation = force.technologies[CONTINUATION]
    local early_holder = force.technologies[EARLY_HOLDER]
    local continuation_holder = force.technologies[CONTINUATION_HOLDER]
    local record = records[force.index]

    if valid_record(record, force) then
      if record.phase == "tail-held-no-continuation" then
        converge_held_tail(force, legacy, continuation, early_holder, continuation_holder, record)
      elseif record.phase == "holder-held-unmatched-profile" then
        converge_held_unmatched_profile(force, legacy, continuation, early_holder, continuation_holder, record)
      elseif record.phase == "holder-retained-unmatched-profile"
          or record.phase == "holder-retained-retryable" then
        apply_destination_transactionally(force, legacy, continuation, early_holder, continuation_holder, record)
      end
    elseif migration_event(event) and valid_carriers(early_holder, continuation_holder) then
      record = source_record(force, early_holder, continuation_holder, event)
      records[force.index] = record
      local early_active = holder_snapshot_active(force, state_alias.early, record.early)
      local continuation_active = holder_snapshot_active(force, state_alias.continuation, record.continuation)
      if early_active or continuation_active then
        apply_destination_transactionally(force, legacy, continuation, early_holder, continuation_holder, record)
      elseif destination_kind(legacy, continuation) then
        -- An unresearched source still passed through JSON.  Remove both
        -- carriers deterministically so they cannot become a hidden path.
        clear_both(early_holder, continuation_holder)
        record.phase = "completed-empty-source"
      else
        -- An empty predecessor is never permission to leave a default carrier
        -- enabled on an unmatched profile.
        clear_both(early_holder, continuation_holder)
        record.phase = "completed-empty-source"
      end
    end
  end
end

-- on_init/on_force_created only clear fresh default rows.  They do not create
-- a predecessor record and do not alter an unexpected active carrier.
function M.initialize_fresh(adoption_state, force)
  adoption_state.k2_imersite_staged_migration = adoption_state.k2_imersite_staged_migration or {}
  local records = adoption_state.k2_imersite_staged_migration
  if force then
    cleanup_fresh_force(force, records)
    return
  end
  for _, candidate in pairs(game.forces) do cleanup_fresh_force(candidate, records) end
end

return M
