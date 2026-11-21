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
    frame = frame(), mod_changes = changes, mod_startup_settings_changed = startup_changed}))
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
end)

remote.add_interface(FIXTURE, {save_successor = function()
  observe("successor-save")
  game.server_save(SAVE)
end})
