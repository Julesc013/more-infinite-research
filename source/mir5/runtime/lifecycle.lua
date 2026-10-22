-- Runtime composition for the first native gear slice.  Persistent ownership
-- is limited to transitions made by runtime.caps; native research remains the
-- authority for levels, completed effects, current research, and progress.
local caps = require("runtime.caps")
local native_owners = require("research.native_owners")
local settings_catalogue = require("research.settings")

local M = {}

local STORAGE_KEY = "mir_caps"
local SCHEMA = 1
local GEAR_TECHNOLOGY = require("research.catalogue").gear_id()
local WORKER_TAIL_NAMES = {"worker-robots-speed-6", "worker-robots-speed-7"}

local function report(message)
  if type(log) == "function" then log(message) end
end

-- `settings` and `helpers` are runtime globals at control parse time.  Startup
-- values cannot change during a loaded save, so this is one immutable native
-- setting/profile resolution for this control instance rather than work on
-- every research event.
local effective_values = settings_catalogue.resolve(settings.startup, helpers, report)
local GEAR_LIMIT = effective_values.max_level
local WORKER_ROBOT_SPEED_LIMIT = effective_values.worker_robots_speed_max_level
local CAPS_ACTIVE = GEAR_LIMIT > 0 or WORKER_ROBOT_SPEED_LIMIT > 0

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
  if next(value.owned_disabled) == nil then storage[STORAGE_KEY] = nil end
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
  local limits = {[GEAR_TECHNOLOGY] = GEAR_LIMIT}
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

local function reconcile_force(force, owned_disabled)
  if not valid_force(force) then return end
  local owned = type(owned_disabled) == "table" and owned_disabled[force.index] or nil
  local include_worker = WORKER_ROBOT_SPEED_LIMIT > 0 or has_worker_ownership(owned)
  local owner = include_worker and worker_owner(force) or nil
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

local function reconcile_all(clean_stale_forces)
  if not game or not game.forces then return end
  -- Unlimited startup settings need no state unless a previous finite setting
  -- left an ownership transition that has to be restored exactly once.
  local current = CAPS_ACTIVE and ensure_state() or existing_state()
  if not current then return end
  local owned_disabled = current.owned_disabled
  if clean_stale_forces then
    for index in pairs(owned_disabled) do
      if not valid_force(game.forces[index]) then owned_disabled[index] = nil end
    end
  end
  for _, force in pairs(game.forces) do
    reconcile_force(force, owned_disabled)
  end
  discard_empty_state(current)
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
  local current = ensure_state()
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
  reconcile_all(true)
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
