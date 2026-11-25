-- Runtime composition for the first native gear slice.  Persistent ownership
-- is limited to transitions made by runtime.caps; native research remains the
-- authority for levels, completed effects, current research, and progress.
local caps = require("runtime.caps")
local legacy_caps = require("runtime.legacy_caps")
local native_owners = require("research.native_owners")
local cap_admission = require("runtime.cap_admission")
local catalogue = require("runtime.catalogue")
local DISCOVERY_TREE = script and script.active_mods and script.active_mods.discovery_tree ~= nil
local platform_target = require("platform.target")

local M = {}

local STORAGE_KEY = "mir_caps"
local SCHEMA = 1
local WORKER_TAIL_NAMES = {"worker-robots-speed-6", "worker-robots-speed-7", "worker-robots-speed-10"}
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

local function catalogue_export(name)
  local exported = catalogue[name]
  if type(exported) ~= "function" then error("MIR caps requires callable " .. name, 2) end
  return exported
end

-- Resolve the authored catalogue and immutable startup values once while
-- control is parsed. Event paths use these compact maps; they never ask the
-- catalogue to rebuild or scan a family list.
local DECLARATIONS = catalogue_export("declared")()
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
  if declaration.fixed_maximum ~= nil then
    if declaration.id ~= "worker-robots-storage-4" or declaration.family ~= "worker-robots-storage"
        or declaration.fixed_maximum ~= 4 then
      error("MIR caps invalid worker storage head declaration", 2)
    end
    row.fixed_maximum = 4
    -- Before the first completion, repeated queued head entries are still
    -- native work. The worker lifecycle moves them to the stable tail before
    -- this cap starts retiring the completed public head.
    CAPS_ACTIVE = true
  end
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
-- Metadata only nominates these bounded declarations. A live exact prototype
-- and an existing caps ledger are still required before any flag is restored.
local RESTORATION_BY_ID = {}
local RESTORATION_DECLARATIONS = catalogue_export("restoration_only")()
local LEGACY_RESTORATION_DECLARATIONS = {}
for index, declaration in ipairs(DECLARATIONS) do LEGACY_RESTORATION_DECLARATIONS[index] = declaration end
for _, declaration in ipairs(RESTORATION_DECLARATIONS) do
  RESTORATION_BY_ID[declaration.id] = {declaration=declaration}
  LEGACY_RESTORATION_DECLARATIONS[#LEGACY_RESTORATION_DECLARATIONS + 1] = declaration
end
-- Default target authority comes from package materialization, never saved
-- state. Current F200 declarations admit settings-derived V3; other targets
-- retain ordinary transported V3 admission. The one-time reader below may
-- additionally consider exact published F200 predecessor tuples.
local LEGACY_ALLOWLIST = legacy_caps.allowlist(LEGACY_RESTORATION_DECLARATIONS, platform_target.id)
-- Actual info.json versions from the hash-checked structured MIR4 F200 ZIPs.
-- RC/stable4.2 F200 share a value. Exact F2104.2 metadata is4.2.21000;
-- the earlier contradictory archive observation is retained with a correction.
-- This event gate therefore permits an additional reader, never replaces the
-- ordinary F210 reader or identifies an engine from the version text alone.
local PUBLISHED_F200_M4_VERSIONS = {
  ["4.2.20000"] = true,
  ["4.2.20001"] = true,
  ["4.2.20002"] = true,
  ["4.3.20000"] = true,
  ["4.4.20000"] = true,
  ["4.4.20001"] = true,
  ["4.4.20002"] = true,
  ["4.5.20000"] = true,
  ["4.5.20001"] = true,
  ["4.5.20002"] = true,
  ["4.6.20000"] = true,
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
local function effective_limit(row, force)
  if row.fixed_maximum ~= nil then
    return bounded_useful_limit(row.limit, row.fixed_maximum)
  end
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

local function ensure_state()
  local value = existing_state()
  if value then return value end
  value = {schema = SCHEMA, owned_disabled = {}}
  storage[STORAGE_KEY] = value
  return value
end

-- Paid worker settlement already applied the cap without enabling the
-- successor. Record the eligibility observed on the retired holder.
function M.record_completed_worker_cap(force, restore_enabled)
  local state = ensure_state()
  local owned = state.owned_disabled[force.index] or {}
  local name = "mir-worker-storage-default-4"
  local record = owned[name] or {}
  if record.disabled == nil or not restore_enabled then record.disabled = restore_enabled end
  owned[name] = record
  state.owned_disabled[force.index] = owned
end

-- The native split moves the old repeat levels and their force flags to the
-- stable tail. Move the existing cap restoration right with that work; a
-- false flag alone never authorizes MIR to enable a technology later.
function M.preflight_worker_storage_split_caps(plan)
  if plan and plan.kind == "default-native-provider-handover" then
    local state = existing_state()
    if not state then return nil end
    local items = {}
    for _, item in ipairs(plan.items) do
      local owned = state.owned_disabled[item.force.index]
      if owned ~= nil and type(owned) ~= "table" then error("MIR invalid worker cap ownership", 2) end
      if owned then
        local records, snapshots = {}, {}
        for _, name in ipairs({"worker-robots-storage-4", "mir-worker-storage-default-4"}) do
          local record = owned[name]
          if record ~= nil then
            if type(record) ~= "table" then error("MIR invalid retiring worker cap right", 2) end
            local copy = {}
            for key, value in pairs(record) do
              if (key ~= "disabled" and key ~= "visible_when_disabled" and key ~= "discovery_enabled")
                  or type(value) ~= "boolean" then error("MIR invalid retiring worker cap right", 2) end
              copy[key] = value
            end
            records[name], snapshots[name] = record, copy
          end
        end
        local public = item.force.technologies["worker-robots-storage-4"]
        if not public or not public.prototype or type(public.prototype.enabled) ~= "boolean"
            or type(public.prototype.visible_when_disabled) ~= "boolean" then
          error("MIR incoming worker provider flags are unavailable", 2)
        end
        items[#items + 1] = {force=item.force, owned=owned, records=records, snapshots=snapshots,
          public=public, returned_flags=item.returning ~= nil}
      end
    end
    return {kind="provider-handover", state=state, items=items}
  end
  if not plan or plan.kind ~= "default-native-owner-transfer" or plan.already_owned then return nil end
  local state = existing_state()
  if not state then return nil end
  local items = {}
  for _, item in ipairs(plan.items) do
    local owned = state.owned_disabled[item.force.index]
    if owned ~= nil and type(owned) ~= "table" then error("MIR invalid worker cap ownership", 2) end
    local record = owned and owned["worker-robots-storage-4"]
    if item.moved == true and record ~= nil then
      if type(record) ~= "table" or owned["mir-worker-storage-default-4"] ~= nil then
        error("MIR conflicting worker cap restoration rights", 2)
      end
      local snapshot = {}
      for key, value in pairs(record) do
        if (key ~= "disabled" and key ~= "visible_when_disabled" and key ~= "discovery_enabled")
            or type(value) ~= "boolean" then error("MIR invalid worker cap restoration right", 2) end
        snapshot[key] = value
      end
      items[#items + 1] = {owned=owned, record=record, snapshot=snapshot}
    end
  end
  return {state=state, items=items}
end

function M.apply_worker_storage_split_caps(plan)
  if not plan then return end
  if existing_state() ~= plan.state then error("MIR worker cap ownership changed after preflight", 2) end
  if plan.kind == "provider-handover" then
    for _, item in ipairs(plan.items) do
      if plan.state.owned_disabled[item.force.index] ~= item.owned
          or item.force.technologies["worker-robots-storage-4"] ~= item.public then
        error("MIR worker cap recipient changed after preflight", 2)
      end
      for _, name in ipairs({"worker-robots-storage-4", "mir-worker-storage-default-4"}) do
        local record, snapshot = item.records[name], item.snapshots[name]
        if item.owned[name] ~= record then error("MIR retiring worker cap right changed", 2) end
        for key, value in pairs(record or {}) do
          if snapshot[key] ~= value then error("MIR retiring worker cap right changed", 2) end
        end
        for key, value in pairs(snapshot or {}) do
          if record[key] ~= value then error("MIR retiring worker cap right changed", 2) end
        end
      end
    end
    for _, item in ipairs(plan.items) do
      local record = item.snapshots["worker-robots-storage-4"]
      local public = item.public
      -- The worker releases its own retirement flag. These positive cap
      -- rights release only additional MIR writes, under incoming policy.
      -- A negative cap baseline may have observed that retired head; it must
      -- not disable the newly admitted provider or enable the retired owner.
      if record and not item.returned_flags then
        if (record.disabled == true or record.discovery_enabled == true) and public.prototype.enabled then
          public.enabled = true
        end
        if record.visible_when_disabled == false and public.visible_when_disabled == true
            and not public.prototype.visible_when_disabled then public.visible_when_disabled = false end
      end
      item.owned["worker-robots-storage-4"], item.owned["mir-worker-storage-default-4"] = nil, nil
      if next(item.owned) == nil then plan.state.owned_disabled[item.force.index] = nil end
    end
    return
  end
  for _, item in ipairs(plan.items) do
    if item.owned["worker-robots-storage-4"] ~= item.record
        or item.owned["mir-worker-storage-default-4"] ~= nil then
      error("MIR worker cap rights changed after preflight", 2)
    end
    for key, value in pairs(item.record) do
      if item.snapshot[key] ~= value then error("MIR worker cap right changed after preflight", 2) end
    end
    for key, value in pairs(item.snapshot) do
      if item.record[key] ~= value then error("MIR worker cap right changed after preflight", 2) end
    end
  end
  for _, item in ipairs(plan.items) do
    item.owned["mir-worker-storage-default-4"] = item.record
    item.owned["worker-robots-storage-4"] = nil
  end
end

local reconciliation_depth = 0

local function discard_empty_state(value)
  if reconciliation_depth == 0 and next(value.owned_disabled) == nil and value.legacy_caps_checked ~= true then
    storage[STORAGE_KEY] = nil
  end
end

-- Native queue writes can synchronously start another research callback.
-- Keep the shared state attached until every active reconciler has finished
-- writing its rights. An inner callback cannot retire an outer writer's empty
-- table. This is transient call state, never another saved ownership record.
local function reconcile_with_state(callback, ...)
  reconciliation_depth = reconciliation_depth + 1
  local ok, reason = pcall(callback, ...)
  reconciliation_depth = reconciliation_depth - 1
  if not ok then error(reason, 0) end
  if reconciliation_depth == 0 then
    local current = existing_state()
    if current then discard_empty_state(current) end
  end
end

local function valid_force(force)
  return force and force.valid ~= false and type(force.index) == "number"
end

local function known_worker_tail(name)
  for index = 1, #WORKER_TAIL_NAMES do
    if name == WORKER_TAIL_NAMES[index] then return true end
  end
  return false
end

local function excluded_family_member(name, excluded_family)
  if excluded_family == nil then return false end
  local row = DECLARATION_BY_ID[name] or RESTORATION_BY_ID[name]
  if row then return (row.family or row.declaration.family) == excluded_family end
  return excluded_family == "worker-robots-speed" and known_worker_tail(name)
end

local function has_worker_ownership(owned)
  if type(owned) ~= "table" then return false end
  for index = 1, #WORKER_TAIL_NAMES do
    if type(owned[WORKER_TAIL_NAMES[index]]) == "table" then return true end
  end
  return false
end

local function worker_owner(force, observed)
  if not valid_force(force) then return nil end
  if observed and observed.worker_observed then return observed.worker end
  local technologies = force.technologies
  return native_owners.runtime_worker_robot_speed_owner(function(name)
    return technologies and technologies[name] or nil
  end, worker_modifiers)
end

local function preflight_worker_owners(forces, admissions)
  local planned = {}
  if not forces then return planned end
  for _, force in pairs(forces) do
    if valid_force(force) then
      -- Keep an explicit row even when the current native shape has no
      -- admissible owner. The importer must consume this one observed result,
      -- rather than treating nil as a reason to read after its marker write.
      planned[force.index] = {owner = worker_owner(force, admissions and admissions[force.index])}
    end
  end
  return planned
end

local function native_owner_admitted(force, row, observed)
  if observed then return observed.native[row.declaration.id] == true end
  return valid_force(force) and cap_admission.admits_native_owner(function(name)
    return force.technologies and force.technologies[name] or nil
  end, row.declaration, row.configured_effect_change)
end

local function authored_generated_prototype_state(force, row)
  if not valid_force(force) then return nil end
  local phase = "technology lookup"
  local ok, technology, enabled = pcall(function()
    local technologies = force.technologies
    local technology = technologies and technologies[row.id] or nil
    if not technology then return nil end
    phase = "prototype lookup"
    local prototype = technology.prototype
    if not prototype then return technology, nil end
    phase = "prototype enabled"
    return technology, prototype.enabled
  end)
  if not ok then
    -- Failed native observations cannot authenticate disappearance and must
    -- not let either consumer discard an existing restoration right.
    -- Preserve a structured native error object instead of flattening its
    -- identity; ordinary string failures also name the technology and phase.
    if type(technology) ~= "string" then error(technology, 0) end
    error("MIR authored cap " .. phase .. " failed for " .. row.id .. ": " .. technology, 2)
  end
  return technology, enabled
end

-- Startup settings decide whether a stream may be considered, but the data
-- stage can retain its identity with prototype.enabled=false when science or
-- lab policy rejects it. Only that immutable default distinguishes the latter
-- from a per-force cap disablement, so do not use ForceTechnology.enabled.
local function authored_generated_admitted(force, row, observed)
  if not valid_force(force) then return false end
  if observed then return observed.authored[row.id] == true end
  local _, enabled = authored_generated_prototype_state(force, row)
  return enabled == true
end

-- A retained generated identity can be deliberately disabled by the data
-- policy while its completed native effects remain in the save.  Its immutable
-- prototype default, rather than ForceTechnology.enabled, identifies that
-- state: the latter is also how a finite cap or another mod disables research.
local function authored_generated_prototype_disabled(force, row, observed)
  if not valid_force(force) then return nil end
  if observed then return observed.disabled[row.id] end
  local technology, enabled = authored_generated_prototype_state(force, row)
  if enabled == false then return technology end
  return nil
end

local function retained_authored_prototype_disablement(force, name, observed)
  local row = DECLARATION_BY_ID[name]
  if not row or row.ownership_kind ~= "authored_generated" then return false end
  return authored_generated_prototype_disabled(force, row, observed) ~= nil
end

local retired_work_observer

function M.set_retired_work_observer(observer)
  retired_work_observer = observer
end

-- This runs at configuration and rare force/effects-reset boundaries over
-- the compact authored list. It never enumerates a force's technologies.
-- A record exists only after this runtime changed an enabled technology to
-- disabled, so later cap relaxation can restore neither a data-stage default
-- nor foreign pre-disablement.
local function disable_authored_prototype(force, name, technology, owned_disabled, imported_reenabled)
  local owned = owned_disabled[force.index]
  if type(owned) ~= "table" then
    owned = {}
    owned_disabled[force.index] = owned
  end
  local record = owned[name]
  if type(record) ~= "table" then
    owned[name] = {disabled = true}
  elseif record.disabled == nil then
    -- Only a newly imported, exact V3 positive proof can accompany this
    -- first policy write. Existing visibility-only/negative decisions
    -- remain foreign; resets cannot manufacture a restoration right.
    record.disabled = imported_reenabled ~= nil and imported_reenabled[name] == record
  end
  technology.enabled = false
end

local function reconcile_authored_prototype_disablement(force, owned_disabled, imported_reenabled, observed, excluded_family)
  if not valid_force(force) then return false end
  for index = 1, #ORDERED_DECLARATIONS do
    local row = ORDERED_DECLARATIONS[index]
    if row.family ~= excluded_family and row.ownership_kind == "authored_generated" then
      local technology = authored_generated_prototype_disabled(force, row, observed)
      if technology and technology.enabled == true and not (retired_work_observer and retired_work_observer(force, row.id)) then
        -- The caller probes with nil before allocating durable storage for an
        -- otherwise unlimited save.
        if type(owned_disabled) ~= "table" then return true end
        disable_authored_prototype(force, row.id, technology, owned_disabled, imported_reenabled)
      end
    end
  end
  return false
end

function M.reconcile_retired_paid_work(force, name, last_payable_level)
  local row = DECLARATION_BY_ID[name]
  if not row or row.ownership_kind ~= "authored_generated" then return end
  local technology = authored_generated_prototype_disabled(force, row)
  if not technology then return end
  reconcile_with_state(function()
    if last_payable_level ~= nil then
      -- Release only MIR's recorded disablement while this exact native
      -- allowance exists. The cap also preserves the ordered queue prefix.
      local _, result = caps.reconcile(force, {[name] = last_payable_level}, ensure_state().owned_disabled)
      if result.unresolved_current then error("MIR cannot enforce the retired research allowance: " .. name, 2) end
    else
      caps.remove_unavailable_from_queue(force, {[name] = true})
      if technology.enabled == true then
        disable_authored_prototype(force, name, technology, ensure_state().owned_disabled)
      end
    end
  end)
end

local function cancel_unavailable_research(force, observed, excluded_family)
  -- Native technology.saved_progress is the modern saved-work surface. Older
  -- engine adapters retain their existing cap/queue behavior.
  if platform_target.factorio_version ~= "2.0" and platform_target.factorio_version ~= "2.1" then return end
  if not valid_force(force) then return end
  local unavailable
  local function inspect(technology)
    local name = technology and technology.name
    local row = name and DECLARATION_BY_ID[name]
    if row and row.family ~= excluded_family and row.ownership_kind == "authored_generated"
        and row.declaration.cancel_queued_when_unavailable == true
        and authored_generated_prototype_disabled(force, row, observed) then
      unavailable = unavailable or {}
      unavailable[name] = true
    end
  end
  -- Inspect actual queued/current identities, not every force technology or
  -- the authored catalogue on each research event. Force-only disablement is
  -- not a prototype-policy decision and gives no authority to cancel it.
  inspect(force.current_research)
  for _, technology in ipairs(force.research_queue or {}) do inspect(technology) end
  if unavailable then caps.remove_unavailable_from_queue(force, unavailable) end
end

local function full_limits_for(force, include_worker, selected_owner, owner_resolved, observed, excluded_family)
  local limits, admitted = {}, {}
  if valid_force(force) then
    for name, row in pairs(STATIC_GENERATED_BY_ID) do
      if row.family ~= excluded_family and authored_generated_admitted(force, row, observed) then
        limits[name], admitted[name] = effective_limit(row, force), true
      end
    end
    for name, row in pairs(NATIVE_OWNER_BY_ID) do
      if row.family ~= excluded_family and row.enabled and native_owner_admitted(force, row, observed) then
        limits[name], admitted[name] = effective_limit(row, force), true
      end
    end
    for name, row in pairs(RESTORATION_BY_ID) do
      if not excluded_family_member(name, excluded_family)
          and native_owner_admitted(force, row, observed) then admitted[name] = true end
    end
    if excluded_family ~= "worker-robots-speed" and (WORKER_ROBOT_SPEED_LIMIT > 0 or include_worker) then
      local owner = selected_owner
      if not owner_resolved then owner = worker_owner(force, observed) end
      if owner then limits[owner], admitted[owner] = WORKER_ROBOT_SPEED_LIMIT, true end
      return limits, admitted, owner
    end
  end
  return limits, admitted, selected_owner
end

local function event_limits_for(force, name, include_worker, observed)
  local row = DECLARATION_BY_ID[name]
  if row and row.enabled then
    if row.ownership_kind == "authored_generated" and authored_generated_admitted(force, row, observed) then
      return {[name] = effective_limit(row, force)}, {[name] = true}, nil
    elseif row.ownership_kind == "nativeowner" and native_owner_admitted(force, row, observed) then
      return {[name] = effective_limit(row, force)}, {[name] = true}, nil
    end
  end
  if known_worker_tail(name) then
    local owner = worker_owner(force, observed)
    if owner == name and (WORKER_ROBOT_SPEED_LIMIT > 0 or include_worker) then
      return {[name] = WORKER_ROBOT_SPEED_LIMIT}, {[name] = true}, owner
    end
  end
  return nil, nil, nil
end

-- Observe the bounded declarations before dependent cap/queue/storage writes.
-- Named research events observe their subject and unavailable queued rows;
-- rare all-force events observe the authored list. Application consumes these
-- facts rather than repeating admission reads after an earlier force changed.
local function preflight_cap_admissions(forces, target_name, legacy, excluded_family)
  local planned = {}
  local current = existing_state()
  for _, force in pairs(forces or {}) do
    if valid_force(force) then
      local observed = {native = {}, authored = {}, disabled = {}}
      local function inspect(row)
        if excluded_family_member(row.id, excluded_family) then return end
        if row.ownership_kind == "nativeowner" then
          observed.native[row.id] = native_owner_admitted(force, row)
        else
          local technology, enabled = authored_generated_prototype_state(force, row)
          observed.authored[row.id] = enabled == true
          if enabled == false then observed.disabled[row.id] = technology end
        end
      end
      if target_name then
        local row = DECLARATION_BY_ID[target_name]
        if row then inspect(row) end
        local restoration = RESTORATION_BY_ID[target_name]
        if restoration and not excluded_family_member(target_name, excluded_family) then
          observed.native[target_name] = native_owner_admitted(force, restoration)
        end
        local function inspect_queued(technology)
          local row = technology and DECLARATION_BY_ID[technology.name]
          if row and row.ownership_kind == "authored_generated"
              and row.declaration.cancel_queued_when_unavailable == true then inspect(row) end
        end
        inspect_queued(force.current_research)
        for _, technology in ipairs(force.research_queue or {}) do inspect_queued(technology) end
      else
        for _, row in ipairs(ORDERED_DECLARATIONS) do inspect(row) end
        for name, row in pairs(RESTORATION_BY_ID) do
          if not excluded_family_member(name, excluded_family) then
            observed.native[name] = native_owner_admitted(force, row)
          end
        end
      end
      local owned = current and current.owned_disabled[force.index]
      local include_worker = has_worker_ownership(owned)
      if excluded_family ~= "worker-robots-speed" and (legacy
          or (target_name == nil and (WORKER_ROBOT_SPEED_LIMIT > 0 or include_worker))
          or known_worker_tail(target_name)) then
        observed.worker = worker_owner(force)
        observed.worker_observed = true
      end
      -- Resolve named recipe caps before allocating state or importing legacy
      -- markers as well. This is not a second native-admission observation.
      if target_name then event_limits_for(force, target_name, include_worker, observed)
      else full_limits_for(force, include_worker, nil, false, observed, excluded_family) end
      planned[force.index] = observed
    end
  end
  return planned
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

function M.discovery_visibility(force)
  local visible = {}
  if not DISCOVERY_TREE or not valid_force(force) then return visible end
  local current = existing_state()
  local owned = current and current.owned_disabled[force.index]
  for name, record in pairs(owned or {}) do
    if type(record) == "table" and record.discovery_enabled == true
        and (DECLARATION_BY_ID[name] ~= nil or known_worker_tail(name)) then
      visible[name] = true
    end
  end
  return visible
end

-- A cap record binds to a current authored identity. If a feature is disabled,
-- an owner no longer matches its exact effect contract, or a worker tail is
-- superseded, discard only MIR's future restoration right. This fails closed:
-- no uncertain ownership is converted into an enablement write.
local function discard_unbound_ownership(force, owned_disabled, admitted, owner, workers_only, observed, excluded_family)
  local owned = owned_disabled[force.index]
  if type(owned) ~= "table" then return owned end
  for name, row in pairs(owned) do
    if not excluded_family_member(name, excluded_family) and (not workers_only or known_worker_tail(name)) then
      -- A disabled authored prototype keeps a record that this runtime
      -- actually wrote. It must remain disabled until that prototype is
      -- admitted again, when caps.reconcile can restore only this proven right.
      if admitted[name] ~= true and not retained_authored_prototype_disablement(force, name, observed) then
        owned[name] = nil
      elseif known_worker_tail(name) then
        local row = owned[name]
        if type(row) == "table" then
          -- Earlier private MIR5 rows could only represent the 0.65 variant.
          -- Historical MIR4 imports are stamped with their admitted variant.
          local modifier = row.worker_effect_modifier
          if modifier == nil then modifier = 0.65 end
          if name ~= owner or modifier ~= worker_modifier(name) then owned[name] = nil end
        elseif row ~= false or name ~= owner then
          -- A false tombstone for the admitted current owner grants no
          -- effect/restoration right. Keep it ahead of historical imports;
          -- deleting it here would let an older ledger reclaim ownership.
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

local function restore_withheld_caps(force, owned_disabled, target_name, discovery_observed, observed, excluded_family)
  local owned = type(owned_disabled) == "table" and owned_disabled[force.index] or nil
  if type(owned) ~= "table" then return end
  local release = {}
  for name, row in pairs(RESTORATION_BY_ID) do
    if not excluded_family_member(name, excluded_family)
        and (target_name == nil or target_name == name) and type(owned[name]) == "table"
        and native_owner_admitted(force, row, observed) then
      -- caps.reconcile visits supplied limits only. Zero here releases this
      -- existing ledger; no zero entry is exposed as a selected/new cap.
      release[name] = 0
    end
  end
  if next(release) ~= nil then
    caps.reconcile(force, release, owned_disabled, nil, nil, discovery_observed)
  end
end

local function reconcile_force(force, owned_disabled, selected_owner, owner_resolved, target_name, imported_reenabled,
    discovery_observed, observed, excluded_family)
  if not valid_force(force) then return end
  local owned = type(owned_disabled) == "table" and owned_disabled[force.index] or nil
  local include_worker = has_worker_ownership(owned)
  local observation
  if DISCOVERY_TREE then observation = discovery_observed == true end
  local limits, admitted, owner
  if target_name then
    limits, admitted, owner = event_limits_for(force, target_name, include_worker, observed)
    if limits == nil then
      restore_withheld_caps(force, owned_disabled, target_name, observation, observed, excluded_family)
      owned = type(owned_disabled) == "table" and owned_disabled[force.index] or nil
      if type(owned_disabled) == "table" and owned and owned[target_name] ~= nil
          and not retained_authored_prototype_disablement(force, target_name, observed) then
        owned[target_name] = nil
        if next(owned) == nil then owned_disabled[force.index] = nil end
      end
      return
    end
  else
    limits, admitted, owner = full_limits_for(force, include_worker, selected_owner, owner_resolved, observed, excluded_family)
  end
  if type(owned_disabled) == "table" then
    if target_name then
      local row = owned_disabled[force.index]
      if type(row) == "table" and row[target_name] ~= nil and admitted[target_name] ~= true
          and not retained_authored_prototype_disablement(force, target_name, observed) then
        row[target_name] = nil
        if next(row) == nil then owned_disabled[force.index] = nil end
      end
      if known_worker_tail(target_name) then
        discard_unbound_ownership(force, owned_disabled, admitted, owner, true, observed, excluded_family)
      end
    else
      owned = discard_unbound_ownership(force, owned_disabled, admitted, owner, nil, observed, excluded_family)
    end
  end
  local targets = target_name and {[target_name] = true} or nil
  local _, result = caps.reconcile(force, limits, owned_disabled, targets, imported_reenabled, observation)
  if target_name == nil then restore_withheld_caps(force, owned_disabled, nil, observation, observed, excluded_family) end
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

local function force_snapshot()
  local registry = game and game.forces
  if registry == nil then return nil end
  -- Indexed access can throw for a genuinely deleted force. Observe the
  -- complete current registry once instead, before any ownership cleanup.
  -- An iteration/property failure propagates without inventing absence.
  local forces = {}
  for _, force in pairs(registry) do
    if valid_force(force) then forces[force.index] = force end
  end
  return forces
end

local function stale_force_indices(forces)
  local stale = {}
  local existing = existing_state()
  if existing then
    for index in pairs(existing.owned_disabled) do
      if not forces[index] then stale[#stale + 1] = index end
    end
  end
  return stale
end

local function reconcile_all_body(clean_stale_forces, selected_owners, imported_reenabled, discovery_observed, admissions, stale, observed_forces)
  local forces = observed_forces or force_snapshot()
  if forces == nil then return end
  admissions = admissions or preflight_cap_admissions(forces)
  stale = stale or (clean_stale_forces and stale_force_indices(forces) or {})
  -- Unlimited startup settings need no state unless a previous finite setting
  -- left an ownership transition that has to be restored exactly once, or an
  -- authored disabled prototype is currently force-enabled and needs this
  -- module's one recorded disablement.
  local current = CAPS_ACTIVE and ensure_state() or existing_state()
  local owned_disabled = current and current.owned_disabled or nil
  if current and clean_stale_forces then
    for _, index in ipairs(stale) do owned_disabled[index] = nil end
  end
  for _, force in pairs(forces) do
    local observed = valid_force(force) and admissions[force.index] or nil
    if current == nil and reconcile_authored_prototype_disablement(force, nil, nil, observed) then
      current = ensure_state()
      owned_disabled = current.owned_disabled
    end
    if current then
      reconcile_authored_prototype_disablement(force, owned_disabled,
        imported_reenabled and imported_reenabled[force.index], observed)
    end
    -- Preserve unavailable current investment before any cap reconciliation
    -- can rewrite the same native queue and drop its now-disabled head.
    cancel_unavailable_research(force, observed)
    local owner_plan = valid_force(force) and selected_owners and selected_owners[force.index] or nil
    local owner = owner_plan and owner_plan.owner or nil
    if current then
      reconcile_force(force, owned_disabled, owner, selected_owners ~= nil, nil,
        imported_reenabled and imported_reenabled[force.index], discovery_observed, observed)
    end
  end
  if current then discard_empty_state(current) end
end

local function reconcile_all(...)
  reconcile_with_state(reconcile_all_body, ...)
end

local function direct_f200_to_f210_transition(event)
  if platform_target.id ~= "f210" or type(event) ~= "table" then return false end
  local changes = event.mod_changes
  local change = type(changes) == "table" and changes["more-infinite-research"] or nil
  return type(change) == "table" and PUBLISHED_F200_M4_VERSIONS[change.old_version] == true
    and change.new_version == platform_target.distribution_version
end

local function legacy_candidates(force, worker_name, direct_f200_hop, observed)
  local candidates = {}
  for index = 1, #ORDERED_DECLARATIONS do
    local row = ORDERED_DECLARATIONS[index]
    local admitted = false
    if row.enabled then
      if row.ownership_kind == "authored_generated" then
        admitted = authored_generated_admitted(force, row, observed)
        if not admitted and row.declaration.retain_unavailable_cap_right == true then
          -- The named Bob material stages can retain an unchanged effect
          -- vector unavailable. Decode an exact old cap right while dormant;
          -- this marker creates no right and cannot enable a disabled default.
          admitted = authored_generated_prototype_disabled(force, row, observed) ~= nil
        end
      else
        admitted = native_owner_admitted(force, row, observed)
      end
    elseif row.ownership_kind == "authored_generated"
        and authored_generated_prototype_disabled(force, row, observed) ~= nil then
      -- A user-disabled family retains this authored identity with a disabled
      -- prototype. Keep only an already-proven V3 cap right until a later
      -- enabled configuration can reconcile it; other policy-disabled rows
      -- remain in the enabled branch and are not deferred here.
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
  if not direct_f200_hop then
    for _, declaration in ipairs(RESTORATION_DECLARATIONS) do
      local name = declaration.id
      local row = RESTORATION_BY_ID[name]
      if native_owner_admitted(force, row, observed) then
        candidates[#candidates + 1] = {name=name, setting=declaration.cap_setting,
          source=declaration.legacy_binding.source, operation=declaration.legacy_binding.operation, admitted=true}
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

local function merge_legacy_rows(owned_disabled, force_index, rows, facts, imported_reenabled)
  local owned = owned_disabled[force_index]
  if owned ~= nil and type(owned) ~= "table" then
    error("MIR invalid caps ownership row", 2)
  end
  if next(rows) == nil then return end
  if owned == nil then
    owned = {}
    owned_disabled[force_index] = owned
  end
  local created = {}
  for name, row in pairs(rows) do
    -- The pure importer has already rejected an existing MIR5 row. Keep this
    -- guard at the persistence boundary so MIR5 ownership always wins.
    if owned[name] == nil then
      owned[name] = {
        disabled = row.disabled == true and true or nil,
        visible_when_disabled = row.visible_when_disabled
      }
      created[name] = owned[name]
      if known_worker_tail(name) then
        owned[name].worker_effect_modifier = worker_modifier(name)
      end
    end
  end
  -- This signal lasts only through this configuration callback. Bind it to
  -- the table actually created here, never a pre-existing row or just a name.
  -- The decoder still imports no enablement right for a live-enabled row;
  -- the current policy below must make its own observed true -> false write.
  if facts.legacy_policy3 then
    for _, decision in ipairs(facts.decisions) do
      local record = created[decision.name]
      if decision.outcome == "visibility_imported_enablement_reenabled"
          and record and record.disabled == nil then
        local force_rows = imported_reenabled[force_index]
        if force_rows == nil then
          force_rows = {}
          imported_reenabled[force_index] = force_rows
        end
        force_rows[decision.name] = record
      end
    end
  end
end

-- This is the sole reader of the published bucket. It is deliberately called
-- only by on_configuration_changed: initialization and load never transport
-- historical cap rights into a new save.
local function import_legacy_caps_on_configuration(event, forces, admissions)
  local mir = storage.mir
  local legacy_bucket = type(mir) == "table" and mir.maximum_level_control or nil
  if legacy_bucket == nil then return nil end

  local current = existing_state()
  if current and current.legacy_caps_checked == true then return nil end

  -- A version label alone grants no per-row ownership. Retain ordinary tuple
  -- admission before the exceptional predecessor reader, and
  -- consider settings-derived V3 only for a known package-change event and
  -- schema. The decoder still requires the exact per-row provenance/state.
  local direct_f200_hop = type(legacy_bucket) == "table"
    and legacy_bucket.policy_version == 3 and direct_f200_to_f210_transition(event)
  -- The one-time marker below keeps this exceptional construction out of
  -- ordinary control parsing, cold loads and subsequent configurations.
  local f200_allowlist = direct_f200_hop and legacy_caps.f200_direct_hop_allowlist(DECLARATIONS)

  -- Bootstrap's immutable admission preflight precedes its worker writes.
  -- Decode mutable native flags/current ownership here, after those transfers
  -- settle; a pre-transfer ownership draft could reinstall a retired head.
  -- This local plan does not promise rollback of earlier bootstrap writers.
  -- Read and decode every force before consuming the one-time marker or
  -- changing persistent ownership. Pruning/import operate on transient maps;
  -- existing record objects remain shared but are never modified by either.
  local owner_plan = preflight_worker_owners(forces, admissions)
  local planned_owned, imported_reenabled = {}, {}
  for index, force in pairs(forces or {}) do
    local previous = current and current.owned_disabled[index]
    if previous ~= nil then
      if type(previous) ~= "table" then error("MIR legacy caps current ownership must be a table or nil", 2) end
      local copy = {}
      for name, record in pairs(previous) do copy[name] = record end
      planned_owned[index] = copy
    end
    -- Revalidate the native tail even if the new worker cap is unlimited;
    -- importing its historical restoration right still depends on that
    -- exact current owner.
    local observed = admissions[index]
    local plan = owner_plan[index]
    local owner = plan and plan.owner or nil
    local _, admitted = full_limits_for(force, true, owner, true, observed)
    local owned = discard_unbound_ownership(force, planned_owned, admitted, owner, nil, observed)
    -- Public policy-v1 used a distinct, boolean component ledger.  Its
    -- marker is the only selector here; both readers still receive the
    -- current preflighted candidate list and current ownership, so an old
    -- version label cannot manufacture a restoration right.
    local import_for_force = type(legacy_bucket) == "table" and legacy_bucket.policy_version == 1
      and legacy_caps.import_boolean_for_force or legacy_caps.import_for_force
    local rows, facts = import_for_force(legacy_bucket, force,
      legacy_candidates(force, owner, false, observed), owned, LEGACY_ALLOWLIST)
    merge_legacy_rows(planned_owned, index, rows, facts, imported_reenabled)
    if direct_f200_hop then
      local predecessor_rows, predecessor_facts = legacy_caps.import_for_force(legacy_bucket, force,
        legacy_candidates(force, owner, true, observed), planned_owned[index], f200_allowlist)
      merge_legacy_rows(planned_owned, index, predecessor_rows,
        predecessor_facts, imported_reenabled)
    end
  end

  current = ensure_state()
  -- The import commit performs no native reads or repeated decoding. Normal
  -- cap reconciliation subsequently uses these retained ownership results.
  for index in pairs(forces or {}) do
    local previous, planned = current.owned_disabled[index], planned_owned[index]
    if previous == nil or planned == nil then current.owned_disabled[index] = planned
    else
      for name in pairs(previous) do if planned[name] == nil then previous[name] = nil end end
      for name, record in pairs(planned) do previous[name] = record end
    end
  end
  -- A genuinely absent candidate or malformed payload still completes this
  -- one-time check; reused force indexes cannot reopen historical authority.
  current.legacy_caps_checked = true
  return owner_plan, imported_reenabled
end

local function event_force(event)
  local research = event and event.research
  if research and research.force and valid_force(research.force) then return research.force end
  if event and valid_force(event.force) then return event.force end
  if event and valid_force(event.destination) then return event.destination end
  return nil
end

local function clear_force(index, excluded_family)
  if type(index) ~= "number" then return end
  local current = existing_state()
  if not current then return end
  local owned = current.owned_disabled[index]
  if excluded_family and type(owned) == "table" then
    for name in pairs(owned) do
      if not excluded_family_member(name, excluded_family) then owned[name] = nil end
    end
    if next(owned) == nil then current.owned_disabled[index] = nil end
  else
    current.owned_disabled[index] = nil
  end
  discard_empty_state(current)
end

local function reconcile_event_body(event, research_only, discovery_observed, clear_index, excluded_family)
  -- One upstream discovery event can change every technology on its force.
  -- Reconcile only MIR's bounded admitted rows, rather than just the finished ID.
  if DISCOVERY_TREE and discovery_observed then research_only = false end
  local force = event_force(event)
  if not force then return end
  local research = event and event.research
  local name = research_only and research and research.name or nil
  if research_only and type(name) ~= "string" then return end
  local observed = preflight_cap_admissions({force}, name, false, excluded_family)[force.index]
  -- A failed observation must retain both source and destination rights.
  clear_force(clear_index, excluded_family)
  cancel_unavailable_research(force, observed, excluded_family)
  -- Named research callbacks need only cap reconciliation. Rare force/reset
  -- events also enforce authored disabled prototypes, even without a finite
  -- cap or prior ledger. Allocate only when an actual policy write is needed.
  local current = CAPS_ACTIVE and ensure_state() or existing_state()
  if not research_only then
    if current == nil and reconcile_authored_prototype_disablement(force, nil, nil, observed, excluded_family) then
      current = ensure_state()
    end
    if current then reconcile_authored_prototype_disablement(force, current.owned_disabled, nil, observed, excluded_family) end
  end
  if not current then return end
  reconcile_force(force, current.owned_disabled, nil, false, name, nil, discovery_observed, observed, excluded_family)
  discard_empty_state(current)
end

local function reconcile_event(...)
  reconcile_with_state(reconcile_event_body, ...)
end

-- Prototype admission is immutable during a runtime callback. Bootstrap can
-- observe it before another reconciler writes; the cap callback consumes the
-- same observations. This grants no native or storage mutation authority.
function M.preflight(configuration_changed)
  local mir = storage.mir
  local current = existing_state()
  local import_pending = configuration_changed and type(mir) == "table"
    and mir.maximum_level_control ~= nil and not (current and current.legacy_caps_checked == true)
  local forces = force_snapshot()
  local admissions = preflight_cap_admissions(forces, nil, import_pending)
  return {admissions = admissions, forces = forces,
    stale = configuration_changed and stale_force_indices(forces or {}) or {}}
end

function M.on_init(observed)
  observed = observed and observed.admissions and observed or M.preflight(false)
  if observed.forces then reconcile_all(false, nil, nil, true, observed.admissions, nil, observed.forces) end
end

function M.on_configuration_changed(event, observed)
  observed = observed or M.preflight(true)
  local owners, imported_reenabled = import_legacy_caps_on_configuration(event, observed.forces, observed.admissions)
  if observed.forces then
    reconcile_all(true, owners, imported_reenabled, true, observed.admissions, observed.stale, observed.forces)
  end
end

function M.on_force_created(event)
  local force = event and event.force
  reconcile_event(event, false, true, valid_force(force) and force.index or nil)
end

function M.on_force_reset(event)
  local force = event and event.force
  reconcile_event(event, false, true, valid_force(force) and force.index or nil)
end

function M.on_forces_merged(event, excluded_family)
  -- An unqualified family retains its native work and cap rights on both
  -- forces. Unrelated families still receive ordinary merge reconciliation.
  -- Force creation/reset clears every old right if an index is reused.
  reconcile_event(event, false, true, event and event.source_index, excluded_family)
end

function M.on_research_finished(event)
  reconcile_event(event, true, true)
end

function M.on_research_reversed(event)
  reconcile_event(event, true, true)
end

function M.on_technology_effects_reset(event)
  reconcile_event(event)
end

function M.on_research_started(event)
  reconcile_event(event, true)
end

function M.on_research_cancelled(event)
  if not M.on_discovery_tree_queue_changed(event) then reconcile_event(event, true) end
end

function M.on_discovery_tree_queue_changed(event)
  if not DISCOVERY_TREE then return false end
  local setting = settings and settings.global and settings.global["discovery-tree-consider-researched"]
  local mode = setting and setting.value
  if mode ~= "queued" and mode ~= "available-after-queue" then return false end
  reconcile_event(event, false, true)
  return true
end

function M.on_discovery_tree_changed(event)
  if not DISCOVERY_TREE then return end
  if event_force(event) then reconcile_event(event, false, true)
  else reconcile_all(false, nil, nil, true) end
end

-- There are no local bindings to reconstruct. The parse-time bootstrap owns
-- event registration; this callback must never initialize storage or touch
-- game on host reload or a joining client.
function M.on_load()
end

return M
