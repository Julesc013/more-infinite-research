local TARGETS = {
  f200 = {
    case = "legacy-boolean-cap-current-f200", base = "2.0.77", mir = "5.0.20000", fixture = "0.2.0",
    prefix = "mir5-legacy-boolean-cap-f200", restored_label = "F200 restored player",
    completed_label = "F200 post-lab player",
  },
  f210 = {
    case = "legacy-boolean-cap-current-f210", base = "2.1.23", mir = "5.0.21000", fixture = "0.3.0",
    prefix = "mir5-legacy-boolean-cap-f210", restored_label = "F210 direct restored player",
    completed_label = "F210 direct post-lab player", reject_space_age = true,
  },
}

local function apply(target_name)
  local target = TARGETS[target_name]
  if target == nil then error("[mir5-legacy-boolean-cap] unknown successor target: " .. tostring(target_name)) end

local KEY = "mir5_legacy_boolean_cap"
local CASE = target.case
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-legacy-boolean-cap"
local GEAR = "recipe-prod-research_gears-1"
local RECIPE = "iron-gear-wheel"
local PROBE = "braking-force-1"
local FOREIGN = "mir5-legacy-boolean-cap-foreign"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack",
}
local UINT32_MAX = 4294967295
local DESTINATION_PACKS = 8
local LAB_ENERGY = 100000000
local DEADLINE = 18000

local loaded, reload_logged = nil, false

local function fail(message) error("[" .. target.prefix .. "] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. tostring(name)) end
  return value
end

local function status(force)
  local value = technology(force, GEAR)
  local recipe = force.recipes[RECIPE]
  if recipe == nil then fail("gear recipe is absent") end
  return {level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, maximum = value.prototype.max_level,
    bonus = recipe.productivity_bonus, saved_progress = value.saved_progress}
end

local function copy_status(value)
  return {level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible, maximum = value.maximum, bonus = value.bonus,
    saved_progress = value.saved_progress}
end

local function assert_status(actual, expected, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.enabled ~= expected.enabled or actual.visible ~= expected.visible
      or actual.maximum ~= expected.maximum or not close(actual.bonus, expected.bonus) then
    fail(label .. " native gear state differs")
  end
  if expected.saved_progress ~= nil and not close(actual.saved_progress, expected.saved_progress) then
    fail(label .. " saved progress differs")
  end
end

local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current = force.current_research and force.current_research.name or false,
    queue = queue, progress = force.research_progress}
end

local function copy_queue(value)
  local queue = {}
  for index, name in ipairs(value.queue or {}) do queue[index] = name end
  return {current = value.current, queue = queue, progress = value.progress}
end

local function read_lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("source player lab is absent") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("source player lab inventory is absent") end
  return value, inventory
end

local function recharge_lab(state)
  local value, inventory = read_lab(state)
  value.energy = LAB_ENERGY
  if value.energy <= 0 then fail("source player lab has no power") end
  return inventory
end

local function freeze_lab(state)
  local value = read_lab(state)
  value.energy = 0
  if value.energy ~= 0 then fail("source player lab did not freeze after completion") end
end

local function assert_acceleration(value)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not retain one-unit one-second native research")
  end
end

local function assert_foreign(force, expected)
  if force == nil or force.valid == false or force.name ~= FOREIGN then fail("foreign witness is absent") end
  assert_status(status(force), {level = 1, researched = false, enabled = false, visible = false,
    maximum = UINT32_MAX, bonus = 0}, "foreign gear")
  local actual = queue_snapshot(force)
  if actual.current ~= PROBE or #actual.queue ~= 1 or actual.queue[1] ~= PROBE
      or not close(actual.progress, .42) then fail("foreign queue or progress differs") end
  if type(expected) ~= "table" or expected.current ~= actual.current or #expected.queue ~= #actual.queue
      or expected.queue[1] ~= actual.queue[1] or not close(expected.progress, actual.progress) then
    fail("foreign source queue witness differs")
  end
  return actual
end

local function assert_source(state)
  if state.source_mir ~= "4.0.20000" or state.actual_lab_completions ~= 2
      or state.milestone ~= "actual2labs" or type(state.player_cap) ~= "table"
      or type(state.foreign_queue) ~= "table" then
    fail("published policy-v1 source witness is absent or malformed")
  end
  local player = status(game.forces.player)
  assert_status(player, {level = 3, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = .20, saved_progress = .27}, target.restored_label)
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue)
  assert_acceleration(technology(game.forces.player, GEAR))
  return player
end

local function assert_completed(state)
  if state.destination_lab_completions ~= 1 then fail("successor did not finish exactly one further lab level") end
  assert_status(status(game.forces.player), {level = 4, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = .30}, target.completed_label)
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue)
  local _, inventory = read_lab(state)
  for _, name in ipairs(SCIENCE) do
    if inventory.get_item_count(name) ~= state.destination_science_before[name] - 1 then
      fail("successor real lab consumption differs for " .. name)
    end
  end
end

local function marker(stage, state)
  local player = status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage, case = CASE, status = "passed", qualification = "native-runner-readback-required",
    witnesses = {source_mir = state.source_mir, destination_mir = script.active_mods["more-infinite-research"],
      source_actual_lab_completions = state.actual_lab_completions,
      destination_actual_lab_completions = state.destination_lab_completions, player_level = player.level,
      player_enabled = player.enabled, player_visible_when_disabled = player.visible,
      productivity_bonus = player.bonus, foreign_disabled = status(game.forces[state.foreign_force_index]).enabled == false,
      foreign_queue_progress = state.foreign_queue.progress, on_load_read_only = stage == "reload"},
  }))
end

script.on_configuration_changed(function()
  if script.active_mods.base ~= target.base or script.active_mods["more-infinite-research"] ~= target.mir
      or script.active_mods[FIXTURE] ~= target.fixture then fail("successor closure differs") end
  if target.reject_space_age and (script.active_mods["space-age"] ~= nil or script.active_mods["elevated-rails"] ~= nil
      or script.active_mods.quality ~= nil or script.active_mods.recycler ~= nil) then
    fail("direct successor carries Space Age companions")
  end
  if settings.startup["ips-max-level-research_gears"].value ~= 0
      or settings.startup["ips-effect-per-level-research_gears"].value ~= 10 then
    fail("successor fixture settings differ")
  end
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "completed" then fail("protected source state is absent") end
  assert_source(state)
  if state.destination_started then fail("successor initialization repeated") end
  local inventory = recharge_lab(state)
  state.destination_science_before = {}
  for _, name in ipairs(SCIENCE) do
    if inventory.insert{name = name, count = DESTINATION_PACKS} ~= DESTINATION_PACKS then
      fail("could not insert successor science " .. name)
    end
    state.destination_science_before[name] = inventory.get_item_count(name)
  end
  local player, gear = game.forces.player, technology(game.forces.player, GEAR)
  if player.add_research(gear) ~= true or player.current_research ~= gear
      or not close(player.research_progress, .27) then
    fail("restored source investment did not become successor research")
  end
  state.destination_started, state.destination_lab_completions = true, 0
  state.phase, state.deadline_tick = "await-successor-lab", game.tick + DEADLINE
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "await-successor-lab" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= GEAR then return end
  state.destination_lab_completions = state.destination_lab_completions + 1
  if state.destination_lab_completions ~= 1 then fail("successor completed duplicate gear level") end
  freeze_lab(state)
  state.phase = "await-successor-observation"
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "completed" and type(state.successor_player) == "table"
    and {player = copy_status(state.successor_player), foreign = copy_queue(state.foreign_queue)} or nil
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("successor fixture storage is absent") end
  if state.phase == "completed" then
    if loaded and not reload_logged then
      assert_completed(state)
      assert_status(status(game.forces.player), loaded.player, "successor cold reload player")
      assert_foreign(game.forces[state.foreign_force_index], loaded.foreign)
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("successor lab did not complete") end
  if state.phase == "await-successor-lab" then
    recharge_lab(state)
  elseif state.phase == "await-successor-observation" then
    assert_completed(state)
    state.successor_player = copy_status(status(game.forces.player))
    state.phase = "completed"
    marker("initial", state)
    game.server_save(SAVE)
  else
    fail("successor fixture phase is invalid")
  end
end)

end

return {apply = apply}
