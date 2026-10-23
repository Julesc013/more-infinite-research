local KEY = "mir5_native_worker_caps"
local NAME = "worker-robots-speed-7"
local API = "more-infinite-research.api.v1"
local MODIFIER = script.active_mods["Krastorio2-spaced-out"] and 0.6 or 0.65
local loaded, reported

local function fail(message)
  error("[mir5-worker-caps-relaxed] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) < 0.0000001
end

local function query(force, expected_enabled)
  local result, code = remote.call(API, "get_research", force.index, NAME)
  if not result or code or result.enabled ~= expected_enabled then fail("public worker status differs") end
  local native = force.technologies[NAME]
  if result.level ~= native.level or result.max_level ~= 4294967295 then fail("public native level differs") end
  result.level, result.enabled = 1, not expected_enabled
  local reread = remote.call(API, "get_research", force.index, NAME)
  if reread.level ~= native.level or reread.enabled ~= expected_enabled then fail("public worker status is aliased") end
end

local function observe(state)
  if state.finished ~= 2 or type(state.before_bonus) ~= "number" then fail("completed source witness is absent") end
  if settings.startup["mir-max-level-worker-robots-speed"].value ~= 0
      or settings.startup["mir-settings-profile-import"].value ~= "" then fail("worker cap did not become unlimited") end
  local force = game.forces.player
  local technology = force.technologies[NAME]
  if technology.level ~= 9 or technology.researched or not technology.enabled
      or technology.visible_when_disabled then fail("MIR-owned native worker state was not restored") end
  if not close(force.worker_robots_speed_modifier, state.before_bonus + 2 * MODIFIER) then
    fail("uncapping changed the earned native worker effect or independent offset")
  end
  if force.current_research ~= nil or #force.research_queue ~= 0 then fail("uncapping changed native queue state") end
  local foreign = game.forces[state.foreign_index]
  if not foreign or foreign.name ~= "mir5-worker-caps-foreign" then fail("foreign force disappeared") end
  local foreign_technology = foreign.technologies[NAME]
  if foreign_technology.level ~= 7 or foreign_technology.enabled or foreign_technology.visible_when_disabled
      or not close(foreign.worker_robots_speed_modifier, 0) then fail("foreign worker state changed") end
  query(force, true)
  query(foreign, false)
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = "worker-caps-relaxed", stage = stage, status = "passed",
    witnesses = {
      profile = MODIFIER == 0.6 and "k2so" or "space-age", native_owner = NAME,
      native_effect_modifier = MODIFIER, source_lab_completed_levels = state.finished,
      cap = 0, next_level = 9, earned_native_effect_and_independent_offset_preserved = true,
      before_bonus_with_independent_offset = state.before_bonus,
      after_bonus = game.forces.player.worker_robots_speed_modifier,
      owned_enabled_and_visibility_restored = true, foreign_disable_preserved = true,
      detached_public_queries = true, fixture_preserves_source_cost_acceleration = true,
      on_load_read_only = stage == "reload"
    }
  }))
end

script.on_init(function() fail("requires the hash-bound completed worker cap save") end)
script.on_configuration_changed(function()
  local state = storage[KEY]
  if not state or state.phase ~= "complete" then fail("completed cap input save is absent") end
  observe(state)
  state.phase = "save-relaxed"
end)
script.on_load(function()
  local state = storage[KEY]
  loaded = state and state.phase == "relaxed" and {finished = state.finished, before_bonus = state.before_bonus} or nil
  reported = false
end)
script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("worker fixture state is absent") end
  if state.phase == "save-relaxed" then
    observe(state)
    state.phase = "relaxed"
    marker("initial", state)
    game.server_save("mir5-native-complete")
  elseif state.phase == "relaxed" and loaded and not reported then
    if state.finished ~= loaded.finished or state.before_bonus ~= loaded.before_bonus then fail("load changed saved witness") end
    observe(state)
    marker("reload", state)
    reported = true
  end
end)
