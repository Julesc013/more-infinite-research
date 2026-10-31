local KEY = "mir5_native_worker_speed_precap"
local NAME = "worker-robots-speed-6"
local loaded, logged = false, false
local function fail(message) error("[mir5-worker-speed-precap] " .. message) end
local function close(left, right) return math.abs(left - right) < 0.0000001 end

local function observe(state)
  local force = game.forces.player
  local owner = force.technologies[NAME]
  local foreign = game.forces[state.foreign_index]
  local other = foreign and foreign.technologies[NAME]
  if owner.level ~= 8 or not owner.enabled or owner.visible_when_disabled
      or not close(force.worker_robots_speed_modifier, state.modifier_after) then
    fail("primary uncapped native baseline differs")
  end
  if not other or other.level ~= 8 or other.enabled or other.visible_when_disabled then
    fail("foreign uncapped native baseline differs")
  end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage, case = "worker-speed-precap", status = "passed",
    witnesses = {
      owner = NAME, next_level = 8, cap = 0, completed_levels = 2,
      modifier_before = state.modifier_before, modifier_after = state.modifier_after,
      native_researched_setter_observation = true,
      primary_enabled = true, primary_visible = false,
      foreign_enabled = false, foreign_visible = false,
      on_load_read_only = stage == "reload"
    }
  }))
end

script.on_init(function()
  local force = game.forces.player
  force.enable_all_prototypes()
  local owner = force.technologies[NAME]
  if not owner or owner.level ~= 6 or owner.prototype.max_level ~= 4294967295
      or #owner.prototype.effects ~= 1 or owner.prototype.effects[1].type ~= "worker-robot-speed"
      or owner.prototype.effects[1].modifier ~= 0.65 then fail("unexpected native base owner") end
  for _, prerequisite in pairs(owner.prerequisites) do prerequisite.research_recursive() end
  local before = force.worker_robots_speed_modifier
  owner.researched = true
  if owner.level ~= 7 then fail("first native setter completion differs") end
  owner.researched = true
  if owner.level ~= 8 or owner.researched
      or not close(force.worker_robots_speed_modifier - before, 1.3) then
    fail("second native setter completion differs")
  end
  owner.enabled, owner.visible_when_disabled = true, false
  local foreign = game.create_force("mir5-native-worker-speed-foreign")
  foreign.enable_all_prototypes()
  local other = foreign.technologies[NAME]
  other.level = 8
  -- No finite cap is active. These are the independently saved foreign flags
  -- observed before any successor gains ownership of a changed field.
  other.enabled, other.visible_when_disabled = false, false
  storage[KEY] = {
    owner = NAME, initial_level = 6, next_level = 8,
    modifier_before = before, modifier_after = force.worker_robots_speed_modifier,
    modifier_delta = force.worker_robots_speed_modifier - before,
    original_owner_enabled = owner.enabled, original_owner_visible = owner.visible_when_disabled,
    foreign_index = foreign.index
  }
end)

script.on_load(function()
  local state = storage[KEY]
  loaded, logged = state and state.saved == true, false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("baseline state missing") end
  if state.saved then
    if loaded and not logged then observe(state); marker("reload", state); logged = true end
    return
  end
  observe(state)
  marker("initial", state)
  state.saved = true
  game.server_save("mir5-native-complete")
end)
