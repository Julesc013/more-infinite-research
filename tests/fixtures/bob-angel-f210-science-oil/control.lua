local facts = require("__mir-fixture-mir5-bob-angel-f210-science-oil__/fixture_facts")
local KEY, SAVE = "mir5_bob_angel_f210_science_oil", "mir5-native-complete"
local loaded, reload_reported = false, false

local function fail(message, fields)
  if helpers and helpers.table_to_json and log then
    log("[MIR5_NATIVE_FIXTURE] DIAGNOSTIC " .. helpers.table_to_json({case="bob-angel-f210-science-oil", status="failed", error=message, fields=fields}))
  end
  error("[mir5-bob-angel-f210-science-oil] " .. message)
end
local function close(actual, expected) return type(actual) == "number" and math.abs(actual - expected) <= .0000001 end
local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. tostring(name)) end
  return value
end
local function closure()
  local expected = facts.closure(script.active_mods)
  for name, version in pairs(expected.mods) do
    if script.active_mods[name] ~= version then fail("runtime closure differs: " .. name) end
  end
  for name in pairs(script.active_mods) do if expected.mods[name] == nil then fail("unexpected runtime mod: " .. name) end end
  return expected
end
local function effect_vector(value, expected, label)
  local effects = value.prototype and value.prototype.effects
  if type(effects) ~= "table" or #effects ~= #expected then fail(label .. " effect count differs") end
  for index, wanted in ipairs(expected) do
    local effect = effects[index]
    if type(effect) ~= "table" or effect.type ~= wanted.type or effect.recipe ~= wanted.recipe
        or not close(effect.change, wanted.change) then fail(label .. " effect differs at " .. tostring(index)) end
  end
end
local function input_vector(value, expected, label)
  local inputs = value.research_unit_ingredients
  if type(inputs) ~= "table" or #inputs ~= #expected then fail(label .. " ingredient count differs") end
  for index, name in ipairs(expected) do
    local input = inputs[index]
    if type(input) ~= "table" or input.name ~= name or input.amount ~= 1 then
      fail(label .. " ingredient differs at " .. tostring(index))
    end
  end
end
local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=force.current_research and force.current_research.name or false, queue=queue, progress=force.research_progress}
end
local function same_queue(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or left.current ~= right.current
      or #left.queue ~= #right.queue or not close(left.progress, right.progress) then return false end
  for index, name in ipairs(left.queue) do if right.queue[index] ~= name then return false end end
  return true
end
local function bonuses(force, effects, expected)
  local values = {}
  for _, effect in ipairs(effects) do
    local recipe = force.recipes and force.recipes[effect.recipe]
    if recipe == nil or type(recipe.productivity_bonus) ~= "number" then fail("native recipe bonus is absent: " .. effect.recipe) end
    if not close(recipe.productivity_bonus, expected) then fail("native recipe bonus differs: " .. effect.recipe) end
    values[effect.recipe] = recipe.productivity_bonus
  end
  return values
end
local function oil_snapshot(force, level, saved, label)
  local value = technology(force, facts.oil)
  effect_vector(value, facts.oil_effects, label .. " oil")
  if value.level ~= level or value.researched ~= false or value.enabled ~= false
      or value.visible_when_disabled ~= true or not close(value.saved_progress, saved)
      or value.prototype.max_level ~= 4294967295 then
    fail(label .. " oil saved identity differs", {
      expected={level=level, researched=false, enabled=false, visible_when_disabled=true,
        saved_progress=saved, prototype_max_level=4294967295},
      actual={level=value.level, researched=value.researched, enabled=value.enabled,
        visible_when_disabled=value.visible_when_disabled, saved_progress=value.saved_progress,
        prototype_max_level=value.prototype.max_level},
    })
  end
  return {level=value.level, enabled=value.enabled, visible=value.visible_when_disabled, saved_progress=value.saved_progress,
    bonuses=bonuses(force, facts.oil_effects, .1 * (level - 1)), queue=queue_snapshot(force)}
end
local function science_snapshot(force, expected, level, label)
  local value = technology(force, facts.science)
  effect_vector(value, expected.effects, label .. " science")
  input_vector(value, expected.vector, label .. " science")
  if value.level ~= level or value.researched ~= false or value.prototype.max_level ~= 4294967295 then
    fail(label .. " science level differs")
  end
  return {level=value.level, bonuses=bonuses(force, expected.effects, .1 * (level - 1))}
end
local function assert_oil_snapshot(actual, expected, label)
  if type(actual) ~= "table" or actual.level ~= expected.level or actual.enabled ~= expected.enabled
      or actual.visible ~= expected.visible or not close(actual.saved_progress, expected.saved_progress)
      or not same_queue(actual.queue, expected.queue) then fail(label .. " oil snapshot differs") end
  for name, bonus in pairs(expected.bonuses) do if not close(actual.bonuses[name], bonus) then fail(label .. " oil bonus snapshot differs") end end
end
local function seed_prerequisites(force, expected)
  for _, name in ipairs(expected.prerequisites) do
    local value = technology(force, name)
    value.enabled = true
    value.researched = true
  end
end
local function seed_oil(force, level, saved, label)
  local value = technology(force, facts.oil)
  -- LuaTechnology.level re-enables its technology. Set disablement and saved
  -- investment afterwards so this fixture observes the real setter boundary.
  -- Native researched=false resets an infinite technology to its first level.
  -- Clear it before the level setter, which establishes the earned levels.
  value.researched = false
  value.level = level
  -- Native reset re-enables an earned technology. Establish the intended
  -- foreign flags and detached investment after that last native operation.
  force.reset_technology_effects()
  value.enabled = false
  value.visible_when_disabled = true
  value.saved_progress = saved
  return oil_snapshot(force, level, saved, label)
end
local function seed_foreign(expected)
  local force = game.create_force("mir5-bob-angel-science-oil-foreign")
  if force == nil or force.valid == false then fail("could not create foreign force") end
  force.enable_all_prototypes()
  local oil = seed_oil(force, facts.foreign_oil_level, facts.foreign_oil_saved_progress, "foreign")
  local prerequisite, probe = technology(force, "automation-science-pack"), technology(force, "automation")
  prerequisite.enabled, prerequisite.researched = true, true
  probe.enabled, probe.researched = true, false
  if force.add_research(probe) ~= true then fail("could not queue foreign Automation after its named prerequisite") end
  force.research_progress = facts.foreign_queue_progress
  oil = oil_snapshot(force, facts.foreign_oil_level, facts.foreign_oil_saved_progress, "foreign queued")
  if oil.queue.current ~= "automation" or #oil.queue.queue ~= 1 or oil.queue.queue[1] ~= "automation"
      or not close(oil.queue.progress, facts.foreign_queue_progress) then fail("foreign queue snapshot differs") end
  return force.index, oil
end
local function create_lab(force, expected)
  local lab = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=force}
  if lab == nil or lab.valid == false then fail("could not create real laboratory") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real laboratory input is absent") end
  local inserted = {}
  for _, name in ipairs(expected.vector) do
    if inventory.insert{name=name, count=facts.lab_initial} ~= facts.lab_initial then fail("real laboratory rejected " .. name) end
    inserted[name] = facts.lab_initial
  end
  lab.energy = 100000000
  return lab, inserted
end
local function assert_consumption(state, expected)
  local inventory = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("saved laboratory input is absent") end
  for _, name in ipairs(expected.vector) do
    local remaining = inventory.get_item_count(name)
    -- Agricultural science can be drawn into stored durability more than once
    -- while spoiling. Every other exact unit input must consume two stacks.
    if name == "agricultural-science-pack" then
      if remaining > facts.lab_initial - 2 then fail("agricultural science was not consumed twice") end
    elseif remaining ~= facts.lab_initial - 2 then
      fail("exact science consumption differs: " .. name, {remaining=remaining})
    end
  end
end
local function assert_complete(state, expected, label)
  local player = game.forces.player
  if state.finished ~= 2 or player.current_research ~= nil then fail(label .. " actual laboratories did not finish twice") end
  local science = science_snapshot(player, expected, 3, label)
  local oil = oil_snapshot(player, facts.oil_level, facts.oil_saved_progress, label)
  assert_oil_snapshot(oil, state.player_oil, label .. " player")
  local foreign = game.forces[state.foreign_index]
  if foreign == nil or foreign.valid == false then fail(label .. " foreign force is absent") end
  local foreign_oil = oil_snapshot(foreign, facts.foreign_oil_level, facts.foreign_oil_saved_progress, label .. " foreign")
  assert_oil_snapshot(foreign_oil, state.foreign_oil, label .. " foreign")
  assert_consumption(state, expected)
  return science, oil, foreign_oil
end
local function marker(stage, state, expected)
  local science, oil, foreign = assert_complete(state, expected, stage)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="bob-angel-f210-science-oil", stage=stage, status="passed",
    witnesses={closure=expected.id, actual_science_laboratory_completions=state.finished,
      exact_science_inputs=expected.vector, admitted_producer_count=#expected.effects,
      science_level=science.level, science_recipe_productivity_bonus=.2,
      oil_seeded_not_laboratory_earned=true, oil_level=oil.level, oil_saved_progress=oil.saved_progress,
      oil_effect_recipes={"heavy-oil-cracking", "light-oil-cracking"}, foreign_disabled=true,
      foreign_queue_progress=foreign.queue.progress, on_load_read_only=stage == "reload",
      fixture_accelerates_science_count_and_time_only=true, ordinary_costs_unqualified=true,
      migration_qualification=false, all_physics_qualification=false},
  }))
end

script.on_init(function()
  local expected = closure()
  if storage[KEY] ~= nil then fail("fixture state already exists") end
  local player = game.forces.player
  player.enable_all_prototypes()
  seed_prerequisites(player, expected)
  local science = technology(player, facts.science)
  science.enabled, science.researched = true, false
  local player_oil = seed_oil(player, facts.oil_level, facts.oil_saved_progress, "player")
  local foreign_index, foreign_oil = seed_foreign(expected)
  local lab, inserted = create_lab(player, expected)
  storage[KEY] = {phase="researching", closure=expected.id, foreign_index=foreign_index, player_oil=player_oil,
    foreign_oil=foreign_oil, lab=lab, inserted=inserted, finished=0, started=false, deadline=game.tick + facts.deadline_ticks}
  game.speed = 16
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if state == nil or state.phase ~= "researching" or event.by_script ~= false
      or event.research == nil or event.research.force ~= game.forces.player then return end
  if event.research.name ~= facts.science or not state.started or state.finished >= 2 then fail("unexpected research completion") end
  state.finished, state.started = state.finished + 1, false
end)

script.on_load(function()
  loaded = storage[KEY] and storage[KEY].phase == "complete" or false
  reload_reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if state == nil then fail("fixture state is absent") end
  local expected = closure()
  if state.closure ~= expected.id then fail("saved closure differs") end
  if state.phase == "complete" then
    if loaded and not reload_reported then marker("reload", state, expected); reload_reported = true end
    return
  end
  if state.phase ~= "researching" or game.tick > state.deadline then fail("laboratory phase or deadline differs") end
  if state.finished == 2 then
    assert_complete(state, expected, "initial")
    state.phase = "complete"
    marker("initial", state, expected)
    game.server_save(SAVE)
    return
  end
  if state.lab == nil or state.lab.valid == false then fail("real laboratory is absent") end
  state.lab.energy = 100000000
  if not state.started then
    state.started = true
    if game.forces.player.add_research(technology(game.forces.player, facts.science)) ~= true then
      fail("could not start declared science research")
    end
  end
end)
