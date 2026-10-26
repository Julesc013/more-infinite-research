-- The source stage earns the finite AAI laboratory chain and one MIR level in
-- real labs.  It seeds only the explicit non-AAI science-pack prerequisites
-- needed to make the isolated MIR owner researchable; those assignments are
-- recorded as setup and are never reported as lab completions.
local KEY = "mir5_aai_parity_native"
local FIXTURE = "mir-fixture-mir5-aai-parity-native"
local PLAN = require("__mir-fixture-mir5-aai-parity-native__/catalogue")
local SOURCE = PLAN.stage == "published-4.7"
local SAVE = "mir5-native-complete"
local OWNER = "recipe-prod-research_electric_engine-1"
local AAI_PLAN = {"fuel-processing", "sand-processing", "electricity", "electronics", "glass-processing", "electric-lab"}
local BASE_SCIENCE = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
-- A burner lab's one automation-science slot is capped by the published
-- stack size (200). Thirty-two packs cover the six accelerated one-unit AAI
-- technologies without treating a partial inventory insertion as success.
local AAI_PACKS = 32
local MIR_PACKS = 64
local PHYSICAL_BATCHES = 10
local LAB_ENERGY = 100000000
local DEADLINE_TICKS = 180000
local STARTING_IRON = 10
local BURNER_LAB_MOTORS = 10
local BURNER_LAB_COPPER = 10
local BURNER_LAB_BRICKS = 5
local BOOTSTRAP_FUEL = 16
local TRIGGER_WAIT_TICKS = 600
local loaded, reported = nil, false

local function fail(message) error("[mir5-aai-parity-native] " .. message) end
local function close(actual, expected) return type(actual) == "number" and math.abs(actual - expected) <= .0000001 end

local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. name) end
  return value
end

local function recipe(force, name)
  local value = force and force.recipes[name]
  if value == nil or value.valid == false or value.name ~= name then fail("recipe is absent: " .. name) end
  return value
end

local function check_closure()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["aai-industry"] ~= "0.7.5"
      or script.active_mods["more-infinite-research"] ~= PLAN.mir_version or script.active_mods[FIXTURE] ~= PLAN.fixture_version then
    fail("AAI, MIR, fixture, or Base closure differs")
  end
  local space = script.active_mods["space-age"] ~= nil
  for _, name in ipairs({"elevated-rails", "quality", "recycler", "space-age"}) do
    if space then
      if script.active_mods[name] ~= "2.1.23" then fail("Space Age closure differs: " .. name) end
    elseif script.active_mods[name] ~= nil then
      fail("Base closure unexpectedly enables " .. name)
    end
  end
  return space
end

local function science(space)
  local out = {}
  for _, name in ipairs(BASE_SCIENCE) do out[#out + 1] = name end
  if space then out[#out + 1] = "electromagnetic-science-pack" end
  return out
end

local function inventory(entity, slot, label)
  local value = entity and entity.get_inventory(slot)
  if value == nil then fail(label .. " inventory is absent") end
  return value
end

local function assert_lab_chain(force)
  if technology(force, "burner-mechanics").researched ~= true or technology(force, "automation-science-pack").researched ~= true then
    fail("AAI burner starting technologies are not researched")
  end
  if recipe(force, "burner-lab").enabled ~= true then fail("AAI burner lab recipe is not enabled") end
  for _, name in ipairs(AAI_PLAN) do
    local value = technology(force, name)
    if value.researched or value.enabled ~= true then fail("AAI progression state differs before actual lab: " .. name) end
  end
end

local function fill_lab(entity, names, count)
  local input = inventory(entity, defines.inventory.lab_input, "lab input")
  for _, name in ipairs(names) do
    if input.insert{name=name, count=count} ~= count then fail("lab rejected science: " .. name) end
  end
  entity.energy = LAB_ENERGY
end

local function create_burner_lab(force)
  local surface = game.surfaces[1]
  local entity = surface.create_entity{name="burner-lab", position={0, 0}, force=force}
  if entity == nil or entity.valid == false then fail("could not create AAI burner lab") end
  local fuel = entity.get_fuel_inventory and entity.get_fuel_inventory()
  if fuel == nil or fuel.insert{name="coal", count=16} ~= 16 then fail("AAI burner lab rejected fuel") end
  fill_lab(entity, {"automation-science-pack"}, AAI_PACKS)
  return entity
end

local function create_starting_furnace(force)
  local entity = game.surfaces[1].create_entity{name="stone-furnace", position={-6, 0}, force=force}
  if entity == nil or entity.valid == false then fail("could not create AAI starting furnace") end
  local input = inventory(entity, defines.inventory.crafter_input, "starting furnace input")
  local output = inventory(entity, defines.inventory.crafter_output, "starting furnace output")
  local fuel = entity.get_fuel_inventory and entity.get_fuel_inventory()
  if fuel == nil or fuel.insert{name="coal", count=BOOTSTRAP_FUEL} ~= BOOTSTRAP_FUEL then
    fail("AAI starting furnace rejected fuel")
  end
  if input.insert{name="iron-ore", count=STARTING_IRON} ~= STARTING_IRON or output.get_item_count("iron-plate") ~= 0 then
    fail("AAI starting furnace rejected exact iron input")
  end
  entity.energy = LAB_ENERGY
  return entity
end

local function create_starting_burner_assembler(force)
  local entity = game.surfaces[1].create_entity{name="burner-assembling-machine", position={-3, 0}, force=force}
  if entity == nil or entity.valid == false then fail("could not create AAI starting burner assembler") end
  entity.set_recipe("burner-lab")
  local selected = entity.get_recipe()
  if selected == nil or selected.name ~= "burner-lab" then
    fail("could not select AAI burner-lab recipe")
  end
  local input = inventory(entity, defines.inventory.crafter_input, "starting burner assembler input")
  local output = inventory(entity, defines.inventory.crafter_output, "starting burner assembler output")
  local fuel = entity.get_fuel_inventory and entity.get_fuel_inventory()
  if fuel == nil or fuel.insert{name="coal", count=BOOTSTRAP_FUEL} ~= BOOTSTRAP_FUEL then
    fail("AAI starting burner assembler rejected fuel")
  end
  if input.insert{name="motor", count=BURNER_LAB_MOTORS} ~= BURNER_LAB_MOTORS
      or input.insert{name="copper-plate", count=BURNER_LAB_COPPER} ~= BURNER_LAB_COPPER
      or input.insert{name="stone-brick", count=BURNER_LAB_BRICKS} ~= BURNER_LAB_BRICKS
      or output.get_item_count("burner-lab") ~= 0 then
    fail("AAI starting burner assembler rejected exact burner-lab inputs")
  end
  entity.energy = LAB_ENERGY
  return entity
end

local function create_electric_lab(force, space)
  if recipe(force, "lab").enabled ~= true then fail("AAI electric lab technology did not unlock lab recipe") end
  local entity = game.surfaces[1].create_entity{name="lab", position={3, 0}, force=force}
  if entity == nil or entity.valid == false then fail("could not create AAI electric lab") end
  fill_lab(entity, science(space), MIR_PACKS)
  return entity
end

local function start_research(force, value, label)
  if force.current_research ~= nil or #(force.research_queue or {}) ~= 0 then fail(label .. " has existing research") end
  if force.add_research(value) ~= true then fail("could not queue real research: " .. value.name) end
end

local function assert_no_beacon_or_modules(entity)
  local beacons = game.surfaces[1].find_entities_filtered{type="beacon"}
  if #beacons ~= 0 then fail("physical recipe witness permits a beacon") end
  local modules = entity.get_module_inventory and entity.get_module_inventory()
  if modules ~= nil and next(modules.get_contents()) ~= nil then fail("physical recipe witness permits modules") end
end

local function start_physical_batch(state, after_research)
  local force = game.forces.player
  local entity = state.machine
  if entity == nil then
    entity = game.surfaces[1].create_entity{name="assembling-machine-2", position={6, 0}, force=force}
    if entity == nil or entity.valid == false then fail("could not create electric-engine assembler") end
    entity.set_recipe("electric-engine-unit")
    local selected = entity.get_recipe()
    if selected == nil or selected.name ~= "electric-engine-unit" then
      fail("could not select electric-engine recipe")
    end
    state.machine = entity
  end
  assert_no_beacon_or_modules(entity)
  local input = inventory(entity, defines.inventory.crafter_input, "assembler input")
  local output = inventory(entity, defines.inventory.crafter_output, "assembler output")
  local expected = after_research and (PHYSICAL_BATCHES + 1) or PHYSICAL_BATCHES
  local before = output.get_item_count("electric-engine-unit")
  if input.insert{name="steel-plate", count=PHYSICAL_BATCHES * 2} ~= PHYSICAL_BATCHES * 2
      or input.insert{name="electronic-circuit", count=PHYSICAL_BATCHES * 4} ~= PHYSICAL_BATCHES * 4
      or input.insert{name="electric-motor", count=PHYSICAL_BATCHES * 2} ~= PHYSICAL_BATCHES * 2 then
    fail("assembler rejected exact electric-engine inputs")
  end
  entity.fluidbox[1] = {name="lubricant", amount=PHYSICAL_BATCHES * 40}
  entity.energy = LAB_ENERGY
  state.production = {after_research=after_research, before=before, expected=expected}
end

local function physical_batch_finished(state)
  local entity = state.machine
  if entity == nil or entity.valid == false then fail("physical assembler was removed") end
  entity.energy = LAB_ENERGY
  local input = inventory(entity, defines.inventory.crafter_input, "assembler input")
  if input.get_item_count("steel-plate") ~= 0 or input.get_item_count("electronic-circuit") ~= 0 or input.get_item_count("electric-motor") ~= 0 then
    return false
  end
  local output = inventory(entity, defines.inventory.crafter_output, "assembler output")
  local produced = output.get_item_count("electric-engine-unit") - state.production.before
  -- Ingredients leave the input inventory when the last craft starts. Wait
  -- for its real output instead of rejecting that normal in-flight state.
  if produced > state.production.expected then
    fail("physical electric-engine output differs: " .. tostring(produced) .. " expected " .. tostring(state.production.expected))
  end
  return produced == state.production.expected
end

local function assert_owner(force, expected_level, expected_bonus)
  local value = technology(force, OWNER)
  if value.level ~= expected_level or value.researched ~= false then fail("electric engine MIR level differs") end
  if not close(recipe(force, "electric-engine-unit").productivity_bonus, expected_bonus) then
    fail("electric engine native productivity differs")
  end
  return value
end

local function queue_witness(force, owner)
  owner.saved_progress = .42
  force.research_queue = {owner}
  force.research_progress = .42
  if force.current_research ~= owner or #(force.research_queue or {}) ~= 1 or not close(force.research_progress, .42) then
    fail("source queued research witness differs")
  end
  local paused = game.create_force("mir5-aai-parity-paused")
  local paused_owner = technology(paused, OWNER)
  paused_owner.saved_progress = .27
  if not close(paused_owner.saved_progress, .27) or paused.current_research ~= nil or #(paused.research_queue or {}) ~= 0 then
    fail("source paused research witness differs")
  end
  return paused.index
end

local function snapshot(state)
  local force = game.forces.player
  local owner = technology(force, OWNER)
  return {
    aai_labs=state.aai_finished, mir_labs=state.mir_labs, owner_level=owner.level,
    owner_bonus=recipe(force, "electric-engine-unit").productivity_bonus,
    before_output=state.before_output, after_output=state.after_output,
    queued_progress=force.research_progress, queued_name=force.current_research and force.current_research.name,
    paused_progress=technology(game.forces[state.paused_index], OWNER).saved_progress,
  }
end

local function assert_snapshot(state, successor)
  local saved = state.source_snapshot
  if type(saved) ~= "table" then fail("source snapshot is absent") end
  local force = game.forces.player
  local owner = technology(force, OWNER)
  if state.aai_finished ~= #AAI_PLAN or state.mir_labs ~= 1 or saved.aai_labs ~= #AAI_PLAN or saved.mir_labs ~= 1
      or saved.owner_level ~= 2 or not close(saved.owner_bonus, .1) or saved.before_output ~= 10 or saved.after_output ~= 11 then
    fail("source AAI or physical witness differs")
  end
  if successor then
    if owner.level ~= 3 or not close(recipe(force, "electric-engine-unit").productivity_bonus, .2) then fail("successor MIR witness differs") end
  else
    if owner.level ~= 2 or not close(recipe(force, "electric-engine-unit").productivity_bonus, .1)
        or force.current_research ~= owner or #(force.research_queue or {}) ~= 1 or not close(force.research_progress, .42) then
      fail("source queue witness differs")
    end
  end
  local paused = game.forces[state.paused_index]
  if paused == nil or not close(technology(paused, OWNER).saved_progress, .27) then fail("paused AAI source witness differs") end
  if not state.machine or not state.machine.valid
      or inventory(state.machine, defines.inventory.crafter_output, "saved assembler output").get_item_count("electric-engine-unit") ~= 21 then
    fail("saved physical electric-engine output differs")
  end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="aai-parity-native", stage=stage, status="passed", witnesses={
      profile=state.profile, aai_actual_lab_completions=state.aai_finished,
      aai_actual_progression={"fuel-processing", "sand-processing", "electricity", "electronics", "glass-processing", "electric-lab"},
      mir_actual_lab_completions=state.mir_labs, physical_before_output=state.before_output,
      physical_after_output=state.after_output, physical_batch_count=PHYSICAL_BATCHES,
      source_queue_progress=.42, paused_progress=.27, source_setup_external_science_prerequisites=true,
      on_load_read_only=stage == "reload", base_space_age_transition_not_claimed=true,
    },
  }))
end

local function source_init()
  local space = check_closure()
  local force = game.forces.player
  game.speed = 16 -- Disposable physical fixture only; no timing claim.
  storage[KEY] = {phase="bootstrap-iron", profile=space and "space-age" or "base", space=space,
    starting_furnace=create_starting_furnace(force),
    aai_next=1, aai_finished=0, mir_labs=0, deadline=game.tick + DEADLINE_TICKS}
end

local function setup_mir_prerequisites(force, space)
  local names = science(space)
  for _, name in ipairs(names) do technology(force, name).researched = true end
  -- These named science technologies are explicit setup only. The AAI chain
  -- and MIR owner completion are counted only through native lab events.
end

local function source_tick()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("AAI source state is absent") end
  if state.phase == "source-complete" then
    if loaded and not reported then assert_snapshot(state, false); marker("reload", state); reported = true end
    return
  end
  if game.tick > state.deadline then fail("AAI native parity fixture exceeded deadline") end
  local force = game.forces.player
  if state.phase == "bootstrap-iron" then
    local furnace = state.starting_furnace
    if furnace == nil or furnace.valid == false then fail("AAI starting furnace was removed") end
    furnace.energy = LAB_ENERGY
    local input = inventory(furnace, defines.inventory.crafter_input, "starting furnace input")
    local output = inventory(furnace, defines.inventory.crafter_output, "starting furnace output")
    local iron = output.get_item_count("iron-plate")
    if iron > STARTING_IRON then fail("AAI starting furnace produced excess iron") end
    if iron == STARTING_IRON then
      if input.get_item_count("iron-ore") ~= 0 then fail("AAI starting furnace did not consume iron") end
      if technology(force, "burner-mechanics").researched ~= true then
        state.trigger_deadline = state.trigger_deadline or (game.tick + TRIGGER_WAIT_TICKS)
        if game.tick > state.trigger_deadline then
          fail("AAI burner-mechanics craft-item trigger did not complete after native iron production")
        end
        return
      end
      state.trigger_deadline = nil
      if recipe(force, "burner-lab").enabled ~= true then fail("AAI burner-mechanics did not unlock burner lab") end
      state.starting_assembler = create_starting_burner_assembler(force)
      state.phase = "bootstrap-burner-lab"
    end
  elseif state.phase == "bootstrap-burner-lab" then
    local assembler = state.starting_assembler
    if assembler == nil or assembler.valid == false then fail("AAI starting burner assembler was removed") end
    assembler.energy = LAB_ENERGY
    local input = inventory(assembler, defines.inventory.crafter_input, "starting burner assembler input")
    local output = inventory(assembler, defines.inventory.crafter_output, "starting burner assembler output")
    local labs = output.get_item_count("burner-lab")
    if labs > 1 then fail("AAI starting burner assembler produced excess burner labs") end
    if labs == 1 then
      if input.get_item_count("motor") ~= 0 or input.get_item_count("copper-plate") ~= 0 or input.get_item_count("stone-brick") ~= 0 then
        fail("AAI starting burner assembler did not consume burner-lab inputs")
      end
      if technology(force, "automation-science-pack").researched ~= true then
        state.trigger_deadline = state.trigger_deadline or (game.tick + TRIGGER_WAIT_TICKS)
        if game.tick > state.trigger_deadline then
          fail("AAI automation-science-pack craft-item trigger did not complete after native burner-lab production")
        end
        return
      end
      state.trigger_deadline = nil
      assert_lab_chain(force)
      state.burner_lab = create_burner_lab(force)
      state.phase = "aai-progression"
    end
  elseif state.phase == "aai-progression" then
    state.burner_lab.energy = LAB_ENERGY
    if state.aai_finished == #AAI_PLAN then
      state.electric_lab = create_electric_lab(force, state.space)
      setup_mir_prerequisites(force, state.space)
      start_physical_batch(state, false)
      state.phase = "physical-before"
      return
    end
    if force.current_research == nil then start_research(force, technology(force, AAI_PLAN[state.aai_next]), "AAI progression") end
  elseif state.phase == "physical-before" then
    if physical_batch_finished(state) then
      state.before_output = state.production.expected
      start_research(force, technology(force, OWNER), "MIR source")
      state.phase = "mir-source"
    end
  elseif state.phase == "mir-source" then
    state.electric_lab.energy = LAB_ENERGY
    if state.mir_labs == 1 then
      assert_owner(force, 2, .1)
      start_physical_batch(state, true)
      state.phase = "physical-after"
    end
  elseif state.phase == "physical-after" then
    if physical_batch_finished(state) then
      state.after_output = state.production.expected
      state.burner_lab.active, state.burner_lab.energy = false, 0
      state.electric_lab.active, state.electric_lab.energy = false, 0
      state.paused_index = queue_witness(force, technology(force, OWNER))
      state.source_snapshot = snapshot(state)
      state.phase = "source-complete"
      marker("initial", state)
      game.server_save(SAVE)
    end
  end
end

local function successor_config()
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "source-complete" then fail("successor lacks completed published AAI save") end
  check_closure()
  assert_snapshot(state, false)
  local force = game.forces.player
  if not state.electric_lab or not state.electric_lab.valid then fail("source electric lab was lost") end
  state.electric_lab.active = true
  state.electric_lab.energy = LAB_ENERGY
  state.phase, state.deadline, state.successor_labs = "successor-research", game.tick + DEADLINE_TICKS, 0
end

local function successor_tick()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("AAI successor state is absent") end
  if state.phase == "successor-complete" then
    if loaded and not reported then assert_snapshot(state, true); marker("reload", state); reported = true end
    return
  end
  if game.tick > state.deadline then fail("AAI successor fixture exceeded deadline") end
  if state.phase ~= "successor-research" then fail("AAI successor phase differs") end
  state.electric_lab.energy = LAB_ENERGY
  if state.successor_labs == 1 then
    assert_snapshot(state, true)
    state.phase = "successor-complete"
    marker("initial", state)
    game.server_save(SAVE)
  end
end

if SOURCE then
  script.on_init(source_init)
else
  script.on_configuration_changed(successor_config)
end

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.by_script ~= false or event.research == nil or event.research.force ~= game.forces.player then return end
  if SOURCE and state.phase == "aai-progression" then
    local expected = AAI_PLAN[state.aai_next]
    if event.research.name ~= expected then fail("AAI progression completion differs") end
    state.aai_finished, state.aai_next = state.aai_finished + 1, state.aai_next + 1
  elseif SOURCE and state.phase == "mir-source" then
    if event.research.name ~= OWNER then fail("source MIR completion differs") end
    state.mir_labs = state.mir_labs + 1
  elseif not SOURCE and state.phase == "successor-research" then
    if event.research.name ~= OWNER then fail("successor MIR completion differs") end
    state.successor_labs = state.successor_labs + 1
  end
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and (state.phase == "source-complete" or state.phase == "successor-complete")
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  if SOURCE then source_tick() else successor_tick() end
end)
