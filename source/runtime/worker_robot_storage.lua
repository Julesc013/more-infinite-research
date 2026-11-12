-- History for an admitted foreign finite worker-storage chain. This records
-- identities and creators only. Changed same-name finite prototypes can discard
-- levels/work before Lua; recovery therefore requires explicit pre-change custody.
local M = {}
local KEY, MIR = "mir_worker_storage_route", "more-infinite-research"

local function refuse(reason, route)
  error("MIR worker storage history: " .. reason .. "; restore the previous mod selection and original save"
    .. " [MIR-WORKER-HISTORY technology=" .. tostring(route and route.technology or "unobserved") .. "]", 3)
end

local function integer(value)
  return type(value) == "number" and value > 0 and value < 4294967295 and value == math.floor(value)
end

local function provider(value)
  return type(value) == "string" and value ~= "" and value ~= MIR
end

local function checked(value)
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= 1 or type(value.route) ~= "table" then
    refuse("invalid saved route")
  end
  for key in pairs(value) do
    if key ~= "schema" and key ~= "route" then refuse("unknown saved route field") end
  end
  local route = value.route
  if not integer(route.level) or route.level <= 4
      or route.technology ~= "worker-robots-storage-" .. route.level
      or type(route.owned) ~= "boolean" or type(route.finite) ~= "table" or #route.finite == 0
      or route.owned and route.provider ~= nil or not route.owned and not provider(route.provider) then
    refuse("invalid saved continuation", route)
  end
  for key in pairs(route) do
    if key ~= "technology" and key ~= "level" and key ~= "predecessor" and key ~= "owned"
        and key ~= "provider" and key ~= "finite" and key ~= "legacy_compatible" then
      refuse("unknown saved continuation field", route)
    end
  end
  if route.legacy_compatible ~= nil and type(route.legacy_compatible) ~= "boolean" then
    refuse("invalid legacy compatibility fact", route)
  end
  local count = 0
  for key in pairs(route.finite) do
    if not integer(key) or key > #route.finite then refuse("invalid finite chain array", route) end
    count = count + 1
  end
  if count ~= #route.finite then refuse("sparse finite chain", route) end
  local next_level, predecessor = 4, nil
  for _, stage in ipairs(route.finite) do
    if type(stage) ~= "table" or stage.name ~= "worker-robots-storage-" .. next_level
        or not integer(stage.max_level) or stage.max_level < next_level or not provider(stage.provider) then
      refuse("invalid saved finite chain", route)
    end
    for key in pairs(stage) do
      if key ~= "name" and key ~= "max_level" and key ~= "provider" then
        refuse("unknown finite chain field", route)
      end
    end
    next_level, predecessor = stage.max_level + 1, stage.name
  end
  if next_level ~= route.level or predecessor ~= route.predecessor then refuse("invalid saved endpoint", route) end
  return route
end

local function copy(route)
  local out = {technology=route.technology, level=route.level, predecessor=route.predecessor,
    owned=route.owned, provider=route.provider, finite={}}
  for index, stage in ipairs(route.finite) do
    out.finite[index] = {name=stage.name, max_level=stage.max_level, provider=stage.provider}
  end
  return out
end

local function same(left, right)
  if left == nil or right == nil then return left == right end
  for _, key in ipairs({"technology", "level", "predecessor", "owned", "provider"}) do
    if left[key] ~= right[key] then return false end
  end
  if #left.finite ~= #right.finite then return false end
  for index, stage in ipairs(left.finite) do
    local other = right.finite[index]
    if stage.name ~= other.name or stage.max_level ~= other.max_level or stage.provider ~= other.provider then return false end
  end
  return true
end

-- Published F2104.7.3's transported-V3 emission record can prove the old
-- continuation. A current prototype, settings-derived row or version alone
-- cannot. Keep the upstream selection and startup settings unchanged here.
local function legacy_emission(event, route)
  if not route.owned or route.legacy_compatible ~= true or type(event) ~= "table"
      or event.mod_startup_settings_changed ~= false then return false end
  local changes = event.mod_changes
  local change = type(changes) == "table" and changes[MIR]
  local active = script and script.active_mods or {}
  if type(change) ~= "table" or change.old_version ~= "4.7.21003"
      or change.new_version ~= active[MIR] or type(change.new_version) ~= "string"
      or not change.new_version:match("^5%.0%.210%d%d$") then return false end
  for name, item in pairs(changes) do
    if name ~= MIR and type(item) == "table" and item.old_version ~= item.new_version then return false end
  end
  local mir = storage.mir
  local bucket = type(mir) == "table" and mir.maximum_level_control
  local managed = type(bucket) == "table" and bucket.managed_technologies
  local row = type(managed) == "table" and managed[route.technology]
  return type(bucket) == "table" and bucket.policy_version == 3 and type(row) == "table"
    and row.technology == route.technology and row.setting == "mir-max-level-worker-robots-storage"
    and row.source == "base-continuation" and row.operation == "emit_base_extension"
    and row.policy_transport == "transported-v3" and row.ownership_kind == "transported-v3"
    and row.legacy == false and row.blocked_reason == nil and row.native_finite_stage == false
    and type(row.binding_fingerprint) == "string" and #row.binding_fingerprint == 14
    and row.binding_fingerprint:match("^mir32%-[0-9a-f]+$") ~= nil
    and (row.selected == "infinite" or integer(row.selected))
end

local function legacy_preflight(event, route)
  local prior = checked(storage[KEY])
  if prior ~= nil then
    if not same(prior, route) then refuse("finite endpoint or creator changed", route) end
    return nil
  end
  if route == nil then return nil end
  checked({schema=1, route=route})
  local changes = type(event) == "table" and event.mod_changes
  local mir = type(changes) == "table" and changes[MIR]
  local first_install = type(mir) == "table" and mir.old_version == nil
    and script and script.active_mods and mir.new_version == script.active_mods[MIR]
  if not first_install and not legacy_emission(event, route) then
    refuse("previous continuation ownership is unknown", route)
  end
  return {schema=1, route=copy(route)}
end

local function legacy_apply(plan)
  if plan ~= nil then storage[KEY] = plan end
end

local function legacy_init(route)
  if storage[KEY] ~= nil then refuse("unexpected initial history", route) end
  if route ~= nil then
    checked({schema=1, route=route})
    legacy_apply({schema=1, route=copy(route)})
  end
end

local recovery = require("research.worker_storage_recovery")
local caps = require("runtime.caps")
local target = require("platform.target")
local effective_values = require("runtime.configuration")
local pending = false
local default_head_pending = false
local default_mutating_force
local owned_queue_force
local delegated_provider_preflight, delegated_provider_apply
local selected_cap, selected_enabled = 0, true

local function clone(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = clone(item) end
  return out
end

-- Only the selected modern engine family and synchronized official patch
-- versions can accompany an otherwise unchanged producer/mod selection.
local ENGINE_MODS = {base=true, ["space-age"]=true, quality=true, ["elevated-rails"]=true, recycler=true}
local function engine_patch(version)
  local pattern = target.id == "f200" and "^2%.0%.(%d+)$" or target.id == "f210" and "^2%.1%.(%d+)$"
  local text = pattern and type(version) == "string" and version:match(pattern)
  local value = text and tonumber(text)
  if not value or not integer(value) or tostring(value) ~= text then return nil end
  return value
end
local function same_family_engine_patch(event)
  local active = script and script.active_mods or {}
  local changes = type(event) == "table" and event.mod_changes
  local floor, current = engine_patch(target.minimum_base), engine_patch(active.base)
  if not floor or not current or current < floor or type(changes) ~= "table" then return false end
  local base = changes.base
  if base ~= nil and (type(base) ~= "table" or base.new_version ~= active.base
      or not engine_patch(base.old_version) or engine_patch(base.old_version) < floor
      or engine_patch(base.old_version) > current) then return false end
  for name in pairs(ENGINE_MODS) do
    if active[name] ~= nil and active[name] ~= active.base then return false end
    local change = changes[name]
    if name ~= "base" and active[name] ~= nil and base and base.old_version ~= base.new_version
        and change == nil then return false end
    if change ~= nil then
      if type(change) ~= "table" or type(change.old_version) ~= "string" or change.new_version ~= active[name]
          or type(change.new_version) ~= "string" then return false end
      if change.old_version ~= change.new_version and (not base or change.old_version ~= base.old_version
          or change.new_version ~= base.new_version) then return false end
    end
  end
  return true
end

local function history_context(event, route, state, current)
  local function value(item)
    if type(item) == "string" then
      return (item:sub(1, 96):gsub("[%z\1-\32\127-\255]", function(byte)
        return string.format("\\x%02X", string.byte(byte))
      end))
    end
    if type(item) == "number" or type(item) == "boolean" then return tostring(item) end
    return "unknown"
  end
  local details = type(event) == "table" and event or {}
  local changes = details.mod_changes
  local mir = type(changes) == "table" and changes[MIR]
  local previous = type(mir) == "table" and (mir.old_version or "absent")
    or type(changes) == "table" and "unchanged" or "unknown"
  local active = script and script.active_mods or {}
  local saved = state == nil and "absent" or state.schema == 1 and "finite"
    or state.kind == "prepared" and "prepared-" .. state.phase or state.current.kind
  local parts = {"previous_mir=" .. value(previous),
    "new_mir=" .. value(type(mir) == "table" and mir.new_version or active[MIR]),
    "startup_changed=" .. value(details.mod_startup_settings_changed),
    "saved_route=" .. value(saved),
    "current_route=" .. value(current and current.kind or route and "finite" or "unobserved")}
  for _, name in ipairs({"secretas", "planet-ferrum", "WorkerRobotCargoSizeResearch"}) do
    local change = type(changes) == "table" and changes[name]
    if type(change) == "table" then
      parts[#parts + 1] = name .. "=" .. value(change.old_version) .. "->" .. value(change.new_version)
    end
  end
  return " [" .. table.concat(parts, " ") .. "]"
end

local function recover_error(reason, route, event, state, current)
  if event ~= nil then reason = reason .. history_context(event, route, state, current) end
  refuse(reason .. "; keep the protected original COPY. Load a separate copy with the previous mod selection"
    .. " and matching MIR settings. Only if that copy has MIR-owned default infinite worker4, run"
    .. " /mir-worker-storage-recovery prepare, then save and exit. Other prior routes require their own"
    .. " verified history; this command cannot infer it", route)
end

local function fields(value, allowed)
  if type(value) ~= "table" or getmetatable(value) ~= nil then recover_error("invalid recovery record") end
  for key in pairs(value) do if not allowed[key] then recover_error("unknown recovery record field") end end
end

local function creator(name)
  if not prototypes or type(prototypes.get_history) ~= "function" then recover_error("modern prototype creation history is unavailable") end
  local history = prototypes.get_history("technology", name)
  return type(history) == "table" and history.created or nil
end

local function native_prototype(name)
  if not prototypes or prototypes.technology == nil then recover_error("modern technology prototypes are unavailable") end
  return prototypes.technology[name]
end

local function fact(route)
  if route ~= nil then checked({schema=1, route=route}); return {kind="finite", route=copy(route)} end
  local technology = native_prototype(recovery.canonical)
  if technology == nil then return {kind="absent"} end
  if technology.level == 4 and technology.max_level == 4294967295 then
    local owner = creator(recovery.canonical)
    if owner == MIR then return {kind="default"} end
    if provider(owner) then return {kind="external", provider=owner} end
  end
  return nil
end

local function checked_fact(value)
  if type(value) ~= "table" then recover_error("missing explicit current route") end
  fields(value, {kind=true, route=true, provider=true})
  if value.kind == "finite" then
    if value.provider ~= nil then recover_error("invalid finite route fields") end
    checked({schema=1, route=value.route})
  elseif value.kind == "external" then
    if not provider(value.provider) or value.route ~= nil then recover_error("invalid external route") end
  elseif value.kind ~= "default" and value.kind ~= "absent" then recover_error("invalid explicit route kind")
  elseif value.provider ~= nil or value.route ~= nil then recover_error("invalid default/absent route fields") end
  return value
end

local function same_fact(left, right)
  if not left or not right or left.kind ~= right.kind then return false end
  if left.kind == "finite" then return same(left.route, right.route) end
  return left.provider == right.provider
end

local function checked_state()
  local state = storage[KEY]
  if state ~= nil and type(state) ~= "table" then recover_error("invalid worker history") end
  if state == nil or state.schema == 1 then checked(state); return state end
  fields(state, {schema=true, kind=true, current=true, phase=true, contract=true, forces=true, cap=true, family_enabled=true})
  if state.schema ~= 2 then recover_error("unsupported recovery schema") end
  if state.kind ~= "prepared" then
    if state.kind ~= "route" then recover_error("invalid recovery state kind") end
    checked_fact(state.current)
    if state.phase ~= nil or state.contract ~= nil or state.forces ~= nil or state.cap ~= nil
        or state.family_enabled ~= nil then recover_error("invalid ordinary route record") end
    return state
  end
  checked_fact(state.current)
  if state.phase ~= "default" and state.phase ~= "provider" then recover_error("invalid prepared phase") end
  if state.phase == "default" and state.current.kind ~= "default"
      or state.phase == "provider" and state.current.kind ~= "finite" then recover_error("invalid prepared route phase") end
  if (state.cap ~= 0 and not integer(state.cap)) or type(state.family_enabled) ~= "boolean" then
    recover_error("invalid prepared cap/settings contract")
  end
  if type(state.contract) ~= "string" or #state.contract < 20 or #state.contract > 8192
      or state.contract:sub(1, 16) ~= "worker-storage-1" then recover_error("invalid preserved contract") end
  if type(state.forces) ~= "table" or getmetatable(state.forces) ~= nil then recover_error("invalid prepared force records") end
  for index, row in pairs(state.forces) do
    if not integer(index) then recover_error("invalid prepared force index") end
    fields(row, {next_level=true, limit=true, pending=true, enabled=true, visible=true})
    if not integer(row.next_level) or row.next_level < 4 or not integer(row.limit) or row.limit < 3
        or row.limit < row.next_level - 1 or row.limit - row.next_level >= 1000 or type(row.pending) ~= "boolean"
        or row.pending ~= (row.limit >= row.next_level)
        or type(row.enabled) ~= "boolean" or type(row.visible) ~= "boolean" then
      recover_error("invalid prepared force history")
    end
  end
  return state
end

local function reconnect(state)
  pending = false
  if state and state.schema == 2 and state.kind == "prepared" then
    for _, row in pairs(state.forces) do if row.pending then pending = true; break end end
  end
end

local function forces()
  if not game or game.forces == nil then recover_error("native force state is unavailable") end
  local out = {}
  for _, force in pairs(game.forces) do out[#out + 1] = force end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end

local function progress(value)
  return type(value) == "number" and value == value and value >= 0 and value < 1
end

local function snapshot(force, id, finished_context, queued_observation)
  local technology = force.technologies[id]
  if not technology or not integer(technology.level) or technology.level < 4
      or type(technology.researched) ~= "boolean" or type(technology.enabled) ~= "boolean"
      or type(technology.visible_when_disabled) ~= "boolean" or not progress(technology.saved_progress) then
    recover_error("invalid native worker frame for " .. tostring(force.name))
  end
  local queue, saved, occurrences = {}, {}, 0
  for _, value in ipairs(force.research_queue or {}) do
    if #queue >= 1000 or not value or type(value.name) ~= "string" then recover_error("unsupported native queue") end
    queue[#queue + 1] = value.name
    if value.name == id then occurrences = occurrences + 1 end
    if not progress(value.saved_progress) then recover_error("invalid queued saved work") end
    saved[value.name] = value.saved_progress
  end
  local current = force.current_research and force.current_research.name or nil
  -- A finished callback can follow removal of its head but precede starting
  -- the queued remainder. Keep that observed nil current and zero progress;
  -- do not promote queued saved work into current research inside the event.
  local default_finished = finished_context == "default-head-finished"
  local waiting_after_finish = (finished_context == true or default_finished) and current == nil and queue[1] ~= nil
    and force.research_progress == 0
  local unsettled_queue = queued_observation == true and current ~= queue[1]
  if (current ~= queue[1] and not waiting_after_finish and not unsettled_queue) or not progress(force.research_progress) then
    recover_error("inconsistent native current/queue frame")
  end
  local next_level = technology.level + (technology.researched and 1 or 0)
  if next_level >= 4294967295 then recover_error("worker level has no preservable continuation") end
  if technology.researched and (occurrences > 0 or technology.saved_progress > 0)
      and not (default_finished and waiting_after_finish and technology.saved_progress == 0) then
    recover_error("completed worker row has ambiguous unfinished work")
  end
  return {technology=technology, next_level=next_level, researched=technology.researched,
    enabled=technology.enabled, visible=technology.visible_when_disabled,
    saved_progress=technology.saved_progress, count=technology.research_unit_count,
    queue=queue, queued_saved=saved, current=current, current_progress=force.research_progress,
    occurrences=occurrences,
    allowance=math.max(occurrences, (technology.saved_progress > 0 or current == id and force.research_progress > 0) and 1 or 0)}
end

local function requeueable(force, frame, moved, infinite_first)
  for _, name in ipairs(frame.queue) do
    local technology = force.technologies[name]
    if technology.enabled ~= true then recover_error("queued disabled research cannot be safely reassigned: " .. name) end
    for _, prerequisite in pairs(technology.prerequisites or {}) do
      local prototype = infinite_first and prerequisite.prototype
      local earned_infinite_first = prototype and prototype.max_level == 4294967295
        and integer(prototype.level) and integer(prerequisite.level) and prerequisite.level > prototype.level
        and prerequisite.researched == false
      if prerequisite.researched ~= true and not earned_infinite_first then
        recover_error("queued research has an unmet prerequisite: " .. name)
      end
    end
  end
  if moved and frame.occurrences > 0 and not frame.enabled then recover_error("disabled worker queue cannot be transferred") end
end

local function empty_private(include_all)
  local prototype = native_prototype(recovery.id)
  if not prototype then recover_error("MIR preservation prototype is missing from this package") end
  if creator(recovery.id) ~= MIR then recover_error("private worker creation custody changed") end
  recovery.fingerprint(prototype)
  local out = {}
  for _, force in ipairs(forces()) do
    local value = force.technologies and force.technologies[recovery.id]
    if not value or value.level ~= 4 or value.researched ~= false or value.saved_progress ~= 0
        or type(value.enabled) ~= "boolean" or type(value.visible_when_disabled) ~= "boolean" then
      recover_error("unrecorded private worker investment")
    end
    if force.current_research and force.current_research.name == recovery.id then recover_error("unrecorded private worker current work") end
    for _, technology in ipairs(force.research_queue or {}) do
      if technology.name == recovery.id then recover_error("unrecorded private worker queued work") end
    end
    if include_all or value.enabled or value.visible_when_disabled then out[#out + 1] = {force=force, technology=value} end
  end
  return out
end

local function private_contract()
  if creator(recovery.id) ~= MIR then recover_error("private worker creation custody changed") end
  return recovery.fingerprint(native_prototype(recovery.id))
end

local function prepared_frames(state)
  if private_contract() ~= state.contract then recover_error("preserved worker effect/cost/science contract changed") end
  local out, seen = {}, {}
  for _, force in ipairs(forces()) do
    local record = state.forces[force.index]
    if not record then recover_error("prepared force history is missing") end
    local frame = snapshot(force, recovery.id)
    if frame.next_level ~= record.next_level or frame.enabled ~= record.enabled
        or frame.visible ~= record.visible then recover_error("private worker history or flags changed") end
    seen[force.index] = true
    out[#out + 1] = {force=force, frame=frame, record=record}
  end
  for index in pairs(state.forces) do if not seen[index] then recover_error("stale prepared force history") end end
  return out
end

local function canonical_empty()
  for _, force in ipairs(forces()) do
    local frame = snapshot(force, recovery.canonical)
    if frame.next_level ~= 4 or frame.researched or frame.saved_progress ~= 0 or frame.occurrences ~= 0 then
      recover_error("canonical worker4 gained work after preparation")
    end
  end
end

local function prepared_current(state, current)
  local frames = prepared_frames(state)
  local closed = state.phase == "provider"
  for _, item in ipairs(frames) do
    if item.record.pending or item.frame.allowance > 0 or item.frame.enabled then closed = false; break end
  end
  -- Matching policy protects the preparation and its unfinished work. Once
  -- the admitted provider is active and every private row is retired, public
  -- worker settings resume their ordinary lifecycle without touching credits.
  if not closed and (state.cap ~= selected_cap or state.family_enabled ~= selected_enabled) then
    recover_error("worker cap or enable setting changed; use the exact prepared MIR settings")
  end
  if state.phase == "default" then
    canonical_empty()
    if not current or current.kind ~= "default" and current.kind ~= "finite" then
      recover_error("prepared default requires its unchanged default or admitted finite provider")
    end
  elseif not same_fact(state.current, current) then
    recover_error("prepared provider removal or changed continuation remains unqualified")
  end
  return frames
end

-- Published9/10 constructed the named Secretas9 route without its history.
-- Published11 accepted unchanged10, but failed to persist that accepted fact.
-- Only a proven unchanged route can be adopted; this recovers no clamped work.
local function unchanged_unrecorded_secretas(event, route)
  if not route or route.technology ~= "worker-robots-storage-9" or #route.finite ~= 5
      or not script.active_mods.secretas then return false end
  local changes = event.mod_changes or {}
  local mir = changes[MIR]
  if not mir then return false end
  local old = mir.old_version
  if not same_family_engine_patch(event) then return false end
  local official_patch = event.mod_startup_settings_changed == false
  local published10 = old == "5.0.21010" or old == "5.0.20010"
  if not published10 then
    local active = script.active_mods
    local f200 = old == "5.0.20009" or old == "5.0.20011"
    local f210 = old == "5.0.21009" or old == "5.0.21011"
    if not (f200 or f210) or route.owned ~= true or event.mod_startup_settings_changed ~= false
        or mir.new_version ~= active[MIR] or type(mir.new_version) ~= "string"
        or type(active.base) ~= "string"
        or not (f200 and target.id == "f200" and mir.new_version:match("^5%.0%.200%d%d$") and active.base:match("^2%.0%.%d+$")
          or f210 and target.id == "f210" and mir.new_version:match("^5%.0%.210%d%d$") and active.base:match("^2%.1%.%d+$")) then
      return false
    end
    for name, change in pairs(changes) do
      if name ~= MIR and not (official_patch and ENGINE_MODS[name]) and (type(change) ~= "table" or change.old_version == nil
          or change.old_version ~= change.new_version or change.new_version ~= active[name]) then return false end
    end
  end
  for name, change in pairs(changes) do
    if name ~= MIR and not (official_patch and ENGINE_MODS[name]) and change.old_version ~= change.new_version then return false end
  end
  return true
end

function M.preflight(event, route, owner_plan)
  if owner_plan ~= nil then return delegated_provider_preflight(event, route, owner_plan) end
  local state = checked_state()
  if state and state.schema == 2 then
    local current = fact(route)
    if state.kind == "prepared" then
      prepared_current(state, current)
      local next_state = clone(state)
      next_state.current = clone(current)
      next_state.cap, next_state.family_enabled = selected_cap, selected_enabled
      if current.kind == "finite" then next_state.phase = "provider" end
      return {recovery=true, state=next_state}
    end
    if not same_fact(state.current, current) then
      recover_error("unprepared worker route changed", route, event, state, current)
    end
    return {recovery=true, state=state, empty=empty_private()}
  end
  local plan
  if state == nil and unchanged_unrecorded_secretas(event or {}, route) then
    checked({schema=1, route=route})
    plan = {schema=1, route=copy(route)}
  else
    local ok, result = pcall(legacy_preflight, event, route)
    if not ok then
      if tostring(result):find("previous continuation ownership is unknown", 1, true) then
        recover_error("previous continuation ownership is unknown", route, event, state)
      end
      error(result, 0)
    end
    plan = result
  end
  local empty = empty_private()
  if #empty > 0 then return {recovery=true, legacy=plan, empty=empty} end
  return plan
end

function M.apply(plan)
  if plan and plan.delegated_handover ~= nil then return delegated_provider_apply(plan) end
  if plan and plan.recovery then
    if plan.state then storage[KEY] = plan.state else legacy_apply(plan.legacy) end
    for _, item in ipairs(plan.empty or {}) do
      item.technology.enabled, item.technology.visible_when_disabled = false, false
    end
    reconnect(storage[KEY])
  else legacy_apply(plan); reconnect(storage[KEY]) end
end

function M.on_init(route)
  if storage[KEY] ~= nil then recover_error("unexpected initial worker history") end
  local empty = empty_private()
  local current = fact(route)
  if route then legacy_init(route)
  elseif current then storage[KEY] = {schema=2, kind="route", current=current} end
  for _, item in ipairs(empty) do item.technology.enabled, item.technology.visible_when_disabled = false, false end
  reconnect(storage[KEY])
end

function M.on_load()
  -- No game access, force/prototype changes or changed-route decision here.
  reconnect(checked_state())
end

function M.plan_prepared(plan) return plan and plan.recovery and plan.state and plan.state.kind == "prepared" or false end
function M.needs_research_events() return pending or default_head_pending end
function M.force_events()
  if not native_prototype(recovery.id) then recover_error("MIR preservation prototype is missing from this package") end
  return true -- New/reset native forces must receive the empty disabled holder.
end
function M.configure(maximum, enabled)
  if maximum ~= nil and maximum ~= 0 and not integer(maximum) then recover_error("invalid current worker cap") end
  selected_cap, selected_enabled = maximum or 0, enabled ~= false
end

local function assign_queue(force, frame, queue, moved, destination, activate_remainder, source_id)
  destination, source_id = destination or recovery.id, source_id or recovery.canonical
  local previous_owner = owned_queue_force
  owned_queue_force = force.index
  local ok, message = pcall(function()
    force.research_queue = queue
    local actual = force.research_queue or {}
    if #actual ~= #queue then recover_error("native queue dropped a prepared entry; reload the original copy") end
    for index, name in ipairs(queue) do
      if actual[index].name ~= name then recover_error("native queue changed prepared order; reload the original copy") end
    end
    for name, saved in pairs(frame.queued_saved) do
      local id = moved and name == source_id and destination or name
      if not (activate_remainder and queue[1] == id) and force.technologies[id].saved_progress ~= saved then
        force.technologies[id].saved_progress = saved
      end
    end
    local current = moved and frame.current == source_id and destination or frame.current
    if current then
      if not force.current_research or force.current_research.name ~= current then recover_error("native current research changed") end
      force.research_progress = frame.current_progress
    elseif activate_remainder then
      local first = frame.queue[1]
      local expected = first and frame.queued_saved[first] or 0
      if (force.current_research and force.current_research.name or nil) ~= queue[1]
          or force.research_progress ~= expected then recover_error("native finished queue activation changed work") end
    end
  end)
  owned_queue_force = previous_owner
  if not ok then error(message, 0) end
end

-- Explicit default-only native ownership; event wiring and caps have separate owners.
-- Native research remains authoritative after this one-time identity transfer.
-- The older route/preparation key and legacy private holder keep their meanings.
local OWNER_KEY = "mir_worker_storage_native_owner"
-- Public MIR5 default C4 has one unchanged native earning/settings contract.
-- This set does not authorize provider routes or new direct engine-hop origins.
local DEFAULT_ORIGINS = {
  f200 = {["5.0.20000"]=true, ["5.0.20001"]=true, ["5.0.20002"]=true, ["5.0.20003"]=true,
    ["5.0.20004"]=true, ["5.0.20005"]=true, ["5.0.20006"]=true, ["5.0.20007"]=true,
    ["5.0.20008"]=true, ["5.0.20009"]=true, ["5.0.20010"]=true, ["5.0.20011"]=true},
  f210 = {["5.0.21000"]=true, ["5.0.21001"]=true, ["5.0.21002"]=true, ["5.0.21003"]=true,
    ["5.0.21004"]=true, ["5.0.21005"]=true, ["5.0.21006"]=true, ["5.0.21007"]=true,
    ["5.0.21008"]=true, ["5.0.21009"]=true, ["5.0.21010"]=true, ["5.0.21011"]=true},
}
local DIRECT_DEFAULT_HOP_ORIGINS = {["5.0.20009"]=true, ["5.0.20010"]=true, ["5.0.20011"]=true}

local function producer_edition(version)
  if type(version) ~= "string" then return nil end
  if version:match("^5%.0%.200%d%d$") then return "f200" end
  if version:match("^5%.0%.210%d%d$") then return "f210" end
end

local function exact_base_hop(event, old_version, owned)
  local active = script and script.active_mods or {}
  local changes = event and event.mod_changes
  local base = type(changes) == "table" and changes.base
  local known = old_version == "4.7.20003" or DIRECT_DEFAULT_HOP_ORIGINS[old_version]
    or owned and producer_edition(old_version) == "f200"
      and tonumber(old_version:sub(-2)) <= tonumber(target.distribution_version:sub(-2))
  if not known or target.id ~= "f210" or target.minimum_base ~= "2.1.23" or active.base ~= "2.1.23"
      or type(base) ~= "table" or base.old_version ~= "2.0.77" or base.new_version ~= "2.1.23" then return false end
  for name in pairs(active) do if name ~= "base" and name ~= MIR then return false end end
  for name in pairs(changes) do if name ~= "base" and name ~= MIR then return false end end
  return true
end

local function equal_plain(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not equal_plain(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end

local function checked_default_force(record, retired)
  fields(record, {phase=true, retired_flags=true})
  if record.phase ~= (retired and "retired" or "owned") then recover_error("invalid full default owner phase") end
  fields(record.retired_flags, {enabled=true, visible=true, disabled_by_mir=true, visibility_hidden_by_mir=true})
  local flags = record.retired_flags
  if type(flags.enabled) ~= "boolean" or type(flags.visible) ~= "boolean"
      or flags.disabled_by_mir ~= flags.enabled or flags.visibility_hidden_by_mir ~= false then
    recover_error("invalid full default retirement rights")
  end
  return record
end

local function reconnect_default(state)
  -- Native H, not a cached level/progress field, proves the paid first level.
  default_head_pending = state ~= nil and state.kind == "full-default"
end

local function owner_record()
  local value = storage[OWNER_KEY]
  if value == nil then return nil end
  fields(value, {schema=true, kind=true, owner=true, source=true, gate=true, contract=true, producer=true, forces=true, current=true})
  local retired = value.kind == "provider-retired"
  if value.schema ~= 3 or value.kind ~= "full-default" and not retired or value.owner ~= recovery.ordinary_default_id
      or value.source ~= recovery.canonical or value.gate ~= recovery.head_id
      or type(value.contract) ~= "string" or #value.contract > 8192
      or value.contract:sub(1, 16) ~= "worker-storage-1" then
    recover_error("invalid full default native-owner record")
  end
  if retired then
    checked_fact(value.current)
    if value.current.kind ~= "finite" then recover_error("retired default owner has no admitted finite route") end
  elseif value.current ~= nil then recover_error("ordinary default owner has a provider route") end
  fields(value.producer, {kind=true, old_version=true, new_version=true})
  local older_empty = value.producer.kind == "older-mir501-empty-default"
  local older_idle = value.producer.kind == "published473-idle-default"
  local published_default = value.producer.kind == "published473-default"
  if (value.producer.kind ~= "initial-empty" and value.producer.kind ~= "recorded-default"
      and value.producer.kind ~= "unchanged-mir5-default" and not older_empty and not older_idle and not published_default)
      or type(value.producer.new_version) ~= "string" or #value.producer.new_version > 64
      or value.producer.kind == "initial-empty" and value.producer.old_version ~= nil
      or value.producer.kind ~= "initial-empty" and type(value.producer.old_version) ~= "string" then
    recover_error("invalid default native-owner producer")
  end
  -- Producer facts describe their historical package, not the current
  -- edition. A valid F200-owned native record survives the supported forward
  -- engine hop; it is not rewritten into a fictional F210 producer.
  local edition, old_edition = producer_edition(value.producer.new_version), producer_edition(value.producer.old_version)
  local known = DEFAULT_ORIGINS[old_edition]
  if not edition or edition ~= target.id and not (edition == "f200" and target.id == "f210")
      or tonumber(value.producer.new_version:sub(-2)) > tonumber(target.distribution_version:sub(-2))
      or older_empty and (edition ~= "f200" or value.producer.old_version ~= "5.0.20001")
      or older_idle and value.producer.old_version ~= "4.7.20003"
      or published_default and (value.producer.old_version ~= "4.7.20003" and value.producer.old_version ~= "4.7.21003"
        or value.producer.old_version == "4.7.21003" and edition ~= "f210")
      or value.producer.kind == "unchanged-mir5-default" and (old_edition ~= edition or not known or not known[value.producer.old_version]
        or tonumber(value.producer.old_version:sub(-2)) > tonumber(value.producer.new_version:sub(-2)))
      or value.producer.kind == "recorded-default" and value.producer.old_version ~= value.producer.new_version
        and (not known or not known[value.producer.old_version]
          or tonumber(value.producer.old_version:sub(-2)) > tonumber(value.producer.new_version:sub(-2))
          or old_edition ~= edition and not (old_edition == "f200" and edition == "f210"
            and DIRECT_DEFAULT_HOP_ORIGINS[value.producer.old_version])) then
    recover_error("unknown default native-owner producer")
  end
  if type(value.forces) ~= "table" or getmetatable(value.forces) ~= nil then
    recover_error("invalid default native-owner forces")
  end
  for index, record in pairs(value.forces) do
    if not integer(index) then recover_error("invalid default owner force index") end
    checked_default_force(record, retired)
  end
  return value
end

-- These older Base transitions have separate, narrower native predicates.
-- MIR501 with a new selection remains empty-only; unchanged-selection MIR501
-- uses the common default contract. Observer additions never stand for old mods.
local function older_default_origin(event, change, active, base_hop)
  local same_edition = (target.id == "f200" and change.old_version ~= "4.7.21003" and target.minimum_base == "2.0.77"
    or target.id == "f210" and change.old_version == "4.7.21003" and target.minimum_base == "2.1.23")
    and active.base == target.minimum_base
  if not base_hop and (not same_edition or event.mod_startup_settings_changed ~= false) then
    recover_error("older default source requires its qualified Base engine and unchanged settings")
  end
  for _, name in ipairs({"space-age", "quality", "elevated-rails", "recycler"}) do
    if active[name] ~= nil then recover_error("older default source requires its Base-only profile") end
  end
  for name, version in pairs(active) do
    if name ~= "base" and name ~= MIR then
      local addition = event.mod_changes[name]
      if type(version) ~= "string" or type(addition) ~= "table" or addition.old_version ~= nil
          or addition.new_version ~= version then recover_error("older default prior mod selection is not Base+MIR") end
    end
  end
  for name, item in pairs(event.mod_changes) do
    if name ~= MIR then
      if type(item) ~= "table" or item.new_version ~= active[name] or type(item.new_version) ~= "string"
          or name == "base" and item.old_version ~= (base_hop and "2.0.77" or target.minimum_base)
          or name ~= "base" and item.old_version ~= nil then
        recover_error("older default source changed a previous mod or engine")
      end
    end
  end
  if change.old_version == "5.0.20001" then
    return {kind="older-mir501-empty-default", old_version=change.old_version, new_version=active[MIR]}
  end
  local values = effective_values.streams and effective_values.streams["worker-robots-storage"]
  local prototype = native_prototype(recovery.canonical)
  local effect = prototype.effects and #prototype.effects == 1 and prototype.effects[1]
  if type(values) ~= "table" or values.base_cost ~= 200 or values.growth_factor ~= 1.5
      or values.linear_increment ~= 0 or values.research_time ~= 60 or values.effect_percent ~= 1
      or values.max_level ~= 0 or values.enabled ~= true or selected_cap ~= 0 or selected_enabled ~= true
      or prototype.level ~= 4 or prototype.max_level ~= 4294967295
      or prototype.research_unit_count_formula ~= "675*1.5^(L-4)" or prototype.research_unit_energy ~= 3600
      or prototype.ignore_tech_cost_multiplier ~= false
      or not effect or effect.type ~= "worker-robot-storage" or effect.modifier ~= 1 then
    recover_error("published473 source requires the resolved default worker work contract")
  end
  local packs = {["automation-science-pack"]=1, ["logistic-science-pack"]=1, ["chemical-science-pack"]=1,
    ["production-science-pack"]=1, ["utility-science-pack"]=1}
  local ingredients = prototype.research_unit_ingredients
  if type(ingredients) ~= "table" or #ingredients ~= 5 then recover_error("published473 default science differs") end
  for _, ingredient in ipairs(ingredients) do
    if type(ingredient) ~= "table" or packs[ingredient.name] ~= ingredient.amount then
      recover_error("published473 default science differs")
    end
    packs[ingredient.name] = nil
  end
  if next(packs) ~= nil then recover_error("published473 default science differs") end
  -- The exact default tuple has the same native earning/work contract. Keep
  -- pending work in the ordinary transfer path, not the older empty-only path.
  return {kind="published473-default", old_version=change.old_version, new_version=active[MIR]}
end

local function default_origin(event, initializing, state)
  local active = script and script.active_mods or {}
  if type(target.distribution_version) ~= "string" or active[MIR] ~= target.distribution_version then
    recover_error("default transfer requires the declared MIR package version")
  end
  if initializing then
    if event ~= nil or state ~= nil and (state.schema ~= 2 or state.kind ~= "route"
        or state.current.kind ~= "default") then recover_error("initial default transfer has prior history") end
    return {kind="initial-empty", new_version=active[MIR]}
  end
  if type(event) ~= "table" or type(event.mod_startup_settings_changed) ~= "boolean"
      or type(event.mod_changes) ~= "table" then recover_error("default transfer requires unchanged startup settings") end
  local change = event.mod_changes[MIR]
  if change ~= nil and (type(change) ~= "table" or change.new_version ~= active[MIR]) then
    recover_error("default transfer package-change event is inconsistent")
  end
  local base_hop = change and exact_base_hop(event, change.old_version)
  if state == nil and event.mod_startup_settings_changed ~= false
      and not (base_hop and change.old_version == "4.7.20003") then
    recover_error("unrecorded default source requires unchanged startup settings")
  end
  local new_selection = false
  for name, item in pairs(event.mod_changes) do
    if name ~= MIR and type(item) == "table" and item.old_version == nil then new_selection = true end
  end
  if state == nil and change and (change.old_version == "4.7.20003" or change.old_version == "4.7.21003"
      or change.old_version == "5.0.20001" and new_selection) then
    return older_default_origin(event, change, active, base_hop)
  end
  local engine_patch_valid = same_family_engine_patch(event)
  if not base_hop and not engine_patch_valid then recover_error("default transfer requires a supported same-family engine patch") end
  if state ~= nil then
    if state.schema ~= 2 or state.kind ~= "route" or state.current.kind ~= "default" then
      recover_error("legacy prepared/finite conversion is not a default-owner transfer")
    end
    -- This saved fact authenticates the old MIR default. The caller also
    -- checks the surviving full native contract and every force's work.
    -- Other mods may change without invalidating those independent facts.
    for name, item in pairs(event.mod_changes) do
      if type(name) ~= "string" or name == "" or type(item) ~= "table" or getmetatable(item) ~= nil then
        recover_error("recorded default has an invalid mod-change entry", nil, event, state, {kind="default"})
      end
      local old, new = item.old_version, item.new_version
      if old ~= nil and (type(old) ~= "string" or old == "")
          or new ~= nil and (type(new) ~= "string" or new == "")
          or old == nil and new == nil or new ~= active[name] then
        recover_error("recorded default mod-change entry disagrees with active mods", nil, event, state, {kind="default"})
      end
      if base_hop and name ~= MIR and name ~= "base" and old ~= new then
        recover_error("recorded default engine hop requires the unchanged Base-only selection", nil, event, state, {kind="default"})
      end
    end
    if change and type(change.old_version) ~= "string" then
      recover_error("recorded default source cannot be a first-install event")
    end
    local old = change and change.old_version or active[MIR]
    local known = DEFAULT_ORIGINS[base_hop and "f200" or target.id]
    if type(old) ~= "string" or old ~= active[MIR] and (not known or not known[old]) then
      recover_error("recorded default source has an inconsistent producer event")
    end
    return {kind="recorded-default", old_version=old, new_version=active[MIR]}
  end
  for name, item in pairs(event.mod_changes) do
    if name ~= MIR and not (base_hop and name == "base") and not (engine_patch_valid and ENGINE_MODS[name]) and (type(item) ~= "table" or item.old_version == nil
        or item.old_version ~= item.new_version or item.new_version ~= active[name]) then
      recover_error("default transfer requires the unchanged mod selection", nil, event, state, {kind="default"})
    end
  end
  local known = DEFAULT_ORIGINS[target.id]
  if not change or not known or known[change.old_version] ~= true or not engine_patch_valid then
    recover_error("unrecorded default source has no qualified MIR5 producer")
  end
  local official = {base=true, [MIR]=true, ["space-age"]=true, quality=true, ["elevated-rails"]=true, recycler=true}
  for name, version in pairs(active) do
    -- The unchanged-selection check above covers added, removed and updated
    -- mods. Unrelated unchanged names do not invalidate surviving native work.
    if official[name] and name ~= MIR and version ~= active.base then
      recover_error("unrecorded default source requires matching official engine versions")
    end
  end
  return {kind="unchanged-mir5-default", old_version=change.old_version, new_version=active[MIR]}
end

local function frame_values(frame)
  return {next_level=frame.next_level, researched=frame.researched, enabled=frame.enabled, visible=frame.visible,
    saved_progress=frame.saved_progress, count=frame.count, current=frame.current,
    current_progress=frame.current_progress, queue=clone(frame.queue), queued_saved=clone(frame.queued_saved)}
end

local function head_gate_contract(source)
  local prototype = native_prototype(recovery.head_id)
  if not prototype or prototype.name ~= recovery.head_id or creator(recovery.head_id) ~= MIR
      or prototype.level ~= 4 or prototype.max_level ~= 4294967295 or prototype.hidden ~= true
      or prototype.enabled ~= false or prototype.visible_when_disabled ~= false
      or prototype.research_unit_count_formula ~= nil or prototype.research_unit_count ~= 1
      or prototype.research_unit_energy ~= 60 or next(prototype.prerequisites or {}) ~= nil
      or prototype.ignore_tech_cost_multiplier ~= true then
    recover_error("default head debit contract is invalid")
  end
  local effects, ingredients = prototype.effects, prototype.research_unit_ingredients
  local effect = type(effects) == "table" and #effects == 1 and effects[1]
  local hidden = effect and effect.hidden
  if hidden == nil and target.id == "f200" then hidden = false end
  local scalar = source.effects[1].modifier
  if not effect or effect.type ~= "worker-robot-storage" or effect.modifier ~= (scalar == 0 and 0 or -scalar)
      or hidden ~= false or type(ingredients) ~= "table" or #ingredients ~= 1
      or ingredients[1].name ~= source.research_unit_ingredients[1].name or ingredients[1].amount ~= 1 then
    recover_error("default head debit science/effect contract is invalid")
  end
end

local function gate_frame(force, configuration)
  local gate = force.technologies[recovery.head_id]
  -- Configuration can re-enable an already-paid native infinite level5 even
  -- though its MIR prototype is disabled. Only that exact flag is settleable;
  -- fresh/ordinary-event frames still require the debit to remain disabled.
  local settleable = gate and configuration == true and gate.level == 5 and gate.enabled == true
  if not gate or (gate.level ~= 4 and gate.level ~= 5) or gate.researched ~= false
      or gate.enabled ~= false and not settleable
      or gate.visible_when_disabled ~= false or gate.saved_progress ~= 0 then
    recover_error("default head debit native state is invalid")
  end
  if force.current_research and force.current_research.name == recovery.head_id then recover_error("head debit cannot be current research") end
  for _, entry in ipairs(force.research_queue or {}) do
    if entry.name == recovery.head_id then recover_error("head debit cannot be queued research") end
  end
  return gate
end

local function gate_paid(gate)
  return gate.level == 5
end

local function set_gate_paid(gate, paid)
  local level = paid and 5 or 4
  if gate.level ~= level then gate.level = level end
  -- A native level write enables the technology. This debit is never an
  -- ordinary research route, including inside the guarded finish callback.
  gate.enabled, gate.visible_when_disabled = false, false
end

local function default_contract()
  local id = recovery.ordinary_default_id
  if id ~= "mir-worker-storage-default-4" or id == recovery.canonical or id == recovery.id then
    recover_error("ordinary default identity is unavailable")
  end
  local source, owner = native_prototype(recovery.canonical), native_prototype(id)
  if not same_fact(fact(nil), {kind="default"}) or creator(id) ~= MIR
      or not recovery.matches_default_owner(source, owner) or owner.hidden ~= false
      or type(owner.enabled) ~= "boolean" or type(owner.visible_when_disabled) ~= "boolean" then
    recover_error("canonical4/full default4 contract or custody differs")
  end
  local contract = recovery.fingerprint(source)
  head_gate_contract(source)
  for level = 5, 9 do
    if native_prototype("worker-robots-storage-" .. level) ~= nil then recover_error("default transfer has a foreign worker tail") end
  end
  empty_private()
  return source, owner, contract
end

-- A full-owner finish never transfers work. Its native queue/current may
-- still be in the callback representation, including progress1. Capture it
-- exactly for readback, without applying transfer/settled-queue assumptions.
local function default_completion_frame(force, id)
  local technology = force.technologies[id]
  if not technology or not integer(technology.level) or technology.level < 4
      or type(technology.researched) ~= "boolean" or type(technology.enabled) ~= "boolean"
      or type(technology.visible_when_disabled) ~= "boolean" or not progress(technology.saved_progress) then
    recover_error("invalid full default completion technology")
  end
  local queue, saved, occurrences = {}, {}, 0
  for _, entry in ipairs(force.research_queue or {}) do
    if #queue >= 1000 or not entry or type(entry.name) ~= "string" or not progress(entry.saved_progress) then
      recover_error("invalid full default completion queue")
    end
    queue[#queue + 1], saved[entry.name] = entry.name, entry.saved_progress
    if entry.name == id then occurrences = occurrences + 1 end
  end
  local value = force.research_progress
  if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
    recover_error("invalid full default completion progress")
  end
  local next_level = technology.level + (technology.researched and 1 or 0)
  if next_level >= 4294967295 then recover_error("worker level has no preservable continuation") end
  return {technology=technology, next_level=next_level, researched=technology.researched,
    enabled=technology.enabled, visible=technology.visible_when_disabled, saved_progress=technology.saved_progress,
    count=technology.research_unit_count, queue=queue, queued_saved=saved,
    current=force.current_research and force.current_research.name or nil, current_progress=value,
    occurrences=occurrences}
end

local function default_frame(force, id, finished)
  if finished then return default_completion_frame(force, id) end
  return snapshot(force, id)
end

local function full_pair(source, owner, gate)
  local paid = owner.next_level >= 5
  return source.next_level == (paid and 5 or 4) and not source.researched
    and source.saved_progress == 0 and source.occurrences == 0 and source.current ~= recovery.canonical and not source.enabled
    and gate_paid(gate) == paid
end

local function native_bonus(force)
  local value = force.worker_robots_storage_bonus
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    recover_error("default native contribution is unavailable")
  end
  return value -- postcondition only; never used to infer earned levels.
end

function M.plan_default_owner_transfer(event, route, initializing, context)
  context = context or {}
  if type(initializing) ~= "boolean" or route ~= nil then recover_error("default-only transfer context required") end
  local id, state, owned = recovery.ordinary_default_id, checked_state(), owner_record()
  local source_prototype, prototype, contract = default_contract()
  local producer = owned and owned.producer or default_origin(event, initializing, state)
  if state and (state.schema ~= 2 or state.kind ~= "route" or state.current.kind ~= "default") then
    recover_error("legacy prepared/finite conversion is not implemented")
  end
  if owned and owned.contract ~= contract and not context.configuration then recover_error("default native-owner contract changed") end
  if context.configuration and (type(event) ~= "table" or type(event.mod_startup_settings_changed) ~= "boolean"
      or type(event.mod_changes) ~= "table" or script.active_mods[MIR] ~= target.distribution_version) then
    recover_error("current default configuration event is unavailable")
  end
  if context.configuration and owned and producer_edition(owned.producer.new_version) == "f200" and target.id == "f210"
      and event.mod_changes.base ~= nil then
    local base, mir = event.mod_changes.base, event.mod_changes[MIR]
    if type(base) ~= "table" or type(base.old_version) ~= "string" or type(base.new_version) ~= "string"
        or base.new_version ~= script.active_mods.base then
      recover_error("owned default has an unsupported engine transition")
    end
    local same_family = base.old_version:match("^2%.1%.%d+$") and base.new_version:match("^2%.1%.%d+$")
    if base.old_version ~= base.new_version and not same_family then
      if type(mir) ~= "table" or mir.new_version ~= script.active_mods[MIR]
          or not exact_base_hop(event, mir.old_version, true)
          or tonumber(mir.old_version:sub(-2)) < tonumber(owned.producer.new_version:sub(-2)) then
        recover_error("owned default has an unsupported engine transition")
      end
    end
  end
  local record = owned and clone(owned) or {schema=3, kind="full-default", owner=id, source=recovery.canonical,
    gate=recovery.head_id, contract=contract, producer=producer, forces={}}
  record.contract = contract
  local items, seen, moved = {}, {}, false
  for _, force in ipairs(forces()) do
    seen[force.index] = true
    local finished = context.finished_force == force.index
    local source = default_frame(force, recovery.canonical, finished)
    local destination = default_frame(force, id, finished)
    local gate, prior = gate_frame(force, owned ~= nil and context.configuration == true), owned and owned.forces[force.index]
    local refresh = context.created_force == force.index or context.reset_force == force.index
    if context.created_force == force.index and prior then recover_error("new default force already has history") end
    local action, next_force = "validate", prior and clone(prior) or nil
    if not prior or refresh then
      if owned and not refresh then recover_error("default force history is missing") end
      if destination.next_level ~= 4 or destination.researched or destination.saved_progress ~= 0
          or destination.occurrences ~= 0 or destination.enabled ~= prototype.enabled
          or destination.visible ~= prototype.visible_when_disabled or gate_paid(gate) then
        recover_error("full default owner/debit is not pristine")
      end
      if (initializing or refresh) and (source.next_level ~= 4 or source.researched
          or source.saved_progress ~= 0 or source.occurrences ~= 0) then
        recover_error("first initialization/new force cannot adopt existing default work")
      end
      if not owned and (producer.kind == "older-mir501-empty-default" or producer.kind == "published473-idle-default") then
        if source.saved_progress ~= 0 or source.occurrences ~= 0 or source.current == recovery.canonical then
          recover_error("older default source has unfinished native worker work")
        end
        if producer.kind == "older-mir501-empty-default" and (source.next_level ~= 4 or source.researched) then
          recover_error("older MIR501 source requires every native worker4 to be empty")
        end
      end
      if source.occurrences > 0 then requeueable(force, source, true, true) end
      action, moved = "transfer", true
      next_force = {phase="owned", retired_flags={enabled=source.enabled, visible=source.visible,
        disabled_by_mir=source.enabled, visibility_hidden_by_mir=false}}
    elseif not full_pair(source, destination, gate) then
      if finished and source.next_level == 4 and not source.researched and not source.enabled
          and source.saved_progress == 0 and source.occurrences == 0 and source.current ~= recovery.canonical and not gate_paid(gate)
          and destination.next_level >= 5 then
        action = "first-credit"
      else recover_error("full default native owner/first-level debit changed") end
    end
    if action == "validate" and gate.enabled then action = "settle-gate" end
    record.forces[force.index] = next_force
    items[#items + 1] = {force=force, source=source, destination=destination, gate=gate, gate_paid=gate_paid(gate),
      gate_enabled=gate.enabled,
      bonus=native_bonus(force), phase="owned", moved=action == "transfer", action=action,
      target_enabled=source.enabled, target_visible=source.visible}
  end
  if #items == 0 then recover_error("default transfer requires native force frames") end
  if owned then
    for index in pairs(owned.forces) do if not seen[index] then recover_error("stale default owner force record") end end
  end
  local changed = not owned or not equal_plain(record, owned)
  for _, item in ipairs(items) do if item.action ~= "validate" then changed = true end end
  return {kind="default-native-owner-transfer", event=clone(event), context=clone(context), initializing=initializing,
    prior_state=state, prior_owner=owned, contract=contract, cap=selected_cap, enabled=selected_enabled, items=items,
    already_owned=owned ~= nil and not moved, changed=changed, record=record}
end

function M.apply_default_owner_transfer(plan)
  if type(plan) ~= "table" or plan.kind ~= "default-native-owner-transfer" then recover_error("invalid default transfer plan") end
  local fresh = M.plan_default_owner_transfer(plan.event, nil, plan.initializing, plan.context)
  -- Seal the raw config flag even when the new read would otherwise be a
  -- no-op. A changed true/false sample must never bypass stale-plan checks.
  for index, item in ipairs(fresh.items) do
    local old = plan.items[index]
    if not old or old.gate_enabled ~= item.gate_enabled then recover_error("head debit flag changed after default preflight") end
  end
  if not fresh.changed then reconnect_default(fresh.record); return false end
  if plan.prior_state ~= fresh.prior_state or plan.prior_owner ~= fresh.prior_owner or plan.contract ~= fresh.contract
      or plan.cap ~= fresh.cap or plan.enabled ~= fresh.enabled or #plan.items ~= #fresh.items
      or not equal_plain(plan.record, fresh.record) then recover_error("stale default transfer plan") end
  for index, item in ipairs(fresh.items) do
    local old = plan.items[index]
    if old.force.index ~= item.force.index or old.action ~= item.action or old.gate_paid ~= item.gate_paid
        or old.bonus ~= item.bonus or not equal_plain(frame_values(old.source), frame_values(item.source))
        or not equal_plain(frame_values(old.destination), frame_values(item.destination)) then
      recover_error("native work changed after default preflight")
    end
  end
  local id = recovery.ordinary_default_id
  for _, item in ipairs(fresh.items) do
    local previous = default_mutating_force
    default_mutating_force = item.force.index
    local ok, message = pcall(function()
      local frame, holder, canonical, gate = item.source, item.destination.technology, item.source.technology, item.gate
      if item.action == "transfer" then
        if holder.level ~= frame.next_level or holder.researched then holder.level = frame.next_level end
        holder.enabled, holder.visible_when_disabled = item.target_enabled, item.target_visible
        local public_level = frame.next_level >= 5 and 5 or 4
        if canonical.level ~= public_level or canonical.researched then canonical.level = public_level end
        canonical.enabled, canonical.visible_when_disabled = false, frame.visible
        set_gate_paid(gate, frame.next_level >= 5)
        canonical.saved_progress, holder.saved_progress = 0, frame.saved_progress
        if frame.occurrences > 0 then
          local queue = {}
          for index, name in ipairs(frame.queue) do queue[index] = name == recovery.canonical and id or name end
          assign_queue(item.force, frame, queue, true, id)
        end
        canonical.saved_progress, holder.saved_progress = 0, frame.saved_progress
        if frame.current == recovery.canonical then item.force.research_progress = frame.current_progress end
        if not frame.researched and holder.research_unit_count ~= frame.count then recover_error("native full default work price differs") end
      elseif item.action == "first-credit" then
        -- The paid work is already on T4. Never rewrite its queue or progress
        -- at completion, including the observed nil-current/queued remainder.
        canonical.level = 5
        canonical.enabled, canonical.visible_when_disabled = false, frame.visible
        set_gate_paid(gate, true)
      elseif item.action == "settle-gate" then
        gate.enabled = false
      end
    end)
    default_mutating_force = previous
    if not ok then error(message, 0) end
  end
  for _, item in ipairs(fresh.items) do
    local finished = fresh.context.finished_force == item.force.index
    local actual_source = default_frame(item.force, recovery.canonical, finished)
    local actual_owner, gate = default_frame(item.force, id, finished), gate_frame(item.force)
    if not full_pair(actual_source, actual_owner, gate) or native_bonus(item.force) ~= item.bonus
        or actual_source.visible ~= item.source.visible then
      recover_error("native full default contribution/first-level state was not preserved; reload the original copy")
    end
    if item.action == "transfer" then
      local expected = frame_values(item.source)
      expected.researched = false
      expected.current = expected.current == recovery.canonical and id or expected.current
      for index, name in ipairs(expected.queue) do if name == recovery.canonical then expected.queue[index] = id end end
      if expected.queued_saved[recovery.canonical] ~= nil then
        expected.queued_saved[id], expected.queued_saved[recovery.canonical] = expected.queued_saved[recovery.canonical], nil
      end
      if item.source.researched then expected.count = actual_owner.count end
      if not equal_plain(expected, frame_values(actual_owner)) or actual_source.visible ~= item.source.visible then
        recover_error("native full default transfer did not preserve the exact frame; reload the original copy")
      end
    elseif not equal_plain(frame_values(item.destination), frame_values(actual_owner)) then
      recover_error("native full default owner work changed during first-level credit")
    elseif (item.action == "validate" or item.action == "settle-gate")
        and not equal_plain(frame_values(item.source), frame_values(actual_source)) then
      recover_error("validated native public first-level state changed")
    end
  end
  if storage[OWNER_KEY] ~= fresh.prior_owner then recover_error("default ownership changed during native mutation; reload the original copy") end
  storage[OWNER_KEY] = fresh.record
  reconnect_default(fresh.record)
  return true
end

-- One native transfer delegates to the existing prepared quota engine.
-- These are ephemeral issued-plan identities, not saved work or a second ledger.
local provider_plans = setmetatable({}, {__mode="k"})

local function finite_provider_contract(route)
  local current = fact(route)
  if not current or current.kind ~= "finite" or route.finite[1].max_level ~= 4 then
    recover_error("full default handover requires an admitted finite public4", route)
  end
  for _, stage in ipairs(route.finite) do
    local prototype = native_prototype(stage.name)
    local first = tonumber(stage.name:match("%-(%d+)$"))
    if not prototype or prototype.level ~= first or prototype.max_level ~= stage.max_level
        or creator(stage.name) ~= stage.provider then recover_error("finite provider prototype custody changed", route) end
  end
  local endpoint = native_prototype(route.technology)
  if not endpoint or endpoint.level ~= route.level or endpoint.max_level ~= 4294967295
      or creator(route.technology) ~= (route.owned and MIR or route.provider) then
    recover_error("finite continuation prototype custody changed", route)
  end
  local public, owner = native_prototype(recovery.canonical), native_prototype(recovery.ordinary_default_id)
  if not owner or creator(recovery.ordinary_default_id) ~= MIR then recover_error("full default owner custody changed", route) end
  local contract = recovery.fingerprint(owner)
  local private = native_prototype(recovery.id)
  if private_contract() ~= contract or private.hidden ~= true or private.enabled ~= false
      or private.visible_when_disabled ~= false then recover_error("full default/private contracts or private flags differ", route) end
  -- Validate the complete new public contract without treating it as the old
  -- cost basis. Only its single worker scalar sets the cancelling head debit.
  local public_view = {level=4, max_level=4294967295, effects=public.effects, prerequisites=public.prerequisites,
    research_unit_count_formula=public.research_unit_count_formula, research_unit_count=public.research_unit_count,
    research_unit_energy=public.research_unit_energy, research_unit_ingredients=public.research_unit_ingredients,
    ignore_tech_cost_multiplier=public.ignore_tech_cost_multiplier}
  recovery.fingerprint(public_view)
  head_gate_contract({effects=public.effects, research_unit_ingredients=owner.research_unit_ingredients,
    ignore_tech_cost_multiplier=owner.ignore_tech_cost_multiplier})
  return current, contract, public
end

local function provider_addition(event, route, owned)
  if type(event) ~= "table" or type(event.mod_startup_settings_changed) ~= "boolean" or type(event.mod_changes) ~= "table"
      or script.active_mods[MIR] ~= target.distribution_version then
    local details = type(event) == "table" and event or {}
    recover_error("full default handover requires a boolean startup event and exact package; startup_type="
      .. type(details.mod_startup_settings_changed) .. " expected_mir=" .. target.distribution_version,
      route, details, checked_state(), fact(route))
  end
  local mir = event.mod_changes[MIR]
  if mir and (type(mir) ~= "table" or type(mir.old_version) ~= "string" or mir.old_version ~= owned.producer.new_version
      or mir.new_version ~= script.active_mods[MIR]) then
    recover_error("full default handover package event is inconsistent", route)
  end
  for _, stage in ipairs(route.finite) do
    local change = event.mod_changes[stage.provider]
    if type(change) ~= "table" or change.old_version ~= nil or change.new_version ~= script.active_mods[stage.provider]
        or type(change.new_version) ~= "string" then recover_error("finite provider must be a proved new addition", route) end
  end
  for name, change in pairs(event.mod_changes) do
    if name ~= MIR and (type(change) ~= "table" or type(change.new_version) ~= "string"
        or change.new_version ~= script.active_mods[name] or change.old_version ~= nil and change.old_version ~= change.new_version) then
      recover_error("provider handover cannot combine removal or existing-mod updates", route)
    end
  end
end

local function plan_provider_handover(event, route)
  local owned, state = owner_record(), checked_state()
  if not owned or owned.kind ~= "full-default" or state ~= nil and (state.schema ~= 2 or state.kind ~= "route"
      or state.current.kind ~= "default") then recover_error("finite handover has no full default authority", route) end
  local current, contract, public_prototype = finite_provider_contract(route)
  if contract ~= owned.contract then recover_error("native full default contract changed before provider handover", route) end
  provider_addition(event, route, owned)
  empty_private()
  local record = clone(owned)
  record.kind, record.current = "provider-retired", clone(current)
  local prepared = {schema=2, kind="prepared", phase="provider", current=clone(current), contract=contract,
    cap=selected_cap, family_enabled=selected_enabled, forces={}}
  local items, seen = {}, {}
  for _, force in ipairs(forces()) do
    local prior = owned.forces[force.index]
    if not prior then recover_error("provider handover force authority is missing", route) end
    seen[force.index] = true
    local frame, destination = snapshot(force, recovery.ordinary_default_id), snapshot(force, recovery.id)
    local public, gate = snapshot(force, recovery.canonical), gate_frame(force, true)
    local paid = frame.next_level >= 5
    if public.next_level ~= (paid and 5 or 4) or public.researched ~= paid or public.saved_progress ~= 0
        or public.occurrences ~= 0 or public.current == recovery.canonical or gate_paid(gate) ~= paid then
      recover_error("finite public first/debit does not match proved owner first level", route)
    end
    if destination.next_level ~= 4 or destination.researched or destination.saved_progress ~= 0
        or destination.occurrences ~= 0 or destination.enabled or destination.visible then
      recover_error("legacy private destination is not pristine", route)
    end
    if frame.occurrences > 0 then requeueable(force, frame, true, true) end
    local allowance = frame.allowance
    -- New provider settings may set the event flag without changing T4's saved
    -- contract. Admit only actual pending work allowed by the current policy.
    local limit = frame.next_level + allowance - 1
    if allowance > 0 and (not selected_enabled or selected_cap > 0 and limit > selected_cap) then
      recover_error("pending default worker work exceeds the current enabled/cap policy; force=" .. force.index
        .. " enabled=" .. tostring(selected_enabled) .. " cap=" .. selected_cap .. " limit=" .. limit,
        route, event, state, current)
    end
    local flags = prior.retired_flags
    local release = flags.disabled_by_mir and not public.enabled and public_prototype.enabled == true
    prepared.forces[force.index] = {next_level=frame.next_level, limit=limit,
      pending=allowance>0, enabled=allowance>0 and frame.enabled or false, visible=frame.visible}
    record.forces[force.index].phase = "retired"
    items[#items+1] = {force=force, source=frame, destination=destination, public=public, gate_paid=gate_paid(gate), gate_enabled=gate.enabled,
      release_public=release, bonus=native_bonus(force), phase="retired", moved=true}
  end
  for index in pairs(owned.forces) do if not seen[index] then recover_error("stale provider handover force history", route) end end
  if #items == 0 then recover_error("provider handover requires native forces", route) end
  return {kind="default-native-provider-handover", event=clone(event), route=copy(route), current=current,
    prior_owner=owned, prior_state=state, record=record, prepared=prepared, items=items, contract=contract,
    cap=selected_cap, enabled=selected_enabled, already_owned=true, changed=true}
end

local function verify_provider_plan(plan, fresh)
  local authorization = provider_plans[plan]
  if not authorization or not equal_plain(plan.event, authorization.event) then
    recover_error("issued provider handover event changed")
  end
  if plan.prior_owner ~= fresh.prior_owner or plan.prior_state ~= fresh.prior_state
      or plan.contract ~= fresh.contract or plan.cap ~= fresh.cap or plan.enabled ~= fresh.enabled
      or not equal_plain(plan.event, fresh.event) or not equal_plain(plan.current, fresh.current)
      or not equal_plain(plan.record, fresh.record) or not equal_plain(plan.prepared, fresh.prepared)
      or #plan.items ~= #fresh.items then recover_error("stale full default provider handover") end
  for index, item in ipairs(fresh.items) do
    local old = plan.items[index]
    if old.force.index ~= item.force.index or old.gate_paid ~= item.gate_paid or old.gate_enabled ~= item.gate_enabled or old.bonus ~= item.bonus
        or old.release_public ~= item.release_public or not equal_plain(frame_values(old.source), frame_values(item.source))
        or not equal_plain(frame_values(old.destination), frame_values(item.destination))
        or not equal_plain(frame_values(old.public), frame_values(item.public)) then
      recover_error("native work changed after provider preflight")
    end
  end
end

function M.default_owner_delegated(plan)
  return type(plan) == "table" and plan.kind == "default-native-provider-handover" and provider_plans[plan] ~= nil
end

delegated_provider_preflight = function(event, route, plan)
  if not M.default_owner_delegated(plan) or not equal_plain(event, plan.event) or not same(route, plan.route) then
    recover_error("unissued or mismatched provider delegation", route)
  end
  local authorization = provider_plans[plan]
  if authorization.applied then recover_error("provider delegation was already applied", route) end
  verify_provider_plan(plan, plan_provider_handover(event, route))
  if not authorization.legacy then
    authorization.legacy = {recovery=true, state=clone(plan.prepared), delegated_handover=plan}
  end
  if not equal_plain(authorization.legacy.state, plan.prepared) then recover_error("provider quota delegation changed") end
  return authorization.legacy
end

delegated_provider_apply = function(legacy)
  local plan, authorization = legacy.delegated_handover, provider_plans[legacy.delegated_handover]
  if not M.default_owner_delegated(plan) or not authorization.applied or authorization.legacy ~= legacy
      or storage[OWNER_KEY] ~= authorization.record then recover_error("native provider handover must precede legacy quota commit") end
  if authorization.committed and storage[KEY] == legacy.state then return end
  if storage[KEY] ~= plan.prior_state or not equal_plain(legacy.state, plan.prepared) then recover_error("provider quota state changed before commit") end
  prepared_frames(legacy.state)
  for _, item in ipairs(authorization.settled) do
    if not equal_plain(item.private, frame_values(snapshot(item.force, recovery.id)))
        or not equal_plain(item.public, frame_values(snapshot(item.force, recovery.canonical)))
        or not equal_plain(item.owner, frame_values(snapshot(item.force, recovery.ordinary_default_id)))
        or gate_paid(gate_frame(item.force)) ~= item.gate_paid or native_bonus(item.force) ~= item.bonus then
      recover_error("native provider frame changed before quota commit")
    end
  end
  storage[KEY] = legacy.state
  reconnect(legacy.state)
  authorization.committed = true
end

local function apply_provider_handover(plan)
  if not M.default_owner_delegated(plan) then recover_error("unissued provider native handover") end
  local authorization = provider_plans[plan]
  if authorization.applied then
    if storage[OWNER_KEY] ~= authorization.record then recover_error("applied provider authority changed") end
    return false
  end
  if not authorization.legacy then recover_error("provider legacy quota must be preflighted before native writes") end
  local fresh = plan_provider_handover(plan.event, plan.route)
  verify_provider_plan(plan, fresh)
  if authorization.legacy.delegated_handover ~= plan or not equal_plain(authorization.legacy.state, fresh.prepared) then
    recover_error("provider quota delegation changed before native writes")
  end
  for _, item in ipairs(fresh.items) do
    local previous = default_mutating_force
    default_mutating_force = item.force.index
    local ok, message = pcall(function()
      local frame, holder = item.source, item.destination.technology
      holder.level = frame.next_level
      holder.enabled = fresh.prepared.forces[item.force.index].enabled
      holder.visible_when_disabled, holder.saved_progress = frame.visible, frame.saved_progress
      frame.technology.level = 4
      frame.technology.enabled, frame.technology.visible_when_disabled = false, false
      frame.technology.saved_progress = 0
      if frame.occurrences > 0 then
        local queue = {}
        for index, name in ipairs(frame.queue) do queue[index] = name == recovery.ordinary_default_id and recovery.id or name end
        assign_queue(item.force, frame, queue, true, recovery.id, false, recovery.ordinary_default_id)
      end
      frame.technology.saved_progress, holder.saved_progress = 0, frame.saved_progress
      if frame.current == recovery.ordinary_default_id then item.force.research_progress = frame.current_progress end
      if not frame.researched and holder.research_unit_count ~= frame.count then recover_error("provider transferred work price differs") end
      if item.release_public then item.public.technology.enabled = true end
      if item.gate_enabled then item.force.technologies[recovery.head_id].enabled = false end
    end)
    default_mutating_force = previous
    if not ok then error(message, 0) end
  end
  local settled = {}
  for _, item in ipairs(fresh.items) do
    local owner, private = snapshot(item.force, recovery.ordinary_default_id), snapshot(item.force, recovery.id)
    local public, gate = snapshot(item.force, recovery.canonical), gate_frame(item.force)
    local expected = frame_values(item.source)
    expected.researched = false
    expected.enabled = fresh.prepared.forces[item.force.index].enabled
    expected.current = expected.current == recovery.ordinary_default_id and recovery.id or expected.current
    for index, name in ipairs(expected.queue) do if name == recovery.ordinary_default_id then expected.queue[index] = recovery.id end end
    if expected.queued_saved[recovery.ordinary_default_id] ~= nil then
      expected.queued_saved[recovery.id], expected.queued_saved[recovery.ordinary_default_id] = expected.queued_saved[recovery.ordinary_default_id], nil
    end
    if item.source.researched then expected.count = private.count end
    local public_expected = frame_values(item.public)
    public_expected.enabled = item.release_public or public_expected.enabled
    public_expected.current, public_expected.current_progress = expected.current, expected.current_progress
    public_expected.queue, public_expected.queued_saved = clone(expected.queue), clone(expected.queued_saved)
    if not equal_plain(expected, frame_values(private)) or not equal_plain(public_expected, frame_values(public))
        or owner.next_level ~= 4 or owner.researched or owner.saved_progress ~= 0 or owner.occurrences ~= 0
        or owner.enabled or owner.visible or gate_paid(gate) ~= item.gate_paid or native_bonus(item.force) ~= item.bonus then
      recover_error("provider handover did not preserve exact native work/contribution; reload the original copy")
    end
    settled[#settled+1] = {force=item.force, private=frame_values(private), public=frame_values(public),
      owner=frame_values(owner), gate_paid=gate_paid(gate), bonus=item.bonus}
  end
  if storage[OWNER_KEY] ~= fresh.prior_owner or storage[KEY] ~= fresh.prior_state then recover_error("provider history changed during native mutation") end
  storage[OWNER_KEY] = fresh.record
  authorization.record, authorization.applied, authorization.settled = fresh.record, true, settled
  reconnect_default(fresh.record)
  return true
end

local function retired_provider_current(event, route)
  local state = owner_record()
  local current, contract = finite_provider_contract(route)
  if state.kind ~= "provider-retired" or not same_fact(state.current, current) or state.contract ~= contract then
    recover_error("retired default provider removal/changed continuation remains unqualified", route)
  end
  for _, stage in ipairs(route.finite) do
    local change = type(event) == "table" and type(event.mod_changes) == "table" and event.mod_changes[stage.provider]
    if change and (type(change) ~= "table" or type(change.old_version) ~= "string" or change.old_version == ""
        or type(change.new_version) ~= "string" or change.new_version ~= script.active_mods[stage.provider]) then
      recover_error("retired provider update event is inconsistent", route)
    end
  end
  local items, changed = {}, false
  for _, force in ipairs(forces()) do
    local frame = snapshot(force, recovery.ordinary_default_id)
    if frame.next_level ~= 4 or frame.researched or frame.saved_progress ~= 0 or frame.occurrences ~= 0 or frame.enabled or frame.visible then
      recover_error("retired default owner gained unrecorded work", route)
    end
    local gate = gate_frame(force, true)
    if gate.enabled and not state.forces[force.index] then recover_error("retired head has no recorded force authority", route) end
    changed = changed or gate.enabled
    items[#items+1] = {force=force, owner=frame, public=snapshot(force, recovery.canonical),
      private=snapshot(force, recovery.id), gate_paid=gate_paid(gate), gate_enabled=gate.enabled, bonus=native_bonus(force)}
  end
  if changed then
    if type(event) ~= "table" or type(event.mod_startup_settings_changed) ~= "boolean"
        or type(event.mod_changes) ~= "table" or script.active_mods[MIR] ~= target.distribution_version then
      recover_error("retired head flag settlement requires a current configuration event", route)
    end
    return {kind="default-native-provider-gate-settle", event=clone(event), route=copy(route),
      prior_owner=state, current=current, contract=contract, items=items, changed=true}
  end
end

local function apply_retired_gate_settlement(plan)
  local authorization = provider_plans[plan]
  if not authorization or not equal_plain(plan.event, authorization.event) then recover_error("unissued retired head flag settlement") end
  if authorization.applied then return false end
  local fresh = retired_provider_current(plan.event, plan.route)
  if not fresh or plan.prior_owner ~= fresh.prior_owner
      or plan.contract ~= fresh.contract or not equal_plain(plan.current, fresh.current)
      or #plan.items ~= #fresh.items then recover_error("stale retired head flag settlement") end
  for index, item in ipairs(fresh.items) do
    local old = plan.items[index]
    if old.force.index ~= item.force.index or old.gate_paid ~= item.gate_paid or old.gate_enabled ~= item.gate_enabled
        or old.bonus ~= item.bonus or not equal_plain(frame_values(old.owner), frame_values(item.owner))
        or not equal_plain(frame_values(old.public), frame_values(item.public))
        or not equal_plain(frame_values(old.private), frame_values(item.private)) then
      recover_error("native frame changed after retired head preflight")
    end
  end
  -- Legacy prepared quota commit legitimately replaces its schema2 table
  -- before this operation. This plan owns no quota field; retain the current
  -- table exactly while settling only the sealed native H flag.
  local prior_state = storage[KEY]
  for _, item in ipairs(fresh.items) do
    if item.gate_enabled then
      local previous = default_mutating_force
      default_mutating_force = item.force.index
      local ok, message = pcall(function() item.force.technologies[recovery.head_id].enabled = false end)
      default_mutating_force = previous
      if not ok then error(message, 0) end
    end
  end
  for _, item in ipairs(fresh.items) do
    local gate = gate_frame(item.force)
    if gate_paid(gate) ~= item.gate_paid or native_bonus(item.force) ~= item.bonus
        or not equal_plain(frame_values(item.owner), frame_values(snapshot(item.force, recovery.ordinary_default_id)))
        or not equal_plain(frame_values(item.public), frame_values(snapshot(item.force, recovery.canonical)))
        or not equal_plain(frame_values(item.private), frame_values(snapshot(item.force, recovery.id))) then
      recover_error("retired head flag settlement changed native work/contribution")
    end
  end
  if storage[OWNER_KEY] ~= fresh.prior_owner or storage[KEY] ~= prior_state then recover_error("retired head authority changed during settlement") end
  authorization.applied = true
  return true
end

local function default_active(route, split_current)
  local state = owner_record()
  if not state and (split_current ~= true or route ~= nil) then return false end
  if split_current ~= true or route ~= nil then recover_error("native default owner provider/unavailable transition is not implemented") end
  return true
end

function M.default_owner_on_init(route, split_current)
  if not default_active(route, split_current) then return false end
  return M.apply_default_owner_transfer(M.plan_default_owner_transfer(nil, route, true))
end

function M.default_owner_preflight(event, route, split_current)
  local owned = owner_record()
  if owned and owned.kind == "provider-retired" then
    local plan = retired_provider_current(event, route)
    if plan then provider_plans[plan] = {event=clone(plan.event)} end
    return plan
  end
  if owned and route ~= nil then
    if split_current ~= true then recover_error("provider handover has no admitted owner data") end
    local plan = plan_provider_handover(event, route)
    provider_plans[plan] = {event=clone(plan.event)}
    return plan
  end
  if not default_active(route, split_current) then return nil end
  return M.plan_default_owner_transfer(event, route, false, owner_record() and {configuration=true} or nil)
end

function M.default_owner_apply(plan)
  if plan == nil then return false end
  if type(plan) == "table" and plan.kind == "default-native-provider-handover" then return apply_provider_handover(plan) end
  if type(plan) == "table" and plan.kind == "default-native-provider-gate-settle" then return apply_retired_gate_settlement(plan) end
  return M.apply_default_owner_transfer(plan)
end

function M.default_owner_on_load()
  -- Storage-only structural validation; no native snapshot or replay on load.
  reconnect_default(owner_record())
end

function M.default_owner_mutating(event)
  local force = event and (event.force or event.research and event.research.force)
  return default_mutating_force ~= nil and force ~= nil and force.index == default_mutating_force
end

function M.default_owner_on_research_finished(event)
  local force, research = event and event.research and event.research.force, event and event.research
  if not default_head_pending or not force or M.default_owner_mutating(event) then return false end
  local state = owner_record()
  if research.name ~= recovery.ordinary_default_id then return false end
  if not state or not state.forces[force.index] then recover_error("default completion has unknown force history") end
  if event.by_script ~= false then recover_error("full default completion must be ordinary native research") end
  local owner = force.technologies[recovery.ordinary_default_id]
  if not owner or not integer(owner.level) or type(owner.researched) ~= "boolean"
      or owner.level + (owner.researched and 1 or 0) < 5 then
    recover_error("full default completion has no native earned first level")
  end
  local plan = M.plan_default_owner_transfer(nil, nil, false, {finished_force=force.index})
  return M.apply_default_owner_transfer(plan)
end

function M.default_owner_on_force_created(event)
  local retired = owner_record()
  if retired and retired.kind == "provider-retired" then return false end
  if not owner_record() or not event or not event.force then return false end
  return M.apply_default_owner_transfer(M.plan_default_owner_transfer(nil, nil, false, {created_force=event.force.index}))
end

function M.default_owner_on_force_reset(event)
  local retired = owner_record()
  if retired and retired.kind == "provider-retired" then return false end
  if not owner_record() or not event or not event.force then return false end
  return M.apply_default_owner_transfer(M.plan_default_owner_transfer(nil, nil, false, {reset_force=event.force.index}))
end

function M.default_owner_on_forces_merged(event)
  local retired = owner_record()
  if retired and retired.kind == "provider-retired" then return false end
  local state = owner_record()
  if not state or not event or not event.destination then return false end
  local destination, source_index = event.destination, event.source_index
  if not integer(source_index) or source_index == destination.index or not state.forces[source_index]
      or not state.forces[destination.index] then recover_error("default native merge has unknown force identity") end
  local _, _, contract = default_contract()
  if contract ~= state.contract then recover_error("default merge contract changed") end
  local next_state, seen = clone(state), {}
  next_state.forces[source_index] = nil
  for _, force in ipairs(forces()) do
    if force.index == source_index or not next_state.forces[force.index] then return false, "unqualified-native-merge-frame" end
    seen[force.index] = true
    local head, owner, gate = snapshot(force, recovery.canonical), snapshot(force, recovery.ordinary_default_id), gate_frame(force)
    if not full_pair(head, owner, gate) then return false, "unqualified-native-merge-frame" end
  end
  for index in pairs(next_state.forces) do if not seen[index] then return false, "unqualified-native-merge-frame" end end
  -- Preserve existing destination rights. Merged native levels/work alone do
  -- not create enablement rights for a previously external-disabled public row.
  storage[OWNER_KEY] = next_state
  reconnect_default(next_state)
  return true, "native-merge-metadata-only"
end

function M.prepare(route)
  if storage[OWNER_KEY] ~= nil then recover_error("ordinary native default ownership cannot use legacy preparation") end
  local state = checked_state()
  if state and state.schema == 2 and state.kind == "prepared" then
    prepared_current(state, fact(route))
    return false, "Already prepared; keep its protected copy and do not repeat the transfer."
  end
  if state and (state.schema ~= 2 or state.kind ~= "route" or state.current.kind ~= "default") then
    recover_error("saved worker route does not establish an unchanged default source")
  end
  if not same_fact(fact(route), {kind="default"}) then recover_error("preparation requires live MIR-owned default infinite4") end
  if creator(recovery.canonical) ~= MIR then recover_error("canonical worker4 creation custody is not MIR") end
  local contract = private_contract()
  if recovery.fingerprint(native_prototype(recovery.canonical)) ~= contract then
    recover_error("canonical/private worker contracts differ")
  end
  for level = 5, 9 do
    if native_prototype("worker-robots-storage-" .. level) ~= nil then recover_error("preparation requires the default4 source without a foreign worker tail") end
  end
  local empty = empty_private(true)
  local plans, next_state = {}, {schema=2, kind="prepared", phase="default", current={kind="default"},
    contract=contract, cap=selected_cap, family_enabled=selected_enabled, forces={}}
  for _, item in ipairs(empty) do
    local force = item.force
    local frame = snapshot(force, recovery.canonical)
    if frame.allowance > 0 and (not selected_enabled or selected_cap > 0
        and frame.next_level + frame.allowance - 1 > selected_cap) then
      recover_error("unfinished default worker work exceeds the current enabled/cap policy")
    end
    requeueable(force, frame, true)
    local queue = {}
    for index, name in ipairs(frame.queue) do queue[index] = name == recovery.canonical and recovery.id or name end
    plans[#plans + 1] = {force=force, source=frame, private=item.technology, queue=queue}
    next_state.forces[force.index] = {next_level=frame.next_level, limit=frame.next_level + frame.allowance - 1,
      pending=frame.allowance > 0, enabled=frame.allowance > 0 and frame.enabled or false, visible=frame.visible}
  end
  if #plans == 0 then recover_error("native force/private frames are unavailable") end
  -- All forces/contracts/work were checked before the first native setter.
  for _, plan in ipairs(plans) do
    local frame, holder = plan.source, plan.private
    holder.level = frame.next_level -- sole native materialization; clears researched=true.
    holder.enabled, holder.visible_when_disabled = next_state.forces[plan.force.index].enabled, frame.visible
    frame.technology.level = 4
    frame.technology.enabled, frame.technology.visible_when_disabled = frame.enabled, frame.visible
    frame.technology.saved_progress = 0
    assign_queue(plan.force, frame, plan.queue, true)
    -- Cancelling the old current through the final queue setter can cache its
    -- progress on canonical4 again. Only the transferred private row owns it.
    frame.technology.saved_progress = 0
    if holder.saved_progress ~= frame.saved_progress then holder.saved_progress = frame.saved_progress end
    if frame.current == recovery.canonical then plan.force.research_progress = frame.current_progress end
    if not frame.researched and holder.research_unit_count ~= frame.count then recover_error("native transferred work price differs") end
  end
  storage[KEY] = next_state
  reconnect(next_state)
  return true, "Prepared " .. #plans .. " forces. Save this COPY under a new name, exit immediately, then add the provider without changing MIR settings."
end

function M.resume(force, route)
  local state = checked_state()
  if not state or state.schema ~= 2 or state.kind ~= "prepared" then recover_error("no prepared work exists") end
  local all = prepared_current(state, fact(route))
  local selected
  for _, item in ipairs(all) do if item.force == force then selected = item; break end end
  if not selected then recover_error("requested prepared force is unavailable") end
  local frame, record = selected.frame, selected.record
  if frame.occurrences > 0 then return false, "Preserved worker work is already queued."
  elseif not record.pending or frame.saved_progress <= 0 then recover_error("no detached partial worker work remains")
  elseif not frame.enabled then recover_error("preserved worker work retains its original disabled flag") end
  requeueable(force, frame)
  for _, prerequisite in pairs(frame.technology.prerequisites or {}) do
    if not prerequisite.researched then recover_error("preserved worker prerequisite is unavailable") end
  end
  local queue = clone(frame.queue); queue[#queue + 1] = recovery.id
  assign_queue(force, frame, queue)
  frame.technology.saved_progress = frame.saved_progress
  if frame.current then force.research_progress = frame.current_progress end
  prepared_current(state, fact(route))
  return true, "Queued the preserved worker partial work for force " .. force.name .. "."
end

function M.command(command, route)
  command = command or {}
  local player = command.player_index and game.get_player(command.player_index)
  local function reply(text) if player then player.print(text) elseif log then log("[MIR worker recovery] " .. text) end end
  if command.player_index and (not player or player.admin ~= true) then reply("Only an administrator or server may prepare recovery."); return end
  local operation, name = tostring(command.parameter or ""):match("^%s*(%S+)%s*(.-)%s*$")
  local ok, result, message
  if operation == "prepare" and name == "" then ok, result, message = pcall(M.prepare, route)
  elseif operation == "resume" then
    local force = name ~= "" and game.forces[name] or player and player.force
    if not force then reply("Use resume <force-name> on the server."); return end
    ok, result, message = pcall(M.resume, force, route)
  else reply("Usage: /mir-worker-storage-recovery prepare | resume <force-name>"); return end
  reply(ok and message or tostring(result))
end

local function actual_record(force)
  local frame = snapshot(force, recovery.id)
  return {next_level=frame.next_level, limit=frame.next_level + frame.allowance - 1,
    pending=frame.allowance > 0, enabled=frame.enabled, visible=frame.visible}
end

function M.on_force_created(event)
  local force = event and event.force
  if not force then return end
  private_contract()
  local state = checked_state()
  local technology = force.technologies and force.technologies[recovery.id]
  if not technology or technology.level ~= 4 or technology.researched ~= false or technology.saved_progress ~= 0
      or type(technology.enabled) ~= "boolean" or type(technology.visible_when_disabled) ~= "boolean" then
    recover_error("new force has unknown private worker investment")
  end
  if force.current_research and force.current_research.name == recovery.id then recover_error("new force has private current work") end
  for _, queued in ipairs(force.research_queue or {}) do if queued.name == recovery.id then recover_error("new force has private queued work") end end
  technology.enabled, technology.visible_when_disabled = false, false
  if state and state.schema == 2 and state.kind == "prepared" then state.forces[force.index] = actual_record(force); reconnect(state) end
end

function M.on_force_reset(event)
  M.on_force_created(event)
end

function M.on_forces_merged(event)
  local state = checked_state()
  if not state or state.schema ~= 2 or state.kind ~= "prepared" or not event or not event.destination then return end
  -- Native merge semantics own the surviving level/effects/queue/partials.
  -- Do not combine two old progress values or write any native state here.
  state.forces[event.source_index] = nil
  state.forces[event.destination.index] = actual_record(event.destination)
  reconnect(state)
end

function M.on_research_event(event, finished)
  -- Native queue setters can emit queued events before current/progress have
  -- settled. Our caller validates the completed frame after its owned write.
  if not pending then return false end
  local force = event and (event.force or event.research and event.research.force)
  if not force then return false end
  if owned_queue_force ~= nil and owned_queue_force == force.index then return false end
  local state = checked_state()
  if not state or state.kind ~= "prepared" then return false end
  local record = state.forces[force.index]
  if not record then recover_error("research force has no prepared private history") end
  -- Other forces can keep the shared hook active after this force retires.
  -- An unrelated queued research grants this retired force no private rights.
  if not record.pending and (not event.research or event.research.name ~= recovery.id) then return false end
  local queued_observation = finished ~= true and defines and defines.events
    and event.name == defines.events.on_research_queued and event.research
    and event.research.force == force and (event.force == nil or event.force == force)
  local finished_context = finished == true and event.research and event.research.force
    and event.research.force.index == force.index
  local frame = snapshot(force, recovery.id, finished_context, queued_observation)
  local advanced = finished and event.research and event.research.name == recovery.id
  if frame.next_level ~= record.next_level + (advanced and 1 or 0)
      or frame.next_level > record.limit + 1 or frame.enabled ~= record.enabled or frame.visible ~= record.visible then
    recover_error("private worker completion/history changed unexpectedly")
  end
  -- Queue setter observations can precede their new current research. Validate
  -- the private cursor/flags above, but never write from a queued observation. The
  -- settled started/cancelled/finished callback enforces the same native quota.
  if queued_observation then return false end
  local remaining = math.min(frame.allowance, math.max(0, record.limit - frame.next_level + 1))
  record.next_level, record.limit, record.pending = frame.next_level, frame.next_level + remaining - 1, remaining > 0
  local previous_owner = owned_queue_force
  owned_queue_force = force.index
  local queue_changed = false
  local ok, message = pcall(function()
    if not record.pending then
      queue_changed = caps.remove_unavailable_from_queue(force, {[recovery.id]=true}).queue_changed
      frame.technology.enabled = false
      frame.technology.visible_when_disabled = record.visible
      record.enabled = false
    else
      local _, result = caps.reconcile(force, {[recovery.id]=record.limit}, {})
      queue_changed = result.queue_changed
      frame.technology.visible_when_disabled = record.visible
    end
  end)
  owned_queue_force = previous_owner
  if not ok then error(message, 0) end
  local settled = snapshot(force, recovery.id, finished_context and not queue_changed)
  if settled.next_level ~= record.next_level or settled.enabled ~= record.enabled or settled.visible ~= record.visible then
    recover_error("private worker frame changed during owned queue mutation")
  end
  reconnect(state)
  return true
end

return M
