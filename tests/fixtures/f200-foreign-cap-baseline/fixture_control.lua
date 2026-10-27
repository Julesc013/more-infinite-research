-- Disposable F200 current-MIR cap baseline fixture.  It does not call MIR
-- internals: the ordinary configuration callback owns cap reconciliation.
local M = {}

local KEY = "mir5_f200_foreign_cap_baseline"
local SAVE = "mir5-native-complete"
local CASE = "f200-foreign-cap-baseline"
local FIXTURE = "mir-fixture-mir5-f200-foreign-cap-baseline"
local GEAR = "recipe-prod-research_gears-1"
local PROBE = "braking-force-1"
local UINT32_MAX = 4294967295
local STAGES = {
  source = {version = "0.1.0", cap = 0, prior = nil},
  finite = {version = "0.2.0", cap = 1, prior = "source-complete"},
  relaxed = {version = "0.3.0", cap = 0, prior = "finite-complete"},
}

local reload_requested, reload_logged = false, false

local function fail(message) error("[mir5-f200-foreign-cap-baseline] " .. message) end
local function close(left, right)
  return type(left) == "number" and math.abs(left - right) <= 0.000001
end

local function stage_info(stage)
  local expected = STAGES[stage]
  if expected == nil then fail("unknown control stage") end
  return expected
end

local function check_closure(expected)
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "5.0.20000"
      or script.active_mods[FIXTURE] ~= expected.version or script.active_mods["space-age"] ~= nil then
    fail("fixture stage closure differs")
  end
  local startup = settings.startup
  local cap = startup and startup["ips-max-level-research_gears"]
  local effect = startup and startup["ips-effect-per-level-research_gears"]
  local enabled = startup and startup["ips-enable-research_gears"]
  local imported = startup and startup["mir-settings-profile-import"]
  if cap == nil or cap.value ~= expected.cap or effect == nil or effect.value ~= 1
      or enabled == nil or enabled.value ~= true or imported == nil or imported.value ~= "" then
    fail("fixture startup settings differ")
  end
end

local function technology(force)
  local value = force and force.technologies and force.technologies[GEAR]
  if value == nil or value.valid == false or value.name ~= GEAR then fail("gear technology is absent") end
  return value
end

local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current = force.current_research and force.current_research.name or false,
    queue = queue, progress = force.research_progress}
end

local function same_queue(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or left.current ~= right.current
      or #left.queue ~= #right.queue or not close(left.progress, right.progress) then return false end
  for index, name in ipairs(left.queue) do if right.queue[index] ~= name then return false end end
  return true
end

local function snapshot(force)
  local value = technology(force)
  local recipe = force.recipes and force.recipes["iron-gear-wheel"]
  if recipe == nil or type(recipe.productivity_bonus) ~= "number" then fail("gear recipe bonus is absent") end
  return {level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, maximum = value.prototype and value.prototype.max_level,
    saved_progress = value.saved_progress, bonus = recipe.productivity_bonus, queue = queue_snapshot(force)}
end

local function assert_state(actual, stage, foreign, label)
  if actual.level ~= 3 or actual.researched ~= false or actual.maximum ~= UINT32_MAX
      or not close(actual.bonus, 0.02) then
    fail(label .. " earned gear state differs")
  end
  if foreign then
    if not close(actual.saved_progress, 0) then fail(label .. " detached work changed") end
    if actual.enabled ~= false then fail(label .. " disablement changed") end
    if stage == "finite" then
      if actual.visible ~= true then fail(label .. " cap visibility is absent") end
    elseif actual.visible ~= false then
      fail(label .. " visibility was not restored")
    end
    if actual.queue.current ~= PROBE or #actual.queue.queue ~= 1 or actual.queue.queue[1] ~= PROBE
        or not close(actual.queue.progress, 0.42) then
      fail(label .. " queue or progress differs")
    end
  else
    if not close(actual.saved_progress, 0.27) then fail(label .. " earned gear state differs") end
    if stage == "finite" then
      if actual.enabled ~= false or actual.visible ~= true then fail(label .. " owned finite cap is absent") end
    elseif actual.enabled ~= true or actual.visible ~= false then
      fail(label .. " owned cap was not restored")
    end
    if actual.queue.current ~= false or #actual.queue.queue ~= 0 or not close(actual.queue.progress, 0) then
      fail(label .. " player queue changed")
    end
  end
  return actual
end

local function assert_snapshot(actual, expected, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched or actual.enabled ~= expected.enabled
      or actual.visible ~= expected.visible or actual.maximum ~= expected.maximum
      or not close(actual.saved_progress, expected.saved_progress) or not close(actual.bonus, expected.bonus)
      or not same_queue(actual.queue, expected.queue) then
    fail(label .. " saved state differs")
  end
end

local function marker(stage, state, expected)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = CASE, stage = stage, status = "passed", qualification = "native-runner-readback-required",
    witnesses = {fixture_stage = script.active_mods[FIXTURE], cap = expected.cap,
      actual_lab_completions = 0, player_level = state.player.level,
      player_saved_progress = state.player.saved_progress, player_enabled = state.player.enabled,
      player_visible_when_disabled = state.player.visible, foreign_enabled = state.foreign.enabled,
      foreign_visible_when_disabled = state.foreign.visible,
      foreign_queue_progress = state.foreign.queue.progress, on_load_read_only = stage == "reload"},
  }))
end

local function seed_foreign()
  local foreign = game.create_force("mir5-f200-foreign-cap-baseline-foreign")
  foreign.enable_all_prototypes()
  local gear, probe = technology(foreign), foreign.technologies[PROBE]
  if probe == nil or probe.valid == false then fail("foreign queue probe is absent") end
  gear.researched = false
  gear.level = 3
  probe.researched = false
  probe.enabled = true
  if foreign.add_research(probe) ~= true then fail("could not queue foreign probe") end
  foreign.research_progress = 0.42
  -- Assignment and reset occur before the externally owned disabled baseline.
  foreign.reset_technology_effects()
  gear.enabled = false
  gear.visible_when_disabled = false
  return foreign
end

function M.apply(stage)
  local expected = stage_info(stage)
  if stage == "source" then
    script.on_init(function()
      check_closure(expected)
      if storage[KEY] ~= nil then fail("source fixture state already exists") end
      local player = game.forces.player
      player.enable_all_prototypes()
      local gear = technology(player)
      gear.researched = false
      gear.level = 3
      player.reset_technology_effects()
      gear.enabled = true
      gear.visible_when_disabled = false
      gear.saved_progress = 0.27
      local player_state = assert_state(snapshot(player), stage, false, "source player")
      local foreign = seed_foreign()
      local foreign_state = assert_state(snapshot(foreign), stage, true, "source foreign")
      storage[KEY] = {phase = "source-prepared", stage = stage, player = player_state,
        foreign = foreign_state, foreign_index = foreign.index}
    end)
  end

  script.on_configuration_changed(function()
    if stage == "source" then fail("source stage does not accept a successor configuration") end
    check_closure(expected)
    local state = storage[KEY]
    if type(state) ~= "table" or state.phase ~= expected.prior or type(state.player) ~= "table"
        or type(state.foreign) ~= "table" then fail("required prior cap-baseline state is absent") end
    local player = assert_state(snapshot(game.forces.player), stage, false, stage .. " player")
    local foreign = game.forces[state.foreign_index]
    local foreign_state = assert_state(snapshot(foreign), stage, true, stage .. " foreign")
    -- The settings callback is the observation boundary. It never seeds or
    -- repairs a failed predecessor; it only records the already-live state.
    state.phase, state.stage, state.player, state.foreign = stage .. "-prepared", stage, player, foreign_state
  end)

  script.on_load(function()
    -- No game/storage access is allowed here. The next tick reads the save.
    reload_requested, reload_logged = true, false
  end)

  script.on_event(defines.events.on_tick, function()
    local state = storage[KEY]
    if type(state) ~= "table" or state.stage ~= stage then fail("fixture stage state differs") end
    if state.phase == stage .. "-prepared" then
      check_closure(expected)
      local player = assert_state(snapshot(game.forces.player), stage, false, "initial server player")
      local foreign = assert_state(snapshot(game.forces[state.foreign_index]), stage, true, "initial server foreign")
      assert_snapshot(player, state.player, "initial server player")
      assert_snapshot(foreign, state.foreign, "initial server foreign")
      state.phase, state.player, state.foreign = stage .. "-complete", player, foreign
      marker("initial", state, expected)
      game.server_save(SAVE)
      reload_requested, reload_logged = false, true
      return
    end
    if state.phase ~= stage .. "-complete" then fail("fixture phase differs") end
    if not reload_requested or reload_logged then return end
    check_closure(expected)
    local player = assert_state(snapshot(game.forces.player), stage, false, "cold reload player")
    local foreign = assert_state(snapshot(game.forces[state.foreign_index]), stage, true, "cold reload foreign")
    assert_snapshot(player, state.player, "cold reload player")
    assert_snapshot(foreign, state.foreign, "cold reload foreign")
    marker("reload", state, expected)
    reload_logged = true
  end)
end

return M
