local KEY = "mir5_k2se_imersite_carrier_retention"
local CASE = "k2se-imersite-carrier-retention-successor"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-k2se-imersite-carrier-retention"
local EARLY = "mir-k2-imersite-staged-state-1"
local TAIL = "mir-k2-imersite-continuation-state-4"
local POWDER = "kr-imersite-powder"
local FOREIGN = "mir5-k2se-imersite-carrier-foreign"
local UINT32_MAX = 4294967295
local loaded, reported = false, false

local function fail(message) error("[mir5-k2se-imersite-successor] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. name) end
  return value
end
local function powder_bonus(force)
  local recipe = force and force.recipes[POWDER]
  if recipe == nil then fail("Imersite powder recipe is absent") end
  return recipe.productivity_bonus
end
local function queue(force)
  local names = {}
  for index, value in ipairs(force.research_queue or {}) do names[index] = value.name end
  return {current=force.current_research and force.current_research.name or false,
    names=names, progress=force.research_progress}
end
local function carrier(force, name, first, label)
  local value = technology(force, name)
  local prototype, effect = value.prototype, value.prototype.effects and value.prototype.effects[1]
  if value.level < first or prototype.hidden ~= true or prototype.max_level ~= UINT32_MAX
      or effect == nil or effect.type ~= "change-recipe-productivity" or effect.recipe ~= POWDER
      or not close(effect.change, 0.02) or prototype.level ~= first or prototype.upgrade ~= false then
    fail(label .. " carrier identity or effect differs")
  end
  return value
end
local function settings_match()
  local startup = settings.startup
  return startup["ips-enable-research_material_imersite"].value == true
    and startup["ips-cost-base-research_material_imersite"].value == 200
    and startup["ips-cost-linear-increment-research_material_imersite"].value == 0
    and startup["ips-cost-growth-research_material_imersite"].value == 2
    and startup["ips-max-level-research_material_imersite"].value == 3
    and startup["ips-research-time-research_material_imersite"].value == 30
    and startup["ips-effect-per-level-research_material_imersite"].value == 2
end
local function assert_retained(label, foreign_enabled)
  if foreign_enabled == nil then foreign_enabled = false end
  if type(foreign_enabled) ~= "boolean" then fail(label .. " invalid foreign observation") end
  local state = storage[KEY]
  if type(state) ~= "table" or state.seed_kind ~= "native-saved-state-not-lab-earned"
      or state.actual_lab_completions ~= 0 or state.k2so_runtime_bridge_exercised ~= false
      or state.source_mir ~= "4.7.21003" or state.fixture_version ~= "0.1.0" then
    fail(label .. " source saved-state witness differs")
  end
  if not settings_match() then fail(label .. " configured Imersite tuning differs") end
  local player_early, player_tail = carrier(game.forces.player, EARLY, 1, label .. " player early"), carrier(game.forces.player, TAIL, 4, label .. " player tail")
  if player_early.level ~= 4 or player_tail.level ~= 6 or player_early.researched or player_tail.researched
      or not player_early.enabled or not player_tail.enabled or player_early.visible_when_disabled
      or player_tail.visible_when_disabled or not close(player_tail.saved_progress, 0)
      or not close(powder_bonus(game.forces.player), 0.10) then
    fail(label .. " player carrier state differs")
  end
  local active = queue(game.forces.player)
  if active.current ~= TAIL or #active.names ~= 2 or active.names[1] ~= TAIL or active.names[2] ~= TAIL
      or not close(active.progress, 0.42) then fail(label .. " player current queue differs") end
  local foreign = game.forces[FOREIGN]
  local foreign_early, foreign_tail = carrier(foreign, EARLY, 1, label .. " foreign early"), carrier(foreign, TAIL, 4, label .. " foreign tail")
  if foreign_early.level ~= 4 or foreign_tail.level ~= 6 or foreign_early.researched or foreign_tail.researched
      or foreign_early.enabled ~= foreign_enabled or foreign_tail.enabled ~= foreign_enabled or foreign_early.visible_when_disabled
      or foreign_tail.visible_when_disabled or not close(foreign_tail.saved_progress, 0.27)
      or not close(powder_bonus(foreign), 0.10) then
    fail(label .. " independently disabled foreign carrier differs")
  end
  local detached = queue(foreign)
  if detached.current ~= false or #detached.names ~= 0 or not close(detached.progress, 0) then
    fail(label .. " foreign queue differs")
  end
  return {player_queue=active, foreign_saved=foreign_tail.saved_progress,
    player_bonus=powder_bonus(game.forces.player), foreign_bonus=powder_bonus(foreign)}
end
local function marker(stage)
  local snapshot = assert_retained("successor marker")
  local owner = storage[KEY].fixture_foreign_owner
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed", qualification="native-runner-readback-required",
    witnesses={source_mir="4.7.21003", destination_mir="5.0.21000", native_saved_state_seeds=true,
      source_actual_lab_completions=0, destination_actual_lab_completions=0,
      k2so_runtime_bridge_exercised=false, successor_retained_before_fixture_writes=owner == nil,
      explicit_fixture_owner_before_mir=owner,
      player_current=snapshot.player_queue.current, player_queue_count=#snapshot.player_queue.names,
      player_research_progress=snapshot.player_queue.progress, player_powder_productivity=snapshot.player_bonus,
      foreign_tail_saved_progress=snapshot.foreign_saved, foreign_disabled=true,
      foreign_powder_productivity=snapshot.foreign_bonus, on_load_read_only=stage == "reload"},
  }))
end

local function configuration_changed(event, expected_version)
  expected_version = expected_version or "0.2.0"
  if expected_version ~= "0.2.0" and expected_version ~= "0.3.0" then fail("unexpected fixture protocol") end
  if script.active_mods.base ~= "2.1.23" or script.active_mods.Krastorio2 ~= "2.1.4"
      or script.active_mods["space-exploration"] ~= "0.7.63" or script.active_mods["Krastorio2-spaced-out"] ~= nil
      or script.active_mods["more-infinite-research"] ~= "5.0.21000" or script.active_mods[FIXTURE] ~= expected_version then
    fail("successor requires exact current K2SE F210 input")
  end
  assert_retained("successor configuration before fixture state write")
  storage[KEY].phase = "successor-retained"
  storage[KEY].destination_mir = "5.0.21000"
end
script.on_configuration_changed(configuration_changed)

script.on_load(function()
  loaded, reported = true, false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("successor fixture state is absent") end
  if state.phase == "successor-retained" then
    assert_retained("successor initial")
    state.phase = "successor-complete"
    marker("initial")
    game.server_save(SAVE)
  elseif state.phase == "successor-complete" and loaded and not reported then
    assert_retained("successor cold reload")
    marker("reload")
    reported = true
  end
end)

return {assert_retained=assert_retained, configuration_changed=configuration_changed}
