-- This fixture deliberately uses only the public runtime API plus documented
-- native Lua objects. Its fixture-owned state is the sole persistent state it
-- writes. The API-beta dependency runs its unresearched init observer first.
local api_name = "more-infinite-research.api.v1"
local beta_technology_name = "mir-api-fixture-beta-cable-1"
local recipe_name = "copper-cable"
local input_name = "copper-plate"
local assembler_name = "assembling-machine-3"
local storage_key = "mir5_api_beta_production"
local save_name = "mir5-native-complete"
local case_name = "api-beta-production"
local plates_per_phase = 100
local baseline_output = 200
local researched_output = 202
local expected_productivity = 0.01

local loaded_snapshot = nil
local reload_logged = false

local function fail(message)
  error("[mir5-api-beta-production] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000000001
end

local function player_force()
  local force = game.forces.player
  if force == nil or force.valid == false then fail("player force is absent") end
  return force
end

local function technology_for(force)
  local technology = force.technologies[beta_technology_name]
  if technology == nil then fail("beta cable technology is absent") end
  return technology
end

local function public_status(force, expected_researched)
  if remote.interfaces[api_name] == nil then fail("public runtime API is absent") end
  local status, code = remote.call(api_name, "get_research", force.index, beta_technology_name)
  local technology = technology_for(force)
  if code ~= nil or status == nil or status.name ~= beta_technology_name
      or status.force_index ~= force.index or status.level ~= 1 or status.max_level ~= 1
      or status.researched ~= expected_researched or status.enabled ~= technology.enabled then
    fail("public beta cable technology query differs")
  end
  return status
end

local function assert_beta_effect(technology)
  local effects = technology.prototype.effects
  if #effects ~= 1 or effects[1].type ~= "change-recipe-productivity"
      or effects[1].recipe ~= recipe_name or not close(effects[1].change, expected_productivity) then
    fail("beta cable technology has an unexpected native effect")
  end
end

local function assert_no_modules(machine)
  local modules = machine.get_inventory(defines.inventory.crafter_modules)
  if modules and not modules.is_empty() then fail("fixture assembler has modules") end
end

local function assert_productivity(force, machine, expected, phase)
  local recipe = force.recipes[recipe_name]
  if recipe == nil then fail("native copper cable recipe is absent") end
  assert_no_modules(machine)
  if not close(recipe.productivity_bonus, expected) then
    fail(phase .. " native recipe productivity bonus differs: " .. tostring(recipe.productivity_bonus))
  end
  if not close(machine.productivity_bonus, expected) then
    fail(phase .. " native assembler productivity bonus differs: " .. tostring(machine.productivity_bonus))
  end
end

local function machine_for(force)
  local machine = game.surfaces[1].create_entity{
    name = assembler_name,
    position = {0, 0},
    force = force
  }
  if machine == nil or machine.valid == false then fail("could not create native cable assembler") end
  -- LuaEntity.set_recipe returns any displaced items, not an operation boolean.
  machine.set_recipe(recipe_name)
  local input = machine.get_inventory(defines.inventory.crafter_input)
  local output = machine.get_inventory(defines.inventory.crafter_output)
  if input == nil or output == nil then fail("native cable assembler inventories are absent") end
  if not input.is_empty() or not output.is_empty() then fail("new cable assembler inventories are not empty") end
  assert_no_modules(machine)
  return machine
end

local function refill(state)
  if state.phase_plates_remaining == 0 then return end
  local machine = state.machine
  if machine == nil or machine.valid == false then fail("native cable assembler disappeared during refill") end
  machine.energy = 1000000000
  local input = machine.get_inventory(defines.inventory.crafter_input)
  local inserted = input.insert{name = input_name, count = state.phase_plates_remaining}
  if inserted < 0 or inserted > state.phase_plates_remaining then
    fail("native cable assembler reported invalid plate insertion " .. tostring(inserted))
  end
  if inserted > 0 then
    state.phase_plates_remaining = state.phase_plates_remaining - inserted
    state.phase_plates_inserted = state.phase_plates_inserted + inserted
    state.phase_refills = state.phase_refills + 1
  end
end

local function begin_crafting(state, phase)
  local machine = state.machine
  if machine == nil or machine.valid == false then fail("native cable assembler disappeared") end
  local input = machine.get_inventory(defines.inventory.crafter_input)
  local output = machine.get_inventory(defines.inventory.crafter_output)
  if input == nil or output == nil or not input.is_empty() or not output.is_empty() then
    fail("native cable assembler inventories were not clean before " .. phase)
  end
  machine.energy = 1000000000
  state.phase = phase
  state.phase_output = 0
  state.phase_plates_remaining = plates_per_phase
  state.phase_plates_inserted = 0
  state.phase_refills = 0
  refill(state)
end

local function drain_crafting(state, expected_output)
  local machine = state.machine
  if machine == nil or machine.valid == false then fail("native cable assembler disappeared while crafting") end
  machine.energy = 1000000000
  refill(state)
  local input = machine.get_inventory(defines.inventory.crafter_input)
  local output = machine.get_inventory(defines.inventory.crafter_output)
  local count = output.get_item_count(recipe_name)
  if count > 0 then
    if output.remove{name = recipe_name, count = count} ~= count then
      fail("could not drain native copper cable output")
    end
    state.phase_output = state.phase_output + count
  end
  if state.phase_plates_remaining ~= 0 or input.get_item_count(input_name) ~= 0
      or machine.crafting_progress ~= 0 then
    return false
  end
  if state.phase_plates_inserted ~= plates_per_phase then
    fail("native cable assembler did not receive exactly 100 copper plates")
  end
  -- A native assembler can expose an empty input and zero crafting progress
  -- between production updates. Do not accept that transient state until the
  -- complete physical output has been collected.
  if state.phase_output < expected_output then return false end
  if state.phase_output ~= expected_output then
    fail("native cable assembler produced an unexpected " .. state.phase .. " output "
      .. tostring(state.phase_output))
  end
  return true
end

local function complete_beta_research_with_native_setter(state)
  local force = player_force()
  local technology = technology_for(force)
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  -- This intentionally exercises the documented native researched setter;
  -- this fixture has no lab and does not claim laboratory completion.
  technology.researched = true
  if technology.researched ~= true or technology.level ~= 1 then
    fail("native setter did not complete the finite beta technology")
  end
  assert_beta_effect(technology)
  public_status(force, true)
  assert_productivity(force, state.machine, expected_productivity, "researched")
  state.research_completed_by_native_setter = true
end

local function assert_reload(state)
  local force = player_force()
  if state.phase ~= "completed" or not state.saved or not state.research_completed_by_native_setter then
    fail("saved production phase differs")
  end
  if state.baseline_plates_inserted ~= plates_per_phase or state.researched_plates_inserted ~= plates_per_phase
      or state.baseline_output ~= baseline_output or state.researched_output ~= researched_output then
    fail("saved cable production counts differ")
  end
  public_status(force, true)
  assert_productivity(force, state.machine, expected_productivity, "reloaded")
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = case_name,
    status = "passed",
    witnesses = {
      beta_consumer_marker_required = "MIR5_API_BETA",
      beta_technology = beta_technology_name,
      beta_public_query_before_research = true,
      beta_public_query_after_research = true,
      research_completed_by_native_setter = state.research_completed_by_native_setter,
      laboratory_research_used = false,
      native_effect_change = expected_productivity,
      baseline_recipe_productivity_bonus = 0,
      researched_recipe_productivity_bonus = expected_productivity,
      baseline_assembler_productivity_bonus = 0,
      researched_assembler_productivity_bonus = expected_productivity,
      assembler_modules_empty = true,
      beacon_entities_created = false,
      baseline_copper_plates_inserted = state.baseline_plates_inserted,
      researched_copper_plates_inserted = state.researched_plates_inserted,
      baseline_copper_cables_output = state.baseline_output,
      researched_copper_cables_output = state.researched_output,
      production_observation = "native-runner-readback-required",
      fixture_on_load_defers_native_checks = stage == "reload"
    }
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["more-infinite-research"] ~= "5.0.21000"
      or script.active_mods["mir-fixture-mir5-api-beta"] ~= "0.1.0" then
    fail("fixture loaded with an unexpected Factorio, MIR, or API-beta closure")
  end
  game.speed = 16
  local force = player_force()
  force.enable_all_prototypes()
  local technology = technology_for(force)
  if technology.researched or technology.level ~= 1 then
    fail("beta init observer did not leave its finite technology unresearched")
  end
  assert_beta_effect(technology)
  local machine = machine_for(force)
  public_status(force, false)
  assert_productivity(force, machine, 0, "baseline")
  storage[storage_key] = {
    phase = "await-baseline",
    machine = machine,
    phase_plates_remaining = 0,
    phase_plates_inserted = 0,
    phase_refills = 0,
    phase_output = 0,
    baseline_plates_inserted = 0,
    researched_plates_inserted = 0,
    baseline_output = 0,
    researched_output = 0,
    research_completed_by_native_setter = false,
    deadline_tick = game.tick + 18000
  }
  -- On-init leaves beta unresearched. Work begins only on the first tick, so
  -- the independent api-beta init observer has already emitted its witness.
end)

script.on_load(function()
  local state = storage[storage_key]
  if state and state.saved then
    loaded_snapshot = {
      phase = state.phase,
      baseline_output = state.baseline_output,
      researched_output = state.researched_output,
      baseline_plates_inserted = state.baseline_plates_inserted,
      researched_plates_inserted = state.researched_plates_inserted
    }
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[storage_key]
  if state == nil then fail("fixture state is absent") end
  if state.saved then
    if loaded_snapshot and not reload_logged then
      if state.phase ~= loaded_snapshot.phase or state.baseline_output ~= loaded_snapshot.baseline_output
          or state.researched_output ~= loaded_snapshot.researched_output
          or state.baseline_plates_inserted ~= loaded_snapshot.baseline_plates_inserted
          or state.researched_plates_inserted ~= loaded_snapshot.researched_plates_inserted then
        fail("on_load did not preserve the completed cable production witness")
      end
      assert_reload(state)
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then
    fail("native copper cable production did not complete within 18000 ticks")
  end
  if state.phase == "await-baseline" then
    -- This first-tick query is an ordering witness before any native setter.
    public_status(player_force(), false)
    begin_crafting(state, "baseline")
  elseif state.phase == "baseline" then
    if not drain_crafting(state, baseline_output) then return end
    if state.phase_output ~= baseline_output then
      fail("100 baseline copper plates did not produce exactly 200 copper cables")
    end
    state.baseline_plates_inserted = state.phase_plates_inserted
    state.baseline_output = state.phase_output
    complete_beta_research_with_native_setter(state)
    begin_crafting(state, "researched")
  elseif state.phase == "researched" then
    if not drain_crafting(state, researched_output) then return end
    if state.phase_output ~= researched_output then
      fail("100 researched copper plates did not produce exactly 202 copper cables")
    end
    state.researched_plates_inserted = state.phase_plates_inserted
    state.researched_output = state.phase_output
    -- assert_reload is the durable-state oracle; set the witnessed state
    -- before invoking it so the initial and cold-reload paths share it.
    state.phase = "completed"
    state.saved = true
    assert_reload(state)
    marker("initial", state)
    game.server_save(save_name)
  else
    fail("unknown fixture phase " .. tostring(state.phase))
  end
end)
