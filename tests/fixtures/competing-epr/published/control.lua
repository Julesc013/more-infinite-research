local KEY = "mir5_competing_epr"
local CASE = "f200-competing-epr-continuity"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-competing-epr"
local TAIL = "epr_iron-gear-wheel-productivity-5"
local PREDECESSOR = "epr_iron-gear-wheel-productivity-4"
local RECIPE = "iron-gear-wheel"
local PROBE = "braking-force-1"
local FOREIGN = "mir5-competing-epr-foreign"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "space-science-pack",
}
local EPR_TAILS = {
  "epr_advanced-circuit-productivity-5", "epr_automation-science-pack-productivity-5",
  "epr_battery-productivity-5", "epr_chemical-science-pack-productivity-5",
  "epr_copper-cable-productivity-5", "epr_copper-plate-productivity-5",
  "epr_electric-engine-unit-productivity-4", "epr_electronic-circuit-productivity-5",
  "epr_engine-unit-productivity-5", "epr_explosives-productivity-5",
  "epr_flying-robot-frame-productivity-4", "epr_heavy-oil-productivity-4",
  "epr_iron-gear-wheel-productivity-5", "epr_iron-plate-productivity-5",
  "epr_iron-stick-productivity-5", "epr_light-oil-productivity-4",
  "epr_logistic-science-pack-productivity-5", "epr_low-density-structure-productivity-4",
  "epr_lubricant-productivity-4", "epr_military-science-pack-productivity-5",
  "epr_petroleum-gas-productivity-5", "epr_plastic-bar-productivity-5",
  "epr_processing-unit-productivity-4", "epr_production-science-pack-productivity-4",
  "epr_rocket-fuel-productivity-4", "epr_steel-plate-productivity-5",
  "epr_stone-brick-productivity-5", "epr_sulfur-productivity-5",
  "epr_sulfuric-acid-productivity-5", "epr_utility-science-pack-productivity-4",
}
local UINT32_MAX = 4294967295
local LAB_ENERGY = 100000000
local INITIAL_PACKS = 16
local DEADLINE = 24000
local loaded_snapshot, reload_logged = nil, false

local function fail(message) error("[mir5-competing-epr-published] " .. message) end
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
  return {level=value.level, researched=value.researched, enabled=value.enabled,
    visible=value.visible_when_disabled, maximum=value.prototype.max_level,
    bonus=recipe.productivity_bonus, saved_progress=value.saved_progress}
end
local function copy_status(value)
  return {level=value.level, researched=value.researched, enabled=value.enabled,
    visible=value.visible, maximum=value.maximum, bonus=value.bonus, saved_progress=value.saved_progress}
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
local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end
local function queue_snapshot(force)
  local queued = {}
  for index, value in ipairs(force.research_queue or {}) do queued[index] = value.name end
  return {current=force.current_research and force.current_research.name or false,
    queue=queued, progress=force.research_progress}
end
local function copy_queue(value)
  local queued = {}
  for index, name in ipairs(value.queue or {}) do queued[index] = name end
  return {current=value.current, queue=queued, progress=value.progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue
      or not close(actual.progress, expected.progress) then fail(label .. " queue or progress differs") end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue changed at " .. tostring(index)) end
  end
  return actual
end
local function inventory(state)
  local lab = state.lab
  if lab == nil or lab.valid == false then fail("real player lab is absent") end
  local value = lab.get_inventory(defines.inventory.lab_input)
  if value == nil then fail("real player lab input inventory is absent") end
  return value
end
local function power_lab(state)
  local lab = state.lab
  if lab == nil or lab.valid == false then fail("real player lab is absent") end
  lab.energy = LAB_ENERGY
  if lab.energy <= 0 or lab.active == false then fail("real player lab cannot consume native science") end
  return inventory(state)
end
local function fill(value)
  for _, item in ipairs(SCIENCE) do
    local inserted = value.insert{name=item, count=INITIAL_PACKS}
    if inserted ~= INITIAL_PACKS then fail("could not insert native science " .. item) end
  end
end
local function assert_acceleration(value)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not reduce only EPR tail count and time")
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
  local value = inventory(state)
  if state.lab.disabled_by_script ~= true or state.lab.energy ~= 0 then fail("source lab was not frozen before cap configuration") end
  for _, item in ipairs(SCIENCE) do
    if value.get_item_count(item) ~= 0 then fail("source lab retained input after freeze: " .. item) end
  end
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
local function assert_source(state)
  if state.source_mir ~= "4.7.20002" or state.fixture_version ~= "0.1.0"
      or state.phase ~= "source-completed" or state.actual_lab_completions ~= 2
      or state.milestone ~= "two-native-epr-tail-labs"
      or state.prerequisite_seeding ~= "completed-before-native-tail-labs" then
    fail("published EPR source witness is absent or malformed")
  end
  local player = game.forces.player
  assert_retained(player, "player")
  -- The current queue entry owns its effective progress on LuaForce.  Its
  -- LuaTechnology.saved_progress must be empty; queued braking remains inactive.
  assert_tail(tail_status(player), {level=7, researched=false, enabled=true, visible=false,
    maximum=UINT32_MAX, bonus=state.player_bonus, saved_progress=0}, "published player")
  assert_queue(player, state.player_queue, "published player")
  if state.player_queue.current ~= TAIL or #state.player_queue.queue ~= 2
      or state.player_queue.queue[1] ~= TAIL or state.player_queue.queue[2] ~= PROBE
      or not close(state.player_queue.progress, 0.27) then fail("source current EPR progress witness differs") end
  if not close(state.player_current_saved_progress, 0) then fail("source current EPR raw progress witness differs") end
  if not close(technology(player, PROBE).saved_progress, 0.42)
      or not close(state.braking_inactive_saved_progress, 0.42) then
    fail("source inactive braking progress witness differs")
  end
  assert_frozen(state)
  assert_foreign(state)
end
local function marker(stage, state)
  local player = tail_status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage=stage, case=CASE, status="passed", qualification="native-runner-readback-required",
    witnesses={source_mir=state.source_mir, fixture_version=state.fixture_version,
      actual_lab_completions=state.actual_lab_completions, prerequisite_seeding=state.prerequisite_seeding,
      tail=TAIL, tail_next_level=player.level, productivity_bonus=player.bonus,
      tail_saved_progress=player.saved_progress, current_research_progress=queue_snapshot(game.forces.player).progress,
      braking_saved_progress=technology(game.forces.player, PROBE).saved_progress,
      player_queue=state.player_queue.queue, foreign_disabled=tail_status(game.forces[state.foreign_force_index]).enabled == false,
      retained_epr_tail_count=#EPR_TAILS, lab_frozen=true, on_load_read_only=stage == "reload"},
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.0.77" or script.active_mods.ExpandedProductivityResearch ~= "1.3.8"
      or script.active_mods["more-infinite-research"] ~= "4.7.20002" or script.active_mods[FIXTURE] ~= "0.1.0" then
    fail("source requires EPR 1.3.8, published MIR 4.7.20002, and fixture 0.1.0 on Factorio 2.0.77")
  end
  if settings.startup["mir-prefer-this-mod-for-competing-techs"].value ~= false then
    fail("source fixture requires the captured foreign EPR preference")
  end
  if storage[KEY] ~= nil then fail("source fixture storage already exists") end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  assert_retained(player, "player")
  local tail = technology(player, TAIL)
  assert_acceleration(tail)
  prerequisites(tail)
  local before = tail_status(player)
  assert_tail(before, {level=5, researched=false, enabled=true, visible=false,
    maximum=UINT32_MAX, bonus=before.bonus, saved_progress=0}, "published pre-lab player")

  local foreign = game.create_force(FOREIGN)
  foreign.enable_all_prototypes()
  assert_retained(foreign, "foreign")
  local foreign_tail = technology(foreign, TAIL)
  prerequisites(foreign_tail)
  local foreign_bonus = tail_status(foreign).bonus
  for _, name in ipairs(EPR_TAILS) do
    local disabled = technology(foreign, name)
    disabled.enabled = false
    disabled.visible_when_disabled = true
  end
  local probe = technology(foreign, PROBE)
  prerequisites(probe)
  if probe.researched then fail("foreign braking probe was already researched") end
  -- Seed while inactive.  Assigning the queue makes braking current and
  -- transfers this value to LuaForce.research_progress.
  probe.saved_progress = 0.42
  if foreign.add_research(probe) ~= true then fail("could not queue foreign braking probe") end
  local foreign_queue = assert_queue(foreign, {current=PROBE, queue={PROBE}, progress=0.42}, "foreign setup")
  if not close(probe.saved_progress, 0) then fail("foreign current braking retained raw saved progress") end

  local lab = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=player}
  if lab == nil or lab.valid == false then fail("could not create real player lab") end
  local state = {phase="await-first-lab", source_mir=script.active_mods["more-infinite-research"],
    fixture_version=script.active_mods[FIXTURE], actual_lab_completions=0,
    milestone="prerequisites-seeded", prerequisite_seeding="completed-before-native-tail-labs",
    player_start_bonus=before.bonus, foreign_bonus=foreign_bonus,
    foreign_force_index=foreign.index, foreign_queue=foreign_queue,
    foreign_current_saved_progress=probe.saved_progress, lab=lab, deadline_tick=game.tick + DEADLINE}
  storage[KEY] = state
  fill(power_lab(state))
  if player.add_research(tail) ~= true then fail("could not queue first native EPR tail research") end
  assert_queue(player, {current=TAIL, queue={TAIL}, progress=0}, "first EPR lab")
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player
      or event.research.name ~= TAIL then return end
  if state.phase ~= "await-first-lab" and state.phase ~= "await-second-lab" then
    fail("unexpected native EPR tail completion phase")
  end
  state.actual_lab_completions = state.actual_lab_completions + 1
  if state.actual_lab_completions == 1 then state.phase = "await-second-queue"
  elseif state.actual_lab_completions == 2 then state.phase = "await-source-freeze"
  else fail("source completed more than two native EPR tail levels") end
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "source-completed" then
    loaded_snapshot = {player=copy_status(state.player_tail), queue=copy_queue(state.player_queue),
      foreign=copy_queue(state.foreign_queue), labs=state.actual_lab_completions}
  else loaded_snapshot = nil end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("source fixture storage is absent") end
  if state.phase == "source-completed" then
    if loaded_snapshot and not reload_logged then
      assert_source(state)
      assert_tail(tail_status(game.forces.player), loaded_snapshot.player, "source cold reload player")
      assert_queue(game.forces.player, loaded_snapshot.queue, "source cold reload player")
      assert_queue(game.forces[state.foreign_force_index], loaded_snapshot.foreign, "source cold reload foreign")
      if loaded_snapshot.labs ~= state.actual_lab_completions then fail("cold reload changed source lab count") end
      marker("reload", state); reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("source lab did not complete two EPR tail levels") end
  if state.phase == "await-second-queue" then
    local player = game.forces.player
    if player.current_research == nil and #player.research_queue == 0 then
      if player.add_research(technology(player, TAIL)) ~= true then fail("could not queue second native EPR tail research") end
      assert_queue(player, {current=TAIL, queue={TAIL}, progress=0}, "second EPR lab")
      state.phase = "await-second-lab"
    end
    return
  end
  if state.phase == "await-source-freeze" then
    local player = game.forces.player
    local now = tail_status(player)
    assert_tail(now, {level=7, researched=false, enabled=true, visible=false, maximum=UINT32_MAX,
      bonus=state.player_start_bonus + 0.2, saved_progress=0}, "two native EPR labs")
    local input = inventory(state)
    state.lab.disabled_by_script = true
    state.lab.energy = 0
    input.clear()
    local probe = technology(player, PROBE)
    prerequisites(probe)
    if probe.researched then fail("unrelated braking probe was already researched by prerequisite seeding") end
    technology(player, TAIL).saved_progress = 0.27
    probe.saved_progress = 0.42
    player.research_queue = {technology(player, TAIL), probe}
    player.research_progress = 0.27
    state.player_bonus = now.bonus
    state.player_queue = assert_queue(player, {current=TAIL, queue={TAIL, PROBE}, progress=0.27}, "source seeded queue")
    -- Factorio transfers the first queued technology's saved progress to the
    -- force.  Keep raw inactive braking progress separately as the successor
    -- will make braking current after removing the EPR tail.
    state.player_current_saved_progress = technology(player, TAIL).saved_progress
    state.braking_inactive_saved_progress = probe.saved_progress
    state.milestone = "two-native-epr-tail-labs"
    state.phase = "source-completed"
    state.player_tail = copy_status(tail_status(player))
    assert_source(state)
    marker("initial", state)
    game.server_save(SAVE)
  else
    power_lab(state)
  end
end)
