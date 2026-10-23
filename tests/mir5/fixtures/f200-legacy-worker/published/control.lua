local KEY = "mir5_f200_legacy_worker"
local CASE = "f200-positive-legacy-worker"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-f200-legacy-worker"
local WORKER = "worker-robots-speed-6"
local PROBE = "automation"
local FOREIGN = "mir5-f200-legacy-worker-foreign"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "space-science-pack",
}
local UINT32_MAX = 4294967295
local MODIFIER = 0.65
local INDEPENDENT_OFFSET = 0.123
local LAB_ENERGY = 100000000
local INITIAL_PACKS = 16
local DEADLINE = 18000

local loaded_snapshot, reload_logged = nil, false

local function fail(message) error("[mir5-f200-legacy-worker-source] " .. message) end
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
  return {
    level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, maximum = value.prototype.max_level,
    bonus = force.worker_robots_speed_modifier, saved_progress = value.saved_progress,
  }
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

local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
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
  local queue = queue_snapshot(force)
  if queue.current ~= PROBE or #queue.queue ~= 1 or queue.queue[1] ~= PROBE
      or not close(queue.progress, 0.42) then
    fail("foreign worker queue or progress changed")
  end
  if expected ~= nil and (expected.current ~= queue.current or #expected.queue ~= #queue.queue
      or expected.queue[1] ~= queue.queue[1] or not close(expected.progress, queue.progress)) then
    fail("foreign worker queue changed after fixture setup")
  end
  return queue
end

local function lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("real player worker lab is absent") end
  value.energy = LAB_ENERGY
  if value.energy <= 0 then fail("real player worker lab has no power") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real player worker lab input inventory is absent") end
  return inventory
end

local function fill(inventory)
  for _, item in ipairs(SCIENCE) do
    local inserted = inventory.insert{name = item, count = INITIAL_PACKS}
    if inserted ~= INITIAL_PACKS then fail("could not insert native worker science " .. item) end
  end
end

local function assert_native_owner(value)
  if value.name ~= WORKER or value.prototype.max_level ~= UINT32_MAX
      -- Published F200 applies its positive-cap presentation patch in data
      -- final fixes before this control-stage observer runs.
      or value.prototype.visible_when_disabled ~= true
      or value.level ~= 6 or value.researched then
    fail("F200 native worker tail identity or initial level differs")
  end
  local effects = value.prototype.effects
  if #effects ~= 1 or effects[1].type ~= "worker-robot-speed"
      or not close(effects[1].modifier, MODIFIER) then
    fail("F200 native worker effect differs")
  end
  if value.prerequisites["worker-robots-speed-5"] == nil
      or value.prerequisites["space-science-pack"] == nil then
    fail("F200 native worker prerequisites differ")
  end
end

local function assert_acceleration(value)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not reduce only the native worker unit count and time")
  end
  for _, item in ipairs(SCIENCE) do
    local found = false
    for _, ingredient in ipairs(value.research_unit_ingredients) do
      if ingredient.name == item and ingredient.amount == 1 then found = true end
    end
    if not found then fail("native worker science is absent: " .. item) end
  end
end

local function assert_source_start(state)
  local player = status(game.forces.player)
  if player.level ~= 6 or player.researched or not player.enabled or not player.visible
      or player.maximum ~= UINT32_MAX or not close(player.saved_progress, 0)
      or not close(player.bonus, state.player_with_independent) or state.published_initial_visible ~= true then
    fail("published cap controller did not expose the enabled native worker at on_init")
  end
  if state.actual_lab_completions ~= 0 then fail("source started with completed worker labs") end
end

local function assert_published_cap(state)
  if state.actual_lab_completions ~= 2 or state.milestone ~= "actual2labs" then
    fail("source did not retain exactly two real native worker completions")
  end
  local player = status(game.forces.player)
  assert_status(player, {level = 8, researched = false, enabled = false, visible = true,
    maximum = UINT32_MAX, bonus = state.player_with_independent + 2 * MODIFIER,
    saved_progress = 0.27}, "published positive-cap native worker")
  if game.forces.player.current_research ~= nil or #game.forces.player.research_queue ~= 0 then
    fail("capped player worker research survived")
  end
  local inventory = lab(state)
  for _, item in ipairs(SCIENCE) do
    if inventory.get_item_count(item) ~= INITIAL_PACKS - 2 then
      fail("real native worker lab consumption differs for " .. item)
    end
  end
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue, state.foreign_baseline)
  return player
end

local function marker(stage, state)
  local player = status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage, case = CASE, status = "passed",
    qualification = "native-runner-readback-required",
    witnesses = {
      source_mir = state.source_mir, source_policy_transport = "settings-derived-v3",
      source_ownership_kind = "settings-derived-v3", source_operation = "native-owner-cap",
      native_owner = WORKER, native_effect_modifier = MODIFIER,
      actual_lab_completions = state.actual_lab_completions,
      milestone = state.milestone, seededpartial = "after-actual2labs",
      next_level = player.level, worker_speed_modifier = player.bonus,
      independent_modifier_baseline = state.player_with_independent,
      published_controller_initial_visible_when_disabled = state.published_initial_visible,
      player_enabled = player.enabled, player_visible_when_disabled = player.visible,
      saved_progress = player.saved_progress, foreign_queue_progress = state.foreign_queue.progress,
      foreign_disabled = status(game.forces[state.foreign_force_index]).enabled == false,
      on_load_read_only = stage == "reload",
    },
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "4.7.20002"
      or script.active_mods[FIXTURE] ~= "0.1.0" then
    fail("source requires published MIR 4.7.20002 and fixture 0.1.0 on Factorio 2.0.77")
  end
  if storage[KEY] ~= nil then fail("source fixture storage already exists") end
  if settings.startup["mir-max-level-worker-robots-speed"].value ~= 7
      or settings.startup["mir-settings-profile-import"].value ~= "" then
    fail("source fixture settings are not the verified positive native-worker cap")
  end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  local native = technology(player, WORKER)
  assert_native_owner(native)
  assert_acceleration(native)
  prerequisites(native)
  local player_baseline = player.worker_robots_speed_modifier
  player.worker_robots_speed_modifier = player_baseline + INDEPENDENT_OFFSET
  local player_with_independent = player.worker_robots_speed_modifier
  local published_initial_visible = native.visible_when_disabled

  local foreign = game.create_force(FOREIGN)
  foreign.enable_all_prototypes()
  local foreign_native = technology(foreign, WORKER)
  assert_native_owner(foreign_native)
  prerequisites(foreign_native)
  local foreign_baseline = foreign.worker_robots_speed_modifier
  foreign_native.enabled = false
  foreign_native.visible_when_disabled = false
  local probe = technology(foreign, PROBE)
  prerequisites(probe)
  if foreign.add_research(probe) ~= true then fail("could not queue foreign worker probe") end
  foreign.research_progress = 0.42
  local foreign_queue = assert_foreign(foreign, nil, foreign_baseline)

  local player_lab = game.surfaces[1].create_entity{name = "lab", position = {0, 0}, force = player}
  if player_lab == nil or player_lab.valid == false then fail("could not create real native worker lab") end
  local state = {
    phase = "await-first-lab", source_mir = script.active_mods["more-infinite-research"],
    fixture_version = script.active_mods[FIXTURE], actual_lab_completions = 0,
    milestone = "unstarted", foreign_force_index = foreign.index, foreign_queue = foreign_queue,
    foreign_baseline = foreign_baseline, player_baseline = player_baseline,
    published_initial_visible = published_initial_visible,
    player_with_independent = player_with_independent, lab = player_lab,
    deadline_tick = game.tick + DEADLINE,
  }
  storage[KEY] = state
  -- Published F200 cap control owns this immediate visibility presentation; the
  -- immutable native prototype remains data-default false and this fixture never writes player presentation.
  assert_source_start(state)
  fill(lab(state))
  if player.add_research(native) ~= true then fail("could not queue first native worker research") end
  if player.current_research == nil or player.current_research.name ~= WORKER
      or #player.research_queue ~= 1 then
    fail("first player research was not a single native worker queue entry")
  end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player
      or event.research.name ~= WORKER then return end
  if state.phase ~= "await-first-lab" and state.phase ~= "await-second-lab" then
    fail("unexpected native worker completion phase")
  end
  state.actual_lab_completions = state.actual_lab_completions + 1
  if state.actual_lab_completions == 1 then
    state.phase = "await-second-queue"
  elseif state.actual_lab_completions == 2 then
    state.phase = "await-published-cap"
  else
    fail("source lab completed more than two native worker levels")
  end
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "completed" then
    loaded_snapshot = {player = copy_status(state.player_cap), queue = copy_queue(state.foreign_queue),
      actual_lab_completions = state.actual_lab_completions, foreign_baseline = state.foreign_baseline}
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("source native worker fixture storage is absent") end
  if state.phase == "completed" then
    if loaded_snapshot and not reload_logged then
      local now = assert_published_cap(state)
      assert_status(now, loaded_snapshot.player, "source cold reload native worker")
      assert_foreign(game.forces[state.foreign_force_index], loaded_snapshot.queue, loaded_snapshot.foreign_baseline)
      if loaded_snapshot.actual_lab_completions ~= state.actual_lab_completions then
        fail("source cold load changed native worker lab count")
      end
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("source lab did not complete two native worker levels") end
  lab(state)
  if state.phase == "await-second-queue" then
    local player = game.forces.player
    if player.current_research == nil and #player.research_queue == 0 then
      if player.add_research(technology(player, WORKER)) ~= true then
        fail("could not queue second native worker research")
      end
      if #player.research_queue ~= 1 then fail("second player native worker research was not queued singly") end
      state.phase = "await-second-lab"
    end
    return
  end
  if state.phase == "await-published-cap" then
    local player = status(game.forces.player)
    if player.level ~= 8 or player.researched or player.enabled or not player.visible
        or player.maximum ~= UINT32_MAX or not close(player.bonus, state.player_with_independent + 2 * MODIFIER)
        or not close(player.saved_progress, 0) then
      fail("published native worker cap was not earned before partial seed")
    end
    technology(game.forces.player, WORKER).saved_progress = 0.27
    state.milestone = "actual2labs"
    state.phase = "completed"
    state.player_cap = copy_status(assert_published_cap(state))
    marker("actual2labs", state)
    game.server_save(SAVE)
  end
end)
