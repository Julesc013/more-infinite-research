-- Runtime composition for the first native gear slice.  Persistent ownership
-- is limited to transitions made by runtime.caps; native research remains the
-- authority for levels, completed effects, current research, and progress.
local caps = require("runtime.caps")
local legacy_caps = require("runtime.legacy_caps")
local native_owners = require("research.native_owners")
local cap_admission = require("runtime.cap_admission")
local catalogue = require("research.catalogue")
local platform_target = require("platform.target")

local M = {}

local STORAGE_KEY = "mir_caps"
local SCHEMA = 1
local DIAGNOSTIC_FIXTURE = "mir-fixture-mir5-native-owner-cap-order"
local DIAGNOSTIC_OWNER = "steel-plate-productivity"
local DIAGNOSTIC_FOREIGN_FORCE = "mir5-native-owner-cap-order-foreign"
local DIAGNOSTIC_LIMIT = 128
local diagnostic_lines = 0
local WORKER_TAIL_NAMES = {"worker-robots-speed-6", "worker-robots-speed-7"}
local active_mods = script and script.active_mods or mods or {}
local worker_modifiers
if active_mods.Krastorio2 and active_mods["Krastorio2-spaced-out"]
    and active_mods.Krastorio2Assets and active_mods["k2so-assets"] and active_mods["space-age"] then
  worker_modifiers = require("compatibility.k2so_worker_speed")
end

local function worker_modifier(name)
  return worker_modifiers and worker_modifiers[name] or 0.65
end

-- `settings` and `helpers` are runtime globals at control parse time.  Startup
-- values cannot change during a loaded save, so this is one immutable native
-- setting/profile resolution for this control instance rather than work on
-- every research event.
local effective_values = require("runtime.configuration")
local WORKER_ROBOT_SPEED_LIMIT = effective_values.worker_robots_speed_max_level

local function nonnegative_integer(value)
  return type(value) == "number" and value == value and value >= 0
    and value < math.huge and value == math.floor(value)
end
local function named_recipe_array(value, label)
  if type(value) ~= "table" then error("MIR caps missing named productivity recipes: " .. label, 2) end
  local out, seen = {}, {}
  for index, name in ipairs(value) do
    if type(name) ~= "string" or name == "" or seen[name] then
      error("MIR caps invalid named productivity recipe: " .. label, 2)
    end
    seen[name], out[index] = true, name
  end
  if #out == 0 then error("MIR caps empty named productivity recipes: " .. label, 2) end
  return out
end
local function bounded_useful_limit(configured, useful)
  return configured > 0 and math.min(configured, useful) or useful
end

-- Resolve the authored catalogue and immutable startup values once while
-- control is parsed. Event paths use these compact maps; they never ask the
-- catalogue to rebuild or scan a family list.
local DECLARATIONS = catalogue.declared()
local STREAM_VALUES = effective_values.streams
if type(STREAM_VALUES) ~= "table" then error("MIR caps missing resolved stream values", 2) end
local STATIC_GENERATED_BY_ID, DECLARATION_BY_ID, NATIVE_OWNER_BY_ID, ORDERED_DECLARATIONS = {}, {}, {}, {}
local CAPS_ACTIVE = WORKER_ROBOT_SPEED_LIMIT > 0
for index = 1, #DECLARATIONS do
  local declaration = DECLARATIONS[index]
  local binding = type(declaration) == "table" and declaration.legacy_binding or nil
  if type(declaration) ~= "table" or type(declaration.id) ~= "string" or declaration.id == ""
      or type(declaration.family) ~= "string" or declaration.family == ""
      or type(declaration.cap_setting) ~= "string" or declaration.cap_setting == ""
      or type(binding) ~= "table" or type(binding.source) ~= "string"
      or type(binding.operation) ~= "string"
      or (declaration.ownership_kind ~= "authored_generated" and declaration.ownership_kind ~= "nativeowner")
      or DECLARATION_BY_ID[declaration.id] ~= nil then
    error("MIR caps invalid authored declaration", 2)
  end
  local values = STREAM_VALUES[declaration.family]
  if type(values) ~= "table" or type(values.enabled) ~= "boolean"
      or not nonnegative_integer(values.max_level) then
    error("MIR caps missing resolved family values: " .. declaration.family, 2)
  end
  local row = {id = declaration.id, family = declaration.family, cap_setting = declaration.cap_setting,
    ownership_kind = declaration.ownership_kind, source = binding.source, operation = binding.operation,
    enabled = values.enabled, limit = values.max_level, declaration = declaration}
  if declaration.productivity_ceiling ~= nil then
    local ceiling, percent = declaration.productivity_ceiling, values.effect_percent
    if type(ceiling) ~= "number" or not (ceiling > 0 and ceiling < math.huge)
      or type(percent) ~= "number" or not (percent > 0 and percent < math.huge) then
      error("MIR caps invalid authored productivity ceiling: " .. declaration.id, 2)
    end
    row.productivity_recipes = named_recipe_array(declaration.productivity_recipes, declaration.id)
    row.productivity_effect_percent = percent
    -- This construction-time bound only keeps the finite-cap lifecycle
    -- registered. Active Bob/Angel rows replace it with the named
    -- LuaRecipePrototype caps after data-final applies the user's
    -- prototype/recycling policies; there is no control-stage fallback.
    row.limit = bounded_useful_limit(row.limit, math.ceil(ceiling * 100 / percent))
  end
  ORDERED_DECLARATIONS[#ORDERED_DECLARATIONS + 1] = row
  DECLARATION_BY_ID[row.id] = row
  if row.enabled and row.limit > 0 then CAPS_ACTIVE = true end
  if row.ownership_kind == "nativeowner" then
    if type(values.configured) == "table" and values.configured.effect_percent == true then
      row.configured_effect_change = values.effect_percent / 100
    end
    NATIVE_OWNER_BY_ID[row.id] = row
  elseif row.enabled then
    STATIC_GENERATED_BY_ID[row.id] = row
  end
end
-- This literal target authority comes from package materialization, never
-- predecessor storage. F200 alone had the published settings-derived V3
-- native-worker transport; all other targets retain transported V3 admission.
local LEGACY_ALLOWLIST = legacy_caps.allowlist(DECLARATIONS, platform_target.id)
local PUBLISHED_F200_M4_VERSIONS = {
  ["4.7.20000"] = true,
  ["4.7.20001"] = true,
  ["4.7.20002"] = true,
  ["4.7.20003"] = true
}

-- Recipe caps are immutable for one loaded control profile. Resolve only the
-- exact authored routes once through Factorio 2.0's `prototypes.recipe`; do
-- not scan recipes or reconstruct the recycler/self-return classifier that
-- data-final already used. A technology with several productivity effects
-- remains useful while any named recipe has headroom, matching the historical
-- per-effect OR semantics, so use the greatest route-derived level bound.
local PRODUCTIVITY_USEFUL_LIMITS = {}
local function useful_productivity_limit(row)
  if row.productivity_recipes == nil then return nil end
  local cached = PRODUCTIVITY_USEFUL_LIMITS[row.family]
  if cached ~= nil then return cached end
  local definitions = prototypes and prototypes.recipe
  if definitions == nil then error("MIR caps missing Factorio 2.0 recipe prototypes", 2) end
  local highest = 0
  for _, name in ipairs(row.productivity_recipes) do
    local prototype = definitions[name]
    local maximum = prototype and tonumber(prototype.maximum_productivity) or nil
    if type(maximum) ~= "number" or maximum ~= maximum
        or maximum <= 0 or maximum == math.huge or maximum == -math.huge then
      error("MIR caps missing valid named recipe productivity cap: " .. name, 2)
    end
    local useful = math.ceil(maximum * 100 / row.productivity_effect_percent)
    if useful > highest then highest = useful end
  end
  if highest < 1 then error("MIR caps invalid named recipe productivity headroom: " .. row.id, 2) end
  PRODUCTIVITY_USEFUL_LIMITS[row.family] = highest
  return highest
end
local function effective_limit(row)
  local useful = useful_productivity_limit(row)
  if useful == nil then return row.limit end
  return bounded_useful_limit(STREAM_VALUES[row.family].max_level, useful)
end

local function existing_state()
  local value = storage[STORAGE_KEY]
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= SCHEMA then
    error("MIR unsupported caps storage schema", 2)
  end
  if type(value.owned_disabled) ~= "table" then error("MIR invalid caps ownership state", 2) end
  return value
end

-- Temporary native-owner fixture telemetry. It observes lifecycle boundaries
-- without allocating state; caps.lua provides the paired write-path snapshots.
local function diagnostic_value(value)
  if value == nil then return "nil" end
  return tostring(value)
end

local function diagnostic_force(phase, force, research)
  if active_mods[DIAGNOSTIC_FIXTURE] == nil or type(log) ~= "function"
      or diagnostic_lines >= DIAGNOSTIC_LIMIT or not force or force.valid == false
      or type(force.index) ~= "number"
      or (force.name ~= "player" and force.name ~= DIAGNOSTIC_FOREIGN_FORCE) then
    return
  end
  local technology = force.technologies and force.technologies[DIAGNOSTIC_OWNER] or nil
  local current = existing_state()
  local owned = current and current.owned_disabled and current.owned_disabled[force.index] or nil
  local record = type(owned) == "table" and owned[DIAGNOSTIC_OWNER] or nil
  diagnostic_lines = diagnostic_lines + 1
  log("[MIR5_CAP_OWNERSHIP_DIAGNOSTIC] module=lifecycle phase=" .. phase
    .. " force=" .. diagnostic_value(force.name)
    .. " index=" .. diagnostic_value(force.index)
    .. " research=" .. diagnostic_value(research and research.name)
    .. " level=" .. diagnostic_value(technology and technology.level)
    .. " researched=" .. diagnostic_value(technology and technology.researched)
    .. " enabled=" .. diagnostic_value(technology and technology.enabled)
    .. " visible=" .. diagnostic_value(technology and technology.visible_when_disabled)
    .. " record_disabled=" .. diagnostic_value(type(record) == "table" and record.disabled or nil)
    .. " record_visible=" .. diagnostic_value(type(record) == "table" and record.visible_when_disabled or nil))
end

local function diagnostic_named_forces(phase)
  if not game or not game.forces then return end
  diagnostic_force(phase, game.forces.player, nil)
  diagnostic_force(phase, game.forces[DIAGNOSTIC_FOREIGN_FORCE], nil)
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
  end, worker_modifiers)
end

local function native_owner_admitted(force, row)
  return valid_force(force) and cap_admission.admits_native_owner(function(name)
    return force.technologies and force.technologies[name] or nil
  end, row.declaration, row.configured_effect_change)
end

-- Startup settings decide whether a stream may be considered, but the data
-- stage can retain its identity with prototype.enabled=false when science or
-- lab policy rejects it. Only that immutable default distinguishes the latter
-- from a per-force cap disablement, so do not use ForceTechnology.enabled.
local function authored_generated_admitted(force, row)
  if not valid_force(force) then return false end
  local ok, enabled = pcall(function()
    local technology = force.technologies and force.technologies[row.id] or nil
    return technology and technology.prototype and technology.prototype.enabled == true
  end)
  return ok and enabled == true
end

-- A retained generated identity can be deliberately disabled by the data
-- policy while its completed native effects remain in the save.  Its immutable
-- prototype default, rather than ForceTechnology.enabled, identifies that
-- state: the latter is also how a finite cap or another mod disables research.
local function authored_generated_prototype_disabled(force, row)
  if not valid_force(force) then return nil end
  local ok, technology = pcall(function()
    local technology = force.technologies and force.technologies[row.id] or nil
    if technology and technology.prototype and technology.prototype.enabled == false then
      return technology
    end
    return nil
  end)
  return ok and technology or nil
end

local function retained_authored_prototype_disablement(force, name)
  local row = DECLARATION_BY_ID[name]
  if not row or row.ownership_kind ~= "authored_generated" then return false end
  return authored_generated_prototype_disabled(force, row) ~= nil
end

-- This runs only during initialization/configuration, over the compact
-- authored declaration list. It does not enumerate a force's technologies.
-- A record exists only after this runtime changed an enabled technology to
-- disabled, so later cap relaxation can restore neither a data-stage default
-- nor foreign pre-disablement.
local function reconcile_authored_prototype_disablement(force, owned_disabled)
  if not valid_force(force) then return false end
  for index = 1, #ORDERED_DECLARATIONS do
    local row = ORDERED_DECLARATIONS[index]
    if row.ownership_kind == "authored_generated" then
      local technology = authored_generated_prototype_disabled(force, row)
      if technology and technology.enabled == true then
        -- The caller probes with nil before allocating durable storage for an
        -- otherwise unlimited save.
        if type(owned_disabled) ~= "table" then return true end
        local owned = owned_disabled[force.index]
        if type(owned) ~= "table" then
          owned = {}
          owned_disabled[force.index] = owned
        end
        local record = owned[row.id]
        if type(record) ~= "table" then
          record = {}
          owned[row.id] = record
        end
        record.disabled = true
        technology.enabled = false
      end
    end
  end
  return false
end

local function full_limits_for(force, include_worker, selected_owner, owner_resolved)
  local limits, admitted = {}, {}
  if valid_force(force) then
    for name, row in pairs(STATIC_GENERATED_BY_ID) do
      if authored_generated_admitted(force, row) then limits[name], admitted[name] = effective_limit(row), true end
    end
    for name, row in pairs(NATIVE_OWNER_BY_ID) do
      if row.enabled and native_owner_admitted(force, row) then
        limits[name], admitted[name] = effective_limit(row), true
      end
    end
    if WORKER_ROBOT_SPEED_LIMIT > 0 or include_worker then
      local owner = selected_owner
      if not owner_resolved then owner = worker_owner(force) end
      if owner then limits[owner], admitted[owner] = WORKER_ROBOT_SPEED_LIMIT, true end
      return limits, admitted, owner
    end
  end
  return limits, admitted, selected_owner
end

local function event_limits_for(force, name, include_worker)
  local row = DECLARATION_BY_ID[name]
  if row and row.enabled then
    if row.ownership_kind == "authored_generated" and authored_generated_admitted(force, row) then
      return {[name] = effective_limit(row)}, {[name] = true}, nil
    elseif row.ownership_kind == "nativeowner" and native_owner_admitted(force, row) then
      return {[name] = effective_limit(row)}, {[name] = true}, nil
    end
  end
  if name == WORKER_TAIL_NAMES[1] or name == WORKER_TAIL_NAMES[2] then
    local owner = worker_owner(force)
    if owner == name and (WORKER_ROBOT_SPEED_LIMIT > 0 or include_worker) then
      return {[name] = WORKER_ROBOT_SPEED_LIMIT}, {[name] = true}, owner
    end
  end
  return nil, nil, nil
end

-- Return a new plain snapshot for presentation callers. It is intentionally
-- separate from the native force and does not expose storage or settings.
function M.cap_limits(force)
  -- Presentation is caller-driven. Include an admitted unlimited native owner
  -- so the Library can explain the zero sentinel without touching storage.
  return full_limits_for(force, true, nil, false)
end

function M.caps_active()
  return CAPS_ACTIVE
end

-- A cap record binds to a current authored identity. If a feature is disabled,
-- an owner no longer matches its exact effect contract, or a worker tail is
-- superseded, discard only MIR's future restoration right. This fails closed:
-- no uncertain ownership is converted into an enablement write.
local function discard_unbound_ownership(force, owned_disabled, admitted, owner, workers_only)
  local owned = owned_disabled[force.index]
  if type(owned) ~= "table" then return owned end
  for name, row in pairs(owned) do
    if not workers_only or name == WORKER_TAIL_NAMES[1] or name == WORKER_TAIL_NAMES[2] then
      -- A disabled authored prototype keeps a record that this runtime
      -- actually wrote. It must remain disabled until that prototype is
      -- admitted again, when caps.reconcile can restore only this proven right.
      if admitted[name] ~= true and not retained_authored_prototype_disablement(force, name) then
        owned[name] = nil
      elseif name == WORKER_TAIL_NAMES[1] or name == WORKER_TAIL_NAMES[2] then
        local row = owned[name]
        if type(row) == "table" then
          -- Earlier private MIR5 rows could only represent the 0.65 variant.
          -- Historical MIR4 imports are stamped with their admitted variant.
          local modifier = row.worker_effect_modifier
          if modifier == nil then modifier = 0.65 end
          if name ~= owner or modifier ~= worker_modifier(name) then owned[name] = nil end
        else
          owned[name] = nil
        end
      end
    end
  end
  if next(owned) == nil then
    owned_disabled[force.index] = nil
    return nil
  end
  return owned
end

local function reconcile_force(force, owned_disabled, selected_owner, owner_resolved, target_name)
  if not valid_force(force) then return end
  local owned = type(owned_disabled) == "table" and owned_disabled[force.index] or nil
  local include_worker = has_worker_ownership(owned)
  local limits, admitted, owner
  if target_name then
    limits, admitted, owner = event_limits_for(force, target_name, include_worker)
    if limits == nil then
      if type(owned_disabled) == "table" and owned and owned[target_name] ~= nil
          and not retained_authored_prototype_disablement(force, target_name) then
        owned[target_name] = nil
        if next(owned) == nil then owned_disabled[force.index] = nil end
      end
      return
    end
  else
    limits, admitted, owner = full_limits_for(force, include_worker, selected_owner, owner_resolved)
  end
  if type(owned_disabled) == "table" then
    if target_name then
      local row = owned_disabled[force.index]
      if type(row) == "table" and row[target_name] ~= nil and admitted[target_name] ~= true
          and not retained_authored_prototype_disablement(force, target_name) then
        row[target_name] = nil
        if next(row) == nil then owned_disabled[force.index] = nil end
      end
      if target_name == WORKER_TAIL_NAMES[1] or target_name == WORKER_TAIL_NAMES[2] then
        discard_unbound_ownership(force, owned_disabled, admitted, owner, true)
      end
    else
      owned = discard_unbound_ownership(force, owned_disabled, admitted, owner)
    end
  end
  local targets = target_name and {[target_name] = true} or nil
  local _, result = caps.reconcile(force, limits, owned_disabled, targets)
  if result.unresolved_current then
    error("MIR unsupported native research queue state for over-cap current research: "
      .. result.unresolved_current, 2)
  end
  local owned = owned_disabled[force.index]
  local row = owner and owned_disabled[force.index] and owned_disabled[force.index][owner]
  if type(row) == "table" and row.worker_effect_modifier == nil then
    row.worker_effect_modifier = worker_modifier(owner)
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
  -- left an ownership transition that has to be restored exactly once, or an
  -- authored disabled prototype is currently force-enabled and needs this
  -- module's one recorded disablement.
  local current = CAPS_ACTIVE and ensure_state() or existing_state()
  local owned_disabled = current and current.owned_disabled or nil
  if current and clean_stale_forces then
    for index in pairs(owned_disabled) do
      if not valid_force(force_for_index(index)) then owned_disabled[index] = nil end
    end
  end
  for _, force in pairs(game.forces) do
    if current == nil and reconcile_authored_prototype_disablement(force, nil) then
      current = ensure_state()
      owned_disabled = current.owned_disabled
    end
    if current then
      reconcile_authored_prototype_disablement(force, owned_disabled)
    end
    local owner = valid_force(force) and selected_owners and selected_owners[force.index] or nil
    if current then reconcile_force(force, owned_disabled, owner, selected_owners ~= nil) end
  end
  if current then discard_empty_state(current) end
end

local function direct_f200_to_f210_transition(event)
  if platform_target.id ~= "f210" or type(event) ~= "table" then return false end
  local changes = event.mod_changes
  local change = type(changes) == "table" and changes["more-infinite-research"] or nil
  return type(change) == "table" and PUBLISHED_F200_M4_VERSIONS[change.old_version] == true
    and change.new_version == platform_target.distribution_version
end

local function legacy_candidates(force, worker_name, direct_f200_hop)
  local candidates = {}
  for index = 1, #ORDERED_DECLARATIONS do
    local row = ORDERED_DECLARATIONS[index]
    local admitted = false
    if row.enabled then
      if row.ownership_kind == "authored_generated" then
        admitted = authored_generated_admitted(force, row)
      else
        admitted = native_owner_admitted(force, row)
      end
    elseif row.ownership_kind == "authored_generated"
        and authored_generated_prototype_disabled(force, row) ~= nil then
      -- A user-disabled family retains this authored identity with a disabled
      -- prototype. Keep only an already-proven V3 cap right until a later
      -- enabled configuration can reconcile it; science/lab policy-disabled
      -- rows remain in the enabled branch and are not deferred here.
      admitted = true
    end
    if admitted then
      local candidate
      if direct_f200_hop then
        candidate = legacy_caps.f200_direct_hop_candidate(row.declaration)
      else
        candidate = {name = row.id, setting = row.cap_setting,
          source = row.source, operation = row.operation}
      end
      if candidate then
        candidate.admitted = true
        candidates[#candidates + 1] = candidate
      end
    end
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
      if name == WORKER_TAIL_NAMES[1] or name == WORKER_TAIL_NAMES[2] then
        owned[name].worker_effect_modifier = worker_modifier(name)
      end
    end
  end
end

-- This is the sole reader of the published bucket. It is deliberately called
-- only by on_configuration_changed: initialization and load never transport
-- historical cap rights into a new save.
local function import_legacy_caps_on_configuration(event)
  local mir = storage.mir
  local legacy_bucket = type(mir) == "table" and mir.maximum_level_control or nil
  if legacy_bucket == nil then return nil end

  local current = existing_state()
  if current and current.legacy_caps_checked == true then return nil end
  current = ensure_state()
  -- Preserve this marker even when no candidate is currently admitted or the
  -- old bucket is malformed. A reused force index must never re-open import.
  current.legacy_caps_checked = true

  -- An old cap bucket cannot report which engine wrote it.  Only this exact
  -- package-change event permits current F210 rows to use the separately
  -- constructed F200 predecessor tuple; ordinary/malformed/no-event F210
  -- imports remain on the transported-only allowlist.
  local direct_f200_hop = direct_f200_to_f210_transition(event)
  -- The one-time marker above keeps this exceptional construction out of
  -- ordinary control parsing, cold loads and subsequent configurations.
  local allowlist = direct_f200_hop and legacy_caps.f200_direct_hop_allowlist(DECLARATIONS)
    or LEGACY_ALLOWLIST

  local selected_owners = {}
  if not game or not game.forces then return selected_owners end
  for _, force in pairs(game.forces) do
    if valid_force(force) then
      -- Revalidate the native tail even if the new worker cap is unlimited;
      -- importing its historical restoration right still depends on that
      -- exact current owner.
      local owner = worker_owner(force)
      selected_owners[force.index] = owner
      local _, admitted = full_limits_for(force, true, owner, true)
      local owned = discard_unbound_ownership(force, current.owned_disabled, admitted, owner)
      local rows = legacy_caps.import_for_force(legacy_bucket, force,
        legacy_candidates(force, owner, direct_f200_hop), owned, allowlist)
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

local function reconcile_event(event, research_only)
  local force = event_force(event)
  if not force then return end
  -- These callbacks are registered only while finite caps are active. Keep
  -- the defensive direct-call path allocation-free for an unlimited fresh
  -- save, while still restoring a retained owned or legacy-marker state.
  local current = CAPS_ACTIVE and ensure_state() or existing_state()
  if not current then return end
  local research = event and event.research
  local name = research_only and research and research.name or nil
  if research_only and type(name) ~= "string" then return end
  reconcile_force(force, current.owned_disabled, nil, false, name)
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
  diagnostic_named_forces("init-before")
  reconcile_all(false)
  diagnostic_named_forces("init-after")
end

function M.on_configuration_changed(event)
  diagnostic_named_forces("configuration-before")
  reconcile_all(true, import_legacy_caps_on_configuration(event))
  diagnostic_named_forces("configuration-after")
end

function M.on_force_created(event)
  local force = event and event.force
  diagnostic_force("force-created-before", force, nil)
  if valid_force(force) then clear_force(force.index) end
  reconcile_event(event)
  diagnostic_force("force-created-after", force, nil)
end

function M.on_force_reset(event)
  local force = event and event.force
  diagnostic_force("force-reset-before", force, nil)
  if valid_force(force) then clear_force(force.index) end
  reconcile_event(event)
  diagnostic_force("force-reset-after", force, nil)
end

function M.on_forces_merged(event)
  clear_force(event and event.source_index)
  reconcile_event(event)
end

function M.on_research_finished(event)
  diagnostic_force("research-finished-before", event_force(event), event and event.research)
  reconcile_event(event, true)
  diagnostic_force("research-finished-after", event_force(event), event and event.research)
end

function M.on_research_reversed(event)
  diagnostic_force("research-reversed-before", event_force(event), event and event.research)
  reconcile_event(event, true)
  diagnostic_force("research-reversed-after", event_force(event), event and event.research)
end

function M.on_technology_effects_reset(event)
  diagnostic_force("technology-effects-reset-before", event_force(event), nil)
  reconcile_event(event)
  diagnostic_force("technology-effects-reset-after", event_force(event), nil)
end

function M.on_research_started(event)
  diagnostic_force("research-started-before", event_force(event), event and event.research)
  reconcile_event(event, true)
  diagnostic_force("research-started-after", event_force(event), event and event.research)
end

function M.on_research_cancelled(event)
  diagnostic_force("research-cancelled-before", event_force(event), event and event.research)
  reconcile_event(event, true)
  diagnostic_force("research-cancelled-after", event_force(event), event and event.research)
end

-- There are no local bindings to reconstruct. The parse-time bootstrap owns
-- event registration; this callback must never initialize storage or touch
-- game on host reload or a joining client.
function M.on_load()
end

return M
