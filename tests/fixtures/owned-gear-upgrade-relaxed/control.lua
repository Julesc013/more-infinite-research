local api_name = "more-infinite-research.api.v1"
local fixture_name = "mir-fixture-mir5-owned-gear-upgrade"
local storage_key = "mir5_owned_gear_upgrade"
local gear_technology_name = "recipe-prod-research_gears-1"
local gear_recipe_name = "iron-gear-wheel"
local foreign_force_name = "mir5-owned-gear-upgrade-foreign"
local maximum_setting_name = "ips-max-level-research_gears"
local import_setting_name = "mir-settings-profile-import"
local save_name = "mir5-native-complete"
local UINT32_MAX = 4294967295

local loaded_snapshot = nil
local reload_logged = false

local function fail(message)
  error("[mir5-owned-gear-upgrade-relaxed] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function technology_for(force)
  local technology = force and force.technologies[gear_technology_name]
  if technology == nil then fail("gear technology is absent for observed force") end
  return technology
end

local function status_for(force)
  local technology = technology_for(force)
  local recipe = force.recipes[gear_recipe_name]
  if recipe == nil then fail("gear recipe is absent for observed force") end
  return {
    level = technology.level,
    researched = technology.researched,
    enabled = technology.enabled,
    visible_when_disabled = technology.visible_when_disabled,
    max_level = technology.prototype.max_level,
    productivity_bonus = recipe.productivity_bonus
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
    fail(label .. " differs")
  end
end

local function assert_source_witness(state)
  local original = state.original_player
  local post_cap = state.post_cap
  local foreign = state.original_foreign
  if state.seeded_mir_version ~= "4.7.21000" or state.finished_levels ~= 2
      or type(original) ~= "table" or original.enabled ~= true
      or original.visible_when_disabled ~= false or original.level ~= 1
      or type(post_cap) ~= "table" or type(post_cap.player) ~= "table"
      or post_cap.player.enabled ~= false or post_cap.player.visible_when_disabled ~= true
      or post_cap.player.level ~= 3 or not close(post_cap.player.productivity_bonus, 0.2)
      or type(foreign) ~= "table" or foreign.enabled ~= false
      or foreign.visible_when_disabled ~= false or type(post_cap.foreign) ~= "table"
      or post_cap.foreign.enabled ~= false or post_cap.foreign.visible_when_disabled ~= false
      or type(state.science_units_consumed) ~= "table" then
    fail("published lab-completed ownership witness is absent or malformed")
  end
  for _, name in ipairs({"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}) do
    if state.science_units_consumed[name] ~= 2 then
      fail("published source witness did not retain two consumed units of " .. name)
    end
  end
end

local function assert_raw_relaxed_settings()
  local startup = settings and settings.startup
  local maximum = startup and startup[maximum_setting_name]
  local profile_import = startup and startup[import_setting_name]
  if maximum == nil or maximum.value ~= 0 then
    fail("fixture cap was not constrained to zero")
  end
  if profile_import == nil or profile_import.value ~= "" then
    fail("fixture requires blank normal profile import")
  end
end

local function public_readonly(force, expected, label)
  if remote.interfaces[api_name] == nil then fail("MIR 5 public API is absent") end
  local before = status_for(force)
  local result, code = remote.call(api_name, "get_research", force.index, gear_technology_name)
  if result == nil or code ~= nil or result.name ~= gear_technology_name
      or result.force_index ~= force.index or result.level ~= expected.level
      or result.researched ~= expected.researched or result.enabled ~= expected.enabled
      or result.max_level ~= expected.max_level then
    fail(label .. " public API status differs")
  end
  result.level = 1
  result.enabled = not expected.enabled
  local reread, reread_code = remote.call(api_name, "get_research", force.index, gear_technology_name)
  if reread == nil or reread_code ~= nil or reread.level ~= expected.level
      or reread.enabled ~= expected.enabled then
    fail(label .. " public API result is not detached")
  end
  assert_status(status_for(force), before, label .. " public API mutated native state")
end

local function observe_relaxed(state)
  if script.active_mods["more-infinite-research"] ~= "5.0.21000"
      or script.active_mods[fixture_name] ~= "0.2.0" then
    fail("successor requires private MIR 5.0.21000 and fixture 0.2.0")
  end
  assert_source_witness(state)
  assert_raw_relaxed_settings()
  local expected_player = {
    level = 3, researched = false, enabled = true,
    visible_when_disabled = false, max_level = UINT32_MAX, productivity_bonus = 0.2
  }
  local player = status_for(game.forces.player)
  assert_status(player, expected_player, "MIR-owned player relaxation")
  public_readonly(game.forces.player, expected_player, "player")

  local foreign_force = game.forces[state.foreign_force_index]
  if foreign_force == nil or foreign_force.valid == false or foreign_force.name ~= foreign_force_name then
    fail("foreign force witness is absent")
  end
  local expected_foreign = {
    level = 1, researched = false, enabled = false,
    visible_when_disabled = false, max_level = UINT32_MAX, productivity_bonus = 0
  }
  local foreign = status_for(foreign_force)
  assert_status(foreign, expected_foreign, "foreign disabled preservation")
  public_readonly(foreign_force, expected_foreign, "foreign")

  return {
    player = copy_status(player),
    foreign = copy_status(foreign),
    raw_maximum = settings.startup[maximum_setting_name].value,
    blank_profile_import = settings.startup[import_setting_name].value == ""
  }
end

local function assert_saved_observation(state, expected)
  if type(expected) ~= "table" or expected.raw_maximum ~= 0
      or expected.blank_profile_import ~= true then
    fail("durable successor observation is malformed")
  end
  assert_status(status_for(game.forces.player), expected.player, "cold-loaded relaxed player")
  local foreign_force = game.forces[state.foreign_force_index]
  if foreign_force == nil or foreign_force.valid == false then fail("cold-loaded foreign force is absent") end
  assert_status(status_for(foreign_force), expected.foreign, "cold-loaded foreign state")
end

local function marker(stage, state)
  local observed = state.relaxed_observed
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = "owned-gear-upgrade-relaxed",
    status = "passed",
    witnesses = {
      source_mir_version = state.seeded_mir_version,
      fixture_successor_version = script.active_mods[fixture_name],
      source_original_player_enabled = state.original_player.enabled,
      source_original_player_visible_when_disabled = state.original_player.visible_when_disabled,
      source_post_cap_player_enabled = state.post_cap.player.enabled,
      source_post_cap_player_visible_when_disabled = state.post_cap.player.visible_when_disabled,
      raw_maximum_setting = observed.raw_maximum,
      blank_profile_import = observed.blank_profile_import,
      next_level = observed.player.level,
      productivity_bonus = observed.player.productivity_bonus,
      player_enabled = observed.player.enabled,
      player_visible_when_disabled = observed.player.visible_when_disabled,
      foreign_enabled = observed.foreign.enabled,
      foreign_visible_when_disabled = observed.foreign.visible_when_disabled,
      public_api_read_only = true,
      scope = "published-gear-cap-ownership-only",
      on_load_read_only = stage == "reload",
      qualification = "native-runner-readback-required"
    }
  }))
end

script.on_init(function()
  fail("successor fixture must start from a published lab-completed 4.7 seed")
end)

script.on_configuration_changed(function()
  local state = storage[storage_key]
  if type(state) ~= "table" or state.phase ~= "completed" then
    fail("published seed state is absent before MIR 5 configuration")
  end
  -- MIR's dependency callback restores only authenticated old ownership before
  -- this dependent fixture observes the native result.
  state.relaxed_observed = observe_relaxed(state)
  state.phase = "await-relaxed-marker"
end)

script.on_load(function()
  local state = storage[storage_key]
  if type(state) == "table" and state.phase == "completed-relaxed"
      and type(state.relaxed_observed) == "table" then
    -- Read-only snapshot; native API access waits for the first subsequent tick.
    loaded_snapshot = {
      player = copy_status(state.relaxed_observed.player),
      foreign = copy_status(state.relaxed_observed.foreign),
      raw_maximum = state.relaxed_observed.raw_maximum,
      blank_profile_import = state.relaxed_observed.blank_profile_import
    }
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[storage_key]
  if type(state) ~= "table" then fail("fixture storage is absent") end
  if state.phase == "await-relaxed-marker" then
    state.relaxed_observed = observe_relaxed(state)
    state.phase = "completed-relaxed"
    marker("initial", state)
    game.server_save(save_name)
    return
  end
  if state.phase == "completed-relaxed" and loaded_snapshot and not reload_logged then
    assert_saved_observation(state, loaded_snapshot)
    observe_relaxed(state)
    marker("reload", state)
    reload_logged = true
  end
end)
