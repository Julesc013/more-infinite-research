local KEY = "mir5_native_worker_speed_cap_relaxed"
local SAVE = "mir5-native-complete"
local CASE = "worker-speed-cap-relaxed"
local UINT32_MAX = 4294967295
local TAILS = {
  {name = "worker-robots-speed-7", predecessor = "worker-robots-speed-6"},
  {name = "worker-robots-speed-6", predecessor = "worker-robots-speed-5"}
}

local loaded, reload_logged = nil, false

local function fail(message) error("[mir5-worker-speed-cap-relaxed] " .. message) end
local function close(left, right)
  return type(left) == "number" and math.abs(left - right) <= 0.0000001
end

local function owner_for(force)
  for _, candidate in ipairs(TAILS) do
    local technology = force.technologies[candidate.name]
    local prototype = technology and technology.prototype
    local effect = prototype and prototype.effects and prototype.effects[1]
    local predecessor = technology and technology.prerequisites[candidate.predecessor]
    if technology and prototype and prototype.max_level == UINT32_MAX and effect
        and prototype.effects[2] == nil and effect.type == "worker-robot-speed"
        and effect.modifier == 0.65 and predecessor and predecessor.name == candidate.predecessor then
      return technology
    end
  end
  fail("no admitted runtime worker-speed tail")
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = CASE,
    status = "passed",
    witnesses = {
      owner = state.owner,
      next_level = state.next_level,
      startup_cap = 0,
      worker_robots_speed_modifier = state.modifier,
      owner_enabled = state.owner_enabled,
      owner_visible = state.owner_visible,
      foreign_enabled = state.foreign_enabled,
      foreign_visible = state.foreign_visible,
      on_load_read_only = stage == "reload"
    }
  }))
end

local function observe(state)
  local force = game.forces.player
  local owner = owner_for(force)
  local foreign = game.forces["mir5-native-worker-speed-foreign"]
  local foreign_owner = foreign and owner_for(foreign)
  if owner.level ~= state.next_level or not owner.enabled or owner.visible_when_disabled then
    fail("unlimited transition did not restore MIR-owned native enablement")
  end
  if not close(force.worker_robots_speed_modifier, state.modifier) then
    fail("unlimited transition changed earned worker speed bonus")
  end
  if not foreign_owner or foreign_owner.enabled or foreign_owner.visible_when_disabled then
    fail("unlimited transition changed foreign native disablement")
  end
  state.owner = owner.name
  state.owner_enabled = owner.enabled
  state.owner_visible = owner.visible_when_disabled
  state.foreign_enabled = foreign_owner.enabled
  state.foreign_visible = foreign_owner.visible_when_disabled
end

script.on_configuration_changed(function()
  -- Read the finite fixture's saved witness, not the already changed native
  -- state. Otherwise a lost level/bonus during configuration could self-pass.
  local prior = storage["mir5_native_worker_speed_cap"]
  if not prior or not prior.saved then fail("finite saved witness is absent") end
  storage[KEY] = {
    owner = prior.owner,
    next_level = prior.next_level,
    modifier = prior.modifier_after,
    deadline = game.tick + 1200,
    phase = "await-relax"
  }
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = state and state.saved and {
    owner = state.owner, next_level = state.next_level, modifier = state.modifier
  } or nil
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("configuration transition did not initialize relaxation witness") end
  if state.saved then
    if loaded and not reload_logged then
      if loaded.owner ~= state.owner or loaded.next_level ~= state.next_level
          or not close(loaded.modifier, state.modifier) then
        fail("on_load changed saved relaxation witness")
      end
      observe(state)
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline then fail("unlimited native cap did not restore") end
  observe(state)
  marker("initial", state)
  state.saved = true
  state.phase = "saved"
  game.server_save(SAVE)
end)
