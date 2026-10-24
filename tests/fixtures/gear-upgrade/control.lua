local api_name = "more-infinite-research.api.v1"
local fixture_storage_key = "mir5_gear_upgrade"
local gear_technology_name = "recipe-prod-research_gears-1"
local gear_recipe_name = "iron-gear-wheel"
local foreign_force_name = "mir5-gear-upgrade-foreign"
local save_name = "mir5-native-complete"
-- Factorio 2.1 exposes an infinite technology max level as a uint32 at
-- runtime, although the data-stage prototype uses the literal "infinite".
local UINT32_MAX = 4294967295

local loaded_snapshot = nil
local reload_logged = false

local function fail(message)
  error("[mir5-gear-upgrade] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function active_mir_version()
  return script.active_mods["more-infinite-research"]
end

local function technology_for(force)
  local technology = force and force.technologies[gear_technology_name]
  if not technology then
    fail("gear technology is absent for force " .. tostring(force and force.name))
  end
  return technology
end

local function prepare_prerequisites(technology)
  for _, prerequisite in pairs(technology.prerequisites) do
    prerequisite.research_recursive()
  end
end

local function native_status(force)
  local technology = technology_for(force)
  return {
    level = technology.level,
    researched = technology.researched,
    enabled = technology.enabled,
    visible_when_disabled = technology.visible_when_disabled,
    max_level = technology.prototype.max_level,
    productivity_bonus = force.recipes[gear_recipe_name].productivity_bonus
  }
end

local function assert_status(actual, expected, label)
  if actual.level ~= expected.level then
    fail(label .. " level differs: " .. tostring(actual.level))
  end
  if actual.researched ~= expected.researched then
    fail(label .. " researched state differs")
  end
  if actual.enabled ~= expected.enabled then
    fail(label .. " enabled state differs")
  end
  if actual.visible_when_disabled ~= expected.visible_when_disabled then
    fail(label .. " visibility differs")
  end
  if actual.max_level ~= expected.max_level then
    fail(label .. " native max level differs: " .. tostring(actual.max_level))
  end
  if not close(actual.productivity_bonus, expected.productivity_bonus) then
    fail(label .. " productivity bonus differs: " .. tostring(actual.productivity_bonus))
  end
end

local function public_research_status(force, expected, label)
  if not remote.interfaces[api_name] then fail("MIR 5 public API is absent") end
  local before = native_status(force)
  local status, code = remote.call(api_name, "get_research", force.index, gear_technology_name)
  if not status or code ~= nil then
    fail(label .. " public API could not read gear research: " .. tostring(code))
  end
  if status.name ~= gear_technology_name or status.force_index ~= force.index
      or status.level ~= expected.level or status.researched ~= expected.researched
      or status.enabled ~= expected.enabled or status.max_level ~= expected.max_level then
    fail(label .. " public API changed native research semantics")
  end
  -- A consumer cannot use this returned table to mutate MIR or native state.
  status.level = 1
  status.enabled = not expected.enabled
  local reread, reread_code = remote.call(api_name, "get_research", force.index, gear_technology_name)
  if not reread or reread_code ~= nil or reread.level ~= expected.level
      or reread.enabled ~= expected.enabled then
    fail(label .. " public API result was not detached")
  end
  assert_status(native_status(force), before, label .. " public API read-only")
end

local function expected_player_state()
  return {
    level = 3,
    researched = false,
    enabled = false,
    visible_when_disabled = true,
    max_level = UINT32_MAX,
    productivity_bonus = 0.2
  }
end

local function expected_foreign_state()
  return {
    level = 1,
    researched = false,
    enabled = false,
    visible_when_disabled = false,
    max_level = UINT32_MAX,
    productivity_bonus = 0
  }
end

local function assert_mir5_continuity(state)
  if active_mir_version() ~= "5.0.21000" then
    fail("continuity assertion requires the private MIR 5 archive")
  end
  local force = game.forces.player
  local automation = force.technologies.automation
  if not automation or automation.researched ~= true then
    fail("unrelated automation research did not survive the upgrade")
  end
  local player_expected = expected_player_state()
  assert_status(native_status(force), player_expected, "player gear continuity")
  if state.next_level ~= player_expected.level
      or not close(state.productivity_bonus, player_expected.productivity_bonus) then
    fail("durable 4.7 gear witness differs after upgrade")
  end
  public_research_status(force, player_expected, "player")

  local foreign = game.forces[state.foreign_force_index]
  if not foreign or foreign.valid == false or foreign.name ~= foreign_force_name then
    fail("foreign force witness is missing after upgrade")
  end
  local foreign_expected = expected_foreign_state()
  assert_status(native_status(foreign), foreign_expected, "foreign gear continuity")
  public_research_status(foreign, foreign_expected, "foreign")
end

local function marker(stage, state)
  local player = native_status(game.forces.player)
  local foreign = game.forces[state.foreign_force_index]
  local foreign_status = native_status(foreign)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = "gear-upgrade",
    status = "passed",
    witnesses = {
      seeded_mir_version = state.seeded_mir_version,
      next_level = player.level,
      productivity_bonus = player.productivity_bonus,
      native_max_level = player.max_level,
      cap = state.cap,
      player_enabled = player.enabled,
      player_visible_when_disabled = player.visible_when_disabled,
      automation_researched = game.forces.player.technologies.automation.researched,
      foreign_enabled = foreign_status.enabled,
      foreign_visible_when_disabled = foreign_status.visible_when_disabled,
      public_api_read_only = true,
      on_load_read_only = stage == "reload",
      qualification = "native-runner-readback-required"
    }
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or active_mir_version() ~= "4.7.21000" then
    fail("seed must use published MIR 4.7.21000 on Factorio 2.1.23")
  end
  if storage[fixture_storage_key] ~= nil then fail("fixture storage already exists") end

  local force = game.forces.player
  force.enable_all_prototypes()
  local automation = force.technologies.automation
  if not automation then fail("automation witness technology is absent") end
  automation.researched = true

  local gear = technology_for(force)
  if gear.level ~= 1 or gear.researched then
    fail("fresh published gear technology is not at its first level")
  end
  prepare_prerequisites(gear)
  -- These are native LuaTechnology setters: each `researched = true`
  -- completes exactly one infinite-research level without a MIR control API.
  gear.researched = true
  if gear.level ~= 2 or gear.researched then
    fail("first native gear completion did not advance to level two")
  end
  gear.researched = true
  if gear.level ~= 3 or gear.researched then
    fail("second native gear completion did not advance to level three")
  end
  local bonus = force.recipes[gear_recipe_name].productivity_bonus
  if not close(bonus, 0.2) then
    fail("two published gear completions did not produce a 0.2 bonus")
  end

  local foreign = game.create_force(foreign_force_name)
  foreign.enable_all_prototypes()
  local foreign_gear = technology_for(foreign)
  foreign_gear.enabled = false
  foreign_gear.visible_when_disabled = false

  storage[fixture_storage_key] = {
    phase = "seeded-4.7",
    seeded_mir_version = active_mir_version(),
    next_level = gear.level,
    productivity_bonus = bonus,
    cap = 2,
    automation_researched = automation.researched,
    foreign_force_index = foreign.index,
    foreign_enabled = foreign_gear.enabled,
    foreign_visible_when_disabled = foreign_gear.visible_when_disabled
  }
end)

script.on_configuration_changed(function()
  if active_mir_version() ~= "5.0.21000" then
    fail("configuration transition must select the private MIR 5 archive")
  end
  local state = storage[fixture_storage_key]
  if type(state) ~= "table" or state.phase ~= "seeded-4.7"
      or state.seeded_mir_version ~= "4.7.21000" then
    fail("published 4.7 seed witness is absent")
  end
  if state.automation_researched ~= true or state.foreign_enabled ~= false
      or state.foreign_visible_when_disabled ~= false then
    fail("durable published witness is malformed")
  end
  assert_mir5_continuity(state)
  state.phase = "await-initial-marker"
end)

script.on_load(function()
  local state = storage[fixture_storage_key]
  if state and state.phase == "completed" then
    -- Read only: the first subsequent tick checks the durable completion.
    loaded_snapshot = {
      next_level = state.next_level,
      productivity_bonus = state.productivity_bonus,
      foreign_force_index = state.foreign_force_index
    }
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[fixture_storage_key]
  if type(state) ~= "table" then fail("fixture state is absent") end

  if state.phase == "await-initial-marker" then
    assert_mir5_continuity(state)
    marker("initial", state)
    state.phase = "completed"
    game.server_save(save_name)
    return
  end

  if state.phase == "completed" and loaded_snapshot and not reload_logged then
    if state.next_level ~= loaded_snapshot.next_level
        or not close(state.productivity_bonus, loaded_snapshot.productivity_bonus)
        or state.foreign_force_index ~= loaded_snapshot.foreign_force_index then
      fail("on_load did not preserve the completed upgrade witness")
    end
    assert_mir5_continuity(state)
    marker("reload", state)
    reload_logged = true
    return
  end
end)