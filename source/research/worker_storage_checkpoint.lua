-- Validate native worker queue observations and retain research terms while
-- the source copy is available. Factorio can discard work during conversion.
local M = {key="mir_worker_storage_engine_checkpoint", source_base="1.1.110",
  legacy_mir="4.7.20002", canonical_worker="worker-robots-storage-4", ordinary_worker="mir-worker-storage-default-4"}
local MIR, WORKER, ORDINARY = "more-infinite-research", M.canonical_worker, M.ordinary_worker
M.preparation_mod, M.preparation_version = "mir-worker-storage-preparation", "0.1.0"
local LEGACY_BASE, LEGACY_SE = "2.0.77", "0.7.57"

local function require_frame(condition, reason)
  if not condition then error("MIR worker engine upgrade: " .. reason .. ". Keep the original save.", 0) end
end

function M.source_version(version)
  return type(version) == "string" and version:match("^5%.0%.110%d%d$") ~= nil
end

function M.valid_progress(value)
  return type(value) == "number" and value >= 0 and value < 1
end

-- A short read must never be saved or applied as an empty or truncated queue.
function M.native_queue(force)
  local queue = force.research_queue
  if type(queue) ~= "table" then return nil, "native queue is unavailable" end
  local length, count = #queue, 0
  if length > 1000 then return nil, "unsupported native queue" end
  for index in pairs(queue) do
    if type(index) ~= "number" or index < 1 or index > length or index % 1 ~= 0 then
      return nil, "incomplete native queue"
    end
    count = count + 1
  end
  if count ~= length then return nil, "incomplete native queue" end
  return queue
end

local function work_terms(technology)
  local terms = {technology.research_unit_count, technology.research_unit_energy}
  require_frame(type(terms[1]) == "number" and terms[1] > 0 and type(terms[2]) == "number" and terms[2] > 0,
    "native research price or time is unavailable on " .. technology.name)
  local ingredients = technology.research_unit_ingredients
  require_frame(type(ingredients) == "table" and #ingredients > 0 and #ingredients <= 32,
    "native science is unavailable on " .. technology.name)
  for _, ingredient in ipairs(ingredients) do
    require_frame(type(ingredient.name) == "string" and type(ingredient.amount) == "number" and ingredient.amount > 0,
      "invalid native science on " .. technology.name)
    terms[#terms + 1] = ingredient.name
    terms[#terms + 1] = ingredient.amount
  end
  return terms
end

local function worker_terms(technology)
  local prototype = technology and technology.prototype
  local effects = prototype and prototype.effects
  local effect = type(effects) == "table" and #effects == 1 and effects[1]
  require_frame(effect and effect.type == "worker-robot-storage" and type(effect.modifier) == "number"
    and prototype.max_level == 4294967295 and technology.level >= 4 and not technology.researched,
    "the public worker is not an infinite native worker4")
  local terms = work_terms(technology)
  terms[#terms + 1] = effect.modifier
  return terms
end

function M.capture(read_saved_progress, identity)
  identity = identity or WORKER
  local saved = {schema=1, tick=game.tick, was_paused=game.tick_paused, mir=script.active_mods[MIR], forces={}}
  for _, force in pairs(game.forces) do
    local worker = force.technologies[identity]
    local terms = worker_terms(worker)
    local queue, parked, paid = {}, {}, {}
    local current = force.current_research
    local fraction = force.research_progress
    local native, reason = M.native_queue(force)
    require_frame(native, reason)
    for index, technology in ipairs(native) do
      local name = technology.name
      local prior = read_saved_progress(force, technology) or 0
      require_frame(M.valid_progress(prior), "invalid native queued progress")
      queue[index], parked[name] = name, prior
      if name ~= identity and (prior > 0 or current and current.name == name and fraction > 0) then
        paid[name] = {level=technology.level, terms=work_terms(technology)}
      end
    end
    local worker_progress = read_saved_progress(force, worker) or 0
    require_frame(queue[1] == (current and current.name) and M.valid_progress(fraction) and M.valid_progress(worker_progress),
      "current native research or progress differs from the queue")
    saved.forces[force.index] = {name=force.name, bonus=force.worker_robots_storage_bonus,
      level=worker.level, terms=terms, saved_progress=worker_progress,
      queue=queue, queued_saved=parked, current_progress=fraction, paid=paid}
    if identity == ORDINARY then
      saved.forces[force.index].enabled = worker.enabled
      saved.forces[force.index].visible = worker.visible_when_disabled
    end
  end
  require_frame(next(saved.forces) ~= nil, "no force research was observed")
  return saved
end

local function prepare()
  local active = script.active_mods
  require_frame(active.base == M.source_base and M.source_version(active[MIR]), "prepare in the Factorio 1.1 edition")
  return M.capture(function(force, technology) return force.get_saved_technology_progress(technology) end)
end

local function watch_prepared_copy()
  script.on_event(defines.events.on_tick, global[M.key] and function()
    global[M.key] = nil
    script.on_event(defines.events.on_tick, nil)
  end or nil)
end

function M.register_source()
  script.on_load(watch_prepared_copy)
  local help = {"mir-command.worker-engine-upgrade"}
  commands.add_command("mir-worker-storage-recovery", help, function(command)
    local player = command.player_index and game.get_player(command.player_index)
    local function say(message)
      if player then player.print(message) else log(type(message) == "string" and "[MIR worker recovery] " .. message or message) end
    end
    if command.player_index and not (player and player.admin) then say(help); return end
    if command.parameter == "cancel" then
      local saved = global[M.key]
      if not saved then say("There is no worker engine upgrade preparation to cancel."); return end
      global[M.key] = nil
      watch_prepared_copy()
      game.tick_paused = saved.was_paused
      say("Cancelled the worker engine upgrade preparation.")
    elseif command.parameter == "prepare" then
      if not global[M.key] then
        local ok, saved = pcall(prepare)
        if not ok then say(saved); return end
        game.tick_paused = true
        global[M.key] = saved
        watch_prepared_copy()
      end
      say("Worker research recorded. Save this paused copy under a new name before opening it in Factorio 2.0.")
    else
      say(help)
    end
  end)
end

function M.matches_preparation_selection(active, original)
  if type(original) ~= "table" then return false end
  for name, version in pairs(original) do
    if name ~= MIR and active[name] ~= version then return false end
  end
  for name, version in pairs(active) do
    if name ~= MIR and name ~= M.preparation_mod and original[name] ~= version then return false end
  end
  return original[MIR] == M.legacy_mir and original.base == LEGACY_BASE
    and original["space-exploration"] == LEGACY_SE and original[M.preparation_mod] == nil
end

local function preparation_snapshot(active)
  require_frame(active[M.preparation_mod] == M.preparation_version and remote.interfaces[M.preparation_mod]
    and remote.interfaces[M.preparation_mod].checkpoint, "the worker preparation mod is incompatible")
  return remote.call(M.preparation_mod, "checkpoint")
end

function M.read_legacy_preparation(event, target)
  local changes = type(event) == "table" and event.mod_changes
  local change = type(changes) == "table" and changes[MIR]
  if target.id ~= "f200" or type(change) ~= "table" or change.old_version ~= M.legacy_mir then return nil end
  local active = script.active_mods
  if active[M.preparation_mod] == nil then return nil end
  local saved = preparation_snapshot(active)
  require_frame(type(saved) == "table" and saved.formula ~= nil and M.matches_preparation_selection(active, saved.source_mods),
    "the worker preparation is missing or its mod selection changed")
  return saved
end

local function require_fresh(saved)
  require_frame(saved.schema == 1 and type(saved.tick) == "number" and game.tick >= saved.tick
    and game.tick - saved.tick <= 1 and type(saved.was_paused) == "boolean"
    and type(saved.forces) == "table", "the preparation expired")
end

function M.read_addon_change_preparation(event, target)
  local active = script.active_mods
  if target.id ~= "f200" or active[M.preparation_mod] == nil or active.base ~= LEGACY_BASE
      or active["space-exploration"] ~= LEGACY_SE then return nil end
  local saved = preparation_snapshot(active)
  if type(saved) ~= "table" or saved.purpose ~= "addon-change" then return nil end
  require_fresh(saved)
  local previous, changes = saved.source_mods, type(event) == "table" and event.mod_changes
  require_frame(saved.mir == active[MIR] and active[MIR] == target.distribution_version
    and type(previous) == "table" and type(changes) == "table" and event.mod_startup_settings_changed == false
    and type(saved.formula) == "string" and #saved.formula > 0 and #saved.formula <= 1024,
    "the prepared add-on change does not match this game")
  for _, retained in ipairs{"base", MIR, "space-exploration", M.preparation_mod} do
    require_frame(previous[retained] == active[retained], "the worker preparation requires its retained engine and providers")
  end
  local function reported(name)
    if previous[name] == active[name] then return true end
    local row = changes[name]
    return type(row) == "table" and row.old_version == previous[name] and row.new_version == active[name]
  end
  for name in pairs(previous) do require_frame(reported(name), "the previous mod selection differs from the preparation") end
  for name in pairs(active) do require_frame(reported(name), "the current mod selection differs from the preparation") end
  for name, row in pairs(changes) do
    require_frame(type(row) == "table" and row.old_version == previous[name] and row.new_version == active[name],
      "the reported mod change differs from the preparation")
  end
  return saved
end

function M.claim(saved, event, target)
  require_frame(type(saved) == "table" and getmetatable(saved) == nil, "invalid preparation")
  local active = script.active_mods
  local changes = type(event) == "table" and event.mod_changes
  local base = type(changes) == "table" and changes.base
  local mir = type(changes) == "table" and changes[MIR]
  local matching_package = target.id == "f200" and active.base == target.minimum_base
    and type(mir) == "table" and mir.old_version == saved.mir and mir.new_version == active[MIR]
    and active[MIR] == target.distribution_version
  if saved.formula ~= nil then
    require_frame(matching_package and saved.mir == M.legacy_mir and active["space-exploration"] == LEGACY_SE
      and event.mod_startup_settings_changed == false and type(saved.formula) == "string"
      and #saved.formula > 0 and #saved.formula <= 1024,
      "open the prepared Space Exploration copy with its previous mod selection and settings")
  else
    require_frame(matching_package and type(base) == "table" and base.old_version == M.source_base
      and base.new_version == active.base and M.source_version(saved.mir),
      "open the prepared copy with its matching Factorio 2.0 edition")
  end
  require_fresh(saved)
  return saved.formula
end

local function observed_bonus(saved, force, planned_bonus)
  local bonus = force.worker_robots_storage_bonus
  if saved.formula and planned_bonus and planned_bonus.force_index == force.index
      and planned_bonus.before == bonus then
    bonus = planned_bonus.after
  end
  return bonus
end

-- Only zero or absent work may be supplied by the paused source. Any surviving
-- nonzero progress, force state or queue order has to corroborate that source.
function M.restore_frame(saved, force, native, equal, planned_bonus)
  local row = saved.forces[force.index]
  require_frame(type(row) == "table" and row.name == force.name
    and row.level == native.next_level and not native.researched,
    "worker force or level changed on " .. force.name)
  require_frame(row.bonus == observed_bonus(saved, force, planned_bonus), "worker cargo changed on " .. force.name)
  require_frame(equal(row.terms, worker_terms(native.technology)), "worker price or science changed on " .. force.name)
  require_frame(type(row.queue) == "table" and type(row.queued_saved) == "table"
    and type(row.paid) == "table" and #row.queue <= 1000
    and M.valid_progress(row.current_progress) and M.valid_progress(row.saved_progress),
    "invalid prepared queue or progress on " .. force.name)
  if saved.formula ~= nil then
    -- The same engine can corroborate the entire checkpoint. Missing work
    -- does not get the restoration allowance used across the 1.1 boundary.
    require_frame(native.saved_progress == row.saved_progress and native.current_progress == row.current_progress
      and equal(row.queue, native.queue) and equal(row.queued_saved, native.queued_saved),
      "same-engine checkpoint progress or queue changed on " .. force.name)
  end
  require_frame(native.saved_progress == 0 or native.saved_progress == row.saved_progress,
    "surviving worker progress changed on " .. force.name)
  local index, occurrences = 1, 0
  local queue_changed = not equal(row.queue, native.queue)
  local worker_queued = row.queued_saved[WORKER] ~= nil
  for _, name in ipairs(row.queue) do
    local technology = force.technologies[name]
    local parked = row.queued_saved[name]
    require_frame(technology and M.valid_progress(parked), "prepared queued technology is unavailable on " .. force.name)
    if name == native.queue[index] then index = index + 1 end
    if name == WORKER then occurrences = occurrences + 1 end
    local active = name == row.queue[1] and row.current_progress or parked
    local native_parked = technology.saved_progress
    require_frame(native_parked == 0 or native_parked == parked or native_parked == active,
      "surviving queued research changed on " .. force.name)
    if native.current == name then
      require_frame(native.current_progress == 0 or native.current_progress == active,
        "surviving active research changed on " .. force.name)
    end
    if name ~= WORKER and (parked > 0 or active > 0) and worker_queued then
      local paid = row.paid[name]
      require_frame(type(paid) == "table" and paid.level == technology.level
        and equal(paid.terms, work_terms(technology)), "queued research price changed on " .. force.name .. ": " .. name)
    end
  end
  require_frame(index == #native.queue + 1, "surviving queue order changed on " .. force.name)
  if occurrences == 0 then
    require_frame(not queue_changed and native.current_progress == row.current_progress
      and equal(native.queued_saved, row.queued_saved), "unrelated native research changed on " .. force.name)
  end
  if saved.formula ~= nil then return native end
  local restored = {}
  for key, value in pairs(native) do restored[key] = value end
  restored.saved_progress, restored.occurrences = row.saved_progress, occurrences
  restored.queue, restored.queued_saved = row.queue, row.queued_saved
  restored.current, restored.current_progress = row.queue[1], row.current_progress
  restored.allowance = math.max(occurrences, row.saved_progress > 0 and 1 or 0)
  return restored
end

function M.restore_addon_change_frame(saved, force, native, holder, equal, planned_bonus)
  local row = saved.forces[force.index]
  require_frame(type(row) == "table" and row.name == force.name and not native.researched
    and row.level == native.next_level and row.bonus == observed_bonus(saved, force, planned_bonus),
    "the prepared worker force, level or cargo changed on " .. force.name)
  require_frame(type(row.terms) == "table" and type(row.terms[1]) == "number"
    and row.terms[1] > 0 and row.terms[1] < math.huge and type(row.queue) == "table"
    and type(row.paid) == "table" and type(row.queued_saved) == "table"
    and type(row.enabled) == "boolean" and type(row.visible) == "boolean"
    and M.valid_progress(row.saved_progress) and M.valid_progress(row.current_progress),
    "the prepared worker work is invalid on " .. force.name)
  local terms = worker_terms(holder)
  local previous_count = row.terms[1]
  terms[1] = previous_count -- Read the level-specific count after native transfer.
  require_frame(equal(row.terms, terms), "the retained worker science or effect differs on " .. force.name)
  require_frame(equal(row.queue, native.queue) and native.current == row.queue[1],
    "the prepared worker queue changed on " .. force.name)
  local function same_paid(current, previous)
    return M.valid_progress(current) and M.valid_progress(previous)
      and math.abs(current * native.count - previous * previous_count) <= 1e-6
  end
  require_frame(native.saved_progress == row.saved_progress or same_paid(native.saved_progress, row.saved_progress),
    "the prepared parked worker work changed on " .. force.name)
  require_frame((native.current == ORDINARY and same_paid(native.current_progress, row.current_progress))
    or (native.current ~= ORDINARY and native.current_progress == row.current_progress),
    "the prepared active research changed on " .. force.name)
  for name, parked in pairs(native.queued_saved) do
    local before = row.queued_saved[name]
    require_frame(parked == before or name == ORDINARY and same_paid(parked, before),
      "prepared queue progress changed on " .. force.name)
    local paid = row.paid[name]
    if name ~= ORDINARY and (parked > 0 or native.current == name and native.current_progress > 0) then
      local technology = force.technologies[name]
      require_frame(type(paid) == "table" and technology and technology.level == paid.level
        and equal(paid.terms, work_terms(technology)),
        "prepared queued research terms changed on " .. force.name .. ": " .. name)
    end
  end
  local restored = {}
  for key, value in pairs(native) do restored[key] = value end
  restored.count, restored.saved_progress, restored.current_progress = previous_count, row.saved_progress, row.current_progress
  restored.queued_saved = row.queued_saved
  restored.enabled, restored.visible = row.enabled, row.visible
  restored.allowance = math.max(native.occurrences, row.saved_progress > 0 and 1 or 0)
  return restored
end

return M
