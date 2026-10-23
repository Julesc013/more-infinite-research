-- The source side is deliberately a small representative, not an assertion
-- that this was Tr1ckY_Fate's provider or that MIR 4.7 loaded it successfully.
local KEY = "mir5_foreign_research_preservation"
local SAVE = "mir5-native-complete"
local FOREIGN = "Space-Lab-Research-61"
local PENDING = "Space-Lab-Research-62"
local NATIVE = "research-speed-7"
local MIR = "recipe-prod-research_gears-1"
local GEAR = "iron-gear-wheel"
local loaded, reload_logged = false, false

local function fail(message)
  error("[mir5-foreign-research-preservation-source] " .. message)
end

local function close(left, right)
  return type(left) == "number" and math.abs(left - right) <= 0.0000001
end

local function technology(force, name)
  local value = force.technologies[name]
  if not value then fail("named technology is absent: " .. name) end
  return value
end

local function prepare_prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end

local function snapshot(force)
  local foreign = technology(force, FOREIGN)
  local native = technology(force, NATIVE)
  local mir = technology(force, MIR)
  local pending = technology(force, PENDING)
  local queue = {}
  for index, queued in ipairs(force.research_queue or {}) do queue[index] = queued.name end
  return {
    pending = {level = pending.level, researched = pending.researched, enabled = pending.enabled,
      max_level = pending.prototype.max_level},
    queue = queue,
    current_research = force.current_research and force.current_research.name or false,
    research_progress = force.research_progress,
    mir_saved_progress = mir.saved_progress,
    foreign = {
      level = foreign.level,
      researched = foreign.researched,
      enabled = foreign.enabled,
      max_level = foreign.prototype.max_level
    },
    native = {
      level = native.level,
      researched = native.researched,
      enabled = native.enabled,
      max_level = native.prototype.max_level
    },
    mir = {
      level = mir.level,
      researched = mir.researched,
      enabled = mir.enabled,
      max_level = mir.prototype.max_level,
      productivity_bonus = force.recipes[GEAR].productivity_bonus
    },
    laboratory_speed_modifier = force.laboratory_speed_modifier
  }
end

local function assert_seeded(force, state)
  local current = snapshot(force)
  local foreign = current.foreign
  local native = current.native
  local mir = current.mir
  if current.pending.level ~= 62 or current.pending.researched ~= false
      or current.pending.enabled ~= true or current.pending.max_level ~= 62
      or current.current_research ~= PENDING or #current.queue ~= 2
      or current.queue[1] ~= PENDING or current.queue[2] ~= MIR
      or not close(current.research_progress, 0.42) or not close(current.mir_saved_progress, 0.27) then
    fail("foreign queue or partial foreign/MIR investment differs")
  end
  if foreign.level ~= 61 or foreign.researched ~= true or foreign.enabled ~= true
      or foreign.max_level ~= 61 then
    fail("finite foreign research state differs")
  end
  if native.level ~= state.native.level or native.researched ~= false
      or native.enabled ~= state.native.enabled or native.max_level ~= 4294967295 then
    fail("named native laboratory-speed continuation differs")
  end
  if mir.level ~= state.mir.level or mir.researched ~= false or mir.enabled ~= state.mir.enabled
      or mir.max_level ~= 4294967295 or not close(mir.productivity_bonus, state.mir.productivity_bonus)
      or not close(mir.productivity_bonus, 0.2) then
    fail("earned MIR gear research differs")
  end
  if not close(current.laboratory_speed_modifier, state.laboratory_speed_modifier)
      or not close(current.laboratory_speed_modifier, state.laboratory_speed_before + 0.661) then
    fail("foreign and named native laboratory-speed bonus differs")
  end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = "SCI-RESEARCH-01-representative",
    status = "passed",
    qualification = "native-runner-readback-required",
    witnesses = {
      source_mir = state.source_mir,
      foreign_name = FOREIGN,
      foreign_level = state.foreign.level,
      foreign_researched = state.foreign.researched,
      native_name = NATIVE,
      native_level = state.native.level,
      mir_name = MIR,
      mir_level = state.mir.level,
      mir_productivity_bonus = state.mir.productivity_bonus,
      laboratory_speed_modifier = state.laboratory_speed_modifier,
      direct_native_setter_completion = state.direct_native_setter_completion,
      current_research = state.current_research, queue = state.queue,
      foreign_progress = state.research_progress, mir_saved_progress = state.mir_saved_progress
    }
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["more-infinite-research"] ~= "4.7.21000" then
    fail("source must use published MIR 4.7.21000 on Factorio 2.1.23")
  end
  if storage[KEY] ~= nil then fail("source fixture state already exists") end

  local force = game.forces.player
  force.enable_all_prototypes()
  local foreign = technology(force, FOREIGN)
  local native = technology(force, NATIVE)
  local mir = technology(force, MIR)
  -- Prerequisite research can itself award laboratory-speed bonuses. Finish
  -- all prerequisite setup before measuring the three explicit completions.
  prepare_prerequisites(foreign)
  prepare_prerequisites(native)
  prepare_prerequisites(mir)
  local laboratory_speed_before = force.laboratory_speed_modifier
  if foreign.level ~= 61 or foreign.prototype.max_level ~= 61 or foreign.researched then
    fail("foreign fixture technology is not finite level 61")
  end
  -- Native LuaTechnology completion establishes the foreign earned effect.
  foreign.researched = true
  if foreign.researched ~= true then fail("foreign native setter did not complete finite research") end

  local native_level = native.level
  -- Native LuaTechnology completion establishes the overlapping +0.6 effect.
  native.researched = true
  if native.level ~= native_level + 1 or native.researched then
    fail("native laboratory-speed setter did not complete exactly one level")
  end

  if mir.level ~= 1 or mir.researched then fail("published MIR gear seed is not at first level") end
  -- Two native LuaTechnology completions create an earned MIR-owned witness.
  mir.researched = true
  mir.researched = true
  if mir.level ~= 3 or mir.researched or not close(force.recipes[GEAR].productivity_bonus, 0.2) then
    fail("published MIR gear setters did not retain two earned levels")
  end

  -- Retain an unfinished foreign level and suspended MIR investment as well
  -- as earned effects. No lab is provisioned, so ordinary ticks cannot spend it.
  local pending = technology(force, PENDING)
  mir.saved_progress = 0.27
  force.research_queue_enabled = true
  force.research_queue = {pending, mir}
  force.research_progress = 0.42

  local state = snapshot(force)
  state.phase = "await-source-save"
  state.source_mir = script.active_mods["more-infinite-research"]
  state.laboratory_speed_before = laboratory_speed_before
  state.direct_native_setter_completion = "foreign-finite-61,native-lab-speed,mir-gear-levels"
  storage[KEY] = state
end)

script.on_load(function()
  loaded = storage[KEY] ~= nil and storage[KEY].phase == "seeded-4.7"
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then return end
  if state.phase == "await-source-save" then
    assert_seeded(game.forces.player, state)
    marker("initial", state)
    state.phase = "seeded-4.7"
    game.server_save(SAVE)
  elseif state.phase == "seeded-4.7" and loaded and not reload_logged then
    assert_seeded(game.forces.player, state)
    marker("reload", state)
    reload_logged = true
  end
end)
