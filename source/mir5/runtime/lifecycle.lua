-- Runtime composition for the first native gear slice.  Persistent ownership
-- is limited to transitions made by runtime.caps; native research remains the
-- authority for levels, completed effects, current research, and progress.
local caps = require("runtime.caps")
local legacy_caps = require("runtime.legacy_caps")
local native_owners = require("research.native_owners")

local M = {}

local STORAGE_KEY = "mir_caps"
local SCHEMA = 1
local GEAR_TECHNOLOGY = require("research.catalogue").gear_id()
local WORKER_TAIL_NAMES = {"worker-robots-speed-6", "worker-robots-speed-7"}

-- `settings` and `helpers` are runtime globals at control parse time.  Startup
-- values cannot change during a loaded save, so this is one immutable native
-- setting/profile resolution for this control instance rather than work on
-- every research event.
local effective_values = require("runtime.configuration")
local GEAR_ENABLED = effective_values.enabled ~= false
local GEAR_LIMIT = effective_values.max_level
local WORKER_ROBOT_SPEED_LIMIT = effective_values.worker_robots_speed_max_level
local CAPS_ACTIVE = (GEAR_ENABLED and GEAR_LIMIT > 0) or WORKER_ROBOT_SPEED_LIMIT > 0

local function existing_state()
  local value = storage[STORAGE_KEY]
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= SCHEMA then
    error("MIR unsupported caps storage schema", 2)
  end
  if type(value.owned_disabled) ~= "table" then error("MIR invalid caps ownership state", 2) end
  return value
end

local function ensure_state()
  local value = existing_state()
  if value then return value end
  value = {schema = SCHEMA, owned_disabled = {}}
  storage[STORAGE_KEY] = value
  return value
end

local function discard_empty_state(value)
  if next(value.owned_disabled) == nil and value.legacy_caps_checked ~= true then
    storage[STORAGE_KEY] = nil
  end
end

local function valid_force(force)
  return force and force.valid ~= false and type(force.index) == "number"
end

-- The native owner selector reads exactly the two admitted tail candidates
-- for this force. It does not enumerate technologies or retain a foreign
-- prototype reference. An unlimited setting is still included when an exact
-- owner exists so a previous MIR-owned disable can be restored on config.
local function has_worker_ownership(owned)
  return type(owned) == "table"
    and (type(owned[WORKER_TAIL_NAMES[1]]) == "table"
      or type(owned[WORKER_TAIL_NAMES[2]]) == "table")
end

local function worker_owner(force)
  if not valid_force(force) then return nil end
  local technologies = force.technologies
  return native_owners.runtime_worker_robot_speed_owner(function(name)
    return technologies and technologies[name] or nil
  end)
end

local function limits_for(force, include_worker, selected_owner, owner_resolved)
  local limits = {}
  if GEAR_ENABLED then limits[GEAR_TECHNOLOGY] = GEAR_LIMIT end
  if not valid_force(force) or (WORKER_ROBOT_SPEED_LIMIT == 0 and not include_worker) then
    return limits
  end
  local owner = selected_owner
  if not owner_resolved then owner = worker_owner(force) end
  if owner then limits[owner] = WORKER_ROBOT_SPEED_LIMIT end
  return limits
end

-- Return a new plain snapshot for presentation callers. It is intentionally
-- separate from the native force and does not expose storage or settings.
function M.cap_limits(force)
  -- Presentation is caller-driven, not a recurring event path. Include an
  -- admitted unlimited native owner here so the Library can explain its 0
  -- sentinel without reading lifecycle state itself.
  return limits_for(force, true, nil, false)
end

function M.caps_active()
  return CAPS_ACTIVE
end

-- A cap record binds to its admitted tail name. If upstream replaces that
-- tail with malformed data or the higher-priority tail, discard the old
-- enablement right before reconciliation. This intentionally fails closed:
-- MIR cannot prove that a later same-named replacement is the object it once
-- disabled, so it must never re-enable it on a later unlimited setting.
local function discard_unbound_worker_ownership(force, owned_disabled, owner)
  local owned = owned_disabled[force.index]
  if not has_worker_ownership(owned) then return owned end
  for _, name in ipairs(WORKER_TAIL_NAMES) do
    if type(owned[name]) == "table" and name ~= owner then owned[name] = nil end
  end
  if next(owned) == nil then
    owned_disabled[force.index] = nil
    return nil
  end
  return owned
end

-- A disabled gear feature has no authority to restore prior cap writes. Drop
-- any rows we previously owned without touching the native technology, so an
-- administrator's explicit disablement cannot re-enable it during a profile
-- or configuration transition.
local function discard_disabled_gear_ownership(force, owned_disabled)
  local owned = owned_disabled[force.index]
  if GEAR_ENABLED or type(owned) ~= "table" then return owned end
  owned[GEAR_TECHNOLOGY] = nil
  if next(owned) == nil then
    owned_disabled[force.index] = nil
    return nil
  end
  return owned
end

local function reconcile_force(force, owned_disabled, selected_owner, owner_resolved)
  if not valid_force(force) then return end
  local owned = type(owned_disabled) == "table" and owned_disabled[force.index] or nil
  if type(owned_disabled) == "table" then
    owned = discard_disabled_gear_ownership(force, owned_disabled)
  end
  local include_worker = WORKER_ROBOT_SPEED_LIMIT > 0 or has_worker_ownership(owned)
  local owner = selected_owner
  if include_worker and not owner_resolved then owner = worker_owner(force) end
  if type(owned_disabled) == "table" and has_worker_ownership(owned) then
    owned = discard_unbound_worker_ownership(force, owned_disabled, owner)
  end
  local _, result = caps.reconcile(force,
    limits_for(force, include_worker, owner, include_worker), owned_disabled)
  if result.unresolved_current then
    error("MIR unsupported native research queue state for over-cap current research: "
      .. result.unresolved_current, 2)
  end
end

local function force_for_index(index)
  local ok, force = pcall(function() return game.forces[index] end)
  if ok then return force end
  return nil
end

local function reconcile_all(clean_stale_forces, selected_owners)
  if not game or not game.forces then return end
  -- Unlimited startup settings need no state unless a previous finite setting
  -- left an ownership transition that has to be restored exactly once.
  local current = CAPS_ACTIVE and ensure_state() or existing_state()
  if not current then return end
  local owned_disabled = current.owned_disabled
  if clean_stale_forces then
    for index in pairs(owned_disabled) do
      if not valid_force(force_for_index(index)) then owned_disabled[index] = nil end
    end
  end
  for _, force in pairs(game.forces) do
    local owner = valid_force(force) and selected_owners and selected_owners[force.index] or nil
    reconcile_force(force, owned_disabled, owner, selected_owners ~= nil)
  end
  discard_empty_state(current)
end

local function legacy_candidates(worker_name)
  local candidates = {}
  if GEAR_ENABLED then
    candidates[#candidates + 1] = {
      name = GEAR_TECHNOLOGY,
      setting = "ips-max-level-research_gears",
      source = "generated-stream",
      operation = "runtime-settings-transport",
      admitted = true
    }
  end
  if worker_name then
    candidates[#candidates + 1] = {
      name = worker_name,
      setting = "mir-max-level-worker-robots-speed",
      source = "native-owner",
      operation = "native-owner-cap",
      admitted = true
    }
  end
  return candidates
end

local function merge_legacy_rows(owned_disabled, force_index, rows)
  local owned = owned_disabled[force_index]
  if owned ~= nil and type(owned) ~= "table" then
    error("MIR invalid caps ownership row", 2)
  end
  if next(rows) == nil then return end
  if owned == nil then
    owned = {}
    owned_disabled[force_index] = owned
  end
  for name, row in pairs(rows) do
    -- The pure importer has already rejected an existing MIR5 row. Keep this
    -- guard at the persistence boundary so MIR5 ownership always wins.
    if owned[name] == nil then
      owned[name] = {
        disabled = row.disabled == true and true or nil,
        visible_when_disabled = row.visible_when_disabled
      }
    end
  end
end

-- This is the sole reader of the published bucket. It is deliberately called
-- only by on_configuration_changed: initialization and load never transport
-- historical cap rights into a new save.
local function import_legacy_caps_on_configuration()
  local mir = storage.mir
  local legacy_bucket = type(mir) == "table" and mir.maximum_level_control or nil
  if legacy_bucket == nil then return nil end

  local current = existing_state()
  if current and current.legacy_caps_checked == true then return nil end
  current = ensure_state()
  -- Preserve this marker even when no candidate is currently admitted or the
  -- old bucket is malformed. A reused force index must never re-open import.
  current.legacy_caps_checked = true

  local selected_owners = {}
  if not game or not game.forces then return selected_owners end
  for _, force in pairs(game.forces) do
    if valid_force(force) then
      local owned = discard_disabled_gear_ownership(force, current.owned_disabled)
      -- Revalidate the native tail even if the new worker cap is unlimited;
      -- importing its historical restoration right still depends on that
      -- exact current owner.
      local owner = worker_owner(force)
      selected_owners[force.index] = owner
      local rows = legacy_caps.import_for_force(legacy_bucket, force,
        legacy_candidates(owner), owned)
      merge_legacy_rows(current.owned_disabled, force.index, rows)
    end
  end
  return selected_owners
end

local function event_force(event)
  local research = event and event.research
  if research and research.force and valid_force(research.force) then return research.force end
  if event and valid_force(event.force) then return event.force end
  if event and valid_force(event.destination) then return event.destination end
  return nil
end

local function reconcile_event(event)
  local force = event_force(event)
  if not force then return end
  -- These callbacks are registered only while finite caps are active. Keep
  -- the defensive direct-call path allocation-free for an unlimited fresh
  -- save, while still restoring a retained owned or legacy-marker state.
  local current = CAPS_ACTIVE and ensure_state() or existing_state()
  if not current then return end
  reconcile_force(force, current.owned_disabled)
  discard_empty_state(current)
end

local function clear_force(index)
  if type(index) ~= "number" then return end
  local current = existing_state()
  if not current then return end
  current.owned_disabled[index] = nil
  discard_empty_state(current)
end

function M.on_init()
  reconcile_all(false)
end

function M.on_configuration_changed()
  reconcile_all(true, import_legacy_caps_on_configuration())
end

function M.on_force_created(event)
  local force = event and event.force
  if valid_force(force) then clear_force(force.index) end
  reconcile_event(event)
end

function M.on_force_reset(event)
  local force = event and event.force
  if valid_force(force) then clear_force(force.index) end
  reconcile_event(event)
end

function M.on_forces_merged(event)
  clear_force(event and event.source_index)
  reconcile_event(event)
end

function M.on_research_finished(event)
  reconcile_event(event)
end

function M.on_research_started(event)
  reconcile_event(event)
end

function M.on_research_cancelled(event)
  reconcile_event(event)
end

-- There are no local bindings to reconstruct. The parse-time bootstrap owns
-- event registration; this callback must never initialize storage or touch
-- game on host reload or a joining client.
function M.on_load()
end

return M
