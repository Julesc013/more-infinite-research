-- Private F210 Bob-core witness. It earns the independently captured MIR
-- material rows in a real lab, then uses two untouched upstream alloy recipes
-- in a fixture-owned clone of their native Bob mixing furnace. The fixture
-- never writes a force recipe bonus, recipe definition, or selected MIR level.
local KEY = "mir5_bob_core_gameplay"
local SAVE = "mir5-native-complete"
local INITIAL_PACKS = 64
local DEADLINE_TICKS = 72000
local LAB_ENERGY = 100000000
local ALLOY_ENERGY = 100000000
local UINT32_MAX = 4294967295
local EFFECT = 0.02
local ALLOY_CRAFTS = 100
local ALLOY_EARNED_BONUS = 0.08
local ALLOY_MIN_BONUS_CRAFTS = 7
local ALLOY_MAX_BONUS_CRAFTS = 8
local MIXING_FIXTURE_MACHINE = "mir5-bob-core-alloy-witness-furnace"
local METALLURGY_FIXTURE_MACHINE = "mir5-bob-core-alloy-witness-foundry"
local loaded, reported

local REQUIRED = {
  base="2.1.23", ["space-age"]="2.1.23", boblibrary="3.0.1", bobores="3.0.0",
  bobplates="3.0.2", bobelectronics="3.0.1", bobtech="3.0.0",
}

local FAMILIES = {
  {key="research_material_tin", early="recipe-prod-research_material_tin-1", tail="recipe-prod-research_material_tin-4", recipes={"bob-tin-plate"}},
  {key="research_material_lead", early="recipe-prod-research_material_lead-1", tail="recipe-prod-research_material_lead-4", recipes={"bob-lead-plate"}},
  {key="research_material_bronze", early="recipe-prod-research_material_bronze-1", tail="recipe-prod-research_material_bronze-4", recipes={"bob-bronze-alloy"}},
  {key="research_material_gunmetal", early="recipe-prod-research_material_gunmetal-1", tail="recipe-prod-research_material_gunmetal-4", recipes={"bob-gunmetal-alloy"}},
  {key="research_material_invar", early="recipe-prod-research_material_invar-1", tail="recipe-prod-research_material_invar-4", recipes={"bob-invar-alloy"}},
  {key="research_material_nitinol", early="recipe-prod-research_material_nitinol-1", tail="recipe-prod-research_material_nitinol-4", recipes={"bob-nitinol-alloy"}},
  {key="research_material_copper_tungsten", early="recipe-prod-research_material_copper_tungsten-1", tail="recipe-prod-research_material_copper_tungsten-4", recipes={"bob-copper-tungsten-alloy"}},
}

-- The finite physical witness is independently fixed from the F210 no-Angel
-- captured routes and the exact bobplates_3.0.2 archive. Copper Tungsten is
-- the Space Age metallurgy/fluid branch, not the archive's non-SA mixing/item
-- branch. This is not a route collector and does not claim full Bob coverage.
local ALLOYS = {
  {
    recipe="bob-bronze-alloy", machine=MIXING_FIXTURE_MACHINE,
    category="bob-mixing-furnace", energy=16, inherent_productivity=0,
    ingredients={{type="item", name="copper-plate", amount=3}, {type="item", name="bob-tin-plate", amount=2}},
    result={type="item", name="bob-bronze-alloy", amount=5},
  },
  {
    recipe="bob-gunmetal-alloy", machine=MIXING_FIXTURE_MACHINE,
    category="bob-mixing-furnace", energy=32, inherent_productivity=0,
    ingredients={{type="item", name="copper-plate", amount=8}, {type="item", name="bob-tin-plate", amount=1}, {type="item", name="bob-zinc-plate", amount=1}},
    result={type="item", name="bob-gunmetal-alloy", amount=10},
  },
  {
    recipe="bob-invar-alloy", machine=MIXING_FIXTURE_MACHINE,
    category="bob-mixing-furnace", energy=16, inherent_productivity=0,
    ingredients={{type="item", name="bob-nickel-plate", amount=2}, {type="item", name="iron-plate", amount=3}},
    result={type="item", name="bob-invar-alloy", amount=5},
  },
  {
    recipe="bob-nitinol-alloy", machine=MIXING_FIXTURE_MACHINE,
    category="bob-mixing-furnace", energy=16, inherent_productivity=0,
    ingredients={{type="item", name="bob-nickel-plate", amount=3}, {type="item", name="bob-titanium-plate", amount=2}},
    result={type="item", name="bob-nitinol-alloy", amount=5},
  },
  {
    recipe="bob-copper-tungsten-alloy", machine=METALLURGY_FIXTURE_MACHINE,
    category="metallurgy", energy=16, inherent_productivity=0.5,
    ingredients={{type="item", name="bob-powdered-tungsten", amount=3}, {type="fluid", name="molten-copper", amount=20}},
    result={type="item", name="bob-copper-tungsten-alloy", amount=5},
  },
}
local ALLOY_BY_RECIPE = {}
for _, route in ipairs(ALLOYS) do ALLOY_BY_RECIPE[route.recipe] = route end

-- These are direct independently captured external prerequisites. No
-- technology traversal can silently earn a selected MIR material row.
local EXTERNAL_PREREQUISITES = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "space-science-pack", "metallurgic-science-pack",
  "bob-alloy-processing", "bob-zinc-processing", "bob-invar-processing",
  "bob-nitinol-processing", "bob-tungsten-processing",
}
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "space-science-pack", "metallurgic-science-pack",
}
local CONSUMPTION = {
  ["automation-science-pack"]=28, ["logistic-science-pack"]=20,
  ["chemical-science-pack"]=16, ["production-science-pack"]=8,
  ["space-science-pack"]=10, ["metallurgic-science-pack"]=4,
}

local function fail(message)
  error("[mir5-bob-core-gameplay] " .. message)
end

local function near(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function near_progress(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0001
end

local function exact_names(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count changed") end
  for index, expected_name in ipairs(expected) do
    if actual[index] ~= expected_name then fail(label .. " changed at " .. tostring(index)) end
  end
end

local function entry_name(value) return type(value) == "table" and (value.name or value[1]) or nil end
local function entry_amount(value) return type(value) == "table" and (value.amount or value[2]) or nil end

local function matching_entries(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count changed") end
  local wanted, seen = {}, {}
  for _, row in ipairs(expected) do
    wanted[row.name] = row
  end
  for index, value in ipairs(actual) do
    local name = entry_name(value)
    local wanted_row = wanted[name]
    if type(value) ~= "table" or wanted_row == nil or seen[name]
        or (value.type or "item") ~= wanted_row.type or entry_amount(value) ~= wanted_row.amount
        or value.temperature ~= wanted_row.temperature
        or value.minimum_temperature ~= wanted_row.minimum_temperature
        or value.maximum_temperature ~= wanted_row.maximum_temperature
        or value.amount_min ~= nil or value.amount_max ~= nil
        or (value.probability ~= nil and value.probability ~= 1)
        or (value.independent_probability ~= nil and value.independent_probability ~= 1)
        or (value.extra_count_fraction ~= nil and value.extra_count_fraction ~= 0)
        or (value.ignored_by_productivity ~= nil and value.ignored_by_productivity ~= 0)
        or (value.ignored_by_stats ~= nil and value.ignored_by_stats ~= 0) then
      fail(label .. " changed at " .. tostring(index) .. ": actual="
        .. tostring(type(value) == "table" and entry_name(value)) .. "/"
        .. tostring(type(value) == "table" and entry_amount(value)))
    end
    seen[name] = true
  end
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if not value or value.valid == false then fail("named technology is absent: " .. name) end
  return value
end

local function check_closure()
  for name, version in pairs(REQUIRED) do
    if script.active_mods[name] ~= version then fail("unexpected Bob-core closure member: " .. name) end
  end
  if script.active_mods["more-infinite-research"] ~= "5.0.21000"
      or script.active_mods["mir-fixture-mir5-bob-core-gameplay"] ~= "0.1.0"
      or script.active_mods.angelssmelting ~= nil or script.active_mods.angelsrefining ~= nil then
    fail("unexpected F210 Bob-core gameplay closure")
  end
end

local function assert_effects(value, family)
  local effects = value.prototype and value.prototype.effects
  if type(effects) ~= "table" or #effects ~= #family.recipes then
    fail(value.name .. " native recipe effects changed")
  end
  for index, recipe in ipairs(family.recipes) do
    local effect = effects[index]
    if not effect or effect.type ~= "change-recipe-productivity"
        or effect.recipe ~= recipe or not near(effect.change, EFFECT) then
      fail(value.name .. " native recipe effect changed")
    end
  end
end

local function assert_prototypes(force, family)
  local early, tail = technology(force, family.early), technology(force, family.tail)
  if not early.prototype or early.prototype.max_level ~= 3
      or not tail.prototype or tail.prototype.max_level ~= UINT32_MAX then
    fail(family.key .. " native finite/tail boundary changed")
  end
  assert_effects(early, family)
  assert_effects(tail, family)
  return early, tail
end

local function assert_acceleration(force)
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_prototypes(force, family)
    for _, value in ipairs({early, tail}) do
      if value.research_unit_count ~= 1 or value.research_unit_energy ~= 60 then
        fail(value.name .. " fixture cost or time differs")
      end
    end
  end
end

local function assert_initial(force)
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_prototypes(force, family)
    if early.level ~= 1 or early.researched or early.enabled ~= true
        or tail.level ~= 4 or tail.researched then
      fail(family.key .. " did not begin at the native early-one/tail-four boundary")
    end
  end
end

local function plan()
  local out = {}
  for _, family in ipairs(FAMILIES) do
    out[#out + 1] = family.early
    out[#out + 1] = family.early
    out[#out + 1] = family.early
    out[#out + 1] = family.tail
  end
  return out
end

local function assert_bonus(force, expected)
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs(family.recipes) do
      local recipe = force.recipes[name]
      if not recipe or not near(recipe.productivity_bonus, expected) then
        fail("native recipe productivity differs for " .. name)
      end
    end
  end
end

local function assert_alloy_route(force, route, expected_bonus, label)
  local prototype = prototypes.recipe[route.recipe]
  if not prototype or prototype.name ~= route.recipe or not near(prototype.energy, route.energy)
      or not near(prototype.maximum_productivity, 3) then
    fail(label .. " native alloy recipe identity changed")
  end
  exact_names(prototype.categories, {route.category}, label .. " native alloy categories")
  -- Runtime recipe entries use engine order, which is not an authored order.
  matching_entries(prototype.ingredients, route.ingredients, label .. " native alloy ingredients")
  matching_entries(prototype.products, {route.result}, label .. " native alloy result")
  local recipe = force.recipes[route.recipe]
  if not recipe or recipe.valid == false or recipe.enabled ~= true
      or not near(recipe.productivity_bonus, expected_bonus) then
    fail(label .. " native alloy force recipe differs")
  end
  return recipe
end

local function route_has_fluid(route)
  for _, ingredient in ipairs(route.ingredients) do
    if ingredient.type == "fluid" then return true end
  end
  return false
end

local function alloy_inventories(machine, route, label)
  if not machine or machine.valid == false or not machine.prototype
      or machine.prototype.name ~= route.machine
      or type(machine.prototype.crafting_categories) ~= "table"
      or machine.prototype.crafting_categories[route.category] ~= true then
    fail(label .. " native alloy machine differs")
  end
  local input = machine.get_inventory(defines.inventory.crafter_input)
  local output = machine.get_inventory(defines.inventory.crafter_output)
  local modules = machine.get_inventory(defines.inventory.crafter_modules)
  if not input or not output then fail(label .. " native alloy inventories are absent") end
  if modules and not modules.is_empty() then fail(label .. " native alloy machine has modules") end
  return input, output
end

local function fluid_storage_observation(machine)
  local selected = machine.get_recipe()
  local recipe = selected and selected.name or "<none>"
  local count = machine.fluids_count
  local capacities = {}
  if type(count) == "number" and count >= 0 and count == math.floor(count)
      and count <= 16 and type(machine.get_fluid_capacity) == "function" then
    for index = 1, count do
      capacities[#capacities + 1] = tostring(machine.get_fluid_capacity(index))
    end
  else
    capacities[1] = "<not-queried>"
  end
  return "recipe=" .. tostring(recipe) .. ",fluids_count=" .. tostring(count)
    .. ",capacities=[" .. table.concat(capacities, ",") .. "]"
end

local function assert_route_fluid_machine(machine, route, label, before)
  if not route_has_fluid(route) then return end
  if type(machine.fluids_count) ~= "number" or machine.fluids_count ~= 4
      or type(machine.get_fluid_capacity) ~= "function"
      or machine.get_fluid_capacity(1) ~= 1000 or machine.get_fluid_capacity(2) ~= 1000
      or machine.get_fluid_capacity(3) ~= 100 or machine.get_fluid_capacity(4) ~= 100
      or type(machine.get_fluid_count) ~= "function" or type(machine.insert_fluid) ~= "function" then
    local observed_before = type(before) == "string" and before or "<not-observed>"
    fail(label .. " native metallurgy fluid machine differs; before={" .. observed_before
      .. "}; after={" .. fluid_storage_observation(machine) .. "}")
  end
end

local function assert_empty_route_fluids(machine, route, label)
  for _, ingredient in ipairs(route.ingredients) do
    if ingredient.type == "fluid" and machine.get_fluid_count(ingredient.name) ~= 0 then
      fail(label .. " native alloy fluid input was not clean")
    end
  end
end

local function setup_alloy_machines(force)
  local surface = game.surfaces[1]
  local out = {}
  for index, route in ipairs(ALLOYS) do
    local machine = surface and surface.create_entity{
      name=route.machine, position={4 + index * 6, 0}, force=force,
    }
    if not machine or machine.valid == false then fail("could not create native alloy machine: " .. route.recipe) end
    out[route.recipe] = machine
  end
  return out
end

local function refill_alloy(production, input, machine, label)
  for _, ingredient in ipairs(production.route.ingredients) do
    local remaining = production.remaining[ingredient.name]
    if remaining > 0 then
      local inserted
      if ingredient.type == "fluid" then
        inserted = machine.insert_fluid{name=ingredient.name, amount=remaining}
      else
        inserted = input.insert{name=ingredient.name, count=remaining}
      end
      if type(inserted) ~= "number" or inserted < 0 or inserted > remaining then
        fail(label .. " alloy input insertion differs: " .. ingredient.type .. "/" .. ingredient.name)
      end
      production.remaining[ingredient.name] = remaining - inserted
      production.inserted[ingredient.name] = production.inserted[ingredient.name] + inserted
    end
  end
end

local function begin_alloy(state, phase)
  local route = ALLOYS[state.alloy_index]
  if not route then fail("physical alloy phase has no named route") end
  local expected_bonus = phase == "physical-before" and 0 or ALLOY_EARNED_BONUS
  assert_alloy_route(game.forces.player, route, expected_bonus, phase .. " " .. route.recipe)
  local machine = state.alloy_machines[route.recipe]
  local input, output = alloy_inventories(machine, route, phase .. " " .. route.recipe)
  local fluid_before = route_has_fluid(route) and fluid_storage_observation(machine) or "<not-applicable>"
  if not input.is_empty() or not output.is_empty() or machine.crafting_progress ~= 0
      or not near(machine.bonus_progress, 0) then
    fail(phase .. " " .. route.recipe .. " native alloy machine was not clean")
  end
  assert_empty_route_fluids(machine, route, phase .. " " .. route.recipe)
  machine.set_recipe(route.recipe)
  local selected = machine.get_recipe()
  if not selected or selected.name ~= route.recipe then
    fail(phase .. " " .. route.recipe .. " could not select native alloy recipe")
  end
  assert_route_fluid_machine(machine, route, phase .. " " .. route.recipe, fluid_before)
  local baseline_crafts = ALLOY_CRAFTS * route.inherent_productivity
  local minimum_bonus = phase == "physical-before" and baseline_crafts
    or baseline_crafts + ALLOY_MIN_BONUS_CRAFTS
  local maximum_bonus = phase == "physical-before" and baseline_crafts
    or baseline_crafts + ALLOY_MAX_BONUS_CRAFTS
  local production = {
    phase=phase, route=route, recipe=route.recipe, earned=expected_bonus,
    minimum_bonus=minimum_bonus, maximum_bonus=maximum_bonus,
    output=0, remaining={}, inserted={}, finished=false,
  }
  for _, ingredient in ipairs(route.ingredients) do
    production.remaining[ingredient.name] = ingredient.amount * ALLOY_CRAFTS
    production.inserted[ingredient.name] = 0
  end
  state.alloy = production
  refill_alloy(production, input, machine, phase .. " " .. route.recipe)
end

local function tick_alloy(state)
  local production = state.alloy
  if type(production) ~= "table" or production.finished then return production and production.finished end
  local route = ALLOY_BY_RECIPE[production.recipe]
  if route ~= production.route then fail("physical alloy route state changed") end
  local label = production.phase .. " " .. route.recipe
  assert_alloy_route(game.forces.player, route, production.earned, label)
  local machine = state.alloy_machines[route.recipe]
  local input, output = alloy_inventories(machine, route, label)
  assert_route_fluid_machine(machine, route, label)
  machine.energy = ALLOY_ENERGY
  refill_alloy(production, input, machine, label)
  local made = output.get_item_count(route.result.name)
  if made > 0 then
    if output.remove{name=route.result.name, count=made} ~= made then
      fail(label .. " could not drain native alloy output")
    end
    production.output = production.output + made
  end
  for _, ingredient in ipairs(route.ingredients) do
    local actual = ingredient.type == "fluid" and machine.get_fluid_count(ingredient.name)
      or input.get_item_count(ingredient.name)
    if production.remaining[ingredient.name] ~= 0 or actual ~= 0 then return false end
    if production.inserted[ingredient.name] ~= ingredient.amount * ALLOY_CRAFTS then
      fail(label .. " alloy input count differs: " .. ingredient.name)
    end
  end
  if machine.crafting_progress ~= 0 then return false end
  local crafts = production.output / route.result.amount
  local bonus_crafts = crafts - ALLOY_CRAFTS
  if production.output % route.result.amount ~= 0
      or bonus_crafts < production.minimum_bonus or bonus_crafts > production.maximum_bonus then
    fail(label .. " native alloy output differs: " .. tostring(production.output))
  end
  local expected_progress = ALLOY_CRAFTS * (route.inherent_productivity + production.earned) - bonus_crafts
  if expected_progress < -0.0001 or expected_progress > 1.0001
      or not near_progress(machine.bonus_progress, expected_progress) then
    fail(label .. " native alloy productivity progress differs")
  end
  production.bonus_crafts = bonus_crafts
  production.native_bonus_progress = machine.bonus_progress
  production.machine_productivity_bonus = machine.productivity_bonus
  if type(production.machine_productivity_bonus) ~= "number" then
    fail(label .. " native alloy productivity observation differs")
  end
  production.finished = true
  return true
end

local function assert_physical_phase(state, phase, observe_machine)
  local records = state.physical and state.physical[phase]
  if type(records) ~= "table" then fail(phase .. " alloy witness is absent") end
  for _, route in ipairs(ALLOYS) do
    local record = records[route.recipe]
    if type(record) ~= "table" then fail(phase .. " alloy record is absent: " .. route.recipe) end
    local baseline_crafts = ALLOY_CRAFTS * route.inherent_productivity
    local minimum_bonus = phase == "physical-before" and baseline_crafts
      or baseline_crafts + ALLOY_MIN_BONUS_CRAFTS
    local maximum_bonus = phase == "physical-before" and baseline_crafts
      or baseline_crafts + ALLOY_MAX_BONUS_CRAFTS
    local minimum = route.result.amount * (ALLOY_CRAFTS + minimum_bonus)
    local maximum = route.result.amount * (ALLOY_CRAFTS + maximum_bonus)
    if record.output < minimum or record.output > maximum
        or record.bonus_crafts < minimum_bonus or record.bonus_crafts > maximum_bonus
        or type(record.native_bonus_progress) ~= "number"
        or type(record.machine_productivity_bonus) ~= "number" then
      fail(phase .. " alloy record differs: " .. route.recipe)
    end
    if phase == "physical-after" then
      local before = state.physical["physical-before"][route.recipe]
      local incremental = before and record.bonus_crafts - before.bonus_crafts
      if type(incremental) ~= "number" or incremental < ALLOY_MIN_BONUS_CRAFTS
          or incremental > ALLOY_MAX_BONUS_CRAFTS then
        fail(phase .. " alloy earned productivity differs: " .. route.recipe)
      end
    end
    if observe_machine then
      local expected_bonus = phase == "physical-before" and 0 or ALLOY_EARNED_BONUS
      assert_alloy_route(game.forces.player, route, expected_bonus, phase .. " " .. route.recipe)
      local machine = state.alloy_machines and state.alloy_machines[route.recipe]
      local input, output = alloy_inventories(machine, route, phase .. " " .. route.recipe)
      assert_route_fluid_machine(machine, route, phase .. " " .. route.recipe)
      if not input.is_empty() or not output.is_empty() or machine.crafting_progress ~= 0
          or not near_progress(machine.bonus_progress, record.native_bonus_progress)
          or not near(machine.productivity_bonus, record.machine_productivity_bonus) then
        fail(phase .. " native alloy machine state differs: " .. route.recipe)
      end
      assert_empty_route_fluids(machine, route, phase .. " " .. route.recipe)
    end
  end
end

local function advance_alloy(state, phase)
  if not state.alloy then begin_alloy(state, phase) end
  if not tick_alloy(state) then return false end
  local production = state.alloy
  state.physical[phase][production.recipe] = {
    output=production.output, bonus_crafts=production.bonus_crafts,
    native_bonus_progress=production.native_bonus_progress,
    machine_productivity_bonus=production.machine_productivity_bonus,
  }
  state.alloy = nil
  state.alloy_index = state.alloy_index + 1
  if state.alloy_index <= #ALLOYS then return false end
  assert_physical_phase(state, phase, true)
  return true
end

local function assert_consumption(state)
  local lab = state.lab
  if not lab or lab.valid == false then fail("real Bob-core lab is absent") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real Bob-core lab input inventory is absent") end
  for _, name in ipairs(SCIENCE) do
    if inventory.get_item_count(name) ~= INITIAL_PACKS - CONSUMPTION[name] then
      fail("real lab science consumption differs for " .. name)
    end
  end
end

local function assert_laboratory_complete(state)
  local force = game.forces.player
  if state.finished ~= #state.plan or state.events ~= #state.plan or state.next ~= #state.plan + 1
      or force.current_research ~= nil or #(force.research_queue or {}) ~= 0 then
    fail("real lab did not complete all twenty-eight selected research levels")
  end
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_prototypes(force, family)
    if early.level ~= 3 or early.researched ~= true or tail.level ~= 5 or tail.researched ~= false then
      fail("real lab did not retain the earned finite-three/tail-four boundary for " .. family.key)
    end
  end
  assert_bonus(force, 0.08)
  assert_consumption(state)
end

local function assert_complete(state)
  assert_laboratory_complete(state)
  assert_physical_phase(state, "physical-before", false)
  assert_physical_phase(state, "physical-after", true)
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="bob-core-gameplay", stage=stage, status="passed",
    witnesses={
      profile="f210-bob-core-no-angel", selected_families=7,
      named_technologies=14, actual_lab_completions=state.finished,
      finite_levels_completed_by_lab=21, continuation_levels_completed_by_lab=7,
      science_consumed=CONSUMPTION, native_recipe_productivity_per_route=0.08,
      native_effect_per_completed_level=EFFECT, fixture_accelerates_count_and_time=true,
      physical_alloy_witness=true, physical_routes={"bob-bronze-alloy", "bob-gunmetal-alloy", "bob-invar-alloy", "bob-nitinol-alloy", "bob-copper-tungsten-alloy"},
      physical_crafts_per_route=ALLOY_CRAFTS,
      physical_before_mir_productivity=true, physical_after_mir_productivity=true,
      physical_mixing_routes=4, physical_metallurgy_fluid_routes=1,
      physical_foundry_inherent_productivity=0.5,
      ordinary_tuning_qualified=false, candidate_full_catalogue_comparison_required=true,
      on_load_read_only=stage == "reload", foreign_force_witness_not_claimed=true,
    },
  }))
end

local function start_next_research(state)
  if state.next > #state.plan then return end
  local force = game.forces.player
  if force.current_research ~= nil then return end
  if state.finished ~= state.next - 1 then fail("next research did not wait for the preceding completion") end
  local value = technology(force, state.plan[state.next])
  if value.enabled ~= true then fail("next native material research is not enabled: " .. value.name) end
  if force.add_research(value) ~= true then fail("could not start real material research: " .. value.name) end
  state.next = state.next + 1
end

script.on_init(function()
  check_closure()
  if storage[KEY] ~= nil then fail("fresh gameplay fixture found existing state") end
  local force = game.forces.player
  for _, name in ipairs(EXTERNAL_PREREQUISITES) do technology(force, name).researched = true end
  assert_initial(force)
  assert_acceleration(force)
  assert_bonus(force, 0)

  local surface = game.surfaces[1]
  local lab = surface.create_entity{name="lab", position=force.get_spawn_position(surface), force=force}
  if not lab or lab.valid == false then fail("could not create real Bob-core lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real Bob-core lab input inventory is absent") end
  for _, name in ipairs(SCIENCE) do
    if inventory.insert{name=name, count=INITIAL_PACKS} ~= INITIAL_PACKS then
      fail("real Bob-core lab rejected " .. name)
    end
  end
  lab.energy = LAB_ENERGY
  game.speed = 16
  storage[KEY] = {
    phase="physical-before", plan=plan(), next=1, finished=0, events=0,
    lab=lab, alloy_machines=setup_alloy_machines(force), alloy_index=1,
    physical={ ["physical-before"]={}, ["physical-after"]={} },
    deadline=game.tick + DEADLINE_TICKS,
  }
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching" or not event.research
      or event.research.force ~= game.forces.player then return end
  local expected = state.plan[state.finished + 1]
  if not expected or event.research.name ~= expected then fail("unexpected native material completion") end
  state.finished, state.events = state.finished + 1, state.events + 1
  if state.finished > #state.plan then fail("native material completion exceeded the plan") end
end)

script.on_load(function()
  local state = storage[KEY]
  if state and state.phase == "complete" then
    -- Saved state is only observed after cold load; nothing is repaired here.
    loaded = {finished=state.finished, events=state.events, next=state.next}
  else
    loaded = nil
  end
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("gameplay fixture state is absent") end
  if state.phase == "complete" then
    if loaded and not reported then
      if loaded.finished ~= state.finished or loaded.events ~= state.events or loaded.next ~= state.next then
        fail("on_load changed the saved Bob-core witness")
      end
      assert_complete(state)
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline then fail("real Bob-core labs exceeded deadline") end
  if not state.lab or state.lab.valid == false then fail("real Bob-core lab was removed") end
  state.lab.energy = LAB_ENERGY
  if state.phase == "physical-before" then
    if advance_alloy(state, "physical-before") then
      state.phase, state.alloy_index = "researching", 1
    end
    return
  end
  if state.phase == "physical-after" then
    if advance_alloy(state, "physical-after") then
      assert_complete(state)
      state.phase = "complete"
      marker("initial", state)
      game.server_save(SAVE)
    end
    return
  end
  if state.phase ~= "researching" then fail("unknown Bob-core fixture phase") end
  if state.finished == #state.plan then
    assert_laboratory_complete(state)
    state.phase, state.alloy_index = "physical-after", 1
    return
  end
  start_next_research(state)
end)
