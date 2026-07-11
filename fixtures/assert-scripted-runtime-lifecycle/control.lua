local technology_name = "recipe-prod-research_spoilage_preservation-1"
local per_level = 1.02
local epsilon = 0.000001

local function fail(message)
  error("MIR scripted runtime lifecycle validation failed: " .. message)
end

local function assert_close(label, actual, expected)
  if math.abs((actual or 0) - expected) > epsilon then
    fail(label .. " was " .. tostring(actual) .. ", expected " .. tostring(expected))
  end
end

local function technology(force)
  local value = force and force.technologies and force.technologies[technology_name]
  if not value then fail("missing scripted spoilage technology for force " .. tostring(force and force.name)) end
  return value
end

local function set_completed_levels(force, levels)
  local tech = technology(force)
  local ok, err = pcall(function() tech.level = levels + 1 end)
  if not ok then fail("could not set infinite technology level: " .. tostring(err)) end
  force.reset_technology_effects()
end

script.on_init(function()
  local force = game.forces.player
  local baseline = game.difficulty_settings.spoil_time_modifier
  storage.mir_scripted_fixture = {baseline = baseline, pending_reload_proof = true}

  set_completed_levels(force, 3)
  assert_close("three-level application", game.difficulty_settings.spoil_time_modifier, baseline * per_level ^ 3)

  set_completed_levels(force, 1)
  assert_close("level reversal", game.difficulty_settings.spoil_time_modifier, baseline * per_level)

  set_completed_levels(force, 0)
  assert_close("zero-level reset", game.difficulty_settings.spoil_time_modifier, baseline)

  local secondary = game.create_force("mir-scripted-secondary")
  set_completed_levels(secondary, 4)
  assert_close("secondary force maximum level", game.difficulty_settings.spoil_time_modifier, baseline * per_level ^ 4)
  game.merge_forces(secondary, force)

  force = game.forces.player
  local applied = baseline * per_level ^ 4
  assert_close("post-merge level", game.difficulty_settings.spoil_time_modifier, applied)

  game.difficulty_settings.spoil_time_modifier = applied * 1.5
  force.reset_technology_effects()
  local rebased = baseline * 1.5
  assert_close("external baseline rebase", game.difficulty_settings.spoil_time_modifier, rebased * per_level ^ 4)

  storage.mir_scripted_fixture.rebased = rebased
  storage.mir_scripted_fixture.expected_saved = rebased * per_level ^ 4
  log("[mir-fixture] scripted lifecycle initial proof complete")
end)

script.on_event(defines.events.on_tick, function()
  local state = storage.mir_scripted_fixture
  if not state or not state.pending_reload_proof then return end

  assert_close("save/load retained application",
    game.difficulty_settings.spoil_time_modifier,
    state.expected_saved)
  state.pending_reload_proof = false
  log("[mir-fixture] scripted lifecycle retention proof complete")
end)

script.on_configuration_changed(function()
  local state = storage.mir_scripted_fixture
  local enabled = settings.startup["ips-enable-research_spoilage_preservation"].value == true
  if not state then
    if not enabled then fail("new scripted fixture was loaded while its stream was disabled") end
    local baseline = game.difficulty_settings.spoil_time_modifier
    set_completed_levels(game.forces.player, 2)
    assert_close("configuration-change enable application",
      game.difficulty_settings.spoil_time_modifier,
      baseline * per_level ^ 2)
    set_completed_levels(game.forces.player, 0)
    assert_close("configuration-change enable restoration", game.difficulty_settings.spoil_time_modifier, baseline)
    log("[mir-fixture] scripted lifecycle enable proof complete")
    return
  end
  if not state.rebased then fail("scripted fixture state did not survive save/load") end
  state.pending_reload_proof = false
  if not enabled then
    assert_close("configuration-change disable restoration",
      game.difficulty_settings.spoil_time_modifier,
      state.rebased)
    log("[mir-fixture] scripted lifecycle disable proof complete")
    return
  end
  assert_close("configuration-change retained application",
    game.difficulty_settings.spoil_time_modifier,
    state.expected_saved)
  log("[mir-fixture] scripted lifecycle retention proof complete")
end)
