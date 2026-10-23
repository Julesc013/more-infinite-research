local KEY = "mir5_f200_legacy_cap"
local CASE = "f200-positive-legacy-cap"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-f200-legacy-cap"
local GEAR = "recipe-prod-research_gears-1"
local RECIPE = "iron-gear-wheel"
local PROBE = "braking-force-1"
local FOREIGN = "mir5-f200-legacy-cap-foreign"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack",
}
local UINT32_MAX = 4294967295
local LAB_ENERGY = 100000000
local INITIAL_PACKS = 16
local DEADLINE = 18000

local loaded_snapshot, reload_logged = nil, false

local function fail(message) error("[mir5-f200-legacy-cap-source] " .. message) end
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
  if recipe == nil then fail("gear recipe is absent for " .. tostring(force.name)) end
  return {
    level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, maximum = value.prototype.max_level,
    bonus = recipe.productivity_bonus, saved_progress = value.saved_progress,
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
    fail(label .. " native gear state differs")
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
  return {
    current = force.current_research and force.current_research.name or false,
    queue = queue, progress = force.research_progress,
  }
end

local function copy_queue(value)
  local queue = {}
  for index, name in ipairs(value.queue or {}) do queue[index] = name end
  return {current = value.current, queue = queue, progress = value.progress}
end

local function assert_foreign(force, expected)
  local current = status(force)
  assert_status(current, {level = 1, researched = false, enabled = false, visible = false,
    maximum = UINT32_MAX, bonus = 0}, "foreign gear")
  local queue = queue_snapshot(force)
  if queue.current ~= PROBE or #queue.queue ~= 1 or queue.queue[1] ~= PROBE
      or not close(queue.progress, 0.42) then
    fail("foreign probe queue or progress differs")
  end
  if expected ~= nil and (expected.current ~= queue.current or #expected.queue ~= #queue.queue
      or expected.queue[1] ~= queue.queue[1] or not close(expected.progress, queue.progress)) then
    fail("foreign queue changed after fixture setup")
  end
  return queue
end

local function lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("real player lab is absent") end
  value.energy = LAB_ENERGY
  if value.energy <= 0 then fail("real player lab has no power") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real player lab input inventory is absent") end
  return inventory
end

local function fill(inventory)
  for _, item in ipairs(SCIENCE) do
    local inserted = inventory.insert{name = item, count = INITIAL_PACKS}
    if inserted ~= INITIAL_PACKS then fail("could not insert native science " .. item) end
  end
end

local function assert_acceleration(value)
  -- Pinned F200 exposes research energy in ticks: unit.time=1 means 60.
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not reduce only the native gear unit count and time")
  end
  for _, item in ipairs(SCIENCE) do
    local found = false
    for _, ingredient in ipairs(value.research_unit_ingredients) do
      if ingredient.name == item and ingredient.amount == 1 then found = true end
    end
    if not found then fail("native gear science is absent: " .. item) end
  end
end

local function assert_source_start(state)
  local player = status(game.forces.player)
  assert_status(player, {level = 1, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = 0, saved_progress = 0}, "published pre-lab player")
  if state.actual_lab_completions ~= 0 then fail("source started with completed labs") end
end

local function assert_published_cap(state)
  if state.actual_lab_completions ~= 2 or state.milestone ~= "actual2labs" then
    fail("source did not retain exactly two real gear completions")
  end
  local player = status(game.forces.player)
  assert_status(player, {level = 3, researched = false, enabled = false, visible = true,
    maximum = UINT32_MAX, bonus = 0.02, saved_progress = 0.27}, "published positive-cap player")
  if game.forces.player.current_research ~= nil then fail("capped player research survived") end
  for _, queued in ipairs(game.forces.player.research_queue or {}) do
    if queued.name == GEAR then fail("capped player gear queue survived") end
  end
  local inventory = lab(state)
  for _, item in ipairs(SCIENCE) do
    if inventory.get_item_count(item) ~= INITIAL_PACKS - 2 then
      fail("real lab consumption differs for " .. item)
    end
  end
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue)
  return player
end

local function marker(stage, state)
  local player = status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage, case = CASE, status = "passed",
    qualification = "native-runner-readback-required",
    witnesses = {
      source_mir = state.source_mir, actual_lab_completions = state.actual_lab_completions,
      milestone = state.milestone, seededpartial = "after-actual2labs",
      next_level = player.level, productivity_bonus = player.bonus,
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
  local startup = settings.startup
  if startup["ips-max-level-research_gears"].value ~= 2
      or startup["ips-effect-per-level-research_gears"].value ~= 1
      or startup["mir-settings-profile-import"].value ~= "" then
    fail("source fixture settings are not the verified positive-cap defaults")
  end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  local gear = technology(player, GEAR)
  assert_acceleration(gear)
  -- Published data-final cap presentation already patches the immutable
  -- prototype to true. Its controller captures that true value at the cap;
  -- this fixture never writes either player gear presentation property.
  if gear.prototype.visible_when_disabled ~= true then fail("published native prototype visibility changed") end
  local before = status(player)
  assert_status(before, {level = 1, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = 0, saved_progress = 0}, "published initial player")
  prerequisites(gear)

  local foreign = game.create_force(FOREIGN)
  foreign.enable_all_prototypes()
  local foreign_gear = technology(foreign, GEAR)
  prerequisites(foreign_gear)
  foreign.reset_technology_effects()
  foreign_gear.enabled = false
  foreign_gear.visible_when_disabled = false
  local probe = technology(foreign, PROBE)
  prerequisites(probe)
  if probe.researched then fail("unrelated foreign probe was already researched: " .. PROBE) end
  if foreign.add_research(probe) ~= true then fail("could not queue foreign probe") end
  foreign.research_progress = 0.42
  local foreign_queue = assert_foreign(foreign)

  local player_lab = game.surfaces[1].create_entity{name = "lab", position = {0, 0}, force = player}
  if player_lab == nil or player_lab.valid == false then fail("could not create real player lab") end
  local state = {
    phase = "await-first-lab", source_mir = script.active_mods["more-infinite-research"],
    fixture_version = script.active_mods[FIXTURE], actual_lab_completions = 0,
    milestone = "unstarted", foreign_force_index = foreign.index, foreign_queue = foreign_queue,
    lab = player_lab, deadline_tick = game.tick + DEADLINE,
  }
  storage[KEY] = state
  assert_source_start(state)
  fill(lab(state))
  if player.add_research(gear) ~= true then fail("could not queue first native gear research") end
  if player.current_research == nil or player.current_research.name ~= GEAR
      or #player.research_queue ~= 1 then fail("first player research was not a single native gear queue entry") end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player
      or event.research.name ~= GEAR then return end
  if state.phase ~= "await-first-lab" and state.phase ~= "await-second-lab" then
    fail("unexpected native gear completion phase")
  end
  state.actual_lab_completions = state.actual_lab_completions + 1
  if state.actual_lab_completions == 1 then
    state.phase = "await-second-queue"
  elseif state.actual_lab_completions == 2 then
    state.phase = "await-published-cap"
  else
    fail("source lab completed more than two gear levels")
  end
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "completed" then
    -- Factorio's on_load contract permits storage reads only.  The following
    -- tick performs the native-object readback against these durable values.
    loaded_snapshot = {player = copy_status(state.player_cap), queue = copy_queue(state.foreign_queue),
      actual_lab_completions = state.actual_lab_completions}
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("source fixture storage is absent") end
  if state.phase == "completed" then
    if loaded_snapshot and not reload_logged then
      local now = assert_published_cap(state)
      assert_status(now, loaded_snapshot.player, "source cold reload player")
      assert_foreign(game.forces[state.foreign_force_index], loaded_snapshot.queue)
      if loaded_snapshot.actual_lab_completions ~= state.actual_lab_completions then fail("source cold load changed lab count") end
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("source lab did not complete two gear levels") end
  lab(state)
  if state.phase == "await-second-queue" then
    local player = game.forces.player
    if player.current_research == nil and #player.research_queue == 0 then
      if player.add_research(technology(player, GEAR)) ~= true then fail("could not queue second native gear research") end
      if #player.research_queue ~= 1 then fail("second player gear research was not queued singly") end
      state.phase = "await-second-lab"
    end
    return
  end
  if state.phase == "await-published-cap" then
    -- The published controller has had the finish event and this following tick
    -- to acquire its cap state.  Save the partial work only after that witness.
    local player = status(game.forces.player)
    assert_status(player, {level = 3, researched = false, enabled = false, visible = true,
      maximum = UINT32_MAX, bonus = 0.02, saved_progress = 0}, "published cap before partial seed")
    technology(game.forces.player, GEAR).saved_progress = 0.27
    state.milestone = "actual2labs"
    state.phase = "completed"
    state.player_cap = copy_status(assert_published_cap(state))
    marker("initial", state)
    game.server_save(SAVE)
  end
end)
