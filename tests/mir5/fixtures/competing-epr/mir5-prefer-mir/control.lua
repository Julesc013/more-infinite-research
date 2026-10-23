local KEY = "mir5_competing_epr"
local CASE = "f200-competing-epr-continuity"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-competing-epr"
local TAIL = "epr_iron-gear-wheel-productivity-5"
local RECIPE = "iron-gear-wheel"
local PROBE = "braking-force-1"
local FOREIGN = "mir5-competing-epr-foreign"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "space-science-pack",
}
local EPR_TAILS = {
  "epr_advanced-circuit-productivity-5", "epr_automation-science-pack-productivity-5", "epr_battery-productivity-5", "epr_chemical-science-pack-productivity-5", "epr_copper-cable-productivity-5", "epr_copper-plate-productivity-5", "epr_electric-engine-unit-productivity-4", "epr_electronic-circuit-productivity-5", "epr_engine-unit-productivity-5", "epr_explosives-productivity-5", "epr_flying-robot-frame-productivity-4", "epr_heavy-oil-productivity-4", "epr_iron-gear-wheel-productivity-5", "epr_iron-plate-productivity-5", "epr_iron-stick-productivity-5", "epr_light-oil-productivity-4", "epr_logistic-science-pack-productivity-5", "epr_low-density-structure-productivity-4", "epr_lubricant-productivity-4", "epr_military-science-pack-productivity-5", "epr_petroleum-gas-productivity-5", "epr_plastic-bar-productivity-5", "epr_processing-unit-productivity-4", "epr_production-science-pack-productivity-4", "epr_rocket-fuel-productivity-4", "epr_steel-plate-productivity-5", "epr_stone-brick-productivity-5", "epr_sulfur-productivity-5", "epr_sulfuric-acid-productivity-5", "epr_utility-science-pack-productivity-4",
}
local UINT32_MAX = 4294967295
local loaded_snapshot, reload_logged = nil, false

local function fail(message) error("[mir5-competing-epr-prefer-mir] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and type(expected) == "number" and math.abs(actual - expected) <= 0.000001
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. tostring(name)) end
  return value
end
local function assert_retained(force, label)
  for _, name in ipairs(EPR_TAILS) do
    local value = technology(force, name)
    if value.name ~= name or value.prototype.max_level ~= UINT32_MAX then
      fail(label .. " did not retain captured EPR tail " .. name)
    end
  end
end
local function tail_status(force)
  local value = technology(force, TAIL)
  local recipe = force.recipes[RECIPE]
  if recipe == nil then fail("gear recipe is absent for " .. tostring(force.name)) end
  return {level=value.level, researched=value.researched, enabled=value.enabled, visible=value.visible_when_disabled,
    maximum=value.prototype.max_level, bonus=recipe.productivity_bonus, saved_progress=value.saved_progress}
end
local function copy_status(value)
  return {level=value.level, researched=value.researched, enabled=value.enabled, visible=value.visible,
    maximum=value.maximum, bonus=value.bonus, saved_progress=value.saved_progress}
end
local function assert_tail(actual, expected, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.enabled ~= expected.enabled or actual.visible ~= expected.visible
      or actual.maximum ~= expected.maximum or not close(actual.bonus, expected.bonus) then
    fail(label .. " EPR tail state differs")
  end
  if expected.saved_progress ~= nil and not close(actual.saved_progress, expected.saved_progress) then
    fail(label .. " EPR tail saved progress differs")
  end
end
local function queue_snapshot(force)
  local queued = {}
  for index, value in ipairs(force.research_queue or {}) do queued[index] = value.name end
  return {current=force.current_research and force.current_research.name or false, queue=queued, progress=force.research_progress}
end
local function copy_queue(value)
  local queued = {}
  for index, name in ipairs(value.queue or {}) do queued[index] = name end
  return {current=value.current, queue=queued, progress=value.progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue or progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue changed at " .. tostring(index)) end
  end
  return actual
end
local function assert_acceleration(value)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not retain one-unit one-second EPR tail research")
  end
  for _, item in ipairs(SCIENCE) do
    local found = false
    for _, ingredient in ipairs(value.research_unit_ingredients) do
      if ingredient.name == item and ingredient.amount == 1 then found = true end
    end
    if not found then fail("native EPR science is absent: " .. item) end
  end
end
local function assert_frozen(state)
  local lab = state.lab
  if lab == nil or lab.valid == false or lab.active ~= false or lab.energy ~= 0 then
    fail("source lab was not frozen before MIR5 preference handling")
  end
  local input = lab.get_inventory(defines.inventory.lab_input)
  if input == nil then fail("source lab input is absent") end
  for _, item in ipairs(SCIENCE) do
    if input.get_item_count(item) ~= 0 then fail("source lab retained input after freeze: " .. item) end
  end
end
local function assert_source(state)
  if type(state) ~= "table" then fail("published EPR source witness is absent") end
  if state.source_mir ~= "4.7.20002" or state.fixture_version ~= "0.1.0" then
    fail("published EPR source identity differs")
  end
  if (state.phase ~= "source-completed" and state.phase ~= "prefer-mir-completed")
      or state.actual_lab_completions ~= 2 or state.milestone ~= "two-native-epr-tail-labs"
      or state.prerequisite_seeding ~= "completed-before-native-tail-labs" then
    fail("published EPR source completion witness differs")
  end
  if type(state.player_queue) ~= "table" or state.player_queue.current ~= TAIL
      or #state.player_queue.queue ~= 2 or state.player_queue.queue[1] ~= TAIL
      or state.player_queue.queue[2] ~= PROBE or not close(state.player_queue.progress, 0.27) then
    fail("published EPR source queue witness is absent")
  end
  if not close(state.player_bonus, state.player_start_bonus + 0.2) then fail("published EPR earned effect witness is absent") end
end
local function assert_foreign(state)
  local force = game.forces[state.foreign_force_index]
  if force == nil or force.valid == false or force.name ~= FOREIGN then fail("foreign force witness is absent") end
  assert_retained(force, "foreign")
  for _, name in ipairs(EPR_TAILS) do
    local foreign_tail = technology(force, name)
    if foreign_tail.enabled ~= false or foreign_tail.visible_when_disabled ~= true then
      fail("foreign EPR tail presentation changed: " .. name)
    end
  end
  assert_tail(tail_status(force), {level=5, researched=false, enabled=false, visible=true,
    maximum=UINT32_MAX, bonus=state.foreign_bonus, saved_progress=0}, "foreign")
  assert_queue(force, state.foreign_queue, "foreign")
end
local function assert_preferred(state)
  assert_source(state)
  local player = game.forces.player
  assert_retained(player, "player")
  assert_tail(tail_status(player), {level=7, researched=false, enabled=false, visible=true,
    maximum=UINT32_MAX, bonus=state.player_bonus, saved_progress=0.27}, "MIR5 preferred player")
  assert_queue(player, {current=PROBE, queue={PROBE}, progress=0.42}, "MIR5 preferred player")
  if not close(technology(player, PROBE).saved_progress, 0.42) then fail("MIR5 changed retained braking progress") end
  assert_acceleration(technology(player, TAIL))
  assert_frozen(state)
  assert_foreign(state)
end
local function marker(stage, state)
  local player = tail_status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage=stage, case=CASE, status="passed", qualification="native-runner-readback-required",
    witnesses={source_mir=state.source_mir, destination_mir=script.active_mods["more-infinite-research"],
      source_actual_lab_completions=state.actual_lab_completions, tail=TAIL, tail_next_level=player.level,
      productivity_bonus=player.bonus, tail_saved_progress=player.saved_progress,
      player_disabled=player.enabled == false, player_visible_when_disabled=player.visible,
      braking_saved_progress=technology(game.forces.player, PROBE).saved_progress,
      player_queue=queue_snapshot(game.forces.player).queue, foreign_disabled=tail_status(game.forces[state.foreign_force_index]).enabled == false,
      retained_epr_tail_count=#EPR_TAILS, lab_frozen=true, on_load_read_only=stage == "reload"},
  }))
end

script.on_configuration_changed(function()
  if script.active_mods.base ~= "2.0.77" or script.active_mods.ExpandedProductivityResearch ~= "1.3.8"
      or script.active_mods["more-infinite-research"] ~= "5.0.20000" or script.active_mods[FIXTURE] ~= "0.2.0" then
    fail("preferred successor requires EPR 1.3.8, MIR5 5.0.20000, and fixture 0.2.0 on Factorio 2.0.77")
  end
  if settings.startup["mir-prefer-this-mod-for-competing-techs"].value ~= true then
    fail("preferred successor requires the MIR preference")
  end
  local state = storage[KEY]
  assert_preferred(state) -- must observe the runtime reconciliation before writing fixture state.
  state.phase = "prefer-mir-completed"
  state.preferred_player = copy_status(tail_status(game.forces.player))
  state.preferred_queue = copy_queue(queue_snapshot(game.forces.player))
  marker("initial", state)
  game.server_save(SAVE)
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "prefer-mir-completed" then
    loaded_snapshot = {player=copy_status(state.preferred_player), queue=copy_queue(state.preferred_queue), labs=state.actual_lab_completions}
  else loaded_snapshot = nil end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("preferred successor fixture storage is absent") end
  if state.phase == "prefer-mir-completed" and loaded_snapshot and not reload_logged then
    assert_preferred(state)
    assert_tail(tail_status(game.forces.player), loaded_snapshot.player, "preferred cold reload player")
    assert_queue(game.forces.player, loaded_snapshot.queue, "preferred cold reload player")
    if loaded_snapshot.labs ~= state.actual_lab_completions then fail("cold reload changed source lab count") end
    marker("reload", state)
    reload_logged = true
  end
end)
