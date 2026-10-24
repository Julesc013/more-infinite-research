-- Private native fixture for the one ambiguous historical competing-preference
-- boundary. It proves only the exact F200/Space Age four-provider closure.
local KEY = "mir5_legacy_preference_transition"
local FIXTURE = "mir-fixture-mir5-legacy-preference-transition"
local CASE = "legacy-preference-transition"
local SAVE = "mir5-native-complete"
local ROW = "recipe-prod-research_breeding-1"
local PROBE = "braking-force-1"
local FOREIGN = "mir5-legacy-preference-foreign"
local DEADLINE = 60 * 60 * 10
local UINT32_MAX = 4294967295
local RECIPES = {"biter-egg", "fish-breeding", "pentapod-egg"}
local CARRIER_POSITIVE = "mir-native-credit-research_breeding-fish-breeding-positive"
local CARRIER_NEGATIVE = "mir-native-credit-research_breeding-fish-breeding-negative"
local loaded_snapshot, reload_logged, pending_save = nil, false, false

local function fail(message) error("[mir5-legacy-preference-transition] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= .000001
end
local function tech(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. name) end
  return value
end
local function mode()
  local active = script.active_mods
  if active.base ~= "2.0.77" or active["space-age"] ~= "2.0.77"
      or active["plates-n-circuit-productivity"] ~= "0.0.2"
      or active.Science_packs_productivity ~= "0.0.1"
      or active["bioflux-productivity"] ~= "0.1.0" or active["fish-productivity"] ~= "1.0.0" then
    fail("fixture closure differs")
  end
  local mir, fixture = active["more-infinite-research"], active[FIXTURE]
  local preference = settings.startup["mir-prefer-this-mod-for-competing-techs"]
  if preference == nil or type(preference.value) ~= "boolean" then fail("competing preference setting differs") end
  local published = mir == "4.7.20002" and (fixture == "0.1.0" or fixture == "0.1.1")
  local candidate = mir == "5.0.20000" and (fixture == "0.2.0" or fixture == "0.2.1")
  if not published and not candidate then fail("fixture/MIR version differs") end
  local expected = (fixture == "0.1.1" or fixture == "0.2.1")
  if preference.value ~= expected then fail("fixture preference stage differs") end
  return {published=published, mir=mir, fixture=fixture, preference=expected}
end
local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end
local function snapshot_queue(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=force.current_research and force.current_research.name or false,
    queue=queue, progress=force.research_progress}
end
local function copy_queue(value)
  local queue = {}
  for index, name in ipairs(value.queue) do queue[index] = name end
  return {current=value.current, queue=queue, progress=value.progress}
end
local function assert_queue(force, expected, label)
  local actual = snapshot_queue(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue
      or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue differs at " .. tostring(index)) end
  end
end
local function effect_map(force)
  local values = {}
  for _, recipe in ipairs(RECIPES) do
    local value = force.recipes[recipe]
    if value == nil then fail("recipe is absent: " .. recipe) end
    values[recipe] = value.productivity_bonus
  end
  return values
end
local function expected_effects(preference, completed)
  return {
    ["biter-egg"] = completed * .1,
    ["fish-breeding"] = preference and completed * .1 or 0,
    ["pentapod-egg"] = completed * .1,
  }
end
local function assert_effects(force, expected, label)
  local actual = effect_map(force)
  for _, recipe in ipairs(RECIPES) do
    if not close(actual[recipe], expected[recipe]) then
      fail(label .. " productivity differs: " .. recipe .. " expected=" .. tostring(expected[recipe])
        .. " actual=" .. tostring(actual[recipe]))
    end
  end
end
local function assert_breeding(force, level, label)
  local value = tech(force, ROW)
  if value.level ~= level or value.researched ~= false or value.enabled ~= true
      or value.visible_when_disabled ~= false or value.prototype.max_level ~= UINT32_MAX
      or not close(value.saved_progress, 0) or value.research_unit_count ~= 1
      or not close(value.research_unit_energy, 60) then
    fail(label .. " MIR breeding state differs")
  end
  return value
end
local function fill(lab, value)
  local input = lab.get_inventory(defines.inventory.lab_input)
  if input == nil then fail("lab input is absent") end
  input.clear()
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    if input.insert{name=ingredient.name, count=20} ~= 20 then fail("lab science insertion differs") end
  end
  lab.energy, lab.active = 1000000000, true
end
local function freeze(state)
  local lab = state.lab
  if lab == nil or lab.valid == false then fail("fixture lab is absent") end
  lab.active, lab.energy = false, 0
  local input = lab.get_inventory(defines.inventory.lab_input)
  if input == nil then fail("fixture lab input is absent") end
  input.clear()
end
local function assert_frozen(state)
  local lab = state.lab
  if lab == nil or lab.valid == false or lab.active ~= false or lab.energy ~= 0 then
    fail("fixture lab was not frozen")
  end
  local input = lab.get_inventory(defines.inventory.lab_input)
  if input == nil or input.get_item_count("automation-science-pack") ~= 0 then
    fail("fixture lab retained science")
  end
end
local function carrier(force, name, level, label)
  local value = tech(force, name)
  local effect = value.prototype.effects and value.prototype.effects[1]
  if value.level ~= level or value.researched ~= false or value.enabled ~= false
      or value.visible_when_disabled ~= false or value.prototype.max_level ~= UINT32_MAX
      or value.prototype.hidden ~= true or type(effect) ~= "table"
      or effect.type ~= "change-recipe-productivity" or effect.recipe ~= "fish-breeding" then
    fail(label .. " native-credit carrier differs: " .. name)
  end
  return value
end
local function assert_carriers(force, positive, negative, label)
  carrier(force, CARRIER_POSITIVE, positive, label)
  carrier(force, CARRIER_NEGATIVE, negative, label)
end
local function assert_foreign(state)
  local foreign = game.forces[state.foreign_force]
  if foreign == nil or foreign.valid == false or foreign.name ~= FOREIGN then fail("foreign force is absent") end
  local row = tech(foreign, ROW)
  if row.enabled ~= false or row.visible_when_disabled ~= false then fail("foreign breeding presentation changed") end
  assert_queue(foreign, state.foreign_queue, "foreign")
end
local function assert_source(state)
  if state.source_mir ~= "4.7.20002" or type(state.source_preference) ~= "boolean"
      or state.fixture_version ~= (state.source_preference and "0.1.1" or "0.1.0")
      or state.actual_lab_completions ~= 2 or state.phase ~= "source-complete" then
    fail("published source witness differs")
  end
  local player = game.forces.player
  assert_breeding(player, 3, "published source")
  assert_effects(player, expected_effects(state.source_preference, 2), "published source")
  assert_frozen(state)
  assert_foreign(state)
end
local function assert_baseline(state)
  if state.phase ~= "m5-baselined" or state.m5_baseline_preference ~= state.source_preference
      or state.m5_baseline_startup_settings_changed ~= false then
    fail("unchanged MIR5 first-upgrade witness differs")
  end
  local player = game.forces.player
  assert_breeding(player, 3, "unchanged MIR5 first upgrade")
  assert_effects(player, expected_effects(state.source_preference, 2), "unchanged MIR5 first upgrade")
  assert_carriers(player, 1, 1, "unchanged MIR5 first upgrade")
  assert_frozen(state)
  assert_foreign(state)
end
local function assert_switch_before_lab(state)
  if state.phase ~= "await-switch-lab" or state.m5_switch_startup_settings_changed ~= true
      or state.m5_baseline_preference == state.switch_preference then
    fail("MIR5 preference switch witness differs")
  end
  local player = game.forces.player
  assert_breeding(player, 3, "MIR5 preference switch")
  assert_effects(player, expected_effects(state.source_preference, 2), "MIR5 preference switch")
  if state.source_preference then assert_carriers(player, 3, 1, "MIR5 true-to-false switch")
  else assert_carriers(player, 1, 3, "MIR5 false-to-true switch") end
  assert_foreign(state)
end
local function assert_switch_complete(state)
  if state.phase ~= "m5-switch-complete" or state.actual_switch_labs ~= 1 then
    fail("MIR5 switched successor witness differs")
  end
  local player = game.forces.player
  assert_breeding(player, 4, "MIR5 switched successor")
  local expected = expected_effects(state.source_preference, 2)
  if state.switch_preference then expected["fish-breeding"] = expected["fish-breeding"] + .1 end
  expected["biter-egg"], expected["pentapod-egg"] = expected["biter-egg"] + .1, expected["pentapod-egg"] + .1
  assert_effects(player, expected, "MIR5 switched successor")
  if state.source_preference then assert_carriers(player, 3, 1, "MIR5 switched successor")
  else assert_carriers(player, 1, 3, "MIR5 switched successor") end
  assert_frozen(state)
  assert_foreign(state)
end
local function marker(stage, state)
  local current_preference = state.switch_preference
  if current_preference == nil then current_preference = state.m5_baseline_preference end
  if current_preference == nil then current_preference = state.source_preference end
  local witness = {
    case=CASE, stage=stage, status="passed", source_preference=state.source_preference,
    current_preference=current_preference,
    actual_lab_completions=state.actual_lab_completions, actual_switch_labs=state.actual_switch_labs or 0,
    next_level=tech(game.forces.player, ROW).level,
    biter_egg_bonus=game.forces.player.recipes["biter-egg"].productivity_bonus,
    fish_breeding_bonus=game.forces.player.recipes["fish-breeding"].productivity_bonus,
    pentapod_egg_bonus=game.forces.player.recipes["pentapod-egg"].productivity_bonus,
    foreign_queue_current=state.foreign_queue.current,
    foreign_queue_progress=state.foreign_queue.progress,
  }
  if state.m5_switch_startup_settings_changed ~= nil then
    witness.event_mod_startup_settings_changed = state.m5_switch_startup_settings_changed
  elseif state.m5_baseline_startup_settings_changed ~= nil then
    witness.event_mod_startup_settings_changed = state.m5_baseline_startup_settings_changed
  end
  local positive = game.forces.player.technologies[CARRIER_POSITIVE]
  local negative = game.forces.player.technologies[CARRIER_NEGATIVE]
  if positive ~= nil and negative ~= nil then
    witness.positive_carrier_level, witness.negative_carrier_level = positive.level, negative.level
  end
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json(witness))
end
local function queue_breeding(state, label)
  local player, row = game.forces.player, tech(game.forces.player, ROW)
  fill(state.lab, row)
  if player.add_research(row) ~= true then fail("could not queue " .. label) end
end

script.on_init(function()
  local current = mode()
  if not current.published then return end
  local player = game.forces.player
  local row = tech(player, ROW)
  prerequisites(row)
  -- The captured breeding vector includes agricultural and cryogenic packs;
  -- use the Space Age biolab that accepts that exact vector.
  local lab = game.surfaces[1].create_entity{name="biolab", position={0, 0}, force=player}
  if lab == nil or lab.valid == false then fail("could not create fixture lab") end
  local foreign = game.create_force(FOREIGN)
  local probe = tech(foreign, PROBE)
  prerequisites(probe)
  if foreign.add_research(probe) ~= true then fail("could not queue foreign braking probe") end
  foreign.research_progress = .42
  local foreign_row = tech(foreign, ROW)
  foreign_row.enabled, foreign_row.visible_when_disabled = false, false
  local state = {
    source_mir="4.7.20002", fixture_version=current.fixture, source_preference=current.preference,
    phase="await-source-lab", actual_lab_completions=0, actual_switch_labs=0, lab=lab,
    foreign_force=foreign.index, foreign_queue=snapshot_queue(foreign), deadline_tick=game.tick + DEADLINE,
  }
  storage[KEY] = state
  queue_breeding(state, "first published breeding lab")
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player
      or event.research.name ~= ROW then return end
  if state.phase == "await-source-lab" then
    state.actual_lab_completions = state.actual_lab_completions + 1
    state.phase = state.actual_lab_completions == 2 and "await-source-freeze" or "await-source-next"
  elseif state.phase == "await-switch-lab" then
    state.actual_switch_labs = state.actual_switch_labs + 1
    state.phase = "await-switch-freeze"
  end
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and (state.phase == "source-complete" or state.phase == "m5-baselined"
      or state.phase == "m5-switch-complete") then
    loaded_snapshot = {phase=state.phase, source_preference=state.source_preference,
      baseline=state.m5_baseline_preference, switched=state.switch_preference}
  else loaded_snapshot = nil end
  reload_logged, pending_save = false, false
end)

script.on_configuration_changed(function(event)
  -- The predecessor save always loads before this callback. It is not yet a
  -- candidate cold reload, so discard that local-only witness first.
  loaded_snapshot, reload_logged = nil, false
  local current = mode()
  if current.published then return end
  local state = storage[KEY]
  if type(state) ~= "table" then fail("candidate has no published source witness") end
  if state.phase == "source-complete" then
    if current.preference ~= state.source_preference then
      fail("simultaneous first preference switch reached fixture after MIR guard")
    end
    if event.mod_startup_settings_changed ~= false then
      fail("unchanged first upgrade reported startup settings changed")
    end
    assert_source(state)
    state.m5_baseline_preference = current.preference
    state.m5_baseline_startup_settings_changed = event.mod_startup_settings_changed
    state.phase, pending_save = "m5-baselined", true
    assert_baseline(state)
  elseif state.phase == "m5-baselined" then
    if current.preference == state.m5_baseline_preference then fail("MIR5 preference did not switch") end
    if event.mod_startup_settings_changed ~= true then fail("MIR5 preference switch event differs") end
    state.switch_preference = current.preference
    state.m5_switch_startup_settings_changed = event.mod_startup_settings_changed
    state.phase = "await-switch-lab"
    state.deadline_tick = game.tick + DEADLINE
    assert_switch_before_lab(state)
    queue_breeding(state, "MIR5 switched breeding lab")
  else
    fail("unexpected candidate transition phase")
  end
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then return end
  if pending_save then
    if state.phase == "m5-baselined" then assert_baseline(state)
    elseif state.phase == "m5-switch-complete" then assert_switch_complete(state)
    elseif state.phase == "source-complete" then assert_source(state)
    else fail("unexpected pending save phase") end
    marker("initial", state)
    game.server_save(SAVE)
    pending_save = false
    return
  end
  if loaded_snapshot and not reload_logged then
    if loaded_snapshot.phase == "source-complete" then assert_source(state)
    elseif loaded_snapshot.phase == "m5-baselined" then assert_baseline(state)
    elseif loaded_snapshot.phase == "m5-switch-complete" then assert_switch_complete(state)
    else fail("cold reload phase differs") end
    marker("reload", state)
    reload_logged = true
    return
  end
  if state.phase == "source-complete" or state.phase == "m5-baselined" or state.phase == "m5-switch-complete" then return end
  if game.tick > state.deadline_tick then fail("fixture did not complete bounded native research") end
  if state.phase == "await-source-next" and game.forces.player.current_research == nil
      and #(game.forces.player.research_queue or {}) == 0 then
    state.phase = "await-source-lab"
    queue_breeding(state, "second published breeding lab")
  elseif state.phase == "await-source-freeze" then
    freeze(state)
    state.phase, pending_save = "source-complete", true
    assert_source(state)
  elseif state.phase == "await-switch-freeze" then
    freeze(state)
    state.phase, pending_save = "m5-switch-complete", true
    assert_switch_complete(state)
  elseif state.phase == "await-source-lab" or state.phase == "await-switch-lab" then
    state.lab.energy = 1000000000
  end
end)
