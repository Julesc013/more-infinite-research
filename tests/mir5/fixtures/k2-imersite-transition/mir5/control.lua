local KEY = "mir5_k2_imersite_transition"
local CASE = "k2-imersite-mir5-recovery"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-k2-imersite-transition"
local EARLY = "recipe-prod-research_material_imersite-1"
local TAIL = "recipe-prod-research_material_imersite-4"
local HOLDER = "mir-k2-imersite-staged-state-1"
local CARRIER = "mir-k2-imersite-continuation-state-4"
local POWDER = "kr-imersite-powder"
local LAB_ENERGY = 100000000
local PACKS = 8
local DEADLINE = 24000
local loaded, reported, pending = nil, false, false

local function fail(message) error("[mir5-k2-imersite-successor] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. tostring(name)) end
  return value
end
local function powder_bonus(force)
  local recipe = force.recipes[POWDER]
  if recipe == nil then fail("Imersite powder recipe is absent") end
  return recipe.productivity_bonus
end
local function status(force, name)
  local value = technology(force, name)
  return {level=value.level, researched=value.researched == true, saved_progress=value.saved_progress or 0,
    enabled=value.enabled, visible=value.visible_when_disabled, hidden=value.prototype.hidden == true,
    maximum=value.prototype.max_level}
end
local function assert_effect(value, label)
  local effects = value.prototype.effects
  local effect = effects and effects[1]
  if #effects ~= 1 or effect.type ~= "change-recipe-productivity" or effect.recipe ~= POWDER
      or not close(effect.change, 0.02) then fail(label .. " powder effect changed") end
end
local function assert_acceleration(value)
  assert_effect(value, "MIR5 continuation")
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("MIR5 fixture did not reduce only continuation count and time")
  end
end
local function assert_holder_cleared(force, name, first)
  local value = status(force, name)
  if value.level ~= first or value.researched or value.saved_progress ~= 0 or value.enabled
      or value.visible or not value.hidden or value.maximum ~= 4294967295 then
    fail("MIR5 did not clear consumed hidden carrier: " .. name)
  end
end
local function assert_recovered(state, label)
  if type(state) ~= "table" or state.phase ~= "published-ready" or state.published_mir ~= "4.7.21002"
      or type(state.published) ~= "table" or state.published.carrier_level ~= 6 or not close(state.published.carrier_progress, 0.42)
      or not close(state.published.bonus, 0.10) then
    fail(label .. " published hidden-carrier witness is absent")
  end
  local force = game.forces.player
  local early, tail = status(force, EARLY), status(force, TAIL)
  if early.level ~= 3 or not early.researched or tail.level ~= 6 or tail.researched
      or not close(tail.saved_progress, 0.42) or tail.maximum ~= 4294967295
      or not close(powder_bonus(force), 0.10) then
    fail(label .. " recovered public Imersite state differs")
  end
  assert_effect(technology(force, EARLY), label .. " early")
  assert_acceleration(technology(force, TAIL))
  assert_holder_cleared(force, HOLDER, 1)
  assert_holder_cleared(force, CARRIER, 4)
  if force.current_research ~= nil or #force.research_queue ~= 0 then fail(label .. " recovery invented a queue") end
  return tail
end
local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites or {}) do prerequisite.research_recursive() end
end
local function lab(state)
  local value = state.destination_lab
  if value == nil or value.valid == false then fail("MIR5 successor lab is absent") end
  value.energy = LAB_ENERGY
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("MIR5 successor lab input is absent") end
  return inventory
end
local function fill(inventory, value)
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    if type(ingredient.name) ~= "string" or type(ingredient.amount) ~= "number" or ingredient.amount <= 0 then
      fail("MIR5 continuation native science is malformed")
    end
    if inventory.insert{name=ingredient.name, count=PACKS} ~= PACKS then
      fail("MIR5 successor lab rejected science: " .. ingredient.name)
    end
  end
end
local function assert_completed(state, label)
  local tail = status(game.forces.player, TAIL)
  if state.destination_lab_completions ~= 1 or tail.level ~= 7 or tail.researched
      or tail.saved_progress ~= 0 or not close(powder_bonus(game.forces.player), 0.12) then
    fail(label .. " successor native Imersite completion differs")
  end
  if game.forces.player.current_research ~= nil or #game.forces.player.research_queue ~= 0 then
    fail(label .. " successor continuation remained queued")
  end
  assert_holder_cleared(game.forces.player, HOLDER, 1)
  assert_holder_cleared(game.forces.player, CARRIER, 4)
end
local function marker(stage, state)
  local tail = status(game.forces.player, TAIL)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed", qualification="native-runner-readback-required",
    witnesses={source_mir=state.source_mir, published_mir=state.published_mir,
      destination_mir=script.active_mods["more-infinite-research"],
      source_actual_lab_completions=state.actual_lab_completions, hidden_tail_level_before=6,
      recovered_tail_saved_progress_before_lab=0.42, destination_actual_lab_completions=state.destination_lab_completions,
      tail_next_level=tail.level, powder_productivity=powder_bonus(game.forces.player),
      public_continuation_readded=true, on_load_read_only=stage == "reload"},
  }))
end

script.on_configuration_changed(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["Krastorio2-spaced-out"] == nil
      or script.active_mods["more-infinite-research"] ~= "5.0.21000" or script.active_mods[FIXTURE] ~= "0.3.0" then
    fail("MIR5 successor requires K2SO, MIR5 5.0.21000, and fixture 0.3.0")
  end
  if settings.startup["ips-max-level-research_material_imersite"].value ~= 0 then
    fail("MIR5 successor must release the published bounded cap")
  end
  local state = storage[KEY]
  local tail = assert_recovered(state, "MIR5 configuration")
  prerequisites(tail)
  if tail.enabled ~= true then fail("MIR5 re-added continuation is not enabled after its named prerequisites") end
  local entity = game.surfaces[1].create_entity{name="lab", position={2, 0}, force=game.forces.player}
  if entity == nil or entity.valid == false then fail("could not create real MIR5 successor lab") end
  state.destination_lab, state.destination_lab_completions = entity, 0
  state.phase, state.deadline_tick = "await-successor-lab", game.tick + DEADLINE
  fill(lab(state), tail)
  if game.forces.player.add_research(tail) ~= true then fail("could not start real MIR5 continuation research") end
  if game.forces.player.current_research ~= tail or #game.forces.player.research_queue ~= 1
      or not close(game.forces.player.research_progress, 0.42) then
    fail("MIR5 did not move detached continuation progress into its real lab queue")
  end
  pending = true
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "await-successor-lab" or event.research == nil
      or event.research.force ~= game.forces.player then return end
  if event.research.name ~= TAIL then fail("unexpected MIR5 Imersite completion") end
  state.destination_lab_completions = state.destination_lab_completions + 1
  if state.destination_lab_completions ~= 1 then fail("duplicate MIR5 Imersite completion") end
  state.phase = "await-successor-observation"
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "complete" and type(state.completed_tail) == "table"
    and {labs=state.destination_lab_completions, tail=state.completed_tail} or nil
  reported, pending = false, false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("MIR5 successor fixture state is absent") end
  if state.phase == "complete" then
    if loaded and not reported then
      assert_completed(state, "MIR5 cold reload")
      local tail = status(game.forces.player, TAIL)
      if loaded.labs ~= state.destination_lab_completions or tail.level ~= loaded.tail.level
          or not close(tail.saved_progress, loaded.tail.saved_progress) then
        fail("MIR5 cold reload changed the completed recovery")
      end
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("MIR5 continuation lab timed out") end
  lab(state)
  if pending then pending = false end
  if state.phase == "await-successor-observation" and state.destination_lab_completions == 1 then
    assert_completed(state, "MIR5 initial")
    local tail = status(game.forces.player, TAIL)
    state.completed_tail = {level=tail.level, saved_progress=tail.saved_progress, bonus=powder_bonus(game.forces.player)}
    state.phase = "complete"
    marker("initial", state)
    game.server_save(SAVE)
  end
end)
