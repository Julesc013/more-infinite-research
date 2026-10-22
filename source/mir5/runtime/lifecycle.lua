-- Runtime composition for the first native gear slice.  Persistent ownership
-- is limited to transitions made by runtime.caps; native research remains the
-- authority for levels, completed effects, current research, and progress.
local caps = require("runtime.caps")
local settings_catalogue = require("research.settings")

local M = {}

local STORAGE_KEY = "mir_caps"
local SCHEMA = 1
local GEAR_TECHNOLOGY = "recipe-prod-research_gears-1"

local function report(message)
  if type(log) == "function" then log(message) end
end

-- `settings` and `helpers` are runtime globals at control parse time.  Startup
-- values cannot change during a loaded save, so this is one immutable native
-- setting/profile resolution for this control instance rather than work on
-- every research event.
local effective_values = settings_catalogue.resolve(settings.startup, helpers, report)
local LIMITS = {[GEAR_TECHNOLOGY] = effective_values.max_level}
local CAPS_ACTIVE = effective_values.max_level > 0

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

local function current_is_over_cap(force, name, limits)
  local limit = limits[name]
  local technology = force.current_research
  if limit == nil or limit == 0 or not technology or technology.name ~= name then return false end
  local current = force.technologies and force.technologies[name]
  return current and type(current.level) == "number" and current.level > limit
end

local function reconcile_force(force, limits, owned_disabled)
  if not valid_force(force) then return end
  local _, result = caps.reconcile(force, limits, owned_disabled)
  -- Queue assignment normally removes an over-cap current entry.  An unqueued
  -- current entry is the documented exception: use the native cancellation
  -- operation only after independently rechecking the admitted cap.
  if result.unresolved_current and current_is_over_cap(force, result.unresolved_current, limits) then
    force.cancel_current_research()
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
    reconcile_force(force, LIMITS, owned_disabled)
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
  reconcile_force(force, LIMITS, current.owned_disabled)
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

-- There are no local bindings or conditional handlers to reconstruct.  Keep
-- this explicit because this callback must never initialize storage or touch
-- game on host reload or a joining client.
function M.on_load()
end

function M.register()
  script.on_init(M.on_init)
  script.on_configuration_changed(M.on_configuration_changed)
  script.on_load(M.on_load)
  if not CAPS_ACTIVE then return end
  script.on_event(defines.events.on_force_created, M.on_force_created)
  script.on_event(defines.events.on_force_reset, M.on_force_reset)
  script.on_event(defines.events.on_forces_merged, M.on_forces_merged)
  script.on_event(defines.events.on_research_finished, M.on_research_finished)
  script.on_event(defines.events.on_research_started, M.on_research_started)
  script.on_event(defines.events.on_research_cancelled, M.on_research_cancelled)
end

return M
