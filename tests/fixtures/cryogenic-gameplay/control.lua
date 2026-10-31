local KEY = "mir5_cryogenic_gameplay"
local OWNER = "cryogenic-science-pack"
local GEAR = "recipe-prod-research_gears-1"
local FOREIGN = "mir5-cryogenic-native-science"
local PACKS = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "military-science-pack", "utility-science-pack",
  "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
  "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack",
}
local INITIAL = 32
local AGRICULTURAL = "agricultural-science-pack"
local AGRICULTURAL_SPOIL_TICKS = 60 * 60 * 60
-- `research_gears` defaults to ten percent. The fixture accelerates count
-- and time only, leaving the authored effect intact for this native witness.
local EXPECTED_GEAR_PRODUCTIVITY = 0.10
local EXPECTED_LABORATORY_PRODUCTIVITY = 0
local loaded, reported

local function diagnostic(message, fields)
  local payload = {
    case="cryogenic-gameplay", status="failed", error=message,
    expected_recipe_productivity=EXPECTED_GEAR_PRODUCTIVITY,
    expected_laboratory_productivity=EXPECTED_LABORATORY_PRODUCTIVITY,
  }
  for key, value in pairs(fields or {}) do payload[key] = value end
  log("[MIR5_NATIVE_FIXTURE] DIAGNOSTIC " .. helpers.table_to_json(payload))
end

local function fail(message, fields)
  if helpers and helpers.table_to_json and log then diagnostic(message, fields) end
  error("[mir5-cryogenic-gameplay] " .. message)
end

local function near(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function research(force, name)
  local value = force.technologies[name]
  if value == nil or value.valid == false then fail("missing native research " .. name) end
  return value
end

local function check_inputs(value, names)
  local expected = {}
  for _, name in ipairs(names) do expected[name] = true end
  local ingredients = value.research_unit_ingredients
  if #ingredients ~= #names then fail(value.name .. " native ingredient count differs") end
  for _, ingredient in ipairs(ingredients) do
    if expected[ingredient.name] ~= true or ingredient.amount ~= 1 then
      fail(value.name .. " native ingredients differ")
    end
    expected[ingredient.name] = nil
  end
  if next(expected) ~= nil then fail(value.name .. " lost a native ingredient") end
end

local function gear_effect_witness(gear)
  local prototype, matches, change = gear.prototype, 0, nil
  for _, effect in ipairs(prototype and prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == "iron-gear-wheel" then
      matches, change = matches + 1, effect.change
    end
  end
  return {technology=gear.name, level=gear.level, researched=gear.researched,
    recipe_effect_matches=matches, recipe_effect_change=change}
end

local function bonus_witness(force, gear)
  return {
    actual_recipe_productivity=force.recipes["iron-gear-wheel"].productivity_bonus,
    actual_laboratory_productivity=force.laboratory_productivity_bonus,
    gear=gear_effect_witness(gear),
  }
end

local function item_input_witness(lab, inventory, name)
  local stacks, prototype = {}, nil
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read and stack.name == name then
      prototype = stack.prototype
      stacks[#stacks + 1] = {
        slot=index, count=stack.count, spoil_percent=stack.spoil_percent,
        spoil_tick=stack.spoil_tick,
      }
    end
  end
  prototype = prototype or (prototypes and prototypes.item and prototypes.item[name])
  local stored = lab.get_stored_durability(name)
  local observed = {
    inventory_count=inventory.get_item_count(name),
    stored_durability=stored and stored.durability or nil,
    prototype_science_capacity=prototype and prototype.science_capacity or nil,
    prototype_spoil_ticks=prototype and prototype.get_spoil_ticks() or nil,
    stacks=stacks,
  }
  if prototype ~= nil then observed.prototype_lab_ignores_spoil_percent = prototype.lab_ignores_spoil_percent end
  return observed
end

local function all_input_witnesses(lab, inventory)
  local inputs = {}
  for _, name in ipairs(PACKS) do inputs[name] = item_input_witness(lab, inventory, name) end
  inputs[FOREIGN] = item_input_witness(lab, inventory, FOREIGN)
  return inputs
end

local function agricultural_consumption_is_valid(observed)
  local capacity, durability = observed.prototype_science_capacity, observed.stored_durability
  if observed.prototype_spoil_ticks ~= AGRICULTURAL_SPOIL_TICKS
      or observed.prototype_lab_ignores_spoil_percent ~= false
      or type(capacity) ~= "number" or capacity <= 0
      or observed.inventory_count ~= INITIAL - 2
      or type(durability) ~= "number" or durability <= 0 or durability >= capacity then
    return false
  end
  for _, stack in ipairs(observed.stacks) do
    if type(stack.spoil_percent) ~= "number" or stack.spoil_percent <= 0 then return false end
  end
  return #observed.stacks > 0
end

local function assert_complete(state)
  local force = game.forces.player
  local owner, gear = research(force, OWNER), research(force, GEAR)
  if state.finished ~= 2 or not owner.researched or gear.level ~= 2 or force.current_research ~= nil then
    fail("both actual laboratory completions were not retained")
  end
  if not near(force.recipes["iron-gear-wheel"].productivity_bonus, EXPECTED_GEAR_PRODUCTIVITY) then
    fail("native gear productivity differs", bonus_witness(force, gear))
  end
  if not near(force.laboratory_productivity_bonus, EXPECTED_LABORATORY_PRODUCTIVITY) then
    fail("native laboratory productivity differs", bonus_witness(force, gear))
  end
  check_inputs(owner, {FOREIGN})
  check_inputs(gear, PACKS)
  if not state.lab or not state.lab.valid then fail("actual laboratory is absent") end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  local inputs = all_input_witnesses(state.lab, inventory)
  for _, name in ipairs(PACKS) do
    if name ~= AGRICULTURAL and inputs[name].inventory_count ~= INITIAL - 1 then
      fail("official input consumption differs: " .. name, {official_input_consumption=inputs})
    end
  end
  if inputs[FOREIGN].inventory_count ~= INITIAL - 1 then
    fail("foreign cryogenic input consumption differs", {official_input_consumption=inputs})
  end
  -- Space Age declares this science pack spoilable. Its value falls with
  -- freshness, so the lab has already drawn a second pack and retains its
  -- partial science durability outside the inventory after this one-unit run.
  if not agricultural_consumption_is_valid(inputs[AGRICULTURAL]) then
    fail("perishable agricultural science consumption differs", {official_input_consumption=inputs})
  end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="cryogenic-gameplay", stage=stage, status="passed",
    witnesses={actual_lab_completions=state.finished, foreign_owner_input=FOREIGN,
      foreign_owner_science_consumed=1, official_science_inputs=PACKS,
      each_nonperishable_official_science_consumed=1, agricultural_science_items_drawn=2,
      agricultural_science=item_input_witness(state.lab,
        state.lab.get_inventory(defines.inventory.lab_input), AGRICULTURAL),
      native_gear_productivity=EXPECTED_GEAR_PRODUCTIVITY,
      laboratory_productivity=EXPECTED_LABORATORY_PRODUCTIVITY,
      gear=gear_effect_witness(game.forces.player.technologies[GEAR]),
      policy="all-official", on_load_read_only=stage == "reload",
      fixture_accelerates_gear_count_and_time=true, ordinary_tuning_qualified=false,
      resource_mining_observed=false, exact_reporter_modpack=false},
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["space-age"] ~= "2.1.23"
      or script.active_mods["more-infinite-research"] ~= "5.0.21000" then fail("unexpected native target") end
  local force = game.forces.player
  local owner, gear = research(force, OWNER), research(force, GEAR)
  check_inputs(owner, {FOREIGN})
  check_inputs(gear, PACKS)
  if owner.researched or gear.researched or gear.level ~= 1 or owner.enabled ~= true or gear.enabled ~= true
      or force.current_research ~= nil or not near(force.recipes["iron-gear-wheel"].productivity_bonus, 0)
      or not near(force.laboratory_productivity_bonus, 0) then fail("initial native research state differs") end
  -- Seed only named direct prerequisites. The cryogenic owner itself must be
  -- earned using its foreign input; no factory or prerequisite graph is walked.
  research(force, "cryogenic-plant").researched = true
  for _, name in ipairs(PACKS) do
    if name ~= OWNER then research(force, name).researched = true end
  end
  local lab = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=force}
  if not lab or not lab.valid then fail("could not create actual laboratory") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if inventory.insert{name=FOREIGN, count=INITIAL} ~= INITIAL then fail("laboratory rejected foreign cryogenic input") end
  for _, name in ipairs(PACKS) do
    if inventory.insert{name=name, count=INITIAL} ~= INITIAL then fail("laboratory rejected " .. name) end
  end
  lab.energy = 100000000
  storage[KEY] = {lab=lab, finished=0, started=false, phase="researching", deadline=game.tick + 36000}
  game.speed = 16
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching" or not event.research or event.research.force ~= game.forces.player then return end
  local expected = state.finished == 0 and OWNER or GEAR
  if not state.started or event.research.name ~= expected or state.finished >= 2 then fail("unexpected laboratory completion") end
  state.finished, state.started = state.finished + 1, false
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
  if game.tick > state.deadline then fail("actual laboratories exceeded deadline") end
  if state.finished == 2 then
    assert_complete(state)
    state.phase = "complete"
    marker("initial", state)
    game.server_save("mir5-native-complete")
    return
  end
  if not state.lab or not state.lab.valid then fail("actual laboratory was removed") end
  state.lab.energy = 100000000
  if not state.started then
    local name = state.finished == 0 and OWNER or GEAR
    state.started = true
    if not game.forces.player.add_research(name) then fail("could not start actual laboratory research " .. name) end
  end
end)
