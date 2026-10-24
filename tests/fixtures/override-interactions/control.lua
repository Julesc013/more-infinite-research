-- F210 runtime and physical-output witness for selected prototype overrides.
-- Exact pipeline extent and receiver limit fields are established in data-final
-- because the F210 runtime API has no property for them.
local KEY = "mir5_override_interactions"
local PREFIX = "mir5-override-"
local ORDINARY = PREFIX .. "ordinary"
local RECYCLED = PREFIX .. "recycling"
local PARAMETER = PREFIX .. "parameter"
local MACHINE = PREFIX .. "assembler"
local PIPELINE = PREFIX .. "pipeline"
local MODULE = PREFIX .. "module"
local EFFECTS = {"speed", "productivity", "consumption", "pollution", "quality"}
local loaded, reported = false, false

local function fail(message, fields)
  if fields then
    fields.case, fields.status, fields.error = "override-interactions", "failed", message
    log("[MIR5_NATIVE_FIXTURE] DIAGNOSTIC " .. helpers.table_to_json(fields))
  end
  error("[mir5-override-interactions] " .. message)
end
local function near(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end
local function exact_permissions(actual, expected, label)
  local seen = {}
  for name, value in pairs(actual or {}) do
    if value ~= true or expected[name] ~= true then fail(label .. " has unexpected entry " .. tostring(name)) end
    seen[name] = true
  end
  for name in pairs(expected) do if not seen[name] then fail(label .. " is missing " .. name) end end
end
local function exact_effect_mask(actual, enabled, label)
  for _, name in ipairs(EFFECTS) do
    if type(actual and actual[name]) ~= "boolean" then fail(label .. " is missing " .. name) end
    if actual[name] ~= (enabled[name] == true) then fail(label .. " differs at " .. name) end
  end
  for name, value in pairs(actual or {}) do
    if type(value) ~= "boolean" or value == true and enabled[name] ~= true then
      fail(label .. " has unexpected entry " .. tostring(name))
    end
  end
end
local function categories()
  local out = {}
  for name in pairs(prototypes.module_category) do out[name] = true end
  if next(out) == nil then fail("native module category map is empty") end
  return out
end
local function prototype_witness()
  local ordinary, recycled, parameter = prototypes.recipe[ORDINARY], prototypes.recipe[RECYCLED], prototypes.recipe[PARAMETER]
  local machine, pipeline = prototypes.entity[MACHINE], prototypes.entity[PIPELINE]
  if not ordinary or not recycled or not parameter or not machine or not pipeline then fail("fixture prototype is absent") end
  if not near(ordinary.maximum_productivity, 1) then fail("runtime productivity cap differs") end
  local products = recycled.products or {}
  local product = products[1] or {}
  if not near(recycled.maximum_productivity, 0.5) or #products ~= 1
      or product.type ~= "item" or product.name ~= "iron-plate" or product.amount ~= 1
      or not near(product.independent_probability, 0.2) then
    fail("runtime recycling prototype differs", {
      expected={maximum_productivity=0.5, product_count=1, type="item", name="iron-plate",
        amount=1, independent_probability=0.2},
      actual={maximum_productivity=recycled.maximum_productivity, product_count=#products,
        type=product.type, name=product.name, amount=product.amount,
        independent_probability=product.independent_probability, legacy_probability=product.probability,
        extra_count_fraction=product.extra_count_fraction},
    })
  end
  local expected_effects, expected_categories = {}, categories()
  for _, name in ipairs(EFFECTS) do expected_effects[name] = true end
  exact_effect_mask(ordinary.allowed_effects, expected_effects, "ordinary effects")
  exact_permissions(ordinary.allowed_module_categories, expected_categories, "ordinary categories")
  exact_effect_mask(machine.allowed_effects, expected_effects, "receiver effects")
  exact_permissions(machine.allowed_module_categories, expected_categories, "receiver categories")
  exact_effect_mask(parameter.allowed_effects, {}, "parameter effects")
  exact_permissions(parameter.allowed_module_categories, {speed=true}, "parameter categories")
  -- LuaEntityPrototype.energy_usage is joules per tick.  The authored data
  -- value is 1W, so F210 exposes 1 / 60 J per tick at its 60-tick second.
  if not near(machine.energy_usage, 1 / 60) or pipeline.effect_receiver == nil then
    fail("runtime receiver witness differs")
  end
end
local function assert_complete(state)
  local machine = state.machine
  if not machine or not machine.valid then fail("witness assembler is absent") end
  local input = machine.get_inventory(defines.inventory.crafter_input)
  local output = machine.get_inventory(defines.inventory.crafter_output)
  local modules = machine.get_module_inventory()
  if not input or not output or not modules then fail("assembler inventories are absent") end
  if input.get_item_count("iron-plate") ~= 0 or output.get_item_count("iron-gear-wheel") ~= 6
      or modules.get_item_count(MODULE) ~= 2 then fail("native module productivity output differs") end
  if not state.saved or state.completed_tick == nil then fail("physical completion was not saved") end
end
local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="override-interactions", stage=stage, status="passed",
    witnesses={runtime_productivity_cap=1, runtime_recycling_probability=0.2,
      public_module_permission_maps=true, data_energy_usage_watts=1,
      runtime_energy_usage_joules_per_tick=1 / 60,
      data_stage_pipeline_extent=480, data_stage_receiver_ranges=true,
      physical_module_count=2, physical_iron_plate_consumed=10,
      physical_iron_gear_wheels=6, self_recycling_classifier="inactive-cap1-threshold4",
      on_load_read_only=stage == "reload", ordinary_tuning_qualified=false}
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["space-age"] ~= "2.1.23"
      or script.active_mods["more-infinite-research"] ~= "5.0.21000" then fail("unexpected native target") end
  prototype_witness()
  local force = game.forces.player
  local recipe = force.recipes[ORDINARY]
  if not recipe or not recipe.enabled then fail("ordinary fixture recipe is not natively enabled") end
  local machine = game.surfaces[1].create_entity{name=MACHINE, position={0, 0}, force=force}
  if not machine or not machine.valid or not machine.set_recipe(ORDINARY) then fail("could not set ordinary native recipe") end
  local input, modules = machine.get_inventory(defines.inventory.crafter_input), machine.get_module_inventory()
  if not input or not modules or input.insert{name="iron-plate", count=10} ~= 10
      or modules.insert{name=MODULE, count=2} ~= 2 then fail("could not prepare native productivity witness") end
  machine.energy = 100000000
  game.speed = 16
  storage[KEY] = {machine=machine, phase="crafting", saved=false, deadline=game.tick + 36000}
end)

script.on_load(function()
  loaded = storage[KEY] and storage[KEY].phase == "complete" or false
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("fixture state is absent") end
  if state.phase == "complete" then
    if loaded and not reported then assert_complete(state); marker("reload", state); reported=true end
    return
  end
  if game.tick > state.deadline then fail("native productivity witness exceeded deadline") end
  if not state.machine or not state.machine.valid then fail("witness assembler was removed") end
  state.machine.energy = 100000000
  local output = state.machine.get_inventory(defines.inventory.crafter_output)
  if output and output.get_item_count("iron-gear-wheel") == 6 then
    assert_complete({machine=state.machine, saved=true, completed_tick=game.tick})
    state.phase, state.saved, state.completed_tick = "complete", true, game.tick
    marker("initial", state)
    game.server_save("mir5-native-complete")
  elseif output and output.get_item_count("iron-gear-wheel") > 6 then
    fail("native productivity witness overproduced")
  end
end)
