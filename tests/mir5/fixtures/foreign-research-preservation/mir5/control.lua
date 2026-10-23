-- Version 0.2.0 is loaded only over the 0.1.0 source save. This representative
-- preserves a foreign technology and effects without claiming the reporter's
-- exact provider, package closure, or MIR 4.7 startup outcome.
local KEY = "mir5_foreign_research_preservation"
local SAVE = "mir5-foreign-research-preservation-mir5"
local FOREIGN = "Space-Lab-Research-61"
local NATIVE = "research-speed-7"
local MIR = "recipe-prod-research_gears-1"
local GEAR = "iron-gear-wheel"

local loaded_snapshot = nil
local reload_logged = false

local function fail(message)
  error("[mir5-foreign-research-preservation] " .. message)
end

local function close(left, right)
  return type(left) == "number" and math.abs(left - right) <= 0.0000001
end

local function technology(force, name)
  local value = force.technologies[name]
  if not value then fail("named technology is absent: " .. name) end
  return value
end

local function snapshot(force)
  local foreign = technology(force, FOREIGN)
  local native = technology(force, NATIVE)
  local mir = technology(force, MIR)
  return {
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

local function same(left, right)
  return left.level == right.level and left.researched == right.researched
      and left.enabled == right.enabled and left.max_level == right.max_level
end

local function assert_continuity(state)
  local current = snapshot(game.forces.player)
  if not same(current.foreign, state.foreign) or current.foreign.level ~= 61
      or current.foreign.researched ~= true or current.foreign.max_level ~= 61 then
    fail("foreign finite research was changed by the MIR 5 transition")
  end
  if not same(current.native, state.native) or current.native.researched ~= false
      or current.native.max_level ~= 4294967295 then
    fail("native laboratory-speed continuation was changed by the MIR 5 transition")
  end
  if not same(current.mir, state.mir) or current.mir.researched ~= false
      or current.mir.max_level ~= 4294967295
      or not close(current.mir.productivity_bonus, state.mir.productivity_bonus)
      or not close(current.mir.productivity_bonus, 0.2) then
    fail("earned MIR gear research was changed by the MIR 5 transition")
  end
  if not close(current.laboratory_speed_modifier, state.laboratory_speed_modifier)
      or not close(current.laboratory_speed_modifier, state.laboratory_speed_before + 0.661) then
    fail("MIR 5 transition duplicated or removed a laboratory-speed effect")
  end
end

local function marker(stage, state)
  log("[MIR5_FOREIGN_RESEARCH_PRESERVATION] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = "SCI-RESEARCH-01-representative",
    status = "passed",
    qualification = "native-runner-readback-required",
    witnesses = {
      source_mir = state.source_mir,
      destination_mir = script.active_mods["more-infinite-research"],
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
      on_load_read_only = stage == "reload"
    }
  }))
end

script.on_configuration_changed(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["more-infinite-research"] ~= "5.0.21000" then
    fail("destination must use MIR 5.0.21000 on Factorio 2.1.23")
  end
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "seeded-4.7" or state.source_mir ~= "4.7.21000"
      or state.direct_native_setter_completion ~= "foreign-finite-61,native-lab-speed,mir-gear-levels" then
    fail("published 4.7 representative seed witness is absent")
  end
  assert_continuity(state)
  state.phase = "await-mir5-save"
end)

script.on_load(function()
  local state = storage[KEY]
  if state and state.phase == "completed" then
    -- Read only: on_tick verifies the durable witness after each cold reload.
    loaded_snapshot = {
      foreign_level = state.foreign.level,
      native_level = state.native.level,
      mir_level = state.mir.level,
      laboratory_speed_modifier = state.laboratory_speed_modifier
    }
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("fixture state is absent") end
  if state.phase == "await-mir5-save" then
    assert_continuity(state)
    marker("initial", state)
    state.phase = "completed"
    game.server_save(SAVE)
    return
  end
  if state.phase == "completed" and loaded_snapshot and not reload_logged then
    if loaded_snapshot.foreign_level ~= state.foreign.level
        or loaded_snapshot.native_level ~= state.native.level
        or loaded_snapshot.mir_level ~= state.mir.level
        or not close(loaded_snapshot.laboratory_speed_modifier, state.laboratory_speed_modifier) then
      fail("on_load changed the completed foreign-research witness")
    end
    assert_continuity(state)
    marker("reload", state)
    reload_logged = true
  end
end)
