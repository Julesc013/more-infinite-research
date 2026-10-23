local KEY = "mir5_f200_legacy_worker"
local CASE = "f200-positive-legacy-worker"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-f200-legacy-worker"
local WORKER = "worker-robots-speed-6"
local PROBE = "braking-force-1"
local FOREIGN = "mir5-f200-legacy-worker-foreign"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "space-science-pack",
}
local UINT32_MAX = 4294967295
local MODIFIER = 0.65
local LAB_ENERGY = 100000000
local DESTINATION_PACKS = 8
local DEADLINE = 18000

local loaded_snapshot, reload_logged = nil, false

local function fail(message) error("[mir5-f200-legacy-worker-successor] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and type(expected) == "number"
    and math.abs(actual - expected) <= 0.000001
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. tostring(name)) end
  return value
end

local function status(force)
  local value = technology(force, WORKER)
  return {level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, maximum = value.prototype.max_level,
    bonus = force.worker_robots_speed_modifier, saved_progress = value.saved_progress}
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
    fail(label .. " native worker state differs")
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

local function assert_foreign(force, expected, baseline)
  if force == nil or force.valid == false or force.name ~= FOREIGN then fail("foreign force witness is absent") end
  assert_status(status(force), {level = 6, researched = false, enabled = false, visible = false,
    maximum = UINT32_MAX, bonus = baseline, saved_progress = 0}, "foreign native worker")
  local current = queue_snapshot(force)
  if current.current ~= PROBE or #current.queue ~= 1 or current.queue[1] ~= PROBE
      or not close(current.progress, 0.42) then fail("foreign worker queue or progress changed") end
  if type(expected) ~= "table" or expected.current ~= current.current or #expected.queue ~= #current.queue
      or expected.queue[1] ~= current.queue[1] or not close(expected.progress, current.progress) then
    fail("foreign native worker source queue witness differs")
  end
  return current
end

local function lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("source player native worker lab is absent") end
  value.energy = LAB_ENERGY
  if value.energy <= 0 then fail("source player native worker lab has no power") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("source player native worker lab inventory is absent") end
  return inventory
end

local function assert_native_owner(value)
  if value.name ~= WORKER or value.prototype.max_level ~= UINT32_MAX
      or value.prototype.visible_when_disabled ~= false
      or value.level < 8 or value.researched then
    fail("F200 native worker tail is absent or regressed")
  end
  local effects = value.prototype.effects
  if #effects ~= 1 or effects[1].type ~= "worker-robot-speed"
      or not close(effects[1].modifier, MODIFIER) then
    fail("F200 native worker effect differs")
  end
end

local function assert_acceleration(value)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not retain one-unit one-second native worker research")
  end
  for _, item in ipairs(SCIENCE) do
    local found = false
    for _, ingredient in ipairs(value.research_unit_ingredients) do
      if ingredient.name == item and ingredient.amount == 1 then found = true end
    end
    if not found then fail("native worker science is absent: " .. item) end
  end
end

local function assert_source_witness(state)
  if state.source_mir ~= "4.7.20002" or state.fixture_version ~= "0.1.0"
      or state.actual_lab_completions ~= 2 or state.milestone ~= "actual2labs"
      or type(state.foreign_queue) ~= "table" or type(state.player_with_independent) ~= "number"
      or type(state.foreign_baseline) ~= "number" then
    fail("published native-worker source witness is absent or malformed")
  end
end

local function assert_restored(state)
  assert_source_witness(state)
  local player = status(game.forces.player)
  -- The source controller captured the positive-cap presentation value after
  -- its data-stage patch. MIR5 restores that owned force presentation even
  -- though the successor prototype itself keeps the Base default.
  assert_status(player, {level = 8, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = state.player_with_independent + 2 * MODIFIER,
    saved_progress = 0.27}, "MIR5 restored native worker")
  assert_native_owner(technology(game.forces.player, WORKER))
  assert_acceleration(technology(game.forces.player, WORKER))
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue, state.foreign_baseline)
  return player
end

local function assert_completed(state)
  if state.destination_lab_completions ~= 1 then fail("successor did not finish exactly one further native worker lab level") end
  local player = status(game.forces.player)
  assert_status(player, {level = 9, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = state.player_with_independent + 3 * MODIFIER},
    "MIR5 post-lab native worker")
  if game.forces.player.current_research ~= nil or #game.forces.player.research_queue ~= 0 then
    fail("successor native worker research queue survived completion")
  end
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue, state.foreign_baseline)
  local inventory = lab(state)
  for _, item in ipairs(SCIENCE) do
    if inventory.get_item_count(item) ~= state.destination_inventory_before[item] - 1 then
      fail("successor real native worker lab consumption differs for " .. item)
    end
  end
  return player
end

local function marker(stage, state)
  local player = status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage, case = CASE, status = "passed",
    qualification = "native-runner-readback-required",
    witnesses = {
      source_mir = state.source_mir, destination_mir = script.active_mods["more-infinite-research"],
      source_actual_lab_completions = state.actual_lab_completions,
      destination_actual_lab_completions = state.destination_lab_completions,
      native_owner = WORKER, native_effect_modifier = MODIFIER,
      milestone = state.milestone, next_level = player.level,
      worker_speed_modifier = player.bonus, independent_modifier_baseline = state.player_with_independent,
      player_enabled = player.enabled, player_visible_when_disabled = player.visible,
      foreign_queue_progress = state.foreign_queue.progress, on_load_read_only = stage == "reload",
    },
  }))
end

script.on_configuration_changed(function()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "5.0.20000"
      or script.active_mods[FIXTURE] ~= "0.2.0" then
    fail("successor requires MIR 5.0.20000 and fixture 0.2.0 on Factorio 2.0.77")
  end
  if settings.startup["mir-max-level-worker-robots-speed"].value ~= 40
      or settings.startup["mir-settings-profile-import"].value ~= "" then
    fail("successor fixture settings are not the verified native-worker cap relaxation")
  end
  local state = storage[KEY]
  assert_restored(state) -- Required before this fixture queues any successor lab work.
  local inventory = lab(state)
  local before = {}
  for _, item in ipairs(SCIENCE) do
    before[item] = inventory.get_item_count(item)
    local inserted = inventory.insert{name = item, count = DESTINATION_PACKS}
    if inserted ~= DESTINATION_PACKS then fail("could not insert successor worker science " .. item) end
    before[item] = before[item] + inserted
  end
  state.destination_inventory_before = before
  state.destination_lab_completions = 0
  state.phase = "await-successor-lab"
  state.deadline_tick = game.tick + DEADLINE
  if game.forces.player.add_research(technology(game.forces.player, WORKER)) ~= true then
    fail("could not queue successor native worker research")
  end
  if #game.forces.player.research_queue ~= 1 then fail("successor native worker research was not queued singly") end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "await-successor-lab" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= WORKER then return end
  state.destination_lab_completions = state.destination_lab_completions + 1
  if state.destination_lab_completions ~= 1 then fail("successor completed duplicate native worker level") end
  state.phase = "await-successor-observation"
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "completed" then
    loaded_snapshot = {player = copy_status(state.successor_player), foreign = copy_queue(state.foreign_queue),
      source = state.actual_lab_completions, destination = state.destination_lab_completions,
      foreign_baseline = state.foreign_baseline}
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("successor native worker fixture storage is absent") end
  if state.phase == "completed" then
    if loaded_snapshot and not reload_logged then
      local player = assert_completed(state)
      assert_status(player, loaded_snapshot.player, "successor cold reload native worker")
      assert_foreign(game.forces[state.foreign_force_index], loaded_snapshot.foreign, loaded_snapshot.foreign_baseline)
      if state.actual_lab_completions ~= loaded_snapshot.source
          or state.destination_lab_completions ~= loaded_snapshot.destination then
        fail("cold reload changed recorded native worker lab completions")
      end
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("successor lab did not complete one native worker level") end
  lab(state)
  if state.phase == "await-successor-observation" then
    state.successor_player = copy_status(assert_completed(state))
    state.phase = "completed"
    marker("initial", state)
    game.server_save(SAVE)
  end
end)
