-- One published-4.7.3 -> MIR5 science-productivity transition.  This fixture
-- observes only its two local recipe effects and earns exactly one real lab
-- completion on each side; it does not seed research levels or effects.
local KEY = "mir5_fresh_science_transition"
local CASE = "fresh-science-transition"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-fresh-science-transition"
local SOURCE_FIXTURE = "mir-fixture-mir5-fresh-science-sources"
local MIR = "more-infinite-research"
local PUBLISHED = "4.7.21003"
local CURRENT = "5.0.21000"
local TARGET = "recipe-prod-research_science_pack_productivity-1"
local RECIPES = {"a-mir473-circular-planetary-data", "z-mir473-seeded-planetary-data"}
local UINT32_MAX = 4294967295
local DEADLINE = 36000
local PACKS = 8
local loaded, reload_logged = nil, false

local function fail(message) error("[mir5-fresh-science-transition] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .0000001
end

local function assert_closure(expected)
  local active = script.active_mods
  for _, name in ipairs({"base", "elevated-rails", "quality", "recycler", "space-age"}) do
    if active[name] ~= "2.1.23" then fail("F210 closure differs: " .. name) end
  end
  if active[MIR] ~= expected or active[FIXTURE] ~= "0.1.0" or active[SOURCE_FIXTURE] ~= "0.1.0" then
    fail("transition archive or fixture closure differs")
  end
end

local function technology(force)
  local value = force and force.technologies and force.technologies[TARGET]
  if value == nil or value.valid == false or value.name ~= TARGET then fail("science productivity technology is absent") end
  return value
end

local function assert_effects(value, label)
  local found = {}
  for _, name in ipairs(RECIPES) do found[name] = 0 end
  for _, effect in pairs(value.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and found[effect.recipe] ~= nil then
      if not close(effect.change, .1) then fail(label .. " science effect changed: " .. effect.recipe) end
      found[effect.recipe] = found[effect.recipe] + 1
    end
  end
  for _, name in ipairs(RECIPES) do
    if found[name] ~= 1 then fail(label .. " science effect was omitted or duplicated: " .. name) end
  end
end

local function assert_target(force, level, count, label)
  local value = technology(force)
  if value.level ~= level or value.researched or value.enabled ~= true
      or value.prototype.max_level ~= UINT32_MAX or value.research_unit_count ~= count
      or not close(value.research_unit_energy, 60) then
    fail(label .. " accelerated science target differs")
  end
  for _ in pairs(value.prerequisites or {}) do fail(label .. " science target gained a prerequisite") end
  local seen, ingredients, planetary = {}, 0, 0
  for _, ingredient in pairs(value.research_unit_ingredients or {}) do
    if type(ingredient.name) ~= "string" or type(ingredient.amount) ~= "number"
        or ingredient.amount ~= 1 or seen[ingredient.name] then
      fail(label .. " science input differs")
    end
    seen[ingredient.name] = true
    ingredients = ingredients + 1
    if ingredient.name == "planetary-data" then planetary = planetary + 1 end
  end
  if ingredients ~= 13 or planetary ~= 1 then fail(label .. " fresh science input was not retained") end
  assert_effects(value, label)
  return value
end

local function bonus(force, recipe, label)
  local value = force and force.recipes and force.recipes[recipe]
  if value == nil or value.valid == false or type(value.productivity_bonus) ~= "number" then
    fail(label .. " native recipe productivity is absent: " .. recipe)
  end
  return value.productivity_bonus
end

local function assert_bonuses(force, expected, label)
  for _, recipe in ipairs(RECIPES) do
    if not close(bonus(force, recipe, label), expected) then
      fail(label .. " native recipe productivity differs: " .. recipe)
    end
  end
end

local function assert_idle(force, label)
  if force.current_research ~= nil then fail(label .. " target remained current") end
  for _ in pairs(force.research_queue or {}) do fail(label .. " target remained queued") end
end

local function lab(state)
  local value = state.lab
  if value == nil or value.valid == false or value.name ~= "biolab" then fail("F210 biolab is absent") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("F210 biolab input is absent") end
  return value, inventory
end

local function fill(state, value)
  local entity, inventory = lab(state)
  inventory.clear()
  for _, ingredient in pairs(value.research_unit_ingredients) do
    if inventory.insert{name=ingredient.name, count=PACKS} ~= PACKS then
      fail("F210 biolab rejected science input: " .. tostring(ingredient.name))
    end
  end
  entity.active = true
  entity.energy = 1000000000
end

local function freeze(state)
  local entity, inventory = lab(state)
  entity.active = false
  entity.energy = 0
  inventory.clear()
end

local function assert_frozen(state, label)
  local entity, inventory = lab(state)
  if entity.active ~= false or entity.energy ~= 0 or not inventory.is_empty() then
    fail(label .. " fixture biolab was not frozen")
  end
end

local function queue(force, value, label)
  if force.add_research(value) ~= true then fail(label .. " could not start actual lab research") end
  if force.current_research ~= value then fail(label .. " target was not made current") end
  local entries = 0
  for _, queued in pairs(force.research_queue or {}) do
    entries = entries + 1
    if queued ~= value then fail(label .. " queue identity differs") end
  end
  if entries ~= 1 or not close(force.research_progress, 0) then fail(label .. " target queue differs") end
end

local function assert_earned(state, level, count, expected, label)
  local force = game.forces.player
  assert_target(force, level, count, label)
  assert_bonuses(force, expected, label)
  assert_idle(force, label)
  assert_frozen(state, label)
end

local function marker(stage, state)
  local target = technology(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed", qualification="native-runner-readback-required",
    witnesses={source_mir=state.source_mir, destination_mir=script.active_mods[MIR],
      source_actual_lab_completions=state.source_labs, successor_actual_lab_completions=state.successor_labs,
      science_target=TARGET, next_level=target.level, next_research_unit_count=target.research_unit_count,
      circular_recipe_productivity=bonus(game.forces.player, RECIPES[1], "marker"),
      seeded_recipe_productivity=bonus(game.forces.player, RECIPES[2], "marker"),
      on_load_read_only=stage == "reload"},
  }))
end

local function complete_source(state)
  if state.source_labs ~= 1 then fail("source did not earn exactly one actual lab completion") end
  freeze(state)
  assert_earned(state, 2, 2, .1, "published source")
  state.phase = "source-completed"
  marker("initial", state)
  game.server_save(SAVE)
end

local function complete_successor(state)
  if state.source_labs ~= 1 or state.successor_labs ~= 1 then
    fail("successor did not retain one source and earn one successor lab completion")
  end
  freeze(state)
  assert_earned(state, 3, 4, .2, "MIR5 successor")
  state.phase = "successor-completed"
  marker("initial", state)
  game.server_save(SAVE)
end

script.on_init(function()
  assert_closure(PUBLISHED)
  if storage[KEY] ~= nil then fail("source transition state already exists") end
  local force = game.forces.player
  local value = assert_target(force, 1, 1, "published source preflight")
  assert_bonuses(force, 0, "published source preflight")
  assert_idle(force, "published source preflight")
  local entity = game.surfaces[1].create_entity{name="biolab", position={0, 0}, force=force}
  if entity == nil or entity.valid == false then fail("could not create F210 biolab") end
  local state = {phase="source-lab", source_mir=PUBLISHED, source_labs=0, successor_labs=0,
    lab=entity, deadline=game.tick + DEADLINE}
  storage[KEY] = state
  game.speed = 16
  fill(state, value)
  queue(force, value, "published source")
end)

script.on_configuration_changed(function()
  loaded, reload_logged = nil, false
  assert_closure(CURRENT)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "source-completed" or state.source_mir ~= PUBLISHED
      or state.source_labs ~= 1 or state.successor_labs ~= 0 then
    fail("published earned source witness is absent")
  end
  assert_earned(state, 2, 2, .1, "MIR5 preflight")
  local value = technology(game.forces.player)
  state.phase, state.deadline = "successor-lab", game.tick + DEADLINE
  fill(state, value)
  queue(game.forces.player, value, "MIR5 successor")
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player then return end
  if event.research.name ~= TARGET then return end
  if state.phase == "source-lab" then
    state.source_labs = state.source_labs + 1
    if state.source_labs ~= 1 then fail("source emitted duplicate actual lab completion") end
    state.phase = "source-observation"
  elseif state.phase == "successor-lab" then
    state.successor_labs = state.successor_labs + 1
    if state.successor_labs ~= 1 then fail("successor emitted duplicate actual lab completion") end
    state.phase = "successor-observation"
  end
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and (state.phase == "source-completed" or state.phase == "successor-completed") then
    loaded = {phase=state.phase, source_labs=state.source_labs, successor_labs=state.successor_labs}
  else
    loaded = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("transition state is absent") end
  if state.phase == "source-lab" or state.phase == "successor-lab" then
    if game.tick > state.deadline then fail("actual science productivity lab did not finish") end
    local entity = lab(state)
    entity.energy = 1000000000
    return
  end
  if state.phase == "source-observation" then complete_source(state); return end
  if state.phase == "successor-observation" then complete_successor(state); return end
  if state.phase ~= "source-completed" and state.phase ~= "successor-completed" then
    fail("transition phase is unknown")
  end
  if loaded ~= nil and not reload_logged then
    if loaded.phase ~= state.phase or loaded.source_labs ~= state.source_labs
        or loaded.successor_labs ~= state.successor_labs then
      fail("cold reload changed completed lab witnesses")
    end
    if state.phase == "source-completed" then
      assert_earned(state, 2, 2, .1, "published cold reload")
    else
      assert_earned(state, 3, 4, .2, "MIR5 cold reload")
    end
    marker("reload", state)
    reload_logged = true
  end
end)
