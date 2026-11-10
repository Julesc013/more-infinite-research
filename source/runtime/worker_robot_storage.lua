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
local pending = false
local default_head_pending = false
local default_mutating_force
local owned_queue_force
local selected_cap, selected_enabled = 0, true

local function clone(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = clone(item) end
  return out
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

local function snapshot(force, id, finished_context)
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
  if (current ~= queue[1] and not waiting_after_finish) or not progress(force.research_progress) then
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
      if name ~= MIR and (type(change) ~= "table" or change.old_version == nil
          or change.old_version ~= change.new_version or change.new_version ~= active[name]) then return false end
    end
  end
  for name, change in pairs(changes) do
    if name ~= MIR and change.old_version ~= change.new_version then return false end
  end
  return true
end

function M.preflight(event, route)
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

local function assign_queue(force, frame, queue, moved, destination, activate_remainder)
  destination = destination or recovery.id
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
      local id = moved and name == recovery.canonical and destination or name
      if not (activate_remainder and queue[1] == id) and force.technologies[id].saved_progress ~= saved then
        force.technologies[id].saved_progress = saved
      end
    end
    local current = moved and frame.current == recovery.canonical and destination or frame.current
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
local DEFAULT_ORIGINS = {
  f200 = {["5.0.20009"]=true, ["5.0.20010"]=true, ["5.0.20011"]=true},
  f210 = {["5.0.21009"]=true, ["5.0.21010"]=true, ["5.0.21011"]=true},
}

local function equal_plain(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not equal_plain(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end

local function checked_default_force(record)
  fields(record, {phase=true, retired_flags=true, tail_disabled_by_mir=true, tail_visibility_hidden_by_mir=true})
  if record.phase ~= "head" and record.phase ~= "tail" then recover_error("invalid default owner phase") end
  fields(record.retired_flags, {enabled=true, visible=true, disabled_by_mir=true, visibility_hidden_by_mir=true})
  local flags = record.retired_flags
  if type(flags.enabled) ~= "boolean" or type(flags.visible) ~= "boolean"
      or flags.disabled_by_mir ~= false or flags.visibility_hidden_by_mir ~= false
      or type(record.tail_disabled_by_mir) ~= "boolean" or type(record.tail_visibility_hidden_by_mir) ~= "boolean"
      or record.phase == "tail" and (record.tail_disabled_by_mir or record.tail_visibility_hidden_by_mir) then
    recover_error("invalid default gating rights; head caps belong to lifecycle")
  end
  return record
end

local function reconnect_default(state)
  default_head_pending = false
  if state then
    for _, record in pairs(state.forces) do
      if record.phase == "head" then default_head_pending = true; break end
    end
  end
end

local function owner_record()
  local value = storage[OWNER_KEY]
  if value == nil then return nil end
  fields(value, {schema=true, kind=true, owner=true, source=true, gate=true, contract=true, producer=true, forces=true})
  if value.schema ~= 2 or value.kind ~= "split-default" or value.owner ~= recovery.ordinary_default_id
      or value.source ~= recovery.canonical or value.gate ~= recovery.head_id
      or type(value.contract) ~= "string" or #value.contract > 8192
      or value.contract:sub(1, 16) ~= "worker-storage-1" then
    recover_error("invalid default native-owner record")
  end
  fields(value.producer, {kind=true, old_version=true, new_version=true})
  if (value.producer.kind ~= "initial-empty" and value.producer.kind ~= "recorded-default"
      and value.producer.kind ~= "unchanged-mir5-default")
      or type(value.producer.new_version) ~= "string" or #value.producer.new_version > 64
      or value.producer.kind == "initial-empty" and value.producer.old_version ~= nil
      or value.producer.kind ~= "initial-empty" and type(value.producer.old_version) ~= "string" then
    recover_error("invalid default native-owner producer")
  end
  local prefix = target.id == "f200" and "^5%.0%.200%d%d$" or "^5%.0%.210%d%d$"
  local known = DEFAULT_ORIGINS[target.id]
  if not value.producer.new_version:match(prefix)
      or value.producer.kind == "unchanged-mir5-default" and (not known or not known[value.producer.old_version])
      or value.producer.kind == "recorded-default" and value.producer.old_version ~= value.producer.new_version
        and (not known or not known[value.producer.old_version]) then
    recover_error("unknown default native-owner producer")
  end
  if type(value.forces) ~= "table" or getmetatable(value.forces) ~= nil then
    recover_error("invalid default native-owner force phases")
  end
  for index, record in pairs(value.forces) do
    if not integer(index) then recover_error("invalid default owner force index") end
    checked_default_force(record)
  end
  return value
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
  if state == nil and event.mod_startup_settings_changed ~= false then
    recover_error("unrecorded default source requires unchanged startup settings")
  end
  local change = event.mod_changes[MIR]
  if change ~= nil and (type(change) ~= "table" or change.new_version ~= active[MIR]) then
    recover_error("default transfer package-change event is inconsistent")
  end
  for name, item in pairs(event.mod_changes) do
    if name ~= MIR and (type(item) ~= "table" or item.old_version == nil
        or item.old_version ~= item.new_version or item.new_version ~= active[name]) then
      recover_error("default transfer requires the unchanged mod selection")
    end
  end
  if state ~= nil then
    if state.schema ~= 2 or state.kind ~= "route" or state.current.kind ~= "default" then
      recover_error("legacy prepared/finite conversion is not a default-owner transfer")
    end
    if change and type(change.old_version) ~= "string" then
      recover_error("recorded default source cannot be a first-install event")
    end
    local old = change and change.old_version or active[MIR]
    local known = DEFAULT_ORIGINS[target.id]
    if type(old) ~= "string" or old ~= active[MIR] and (not known or not known[old]) then
      recover_error("recorded default source has an inconsistent producer event")
    end
    return {kind="recorded-default", old_version=old, new_version=active[MIR]}
  end
  local known = DEFAULT_ORIGINS[target.id]
  if not change or not known or known[change.old_version] ~= true or active.base ~= target.minimum_base then
    recover_error("unrecorded default source has no qualified MIR5 producer")
  end
  local official = {base=true, [MIR]=true, ["space-age"]=true, quality=true, ["elevated-rails"]=true, recycler=true}
  for name, version in pairs(active) do
    if not official[name] or name ~= MIR and version ~= active.base then
      recover_error("unrecorded default source requires its qualified official mod selection")
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
      or prototype.level ~= 4 or prototype.max_level ~= 4 or prototype.hidden ~= true
      or prototype.enabled ~= false or prototype.visible_when_disabled ~= false
      or prototype.research_unit_count_formula ~= nil or prototype.research_unit_count ~= 1
      or prototype.research_unit_energy ~= 60 or next(prototype.prerequisites or {}) ~= nil
      or prototype.ignore_tech_cost_multiplier ~= source.ignore_tech_cost_multiplier then
    recover_error("default head gate contract is invalid")
  end
  local effects, ingredients = prototype.effects, prototype.research_unit_ingredients
  local effect = type(effects) == "table" and #effects == 1 and effects[1]
  local hidden = effect and effect.hidden
  if hidden == nil and target.id == "f200" then hidden = false end
  if not effect or effect.type ~= "worker-robot-storage" or effect.modifier ~= 0 or hidden ~= false
      or type(ingredients) ~= "table" or #ingredients ~= 1
      or ingredients[1].name ~= source.research_unit_ingredients[1].name or ingredients[1].amount ~= 1 then
    recover_error("default head gate science/effect contract is invalid")
  end
end

local function gate_frame(force)
  local gate = force.technologies[recovery.head_id]
  if not gate or gate.level ~= 4 or type(gate.researched) ~= "boolean" or gate.enabled ~= false
      or gate.visible_when_disabled ~= false or gate.saved_progress ~= 0 then
    recover_error("default head gate native state is invalid")
  end
  if force.current_research and force.current_research.name == recovery.head_id then recover_error("head gate cannot be current research") end
  for _, entry in ipairs(force.research_queue or {}) do
    if entry.name == recovery.head_id then recover_error("head gate cannot be queued research") end
  end
  return gate
end

function M.plan_default_owner_transfer(event, route, initializing, context)
  context = context or {}
  if type(initializing) ~= "boolean" or route ~= nil then recover_error("default-only transfer context required") end
  local id = recovery.ordinary_default_id
  if type(id) ~= "string" or id == recovery.canonical or id == recovery.id then recover_error("ordinary default identity is unavailable") end
  local state, owned = checked_state(), owner_record()
  if not same_fact(fact(nil), {kind="default"}) or creator(id) ~= MIR then
    recover_error("default transfer requires exact MIR canonical/tail creation custody")
  end
  local source_prototype, prototype = native_prototype(recovery.canonical), native_prototype(id)
  local contract = recovery.fingerprint(source_prototype)
  if not recovery.matches_default_tail(source_prototype, prototype) or prototype.hidden ~= false
      or type(prototype.enabled) ~= "boolean" or type(prototype.visible_when_disabled) ~= "boolean" then
    recover_error("canonical4/default tail5 contract or flags differ")
  end
  head_gate_contract(source_prototype)
  for level = 5, 9 do
    if native_prototype("worker-robots-storage-" .. level) ~= nil then recover_error("default transfer has a foreign worker tail") end
  end
  empty_private()
  local producer = owned and owned.producer or default_origin(event, initializing, state)
  if state and (state.schema ~= 2 or state.kind ~= "route" or state.current.kind ~= "default") then
    recover_error("legacy prepared/finite conversion is not implemented")
  end
  if owned and owned.contract ~= contract and not context.configuration then recover_error("default native-owner contract changed") end
  if context.configuration and (type(event) ~= "table" or type(event.mod_startup_settings_changed) ~= "boolean"
      or type(event.mod_changes) ~= "table" or script.active_mods[MIR] ~= target.distribution_version) then
    recover_error("current default configuration event is unavailable")
  end
  local record = owned and clone(owned) or {schema=2, kind="split-default", owner=id, source=recovery.canonical,
    gate=recovery.head_id, contract=contract, producer=producer, forces={}}
  record.contract = contract -- current owned native contract, not a frozen private-recovery policy.
  local items, seen, moved = {}, {}, false
  for _, force in ipairs(forces()) do
    seen[force.index] = true
    if not context.finished_force or context.finished_force == force.index then
      local finished = context.finished_force == force.index
      local source = snapshot(force, recovery.canonical, finished and "default-head-finished" or nil)
      local destination, gate = snapshot(force, id, finished and "default-head-finished" or nil), gate_frame(force)
      local prior = owned and owned.forces[force.index]
      local refresh = context.created_force == force.index or context.reset_force == force.index
      if context.created_force == force.index and prior then recover_error("new default force already has history") end
      if refresh and (source.next_level ~= 4 or source.researched or source.saved_progress ~= 0 or source.occurrences ~= 0
          or destination.next_level ~= 5 or destination.researched or destination.saved_progress ~= 0
          or destination.occurrences ~= 0 or gate.researched) then recover_error("new/reset force has unexplained default work") end
      local phase, action, flags = source.next_level == 4 and "head" or "tail", "validate", nil
      local target_enabled, target_visible = source.enabled, source.visible
      local next_force = prior and clone(prior) or nil
      if not prior or refresh then
        if owned and not refresh then recover_error("default force history is missing") end
        if destination.next_level ~= 5 or destination.researched or destination.saved_progress ~= 0
            or destination.occurrences ~= 0 or destination.enabled ~= prototype.enabled
            or destination.visible ~= prototype.visible_when_disabled or gate.researched then
          recover_error("ordinary default tail/gate is not pristine")
        end
        if initializing and (phase ~= "head" or source.saved_progress ~= 0 or source.occurrences ~= 0) then
          recover_error("first initialization cannot adopt existing default work")
        end
        -- Ownership is independent of current startup caps. Preserve the
        -- exact native work first; the lifecycle applies policy afterward.
        next_force = {phase=phase, retired_flags={enabled=source.enabled, visible=source.visible,
          disabled_by_mir=false, visibility_hidden_by_mir=false},
          tail_disabled_by_mir=false, tail_visibility_hidden_by_mir=false}
        action = phase == "tail" and "split" or "gate-head"
      elseif prior.phase == "head" then
        if destination.next_level ~= 5 or destination.researched or destination.saved_progress ~= 0
            or destination.occurrences ~= 0 or gate.researched then recover_error("unfinished default head has invested tail/gate") end
        if source.next_level >= 5 then
          if not (finished or context.configuration) then recover_error("earned head requires an explicit completion/configuration context") end
          phase, action = "tail", "split"
          target_enabled = source.enabled and (destination.enabled or prior.tail_disabled_by_mir)
          target_visible = source.visible
          if source.occurrences > 0 and not target_enabled then recover_error("foreign-disabled default tail cannot receive queued work") end
          next_force.phase = "tail"
          next_force.retired_flags = {enabled=source.enabled, visible=source.visible,
            disabled_by_mir=false, visibility_hidden_by_mir=false}
          next_force.tail_disabled_by_mir, next_force.tail_visibility_hidden_by_mir = false, false
        else
          phase = "head"
          if source.researched then recover_error("invalid unpaid public head representation") end
          action = (destination.enabled or destination.visible) and "gate-head" or "validate"
        end
      else
        phase = "tail"
        if source.next_level ~= 5 or source.researched or source.saved_progress ~= 0 or source.occurrences ~= 0
            or gate.researched ~= true then recover_error("earned public head/default tail ownership changed") end
        -- Head enabled/visibility belong solely to the normal lifecycle cap.
      end
      local activate = action == "split" and source.current == nil and source.queue[1] ~= nil
      if activate and (not finished or source.current_progress ~= 0) then recover_error("default queue activation requires the exact finished context") end
      if action == "split" then requeueable(force, source, true, true); moved = true end
      record.forces[force.index] = next_force
      items[#items + 1] = {force=force, source=source, destination=destination, gate=gate, phase=phase,
        moved=action == "split", action=action, activate_remainder=activate,
        target_enabled=target_enabled, target_visible=target_visible}
    elseif not owned or not owned.forces[force.index] then recover_error("default event has unknown force history") end
  end
  if #items == 0 then recover_error("default transfer requires native force frames") end
  if owned then
    for index in pairs(owned.forces) do if not seen[index] then recover_error("stale default owner force phase") end end
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
  if not fresh.changed then reconnect_default(fresh.record); return false end
  if plan.prior_state ~= fresh.prior_state or plan.prior_owner ~= fresh.prior_owner or plan.contract ~= fresh.contract
      or plan.cap ~= fresh.cap or plan.enabled ~= fresh.enabled or #plan.items ~= #fresh.items then recover_error("stale default transfer plan") end
  for index, item in ipairs(fresh.items) do
    local old = plan.items[index]
    if old.force.index ~= item.force.index or old.action ~= item.action
        or not equal_plain(frame_values(old.source), frame_values(item.source))
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
      if item.action == "gate-head" then
        local record = fresh.record.forces[item.force.index]
        record.tail_disabled_by_mir = record.tail_disabled_by_mir or holder.enabled
        record.tail_visibility_hidden_by_mir = record.tail_visibility_hidden_by_mir or holder.visible_when_disabled
        holder.enabled, holder.visible_when_disabled = false, false
      elseif item.action == "split" then
        if frame.next_level ~= 5 then holder.level = frame.next_level end
        holder.enabled, holder.visible_when_disabled = item.target_enabled, item.target_visible
        gate.researched = true
        gate.enabled, gate.visible_when_disabled = false, false
        if frame.next_level ~= 5 or frame.researched then canonical.level = 5 end
        -- Restore the incoming flags after a native level write. The lifecycle
        -- alone retires public4 at cap4 and owns its normal capped visibility.
        canonical.enabled, canonical.visible_when_disabled = frame.enabled, frame.visible
        canonical.saved_progress, holder.saved_progress = 0, frame.saved_progress
        if frame.occurrences > 0 or item.activate_remainder then
          local queue = {}
          for index, name in ipairs(frame.queue) do queue[index] = name == recovery.canonical and id or name end
          assign_queue(item.force, frame, queue, true, id, item.activate_remainder)
        end
        canonical.saved_progress = 0
        if item.activate_remainder and item.force.current_research and item.force.current_research.name == id then
          holder.saved_progress = 0
        else holder.saved_progress = frame.saved_progress end
        if frame.current == recovery.canonical then item.force.research_progress = frame.current_progress end
        if not frame.researched and holder.research_unit_count ~= frame.count then recover_error("native default tail work price differs") end
      end
    end)
    default_mutating_force = previous
    if not ok then error(message, 0) end
  end
  for _, item in ipairs(fresh.items) do
    local frame, gate = item.source, gate_frame(item.force)
    local context = item.activate_remainder and "default-head-finished" or nil
    local actual_source, actual_tail = snapshot(item.force, recovery.canonical, context), snapshot(item.force, id, context)
    if item.action == "split" then
      local expected = frame_values(frame)
      expected.researched, expected.enabled, expected.visible = false, item.target_enabled, item.target_visible
      if frame.researched then expected.count = actual_tail.count end
      expected.current = frame.current == recovery.canonical and id or frame.current
      for index, name in ipairs(expected.queue) do if name == recovery.canonical then expected.queue[index] = id end end
      if expected.queued_saved[recovery.canonical] ~= nil then
        expected.queued_saved[id], expected.queued_saved[recovery.canonical] = expected.queued_saved[recovery.canonical], nil
      end
      if item.activate_remainder then
        expected.current = expected.queue[1]
        expected.current_progress = frame.queued_saved[frame.queue[1]] or 0
        if expected.current then expected.queued_saved[expected.current] = 0 end
        if expected.current == id then expected.saved_progress = 0 end
      end
      if not equal_plain(expected, frame_values(actual_tail)) or actual_source.next_level ~= 5 or actual_source.researched
          or actual_source.saved_progress ~= 0 or actual_source.occurrences ~= 0
          or actual_source.enabled ~= frame.enabled or actual_source.visible ~= frame.visible or gate.researched ~= true then
        recover_error("native default split did not preserve the exact settled frame; reload the original copy")
      end
    elseif item.phase == "head" then
      if not equal_plain(frame_values(frame), frame_values(actual_source)) or actual_tail.next_level ~= 5 or actual_tail.researched
          or actual_tail.saved_progress ~= 0 or actual_tail.occurrences ~= 0 or actual_tail.enabled or actual_tail.visible
          or gate.researched then recover_error("native default head work changed; reload the original copy") end
    elseif not equal_plain(frame_values(frame), frame_values(actual_source))
        or not equal_plain(frame_values(item.destination), frame_values(actual_tail)) then
      recover_error("validated native default owner changed")
    end
  end
  if storage[OWNER_KEY] ~= fresh.prior_owner then recover_error("default ownership changed during native mutation; reload the original copy") end
  storage[OWNER_KEY] = fresh.record
  reconnect_default(fresh.record)
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
  if not default_active(route, split_current) then return nil end
  return M.plan_default_owner_transfer(event, route, false, owner_record() and {configuration=true} or nil)
end

function M.default_owner_apply(plan)
  if plan == nil then return false end
  return M.apply_default_owner_transfer(plan)
end

function M.default_owner_on_load()
  -- Only structural state validation and local event subscriptions on_load.
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
  local record = state and state.forces[force.index]
  if not record or record.phase ~= "head" or research.name ~= recovery.canonical then return false end
  if type(event.by_script) ~= "boolean" then recover_error("default completion event has no native origin flag") end
  local plan = M.plan_default_owner_transfer(nil, nil, false, {finished_force=force.index})
  if #plan.items ~= 1 or not plan.items[1].moved then recover_error("default completion has not earned its first head") end
  return M.apply_default_owner_transfer(plan)
end

function M.default_owner_on_force_created(event)
  if not owner_record() or not event or not event.force then return false end
  return M.apply_default_owner_transfer(M.plan_default_owner_transfer(nil, nil, false, {created_force=event.force.index}))
end

function M.default_owner_on_force_reset(event)
  if not owner_record() or not event or not event.force then return false end
  return M.apply_default_owner_transfer(M.plan_default_owner_transfer(nil, nil, false, {reset_force=event.force.index}))
end

function M.default_owner_on_forces_merged(event)
  local state = owner_record()
  if not state or not event or not event.destination then return false end
  local destination, source_index = event.destination, event.source_index
  if not integer(source_index) or source_index == destination.index or not state.forces[source_index]
      or not state.forces[destination.index] then recover_error("default native merge has unknown force identity") end
  local source = native_prototype(recovery.canonical)
  if not same_fact(fact(nil), {kind="default"}) or creator(recovery.ordinary_default_id) ~= MIR
      or not recovery.matches_default_tail(source, native_prototype(recovery.ordinary_default_id))
      or recovery.fingerprint(source) ~= state.contract then recover_error("default merge contract changed") end
  head_gate_contract(source)
  local next_state, seen = clone(state), {}
  next_state.forces[source_index] = nil
  for _, force in ipairs(forces()) do
    if force.index == source_index or not next_state.forces[force.index] then
      return false, "unqualified-native-merge-frame"
    end
    seen[force.index] = true
    local head, tail, gate = snapshot(force, recovery.canonical), snapshot(force, recovery.ordinary_default_id), gate_frame(force)
    local phase
    if not gate.researched and head.next_level == 4 and not head.researched
        and tail.next_level == 5 and not tail.researched and tail.saved_progress == 0 and tail.occurrences == 0 then
      phase = "head"
    elseif gate.researched and head.next_level == 5 and not head.researched
        and head.saved_progress == 0 and head.occurrences == 0 then phase = "tail"
    else
      -- The engine alone owns merged levels/queue/partials. A mixed native
      -- contract is retained, never collapsed by inventing combined rights.
      return false, "unqualified-native-merge-frame"
    end
    if force.index == destination.index then
      local prior = state.forces[force.index]
      next_state.forces[force.index] = {phase=phase,
        retired_flags={enabled=head.enabled, visible=head.visible, disabled_by_mir=false, visibility_hidden_by_mir=false},
        tail_disabled_by_mir=phase == "head" and prior.tail_disabled_by_mir and not tail.enabled,
        tail_visibility_hidden_by_mir=phase == "head" and prior.tail_visibility_hidden_by_mir and not tail.visible}
    elseif phase ~= next_state.forces[force.index].phase then return false, "unqualified-native-merge-frame" end
  end
  for index in pairs(next_state.forces) do if not seen[index] then return false, "unqualified-native-merge-frame" end end
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
  local finished_context = finished == true and event.research and event.research.force
    and event.research.force.index == force.index
  local frame = snapshot(force, recovery.id, finished_context)
  local advanced = finished and event.research and event.research.name == recovery.id
  if frame.next_level ~= record.next_level + (advanced and 1 or 0)
      or frame.next_level > record.limit + 1 or frame.enabled ~= record.enabled or frame.visible ~= record.visible then
    recover_error("private worker completion/history changed unexpectedly")
  end
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
