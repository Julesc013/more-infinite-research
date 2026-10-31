-- This is version 0.2.0 of the published seed fixture mod identity. It never
-- creates an old world: configuration change must receive the accepted 4.7
-- seed's fixture bucket and observe the player source's one-shot importer.
local api_name = "more-infinite-research.api.v1"
local fixture_name = "mir-fixture-mir5-gear-upgrade"
local fixture_storage_key = "mir5_gear_upgrade"
local gear_technology_name = "recipe-prod-research_gears-1"
local gear_recipe_name = "iron-gear-wheel"
local foreign_force_name = "mir5-gear-upgrade-foreign"
local maximum_setting_name = "ips-max-level-research_gears"
local import_setting_name = "mir-settings-profile-import"
local save_name = "mir5-native-complete"
local UINT32_MAX = 4294967295

local loaded_snapshot = nil
local reload_logged = false

local function fail(message)
  error("[mir5-gear-upgrade-relaxed] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function active_mir_version()
  return script.active_mods["more-infinite-research"]
end

local function technology_for(force)
  local technology = force and force.technologies[gear_technology_name]
  if not technology then fail("gear technology is absent for the observed force") end
  return technology
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

local function copy_status(value)
  return {
    level = value.level,
    researched = value.researched,
    enabled = value.enabled,
    visible_when_disabled = value.visible_when_disabled,
    max_level = value.max_level,
    productivity_bonus = value.productivity_bonus
  }
end

local function assert_status(actual, expected, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.enabled ~= expected.enabled
      or actual.visible_when_disabled ~= expected.visible_when_disabled
      or actual.max_level ~= expected.max_level
      or not close(actual.productivity_bonus, expected.productivity_bonus) then
    fail(label .. " native status differs")
  end
end

local function expected_player_state()
  return {
    level = 3,
    researched = false,
    enabled = true,
    visible_when_disabled = false,
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

local function public_research_status(force, expected, label)
  if remote.interfaces[api_name] == nil then fail("MIR 5 public API is absent") end
  local before = native_status(force)
  local status, code = remote.call(api_name, "get_research", force.index, gear_technology_name)
  if status == nil or code ~= nil or status.name ~= gear_technology_name
      or status.force_index ~= force.index or status.level ~= expected.level
      or status.researched ~= expected.researched or status.enabled ~= expected.enabled
      or status.max_level ~= expected.max_level then
    fail(label .. " public research status differs")
  end
  status.level, status.enabled = 1, not expected.enabled
  local reread, reread_code = remote.call(api_name, "get_research", force.index, gear_technology_name)
  if reread == nil or reread_code ~= nil or reread.level ~= expected.level
      or reread.enabled ~= expected.enabled then
    fail(label .. " public research result is not detached")
  end
  assert_status(native_status(force), before, label .. " public query mutated native state")
end

local function required_raw_settings()
  local startup = settings and settings.startup
  local maximum = startup and startup[maximum_setting_name]
  local profile_import = startup and startup[import_setting_name]
  if maximum == nil or maximum.value ~= 0 then
    fail("fixture maximum setting was not constrained to zero")
  end
  if profile_import == nil or profile_import.value ~= "" then
    fail("fixture requires a blank normal profile import; imported values take precedence")
  end
end

local function seed_state()
  local state = storage[fixture_storage_key]
  if type(state) ~= "table" or state.phase ~= "seeded-4.7"
      or state.seeded_mir_version ~= "4.7.21000" or state.next_level ~= 3
      or not close(state.productivity_bonus, 0.2) or state.cap ~= 2
      or state.automation_researched ~= true or state.foreign_enabled ~= false
      or state.foreign_visible_when_disabled ~= false
      or type(state.foreign_force_index) ~= "number" then
    fail("accepted published 4.7 gear seed witness is absent or malformed")
  end
  return state
end

local function observe_relaxed_state(state)
  if active_mir_version() ~= "5.0.21000" or script.active_mods[fixture_name] ~= "0.2.0" then
    fail("relaxed observation requires MIR 5.0.21000 and fixture successor 0.2.0")
  end
  required_raw_settings()
  local player = game.forces.player
  local automation = player and player.technologies.automation
  if automation == nil or automation.researched ~= true then
    fail("unrelated automation research did not survive the upgrade")
  end
  local expected_player = expected_player_state()
  local player_status = native_status(player)
  assert_status(player_status, expected_player, "MIR-owned player gear relaxation")
  public_research_status(player, expected_player, "player")

  local foreign = game.forces[state.foreign_force_index]
  if foreign == nil or foreign.valid == false or foreign.name ~= foreign_force_name then
    fail("separately foreign-disabled force is absent")
  end
  local expected_foreign = expected_foreign_state()
  local foreign_status = native_status(foreign)
  assert_status(foreign_status, expected_foreign, "foreign gear preservation")
  public_research_status(foreign, expected_foreign, "foreign")
  return {
    player = copy_status(player_status),
    foreign = copy_status(foreign_status),
    automation_researched = automation.researched,
    raw_maximum = settings.startup[maximum_setting_name].value,
    blank_profile_import = settings.startup[import_setting_name].value == ""
  }
end

local function assert_observed_snapshot(state, observed)
  if type(observed) ~= "table" or observed.automation_researched ~= true
      or observed.raw_maximum ~= 0 or observed.blank_profile_import ~= true then
    fail("durable relaxed fixture snapshot is malformed")
  end
  assert_status(native_status(game.forces.player), observed.player, "saved player relaxation")
  local foreign = game.forces[state.foreign_force_index]
  if foreign == nil or foreign.valid == false then fail("saved foreign force is absent") end
  assert_status(native_status(foreign), observed.foreign, "saved foreign preservation")
end

local function marker(stage, state)
  local observed = state.relaxed_observed
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = "gear-upgrade-relaxed",
    status = "passed",
    witnesses = {
      seeded_mir_version = state.seeded_mir_version,
      fixture_successor_version = script.active_mods[fixture_name],
      raw_maximum_setting = observed.raw_maximum,
      blank_profile_import = observed.blank_profile_import,
      next_level = observed.player.level,
      productivity_bonus = observed.player.productivity_bonus,
      player_enabled = observed.player.enabled,
      player_visible_when_disabled = observed.player.visible_when_disabled,
      foreign_enabled = observed.foreign.enabled,
      foreign_visible_when_disabled = observed.foreign.visible_when_disabled,
      unrelated_automation_researched = observed.automation_researched,
      public_api_equals_native = true,
      worker_ownership_import_observed = false,
      scope = "gear-relaxation-only",
      on_load_read_only = stage == "reload",
      qualification = "native-runner-readback-required"
    }
  }))
end

script.on_init(function()
  fail("relaxed fixture must start from the accepted published 4.7 gear seed")
end)

script.on_configuration_changed(function()
  local state = seed_state()
  -- MIR is the required dependency and its configuration callback reconciles
  -- the one-shot authenticated legacy ownership before this fixture observes.
  local observed = observe_relaxed_state(state)
  state.relaxed_observed = observed
  state.phase = "await-relaxed-initial-marker"
end)

script.on_load(function()
  local state = storage[fixture_storage_key]
  if type(state) == "table" and state.phase == "completed-relaxed"
      and type(state.relaxed_observed) == "table" then
    -- Read only: native API checks occur on the first later tick.
    loaded_snapshot = {
      player = copy_status(state.relaxed_observed.player),
      foreign = copy_status(state.relaxed_observed.foreign),
      automation_researched = state.relaxed_observed.automation_researched,
      raw_maximum = state.relaxed_observed.raw_maximum,
      blank_profile_import = state.relaxed_observed.blank_profile_import
    }
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[fixture_storage_key]
  if type(state) ~= "table" then fail("fixture state is absent") end
  if state.phase == "await-relaxed-initial-marker" then
    local observed = observe_relaxed_state(state)
    state.relaxed_observed = observed
    state.phase = "completed-relaxed"
    marker("initial", state)
    game.server_save(save_name)
    return
  end
  if state.phase == "completed-relaxed" and loaded_snapshot and not reload_logged then
    assert_observed_snapshot(state, loaded_snapshot)
    observe_relaxed_state(state)
    marker("reload", state)
    reload_logged = true
  end
end)
