-- Same-ID successor to the R05 actor. Read its saved state without advancing it.
local FIXTURE = "mir-fixture-mir5-worker-storage-published517-earned-source"
local KEY = "mir5_worker_storage_published517_earned_source"
local MIR = "more-infinite-research"
local HOLDER = "mir-worker-storage-published517-4"
local ORDINARY = "mir-worker-storage-default-4"
local TAIL = "mir-fixture-published517-earned-source-tail"
local SAVE = "mir5-published517-paid-successor"

local cold_pending = false
local function check(condition, message)
  assert(condition, "[MIR_PUBLISHED517_SUCCESSOR] " .. message)
end

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function name_of(row)
  check(row and row.valid == true and type(row.name) == "string" and row.name ~= "", "invalid native object")
  return row.name
end

local function technology(force, name)
  local row = force.technologies[name]
  check(name_of(row) == name, "incorrect technology: " .. name)
  local level, researched, enabled, visible = row.level, row.researched, row.enabled, row.visible_when_disabled
  local saved_progress, count, time = row.saved_progress, row.research_unit_count, row.research_unit_energy
  check(finite(level) and type(researched) == "boolean" and type(enabled) == "boolean"
    and type(visible) == "boolean", "invalid technology state: " .. name)
  check(saved_progress == nil or finite(saved_progress), "invalid saved progress: " .. name)
  check(finite(count) and finite(time), "invalid research unit: " .. name)
  local science, ingredient_count = {}, 0
  local ingredients = row.research_unit_ingredients
  check(type(ingredients) == "table", "research ingredients unavailable: " .. name)
  for _, ingredient in pairs(ingredients) do
    ingredient_count = ingredient_count + 1
    check(ingredient_count <= 32 and type(ingredient.name) == "string" and finite(ingredient.amount)
      and science[ingredient.name] == nil, "invalid research ingredient: " .. name)
    science[ingredient.name] = ingredient.amount
  end
  return {name = name, level = level, researched = researched, enabled = enabled, visible = visible,
    saved_progress = saved_progress or false, science = science, count = count, time = time}
end

local function queue_names(force)
  local queue = force.research_queue
  check(queue ~= nil and #queue <= 8, "research queue unavailable or out of bounds")
  local names, count = {}, 0
  for index, row in pairs(queue) do
    check(type(index) == "number" and index >= 1 and index <= #queue and index % 1 == 0,
      "invalid research queue index")
    names[index] = name_of(row)
    count = count + 1
  end
  check(count == #queue, "research queue length differs")
  return names
end

local function force_vectors()
  local rows, seen = {}, {}
  for _, force in pairs(game.forces) do
    local name, index = name_of(force), force.index
    check(finite(index) and index >= 1 and index % 1 == 0, "invalid force index")
    if not seen[index] then
      check(#rows < 32, "force vector count out of bounds")
      local values = {
        force.worker_robots_storage_bonus,
        force.worker_robots_speed_modifier,
        force.artillery_range_modifier,
        force.get_gun_speed_modifier("artillery-shell"),
        force.get_gun_speed_modifier("laser"),
        force.get_ammo_damage_modifier("laser")
      }
      for slot = 1, 6 do check(finite(values[slot]), "invalid force vector: " .. name) end
      rows[#rows + 1] = {index = index, name = name, values = values}
      seen[index] = true
    end
  end
  check(#rows > 0, "force vectors unavailable")
  table.sort(rows, function(left, right) return left.index < right.index end)
  return rows
end

local function frame()
  check(script.active_mods[FIXTURE] == "0.1.0" and script.active_mods[MIR] == "5.0.20018", "unexpected mod versions")
  local state = storage[KEY]
  check(type(state) == "table" and state.phase == "source-partial", "saved source phase differs")
  local force, lab = state.research_force, state.lab
  check(name_of(force) == state.research_force_name and force.index == state.research_force_index
    and game.forces[force.index] == force, "saved research force differs")
  check(name_of(lab) == "se-space-science-lab" and lab.force == force, "saved laboratory differs")
  local current, progress, lab_disabled = force.current_research, force.research_progress, lab.disabled_by_script
  check(finite(progress) and type(lab_disabled) == "boolean", "invalid research progress or lab disablement")
  return {
    force_index = force.index, force_name = force.name,
    current = current and name_of(current) or false, progress = progress,
    queue = queue_names(force), vectors = force_vectors(), lab_disabled = lab_disabled,
    holder = technology(force, HOLDER), ordinary = technology(force, ORDINARY), tail = technology(force, TAIL)
  }
end

local function observe(phase, event)
  local changes, startup_changed = false, false
  if event then
    startup_changed = event.mod_startup_settings_changed
    check(type(event.mod_changes) == "table" and type(startup_changed) == "boolean", "invalid configuration event")
    changes = {}
    local count = 0
    for name, change in pairs(event.mod_changes) do
      count = count + 1
      check(count <= 32 and type(name) == "string" and type(change) == "table", "invalid mod transition")
      local old, new = change.old_version, change.new_version
      check((old == nil or type(old) == "string") and (new == nil or type(new) == "string"), "invalid mod version")
      changes[name] = {old_version = old or false, new_version = new or false}
    end
  end
  log("[MIR_PUBLISHED517_SUCCESSOR] " .. helpers.table_to_json({phase = phase, tick = game.tick,
    frame = frame(), mod_changes = changes, mod_startup_settings_changed = startup_changed,
    laboratory_speed = storage[KEY].research_force.laboratory_speed_modifier}))
end

-- Use the existing isolated fixture lab and the existing native queue.
local PACKS = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack"
}
local completion

local function science_units(input)
  local totals = {}
  for _, name in ipairs(PACKS) do totals[name] = 0 end
  for index = 1, #input do
    local stack = input[index]
    if stack.valid_for_read and totals[stack.name] ~= nil then
      local maximum = prototypes.item[stack.name].get_durability(stack.quality)
      local durability = stack.durability
      check(stack.quality.name == "normal" and stack.is_tool and maximum == 1
        and finite(durability) and durability > 0 and durability <= maximum, "paid science stack differs")
      totals[stack.name] = totals[stack.name] + stack.count - 1 + durability / maximum
    end
  end
  return totals
end

local function feed_paid(actor)
  for _, name in ipairs(PACKS) do
    local present = actor.input.get_item_count(name)
    if present < 32 then
      local count = 200 - present
      check(actor.input.insert{name = name, count = count} == count, "could not feed paid science: " .. name)
      actor.issued[name] = actor.issued[name] + count
    end
  end
end

local function observe_paid(phase, actor, event)
  local remaining = science_units(actor.input)
  local debit = {}
  for _, name in ipairs(PACKS) do
    debit[name] = actor.initial[name] + actor.issued[name] - remaining[name]
  end
  log("[MIR_PUBLISHED517_SUCCESSOR] " .. helpers.table_to_json({
    phase = phase, tick = game.tick, frame = frame(), finished = actor.finished,
    research = event and event.research.name or false, by_script = event and event.by_script == true or false,
    laboratory_speed = actor.force.laboratory_speed_modifier, science_debit = debit,
    next_level_refused = actor.next_level_refused or false
  }))
end

local function begin_paid()
  check(completion == nil and not cold_pending, "paid test load is not ready")
  local before = frame()
  check(before.lab_disabled and before.current == HOLDER and before.holder.level == 9
    and before.progress > 0 and before.progress < 1 and #before.queue == 3
    and before.queue[1] == HOLDER and before.queue[2] == HOLDER and before.queue[3] == TAIL,
    "protected paid starting frame differs")
  for _, name in ipairs(PACKS) do
    check(before.holder.science[name] == 1, "historical science differs: " .. name)
  end
  local state = storage[KEY]
  local lab, force = state.lab, state.research_force
  local input = lab.get_inventory(defines.inventory.lab_input)
  check(input and input.valid and lab.is_connected_to_electric_network(), "paid native lab supply is unavailable")
  local speed = force.laboratory_speed_modifier
  check(finite(speed) and speed == state.speed_before, "saved laboratory speed differs")
  completion = {lab = lab, force = force, input = input, started = game.tick, speed = speed,
    initial = science_units(input), issued = {}, finished = 0}
  for _, name in ipairs(PACKS) do completion.issued[name] = 0 end
  observe_paid("paid-begin", completion)
  -- Same laboratory speed stimulus as the original earned-source fixture.
  force.laboratory_speed_modifier = speed + 115199
  feed_paid(completion)
  lab.disabled_by_script = false
end

script.on_event(defines.events.on_research_finished, function(event)
  local actor = completion
  if actor == nil or event.research.force ~= actor.force then return end
  check(event.research.name == HOLDER and event.by_script == false and actor.finished < 2
    and (actor.finished == 0 or actor.second_observed),
    "unexpected research completion on the paid force")
  actor.finished = actor.finished + 1
  if actor.finished == 2 then
    actor.lab.disabled_by_script = true
    actor.force.laboratory_speed_modifier = actor.speed
  end
  observe_paid("holder-completed", actor, event)
end)

local function advance_paid()
  local actor = completion
  if actor == nil then return end
  check(game.tick - actor.started <= 2700, "native holder did not complete and settle within 2700 updates")
  if actor.finished < 2 then
    if actor.finished == 1 and not actor.second_observed then
      local second = frame()
      if second.current == HOLDER and second.holder.level == 10 and not second.holder.researched
        and #second.queue == 2 and second.queue[1] == HOLDER and second.queue[2] == TAIL then
        actor.second_observed = true
        observe_paid("second-holder-started", actor)
      end
    end
    feed_paid(actor)
    return
  end
  local settled = frame()
  if settled.ordinary.level ~= 11 or settled.current ~= TAIL then return end
  check(settled.lab_disabled and settled.holder.level == 4 and not settled.holder.enabled
    and not settled.holder.visible and not settled.ordinary.enabled and settled.progress == 0
    and #settled.queue == 1 and settled.queue[1] == TAIL and not settled.tail.researched,
    "settled cap or unrelated tail differs")
  check(actor.force.add_research(actor.force.technologies[ORDINARY]) == false, "cap allowed ordinary level 11 to start")
  local after_refusal = frame()
  check(after_refusal.current == TAIL and after_refusal.progress == 0
    and #after_refusal.queue == 1 and after_refusal.queue[1] == TAIL, "cap refusal changed the unrelated tail")
  actor.next_level_refused = true
  observe_paid("paid-completion-save", actor)
  game.server_save("mir5-published517-paid-completion")
  completion = nil
end


script.on_load(function()
  cold_pending = true
end)

-- The fixture depends on MIR, so its callback runs after MIR's callback.
script.on_configuration_changed(function(event)
  cold_pending = false
  observe("configuration", event)
end)

script.on_event(defines.events.on_tick, function()
  if cold_pending then
    cold_pending = false
    observe("cold-read")
  end
  advance_paid()
end)

remote.add_interface(FIXTURE, {complete_paid = begin_paid})
