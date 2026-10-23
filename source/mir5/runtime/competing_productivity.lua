-- Runtime ownership for the fixed competing-productivity F200 overlaps.
--
-- Foreign rows remain native and retain earned effects. Exact EPR tails use
-- the shared absolute-cap reconciler. The five non-suffixed fixed-provider
-- rows have no pre-tail level to cap, so this module records and disables only
-- an unqueued, unearned initial level; it never removes a current or partial
-- research entry.
local caps = require("runtime.caps")
local binding = require("compatibility.competing_productivity")
local target = require("platform.target")
local effective = require("runtime.configuration")

local M = {}

local STORAGE_KEY = "mir_competing_productivity"
local SCHEMA = 1
local UINT32_MAX = 4294967295
local PREFERENCE_SETTING = "mir-prefer-this-mod-for-competing-techs"
local active_mods = script and script.active_mods or mods or {}
local ACTIVE = binding.active(active_mods, target)
local CONTRACT = binding.select(active_mods, target)
local ALL_BINDINGS = binding.bindings()
local BINDING_BY_ID, CONTRACT_BINDING_BY_ID = {}, {}
for _, item in ipairs(ALL_BINDINGS) do BINDING_BY_ID[item.id] = item end
if CONTRACT then
  for _, item in ipairs(CONTRACT.bindings) do CONTRACT_BINDING_BY_ID[item.id] = item end
end
local options = type(effective) == "table" and effective.options or nil
local PREFER_MIR = type(options) == "table" and options[PREFERENCE_SETTING]
if ACTIVE and type(PREFER_MIR) ~= "boolean" then
  error("MIR competing productivity preference setting is unavailable", 2)
end

local function valid_force(force)
  return force and force.valid ~= false and type(force.index) == "number"
end

local function existing_state()
  local value = storage[STORAGE_KEY]
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= SCHEMA or type(value.owned_disabled) ~= "table" then
    error("MIR unsupported competing productivity storage", 2)
  end
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
  if value and next(value.owned_disabled) == nil then storage[STORAGE_KEY] = nil end
end

local function drop_owned(owned_disabled, force_index, name)
  local owned = owned_disabled[force_index]
  if type(owned) ~= "table" then return end
  owned[name] = nil
  if next(owned) == nil then owned_disabled[force_index] = nil end
end

local function ensure_owned_record(owned_disabled, force_index, name)
  local owned = owned_disabled[force_index]
  if type(owned) ~= "table" then
    owned = {}
    owned_disabled[force_index] = owned
  end
  local record = owned[name]
  if type(record) ~= "table" then
    record = {}
    owned[name] = record
  end
  return record
end

local function runtime_foreign_admitted(technology, item)
  local prototype = technology and technology.prototype
  local prerequisites = prototype and prototype.prerequisites
  local predecessor = item.predecessor ~= false and prerequisites and prerequisites[item.predecessor]
  local empty_prerequisites = item.predecessor == false and prerequisites ~= nil
  if empty_prerequisites then
    for _ in pairs(prerequisites) do
      empty_prerequisites = false
      break
    end
  end
  return technology and technology.valid ~= false and technology.name == item.id
    and prototype and prototype.enabled == true and prototype.level == item.first_level
    and prototype.max_level == UINT32_MAX
    and ((item.predecessor == false and empty_prerequisites)
      or (item.predecessor ~= false and predecessor and predecessor.name == item.predecessor))
    and binding.runtime_effects_match(prototype.effects, item.effects)
end

local function runtime_replacements_admitted(force, item)
  local technologies = force and force.technologies
  for _, replacement in ipairs(item.replacements) do
    local technology = technologies and technologies[replacement.id]
    local prototype = technology and technology.prototype
    if not technology or technology.valid == false or not prototype or prototype.enabled ~= true
        or prototype.level ~= replacement.first_level or prototype.max_level ~= UINT32_MAX
        or not binding.runtime_effects_include(prototype.effects, replacement.effects) then
      return false
    end
  end
  return true
end

local function queued_names(force)
  local names = {}
  local current = force.current_research
  if current and type(current.name) == "string" then names[current.name] = true end
  local queue = force.research_queue
  if type(queue) == "table" then
    for _, value in ipairs(queue) do
      if value and type(value.name) == "string" then names[value.name] = true end
    end
  end
  return names
end

local function can_retire_unearned(technology, item, queued)
  return (item.initial_retirement == true or item.retire_if_unearned == true) and technology.enabled == true
    and technology.level == item.first_level and technology.researched ~= true
    and (technology.saved_progress == nil or technology.saved_progress == 0)
    and queued[item.id] ~= true
end

local function retire_unearned(force, current, item)
  local technology = force.technologies[item.id]
  if technology == nil or technology.enabled ~= true then return end
  local record = ensure_owned_record(current.owned_disabled, force.index, item.id)
  if technology.visible_when_disabled ~= true then
    if record.visible_when_disabled == nil then
      record.visible_when_disabled = technology.visible_when_disabled == true
    end
    technology.visible_when_disabled = true
  end
  record.disabled = true
  technology.enabled = false
end

local function reconcile_item(force, current, item, limits, unearned, queued)
  local technology = force.technologies[item.id]
  if not runtime_foreign_admitted(technology, item) then
    -- A changed provider identity/effect makes historic ownership unknowable.
    -- Forget only MIR's right; never turn it into an enablement write.
    drop_owned(current.owned_disabled, force.index, item.id)
    return
  end
  if PREFER_MIR ~= true or not runtime_replacements_admitted(force, item) then
    -- A false preference or incomplete/MIR-mismatching coverage releases an
    -- already-proved MIR right, but never allocates one for a foreign row.
    limits[item.id] = 0
    return
  end
  if item.initial_retirement ~= true and item.retire_if_unearned ~= true then
    limits[item.id] = item.first_level - 1
    return
  end
  if technology.enabled ~= true then
    -- A foreign disablement has no MIR record and stays wholly foreign. An
    -- existing MIR record is retained until a valid false-preference release.
    return
  end
  if can_retire_unearned(technology, item, queued) then
    unearned[#unearned + 1] = item
  elseif technology.level ~= item.first_level or technology.researched == true then
    -- The first native level is already earned. Keep that credit, then use the
    -- common cap path to retire only subsequent levels.
    limits[item.id] = item.first_level
  end
end

local function reconcile_force(force, target_name)
  if not valid_force(force) then return end
  local selected_item = target_name and BINDING_BY_ID[target_name] or nil
  if target_name ~= nil and (selected_item == nil or CONTRACT_BINDING_BY_ID[target_name] == nil) then return end
  if not CONTRACT then return end

  local current = existing_state()
  -- A false preference or an invalid replacement can only restore a right
  -- after the exact foreign tail itself is still known. Do not allocate state
  -- for a fresh no-preference profile.
  if not current and PREFER_MIR ~= true then return end
  current = current or ensure_state()
  local limits, unearned = {}, {}
  local queued = queued_names(force)
  if selected_item then
    reconcile_item(force, current, selected_item, limits, unearned, queued)
  else
    for _, item in ipairs(CONTRACT.bindings) do
      reconcile_item(force, current, item, limits, unearned, queued)
    end
  end
  if next(limits) ~= nil then
    local _, result = caps.reconcile(force, limits, current.owned_disabled)
    if result.unresolved_current then
      error("MIR unsupported native research queue state for competing productivity: "
        .. result.unresolved_current, 2)
    end
  end
  for _, item in ipairs(unearned) do retire_unearned(force, current, item) end
  discard_empty_state(current)
end

local function force_for_index(index)
  local ok, force = pcall(function() return game.forces[index] end)
  return ok and force or nil
end

local function discard_unselected_rights(current)
  for index, owned in pairs(current.owned_disabled) do
    if not valid_force(force_for_index(index)) then
      current.owned_disabled[index] = nil
    elseif type(owned) == "table" then
      for name in pairs(owned) do
        if CONTRACT_BINDING_BY_ID[name] == nil then owned[name] = nil end
      end
      if next(owned) == nil then current.owned_disabled[index] = nil end
    end
  end
end

local function reconcile_all(clean_stale)
  local current = existing_state()
  if not CONTRACT then
    -- A provider removal, unsupported version, or unqualified EPR/fixed mix
    -- cannot safely carry our old right into another provider identity.
    if current then storage[STORAGE_KEY] = nil end
    return
  end
  if not game or not game.forces then return end
  if clean_stale and current then discard_unselected_rights(current) end
  for _, force in pairs(game.forces) do reconcile_force(force) end
  discard_empty_state(existing_state())
end

local function event_force(event)
  local research = event and event.research
  if research and valid_force(research.force) then return research.force end
  if event and valid_force(event.force) then return event.force end
  if event and valid_force(event.destination) then return event.destination end
  return nil
end

local function reconcile_event(event, research_only)
  local force = event_force(event)
  if not force then return end
  local name = research_only and event and event.research and event.research.name or nil
  if research_only and type(name) ~= "string" then return end
  reconcile_force(force, name)
end

local function clear_force(index)
  local current = existing_state()
  if current and type(index) == "number" then
    current.owned_disabled[index] = nil
    discard_empty_state(current)
  end
end

function M.active()
  -- A false preference still reaches on_configuration_changed so a retained
  -- owned disablement is released, but it installs no steady-state callbacks.
  return ACTIVE and CONTRACT ~= nil and PREFER_MIR == true
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
  reconcile_event(event, true)
end

function M.on_research_reversed(event)
  reconcile_event(event, true)
end

function M.on_technology_effects_reset(event)
  reconcile_event(event)
end

function M.on_research_started(event)
  reconcile_event(event, true)
end

function M.on_research_cancelled(event)
  reconcile_event(event, true)
end

-- Parse-time registration owns the callbacks. This must not inspect storage or
-- game while a save is loading or a client joins.
function M.on_load()
end

return M
