local KEY = "mir5_k2_imersite_transition"
local CASE = "k2-imersite-predecessor-4.6"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-k2-imersite-transition"
local LEGACY = "recipe-prod-research_material_imersite-1"
local POWDER = "kr-imersite-powder"
local REQUIRED_COMPLETIONS = 5
local LAB_ENERGY = 100000000
local PACKS = 12
local DEADLINE = 36000
local loaded, reported = nil, false

local function fail(message) error("[mir5-k2-imersite-predecessor] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end
local function technology(force)
  local value = force and force.technologies[LEGACY]
  if value == nil or value.valid == false then fail("published predecessor Imersite technology is absent") end
  return value
end
local function powder_bonus(force)
  local recipe = force.recipes[POWDER]
  if recipe == nil then fail("Imersite powder recipe is absent") end
  return recipe.productivity_bonus
end
local function assert_effect(value, label)
  local effects = value.prototype.effects
  if type(effects) ~= "table" or #effects ~= 1 then fail(label .. " powder effect count changed") end
  local effect = effects[1]
  if effect.type ~= "change-recipe-productivity" or effect.recipe ~= POWDER or not close(effect.change, 0.02) then
    fail(label .. " powder effect changed")
  end
end
local function assert_acceleration(value, label)
  assert_effect(value, label)
  if value.prototype.max_level ~= 4294967295 or value.research_unit_count ~= 1
      or not close(value.research_unit_energy, 60) then
    fail(label .. " fixture count, time, or infinite boundary changed")
  end
  if type(value.research_unit_ingredients) ~= "table" or #value.research_unit_ingredients ~= 4 then
    fail(label .. " native science changed")
  end
end
local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites or {}) do prerequisite.research_recursive() end
end
local function queue(force)
  local value = technology(force)
  if force.add_research(value) ~= true then fail("could not start real predecessor Imersite research") end
  if force.current_research ~= value or #force.research_queue ~= 1 then
    fail("predecessor Imersite research was not singly current")
  end
end
local function lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("real predecessor lab is absent") end
  value.energy = LAB_ENERGY
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real predecessor lab input is absent") end
  return inventory
end
local function fill(inventory, value)
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    if type(ingredient.name) ~= "string" or type(ingredient.amount) ~= "number" or ingredient.amount <= 0 then
      fail("native predecessor science ingredient is malformed")
    end
    if inventory.insert{name=ingredient.name, count=PACKS} ~= PACKS then
      fail("real predecessor lab rejected Imersite science: " .. ingredient.name)
    end
  end
end
local function status(force)
  local value = technology(force)
  return {level=value.level, researched=value.researched == true, saved_progress=value.saved_progress or 0}
end
local function assert_complete(state, label)
  local force, legacy = game.forces.player, status(game.forces.player)
  if state.actual_lab_completions ~= REQUIRED_COMPLETIONS or state.phase ~= "complete" then
    fail(label .. " lab count differs")
  end
  if legacy.level ~= 6 or legacy.researched or not close(legacy.saved_progress, 0.42)
      or not close(powder_bonus(force), 0.10) then
    fail(label .. " earned predecessor state differs")
  end
  if force.current_research ~= nil or #force.research_queue ~= 0 then fail(label .. " completed predecessor remained queued") end
  assert_acceleration(technology(force), label)
end
local function marker(stage, state)
  local legacy = status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed", qualification="native-runner-readback-required",
    witnesses={source_mir=script.active_mods["more-infinite-research"], actual_lab_completions=state.actual_lab_completions,
      legacy_next_level=legacy.level, legacy_saved_progress=legacy.saved_progress,
      powder_productivity=powder_bonus(game.forces.player), on_load_read_only=stage == "reload"},
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["Krastorio2-spaced-out"] == nil
      or script.active_mods["more-infinite-research"] ~= "4.6.21000" or script.active_mods[FIXTURE] ~= "0.1.0" then
    fail("predecessor requires K2SO, published MIR 4.6.21000, and fixture 0.1.0")
  end
  if storage[KEY] ~= nil then fail("predecessor fixture state already exists") end
  if settings.startup["ips-max-level-research_material_imersite"].value ~= 0 then
    fail("predecessor requires the released unlimited Imersite cap")
  end
  game.speed = 16
  local force, legacy = game.forces.player, technology(game.forces.player)
  force.enable_all_prototypes()
  if legacy.prototype.max_level ~= 4294967295 then fail("published predecessor Imersite is not infinite") end
  assert_acceleration(legacy, "predecessor")
  prerequisites(legacy)
  local entity = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=force}
  if entity == nil or entity.valid == false then fail("could not create real predecessor lab") end
  local state = {phase="await-lab", actual_lab_completions=0, lab=entity,
    deadline_tick=game.tick + DEADLINE, source_mir=script.active_mods["more-infinite-research"]}
  storage[KEY] = state
  fill(lab(state), legacy)
  queue(force)
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "await-lab" or event.research == nil
      or event.research.force ~= game.forces.player then return end
  if event.research.name ~= LEGACY then fail("unexpected predecessor research completion") end
  state.actual_lab_completions = state.actual_lab_completions + 1
  if state.actual_lab_completions > REQUIRED_COMPLETIONS then fail("duplicate predecessor Imersite completion") end
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "complete" and type(state.completed_legacy) == "table"
    and {completed=state.actual_lab_completions, progress=state.completed_legacy.saved_progress} or nil
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("predecessor fixture state is absent") end
  if state.phase == "complete" then
    if loaded and not reported then
      if state.actual_lab_completions ~= loaded.completed then fail("predecessor cold reload changed lab count") end
      assert_complete(state, "predecessor cold reload")
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("predecessor Imersite labs timed out") end
  lab(state)
  if state.actual_lab_completions == REQUIRED_COMPLETIONS then
    local legacy = technology(game.forces.player)
    if legacy.level ~= 6 or legacy.researched or not close(powder_bonus(game.forces.player), 0.10) then
      fail("predecessor did not earn five actual Imersite levels")
    end
    legacy.saved_progress = 0.42
    if not close(legacy.saved_progress, 0.42) then fail("predecessor did not retain detached partial progress") end
    state.completed_legacy = {level=legacy.level, saved_progress=legacy.saved_progress,
      bonus=powder_bonus(game.forces.player)}
    state.phase = "complete"
    assert_complete(state, "predecessor initial")
    marker("initial", state)
    game.server_save(SAVE)
    return
  end
  if game.forces.player.current_research == nil then queue(game.forces.player) end
end)
