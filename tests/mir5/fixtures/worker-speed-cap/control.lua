local KEY = "mir5_native_worker_speed_cap"
local SAVE = "mir5-native-complete"
local CASE = "worker-speed-cap"
local CAP = 7
local UINT32_MAX = 4294967295
local TAILS = {
  {name = "worker-robots-speed-7", predecessor = "worker-robots-speed-6"},
  {name = "worker-robots-speed-6", predecessor = "worker-robots-speed-5"}
}

local loaded, reload_logged = nil, false

local function fail(message) error("[mir5-worker-speed-cap] " .. message) end
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

local function prepare_prerequisites(technology)
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
end

local function start_unrelated_research(force)
  local probe = force.technologies["mir5-worker-speed-cap-probe"]
  if not probe then fail("native fixture research probe is absent") end
  prepare_prerequisites(probe)
  if not force.add_research(probe) then fail("could not start native fixture research probe") end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = CASE,
    status = "passed",
    witnesses = {
      owner = state.owner,
      cap = CAP,
      initial_level = state.initial_level,
      next_level = state.next_level,
      completed_levels = 2,
      modifier_before = state.modifier_before,
      modifier_after = state.modifier_after,
      modifier_delta = state.modifier_delta,
      owner_enabled = state.owner_enabled,
      owner_visible = state.owner_visible,
      foreign_enabled = state.foreign_enabled,
      foreign_visible = state.foreign_visible,
      native_researched_setter_observation = true,
      on_load_read_only = stage == "reload"
    }
  }))
end

local function verify_saved(state)
  local force = game.forces.player
  local owner = owner_for(force)
  local foreign = game.forces["mir5-native-worker-speed-foreign"]
  local foreign_owner = foreign and owner_for(foreign)
  if owner.name ~= state.owner or owner.level ~= state.next_level or owner.enabled
      or not owner.visible_when_disabled then
    fail("saved primary cap state differs")
  end
  if not close(force.worker_robots_speed_modifier, state.modifier_after) then
    fail("saved worker robot speed modifier differs")
  end
  if not foreign_owner or foreign_owner.enabled or not foreign_owner.visible_when_disabled then
    fail("saved foreign-disabled state differs")
  end
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["more-infinite-research"] ~= "5.0.21000" then
    fail("unexpected Factorio or MIR version")
  end
  local force = game.forces.player
  force.enable_all_prototypes()
  local owner = owner_for(force)
  local initial_level = owner.level
  prepare_prerequisites(owner)
  local modifier_before = force.worker_robots_speed_modifier
  -- These two direct native setters observe earned infinite levels. They do
  -- not claim lab work or science consumption; the assertions below read the
  -- engine's actual level and force modifier after each completion.
  owner.researched = true
  if owner.level ~= initial_level + 1 or owner.researched then fail("first native completion differs") end
  owner.researched = true
  if owner.level ~= initial_level + 2 or owner.researched then fail("second native completion differs") end
  local modifier_after = force.worker_robots_speed_modifier
  if not close(modifier_after - modifier_before, 1.3) then
    fail("two native completions did not add 1.3 worker speed")
  end

  -- This real research-start event lets MIR reconcile the now above-cap tail.
  start_unrelated_research(force)
  local foreign = game.create_force("mir5-native-worker-speed-foreign")
  foreign.enable_all_prototypes()
  local foreign_owner = owner_for(foreign)
  foreign_owner.level = owner.level
  foreign_owner.enabled = false
  foreign_owner.visible_when_disabled = false
  start_unrelated_research(foreign)

  storage[KEY] = {
    owner = owner.name,
    initial_level = initial_level,
    next_level = owner.level,
    modifier_before = modifier_before,
    modifier_after = modifier_after,
    modifier_delta = modifier_after - modifier_before,
    deadline = game.tick + 1200,
    phase = "await-cap"
  }
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = state and state.saved and {
    owner = state.owner, next_level = state.next_level, modifier_after = state.modifier_after
  } or nil
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("fixture state is absent") end
  if state.saved then
    if loaded and not reload_logged then
      if loaded.owner ~= state.owner or loaded.next_level ~= state.next_level
          or not close(loaded.modifier_after, state.modifier_after) then
        fail("on_load changed saved witness")
      end
      verify_saved(state)
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline then fail("native worker cap did not reconcile") end
  local force = game.forces.player
  local owner = owner_for(force)
  local foreign = game.forces["mir5-native-worker-speed-foreign"]
  local foreign_owner = foreign and owner_for(foreign)
  if owner.level ~= state.next_level or owner.enabled or not owner.visible_when_disabled then
    fail("finite cap did not disable the earned above-cap native tail")
  end
  if not foreign_owner or foreign_owner.enabled or not foreign_owner.visible_when_disabled then
    fail("foreign-disabled native tail was not preserved")
  end
  state.owner_enabled = owner.enabled
  state.owner_visible = owner.visible_when_disabled
  state.foreign_enabled = foreign_owner.enabled
  state.foreign_visible = foreign_owner.visible_when_disabled
  marker("initial", state)
  state.saved = true
  state.phase = "saved"
  game.server_save(SAVE)
end)
