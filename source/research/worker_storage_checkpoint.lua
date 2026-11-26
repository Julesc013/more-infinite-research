-- Factorio 1.1 can discard current worker research when it converts a save to 2.0.
-- Record its native terms and queue while the source copy is still paused in 1.1.
local M = {key="mir_worker_storage_engine_checkpoint", source_base="1.1.110"}
local MIR, WORKER = "more-infinite-research", "worker-robots-storage-4"

local function require_frame(condition, reason)
  if not condition then error("MIR worker engine upgrade: " .. reason .. ". Keep the original save.", 0) end
end

function M.source_version(version)
  return type(version) == "string" and version:match("^5%.0%.110%d%d$") ~= nil
end

local function progress(value)
  return type(value) == "number" and value >= 0 and value < 1
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

function M.capture(read_saved_progress)
  local saved = {schema=1, tick=game.tick, was_paused=game.tick_paused, mir=script.active_mods[MIR], forces={}}
  for _, force in pairs(game.forces) do
    local worker = force.technologies[WORKER]
    local terms = worker_terms(worker)
    local queue, parked, paid = {}, {}, {}
    local current = force.current_research
    local fraction = force.research_progress
    for index, technology in ipairs(force.research_queue or {}) do
      local name = technology.name
      require_frame(index <= 1000, "native queue exceeds its supported length")
      local prior = read_saved_progress(force, technology) or 0
      require_frame(progress(prior), "invalid native queued progress")
      queue[index], parked[name] = name, prior
      if name ~= WORKER and (prior > 0 or current and current.name == name and fraction > 0) then
        paid[name] = {level=technology.level, terms=work_terms(technology)}
      end
    end
    local worker_progress = read_saved_progress(force, worker) or 0
    require_frame(queue[1] == (current and current.name) and progress(fraction) and progress(worker_progress),
      "current native research or progress differs from the queue")
    saved.forces[force.index] = {name=force.name, bonus=force.worker_robots_storage_bonus,
      level=worker.level, terms=terms, saved_progress=worker_progress,
      queue=queue, queued_saved=parked, current_progress=fraction, paid=paid}
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
  commands.add_command("mir-worker-storage-recovery", "Use prepare before upgrading this save to Factorio 2.0, or cancel.", function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if command.player_index and not (player and player.admin) then return end
    local function say(message)
      if player then player.print(message) else log("[MIR worker recovery] " .. message) end
    end
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
      say("Use /mir-worker-storage-recovery prepare or /mir-worker-storage-recovery cancel.")
    end
  end)
end

function M.claim(saved, event, target)
  require_frame(type(saved) == "table", "invalid preparation")
  local active = script.active_mods
  local changes = type(event) == "table" and event.mod_changes
  local base = type(changes) == "table" and changes.base
  local mir = type(changes) == "table" and changes[MIR]
  require_frame(target.id == "f200" and type(base) == "table" and base.old_version == M.source_base
    and base.new_version == active.base and active.base == target.minimum_base
    and type(mir) == "table" and mir.old_version == saved.mir and mir.new_version == active[MIR]
    and active[MIR] == target.distribution_version and M.source_version(saved.mir),
    "open the prepared copy with its matching Factorio 2.0 edition")
  require_frame(saved.schema == 1 and type(saved.tick) == "number" and game.tick >= saved.tick
    and game.tick - saved.tick <= 1 and type(saved.was_paused) == "boolean"
    and type(saved.forces) == "table", "the preparation expired")
end

-- Only zero or absent work may be supplied by the paused source. Any surviving
-- nonzero progress, force state or queue order has to corroborate that source.
function M.restore_frame(saved, force, native, equal)
  local row = saved.forces[force.index]
  require_frame(type(row) == "table" and row.name == force.name
    and row.bonus == force.worker_robots_storage_bonus and row.level == native.next_level
    and not native.researched and equal(row.terms, worker_terms(native.technology)),
    "worker level, cargo or science changed on " .. force.name)
  require_frame(type(row.queue) == "table" and type(row.queued_saved) == "table"
    and type(row.paid) == "table" and #row.queue <= 1000
    and progress(row.current_progress) and progress(row.saved_progress),
    "invalid prepared queue or progress on " .. force.name)
  require_frame(native.saved_progress == 0 or native.saved_progress == row.saved_progress,
    "surviving worker progress changed on " .. force.name)
  local index, occurrences = 1, 0
  local queue_changed = not equal(row.queue, native.queue)
  local worker_queued = row.queued_saved[WORKER] ~= nil
  for _, name in ipairs(row.queue) do
    local technology = force.technologies[name]
    local parked = row.queued_saved[name]
    require_frame(technology and progress(parked), "prepared queued technology is unavailable on " .. force.name)
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
  local restored = {}
  for key, value in pairs(native) do restored[key] = value end
  restored.saved_progress, restored.occurrences = row.saved_progress, occurrences
  restored.queue, restored.queued_saved = row.queue, row.queued_saved
  restored.current, restored.current_progress = row.queue[1], row.current_progress
  restored.allowance = math.max(occurrences, row.saved_progress > 0 and 1 or 0)
  return restored
end

return M
