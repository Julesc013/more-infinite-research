-- This fixture uses only shipped remote settings calls and documented native
-- entity/force APIs. Its durable data lives under its own root storage key;
-- it does not inspect MIR's runtime state.
local KEY = "mir5_settings_repair"
local SAVE = "mir5-native-complete"
local CASE = "settings-repair"
local MIR_VERSION = "5.0.21000"
local SETTINGS_INTERFACE = "more-infinite-research-settings"
local GEAR = "recipe-prod-research_gears-1"
local FRIENDLY_FORCE = "mir5-settings-repair-friendly"
local FOREIGN_FORCE = "mir5-settings-repair-foreign"
local DAMAGE_TYPE = "electric"
local DAMAGE_AMOUNT = 2
local QUIET_TICKS = 600
local SERVICE_TICKS = 60
local IDLE_AFTER_DRAIN_TICKS = 120

local expected_effective = {
  ["ips-enable-research_gears"] = true,
  ["ips-cost-base-research_gears"] = 1,
  ["ips-cost-linear-increment-research_gears"] = 0,
  ["ips-cost-growth-research_gears"] = 1,
  ["ips-max-level-research_gears"] = 0,
  ["ips-research-time-research_gears"] = 1,
  ["ips-effect-per-level-research_gears"] = 10,
  ["mir-max-level-worker-robots-speed"] = 0,
  ["mir-enable-passive-repair"] = true
}

local expected_compact = {
  ["ips-cost-base-research_gears"] = 1,
  ["ips-cost-growth-research_gears"] = 1,
  ["ips-research-time-research_gears"] = 1,
  ["mir-enable-passive-repair"] = true
}

local raw_valid = [[{"schema":1,"kind":"mir-settings-profile","settings":{"ips-enable-research_gears":true,"ips-cost-base-research_gears":1,"ips-cost-linear-increment-research_gears":0,"ips-cost-growth-research_gears":1,"ips-max-level-research_gears":0,"ips-research-time-research_gears":1,"ips-effect-per-level-research_gears":10,"mir-max-level-worker-robots-speed":0,"mir-enable-passive-repair":true}}]]
local raw_invalid = [[{"schema":1,"kind":"mir-settings-profile","settings":{"ips-cost-base-research_gears":0}}]]
local raw_unknown = [[{"schema":1,"kind":"mir-settings-profile","settings":{"mir5-fixture-unknown-setting":true}}]]

local loaded_snapshot = nil
local reload_logged = false

local function fail(message)
  error("[mir5-settings-repair] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end

local function valid(value)
  return value ~= nil and value.valid ~= false
end

local function count_entries(value)
  local count = 0
  for _ in pairs(value or {}) do count = count + 1 end
  return count
end

local function settings_call(method, ...)
  if not remote.interfaces[SETTINGS_INTERFACE] then
    fail("shipped settings remote interface is absent")
  end
  return remote.call(SETTINGS_INTERFACE, method, ...)
end

local function decode_export(wire, label)
  if type(wire) ~= "string" or wire:sub(1, 8) ~= "MIRSET1:" then
    fail(label .. " export is not a MIRSET1 string")
  end
  local json = helpers.decode_string(wire:sub(9))
  if type(json) ~= "string" then fail(label .. " export does not decode") end
  local profile = helpers.json_to_table(json)
  if type(profile) ~= "table" or type(profile.settings) ~= "table" then
    fail(label .. " export profile is malformed")
  end
  return profile
end

local function assert_settings(actual, expected, label)
  if count_entries(actual) ~= count_entries(expected) then
    fail(label .. " setting count differs")
  end
  for name, expected_value in pairs(expected) do
    local actual_value = actual[name]
    if type(expected_value) == "number" then
      if not close(actual_value, expected_value) then
        fail(label .. " setting differs: " .. name)
      end
    elseif actual_value ~= expected_value then
      fail(label .. " setting differs: " .. name)
    end
  end
end

local function assert_status(result, expected, label)
  if type(result) ~= "table" or result.valid ~= expected.valid then
    fail(label .. " validity differs")
  end
  for _, field in ipairs({"recognized", "invalid", "unknown"}) do
    if expected[field] ~= nil and result[field] ~= expected[field] then
      fail(label .. " " .. field .. " count differs")
    end
  end
  if expected.import_setting and result.import_setting ~= "mir-settings-profile-import" then
    fail(label .. " import setting identity differs")
  end
  if expected.error and type(result.error) ~= "string" then fail(label .. " error is absent") end
end

local function observe_settings()
  local full = decode_export(settings_call("export_string", {}), "full")
  if full.metadata == nil or full.metadata.export_mode ~= "full" then
    fail("full export mode differs")
  end
  assert_settings(full.settings, expected_effective, "full export effective")

  -- The public method accepts compact only when it is exactly true.
  local non_boolean = decode_export(settings_call("export_string", {compact = 1}), "strict full")
  if non_boolean.metadata == nil or non_boolean.metadata.export_mode ~= "full" then
    fail("non-boolean compact option was accepted")
  end
  assert_settings(non_boolean.settings, expected_effective, "strict full export effective")

  local compact = decode_export(settings_call("export_string", {compact = true}), "compact")
  if compact.metadata == nil or compact.metadata.export_mode ~= "compact" then
    fail("compact export mode differs")
  end
  assert_settings(compact.settings, expected_compact, "compact export effective")

  assert_status(settings_call("validate_string", raw_valid),
    {valid = true, recognized = 9, invalid = 0, unknown = 0, import_setting = true}, "raw valid")
  local encoded = helpers.encode_string(raw_valid)
  if type(encoded) ~= "string" or encoded == "" then fail("native helper did not encode MIRSET1 input") end
  assert_status(settings_call("validate_string", "MIRSET1:" .. encoded),
    {valid = true, recognized = 9, invalid = 0, unknown = 0, import_setting = true}, "MIRSET1 valid")
  assert_status(settings_call("validate_string", raw_invalid),
    {valid = true, recognized = 0, invalid = 1, unknown = 0, import_setting = true}, "raw invalid value")
  assert_status(settings_call("validate_string", raw_unknown),
    {valid = true, recognized = 0, invalid = 0, unknown = 1, import_setting = true}, "raw unknown")
  assert_status(settings_call("validate_string", "MIRSET1:"),
    {valid = false, error = true}, "MIRSET1 malformed")

  local technology = game.forces.player.technologies[GEAR]
  if not valid(technology) or technology.level ~= 1 or technology.enabled ~= true
      or technology.research_unit_count ~= 1
      or not technology.prototype or not close(technology.prototype.research_unit_energy, 60) then
    fail("native gear values do not reflect the imported low-cost profile")
  end
  local effects = technology.prototype.effects
  local effect = effects and effects[1]
  if not effect or effects[2] ~= nil or effect.type ~= "change-recipe-productivity"
      or effect.recipe ~= "iron-gear-wheel" or not close(effect.change, 0.1) then
    fail("native gear effect does not reflect the imported profile")
  end
  return {full_count = count_entries(full.settings), compact_count = count_entries(compact.settings)}
end

local function create_entity(surface, name, position, force)
  local entity = surface.create_entity{name = name, position = position, force = force}
  if not valid(entity) then fail("could not create native " .. name) end
  return entity
end

local function damage(entity, enemy)
  local before = entity.health
  local applied = entity.damage(DAMAGE_AMOUNT, enemy, DAMAGE_TYPE)
  if not close(applied, DAMAGE_AMOUNT) or not close(entity.health, before - DAMAGE_AMOUNT) then
    fail("native electric damage did not apply the expected amount")
  end
  return entity.health, entity.max_health
end

local function health_is(entity, expected, label)
  if not valid(entity) or not close(entity.health, expected) then
    fail(label .. " health differs")
  end
end

local function first_service_at_or_after(tick)
  return math.floor((tick + SERVICE_TICKS - 1) / SERVICE_TICKS) * SERVICE_TICKS
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = CASE,
    status = "passed",
    witnesses = {
      settings_remote_interface = SETTINGS_INTERFACE,
      full_effective_setting_count = state.full_count,
      compact_effective_setting_count = state.compact_count,
      raw_profile_validated = true,
      mirset1_profile_validated = true,
      invalid_profile_value_reported = true,
      unknown_profile_value_reported = true,
      malformed_mirset1_rejected = true,
      imported_base_cost = 1,
      imported_growth_factor = 1,
      imported_research_time = 1,
      imported_passive_repair_enabled = true,
      native_level_one_count = 1,
      native_research_unit_energy = 60,
      native_productivity_change = 0.1,
      repair_damage_type = DAMAGE_TYPE,
      quiet_ticks = QUIET_TICKS,
      repair_interval_ticks = SERVICE_TICKS,
      repair_amount = 1,
      player_wall_repaired = true,
      reciprocal_friendly_wall_repaired = true,
      foreign_wall_unchanged = true,
      non_wall_unchanged = true,
      queue_drain_inferred_after_full_health = true,
      idle_ticks_after_drain = IDLE_AFTER_DRAIN_TICKS,
      fixture_on_load_defers_native_checks = stage == "reload",
      native_result_required = true,
      gui_qualified = false,
      multiplayer_qualified = false
    }
  }))
end

local function assert_runtime_versions()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["more-infinite-research"] ~= MIR_VERSION then
    fail("fixture requires Factorio 2.1.23 and MIR " .. MIR_VERSION)
  end
end

script.on_init(function()
  assert_runtime_versions()
  if storage[KEY] ~= nil then fail("fixture storage already exists") end
  game.speed = 16

  local settings_witness = observe_settings()
  local player = game.forces.player
  local friendly = game.create_force(FRIENDLY_FORCE)
  local foreign = game.create_force(FOREIGN_FORCE)
  player.set_friend(friendly, true)
  friendly.set_friend(player, true)
  local surface = game.surfaces[1]
  if not valid(surface) then fail("native surface is absent") end

  local player_wall = create_entity(surface, "stone-wall", {0, 0}, player)
  local friendly_wall = create_entity(surface, "stone-wall", {2, 0}, friendly)
  local foreign_wall = create_entity(surface, "stone-wall", {4, 0}, foreign)
  local non_wall = create_entity(surface, "wooden-chest", {6, 0}, player)
  local enemy = game.forces.enemy
  if not valid(enemy) then fail("native enemy force is absent") end

  local player_health, player_maximum = damage(player_wall, enemy)
  local friendly_health, friendly_maximum = damage(friendly_wall, enemy)
  local foreign_health, foreign_maximum = damage(foreign_wall, enemy)
  local non_wall_health, non_wall_maximum = damage(non_wall, enemy)
  if not close(player_maximum, friendly_maximum) or not close(player_maximum, foreign_maximum)
      or not close(player_health, friendly_health) or not close(player_health, foreign_health)
      or non_wall_maximum <= non_wall_health then
    fail("native fixture damage witnesses differ")
  end

  storage[KEY] = {
    phase = "waiting-first-service",
    full_count = settings_witness.full_count,
    compact_count = settings_witness.compact_count,
    player_wall = player_wall,
    friendly_wall = friendly_wall,
    foreign_wall = foreign_wall,
    non_wall = non_wall,
    player_health = player_health,
    friendly_health = friendly_health,
    foreign_health = foreign_health,
    non_wall_health = non_wall_health,
    player_maximum = player_maximum,
    friendly_maximum = friendly_maximum,
    foreign_maximum = foreign_maximum,
    damage_tick = game.tick,
    quiet_until = game.tick + QUIET_TICKS,
    first_service_tick = first_service_at_or_after(game.tick + QUIET_TICKS),
    deadline = game.tick + QUIET_TICKS + (SERVICE_TICKS * 2) + IDLE_AFTER_DRAIN_TICKS + 120
  }
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "completed" then
    -- Only local references are rebuilt. Storage and game objects stay
    -- untouched until the first benchmark tick checks this durable witness.
    loaded_snapshot = {
      player_health = state.player_health,
      friendly_health = state.friendly_health,
      foreign_health = state.foreign_health,
      non_wall_health = state.non_wall_health
    }
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("fixture state is absent") end
  if state.phase ~= "completed" and game.tick > state.deadline then
    fail("repair witnesses did not settle before the fixture deadline")
  end

  if state.phase == "waiting-first-service" then
    if game.tick < state.first_service_tick then
      health_is(state.player_wall, state.player_health, "player wall before quiet period")
      health_is(state.friendly_wall, state.friendly_health, "friendly wall before quiet period")
      health_is(state.foreign_wall, state.foreign_health, "foreign wall before quiet period")
      health_is(state.non_wall, state.non_wall_health, "non-wall before quiet period")
      return
    end
    if game.tick == state.first_service_tick then return end
    health_is(state.player_wall, state.player_health + 1, "player wall first service")
    health_is(state.friendly_wall, state.friendly_health + 1, "friendly wall first service")
    health_is(state.foreign_wall, state.foreign_health, "foreign wall first service")
    health_is(state.non_wall, state.non_wall_health, "non-wall first service")
    state.second_service_tick = state.first_service_tick + SERVICE_TICKS
    state.phase = "waiting-second-service"
    return
  end

  if state.phase == "waiting-second-service" then
    if game.tick < state.second_service_tick then
      health_is(state.player_wall, state.player_health + 1, "player wall between services")
      health_is(state.friendly_wall, state.friendly_health + 1, "friendly wall between services")
      return
    end
    if game.tick == state.second_service_tick then return end
    health_is(state.player_wall, state.player_maximum, "player wall second service")
    health_is(state.friendly_wall, state.friendly_maximum, "friendly wall second service")
    health_is(state.foreign_wall, state.foreign_health, "foreign wall second service")
    health_is(state.non_wall, state.non_wall_health, "non-wall second service")
    state.idle_until = game.tick + IDLE_AFTER_DRAIN_TICKS
    state.phase = "waiting-drain-idle"
    return
  end

  if state.phase == "waiting-drain-idle" then
    health_is(state.player_wall, state.player_maximum, "player wall after drain")
    health_is(state.friendly_wall, state.friendly_maximum, "friendly wall after drain")
    health_is(state.foreign_wall, state.foreign_health, "foreign wall after drain")
    health_is(state.non_wall, state.non_wall_health, "non-wall after drain")
    if game.tick < state.idle_until then return end
    state.phase = "completed"
    marker("initial", state)
    game.server_save(SAVE)
    return
  end

  if state.phase == "completed" and loaded_snapshot and not reload_logged then
    if loaded_snapshot.player_health ~= state.player_health
        or loaded_snapshot.friendly_health ~= state.friendly_health
        or loaded_snapshot.foreign_health ~= state.foreign_health
        or loaded_snapshot.non_wall_health ~= state.non_wall_health then
      fail("on_load changed the saved fixture witness")
    end
    health_is(state.player_wall, state.player_maximum, "reloaded player wall")
    health_is(state.friendly_wall, state.friendly_maximum, "reloaded friendly wall")
    health_is(state.foreign_wall, state.foreign_health, "reloaded foreign wall")
    health_is(state.non_wall, state.non_wall_health, "reloaded non-wall")
    marker("reload", state)
    reload_logged = true
  end
end)
