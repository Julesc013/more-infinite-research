-- One private F200 ATAN gameplay scenario.  It completes the two distinct
-- owned MIR research rows in one run.  Space Age's two ATAN native owners
-- deliberately remain one shared clean-filter continuation/effect vector.
local KEY = "mir5_atan_gameplay"
local CASE = "f200-atan-gameplay"
local FIXTURE = "mir-fixture-mir5-atan-gameplay"
local SAVE = "mir5-native-complete"
local AIR = "recipe-prod-research_air_scrubbing_clean_filter-1"
local ASH = "recipe-prod-research_ash_separation-1"
local PROBE = "braking-force-1"
local DEADLINE = 60 * 60 * 10

local loaded = false

local function fail(message)
  error("[mir5-atan-gameplay] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then
    fail("technology is absent: " .. tostring(name))
  end
  return value
end

local function recipe_bonus(force, name)
  local value = force and force.recipes and force.recipes[name]
  if value == nil or value.valid == false or type(value.productivity_bonus) ~= "number" then
    fail("recipe productivity fact is absent: " .. tostring(name))
  end
  return value.productivity_bonus
end

local function profile()
  local active = script.active_mods
  if active.base ~= "2.0.77" or active["atan-air-scrubbing"] ~= "0.2.8"
      or active["atan-ash"] ~= "2.2.1" or active["more-infinite-research"] ~= "5.0.20000"
      or active[FIXTURE] ~= "0.1.0" or active["mir-fixture-mir5-active-mods-observer"] ~= "0.1.0" then
    fail("fixture closure differs")
  end
  if active["space-age"] == nil then
    if active["elevated-rails"] ~= nil or active.quality ~= nil then
      fail("Base closure contains Space Age companions")
    end
    return {name="base", lab="lab", air_recipes={"atan-pollution-filter"},
      owners={"atan-pollution-scrubbing", "automation-3"}}
  end
  if active["space-age"] ~= "2.0.77" or active["elevated-rails"] ~= "2.0.77" or active.quality ~= "2.0.77" then
    fail("Space Age closure differs")
  end
  return {name="space-age", lab="biolab", air_recipes={"atan-pollution-filter", "atan-spore-filter"},
    owners={"atan-pollution-scrubbing", "atan-spore-scrubbing", "automation-3"}}
end

local function research_prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end

local function assert_owners(force, selected, label)
  for _, name in ipairs(selected.owners) do
    if technology(force, name).researched ~= true then fail(label .. " native owner is not researched: " .. name) end
  end
end

local function assert_technology(force, name, level, label)
  local value = technology(force, name)
  if value.level ~= level or value.researched ~= false or value.enabled ~= true
      or value.visible_when_disabled ~= false or value.prototype.max_level ~= 4294967295 then
    fail(label .. " technology state differs: " .. name)
  end
  return value
end

local function assert_effects(force, selected, air, ash, label)
  for _, recipe in ipairs(selected.air_recipes) do
    if not close(recipe_bonus(force, recipe), air) then
      fail(label .. " clean-filter productivity differs: " .. recipe)
    end
  end
  if not close(recipe_bonus(force, "atan-ash-seperation"), ash) then
    fail(label .. " ash productivity differs")
  end
end

local function queue_snapshot(force)
  local queued = {}
  for index, value in ipairs(force.research_queue or {}) do queued[index] = value.name end
  return {current=force.current_research and force.current_research.name or false,
    queued=queued, progress=force.research_progress}
end

local function assert_probe_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= PROBE or #actual.queued ~= 1 or actual.queued[1] ~= PROBE
      or not close(actual.progress, expected.progress) then
    fail(label .. " shared queue/progress differs")
  end
end

local function fill(lab, value)
  local inventory = lab and lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("lab input is absent") end
  inventory.clear()
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    local inserted = inventory.insert{name=ingredient.name, count=100}
    if inserted ~= 100 then fail("lab did not receive science: " .. ingredient.name) end
  end
  lab.energy, lab.active = 1000000000, true
end

local function freeze(lab)
  if lab == nil or lab.valid == false then fail("lab is absent") end
  lab.active, lab.energy = false, 0
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("lab input is absent while freezing") end
  inventory.clear()
end

local function marker(stage, state, detail)
  local player, selected = game.forces.player, state.selected
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed", qualification="bounded-atan-gameplay",
    witnesses={profile=selected.name, completed=state.actual_lab_completions,
      air_next_level=technology(player, AIR).level, ash_next_level=technology(player, ASH).level,
      air_effects=selected.air_recipes, air_bonus=recipe_bonus(player, selected.air_recipes[1]),
      ash_bonus=recipe_bonus(player, "atan-ash-seperation"), queue=queue_snapshot(player), detail=detail}
  }))
end

local function assert_completed(state, label)
  local player, selected = game.forces.player, state.selected
  if state.phase ~= "completed" or state.actual_lab_completions ~= 2 then
    fail(label .. " native completion count differs")
  end
  assert_owners(player, selected, label)
  assert_technology(player, AIR, 2, label)
  assert_technology(player, ASH, 2, label)
  assert_effects(player, selected, 0.05, 0.05, label)
  assert_probe_queue(player, state.queue, label)
  if state.lab == nil or state.lab.valid == false or state.lab.active ~= false or state.lab.energy ~= 0 then
    fail(label .. " completed lab state differs")
  end
end

script.on_init(function()
  local selected = profile()
  if storage[KEY] ~= nil then fail("fixture state already exists") end
  game.speed = 16
  local player, air, ash, probe = game.forces.player, technology(game.forces.player, AIR),
    technology(game.forces.player, ASH), technology(game.forces.player, PROBE)
  research_prerequisites(air)
  research_prerequisites(ash)
  research_prerequisites(probe)
  assert_owners(player, selected, "initial")
  assert_technology(player, AIR, 1, "initial")
  assert_technology(player, ASH, 1, "initial")
  assert_effects(player, selected, 0, 0, "initial")

  local lab = game.surfaces[1].create_entity{name=selected.lab, position={0, 0}, force=player}
  if lab == nil or lab.valid == false then fail("could not create selected native lab") end
  fill(lab, air)
  if player.add_research(air) ~= true or player.add_research(ash) ~= true or player.add_research(probe) ~= true then
    fail("could not queue the shared ATAN research sequence")
  end
  storage[KEY] = {phase="await-air-lab", selected=selected, lab=lab,
    actual_lab_completions=0, deadline_tick=game.tick + DEADLINE}
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player then return end
  local player = game.forces.player
  if state.phase == "await-air-lab" and event.research.name == AIR then
    state.actual_lab_completions = state.actual_lab_completions + 1
    assert_technology(player, AIR, 2, "clean-filter completion")
    assert_technology(player, ASH, 1, "clean-filter completion")
    assert_effects(player, state.selected, 0.05, 0, "clean-filter completion")
    fill(state.lab, technology(player, ASH))
    state.phase = "await-ash-lab"
  elseif state.phase == "await-ash-lab" and event.research.name == ASH then
    state.actual_lab_completions = state.actual_lab_completions + 1
    freeze(state.lab)
    -- Factorio advances the queued research after this callback.  Do not
    -- mistake the just-finished ash research for the retained probe queue.
    state.phase = "await-completed-observation"
  end
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "completed"
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then return end
  if state.phase == "await-completed-observation" then
    state.phase, state.queue = "completed", queue_snapshot(game.forces.player)
    assert_completed(state, "post-ash queue observation")
    marker("initial", state, "two-owned-rows-one-shared-air-continuation")
    game.server_save(SAVE)
    return
  end
  if loaded then
    assert_completed(state, "cold reload")
    marker("reload", state, "ATAN effects-and-queue-survived-cold-load")
    loaded = false
    return
  end
  if state.phase == "await-air-lab" or state.phase == "await-ash-lab" then
    if state.lab == nil or state.lab.valid == false then fail("lab disappeared while awaiting research") end
    state.lab.energy = 1000000000
  end
  if state.phase ~= "completed" and game.tick > state.deadline_tick then
    fail("ATAN native research did not complete before bounded deadline")
  end
end)
