-- Shared native production witness for the two Bob/Angel prototype-cap stages.
-- The route is pinned from independently captured F200 2.0.77 upstream and
-- published 4.7.2 raw prototypes. The fixture never writes a recipe bonus or
-- recipe definition; Factorio's native assembler produces every observed item.
local M = {}

local RECIPE = "bob-copper-tungsten-alloy"
local MACHINE = "mir5-ba-cap-production-oven"
local CATEGORY = "angels-sintering-4"
local ENERGY = 8
local CRAFTS = 1000
local INPUTS = {
  {name="bob-powdered-tungsten", amount=15},
  {name="angels-powder-copper", amount=10},
}
local RESULT = {name="bob-copper-tungsten-alloy", amount=25}
local POWER = 1000000000
local ROUNDING = 0.0001

local function fail(message)
  error("[mir5-bob-angel-physical-production] " .. message, 2)
end

local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001
end

local function exact_entries(entries, expected, label)
  if type(entries) ~= "table" or #entries ~= #expected then fail(label .. " count differs") end
  for index, wanted in ipairs(expected) do
    local actual = entries[index]
    if type(actual) ~= "table" or actual.type ~= "item" or actual.name ~= wanted.name
        or actual.amount ~= wanted.amount then
      fail(label .. " differs at " .. tostring(index))
    end
  end
end

local function batch(expected, effective)
  if type(expected) ~= "table" or type(expected.cap) ~= "number" or type(expected.earned) ~= "number"
      or type(expected.effective) ~= "number" or type(expected.minimum_bonus_crafts) ~= "number"
      or type(expected.maximum_bonus_crafts) ~= "number" or type(expected.minimum_output) ~= "number"
      or type(expected.maximum_output) ~= "number" then
    fail("production expectation is malformed")
  end
  if not close(effective, expected.effective) then
    fail("configured production cap does not produce the expected effective bonus")
  end
  local minimum, maximum = expected.minimum_bonus_crafts, expected.maximum_bonus_crafts
  if minimum ~= math.floor(minimum) or maximum ~= math.floor(maximum) or minimum < 0 or maximum < minimum
      or maximum - minimum > 1 then
    fail("production bonus-craft rounding bound is malformed")
  end
  local base = RESULT.amount * CRAFTS
  local minimum_output = RESULT.amount * (CRAFTS + minimum)
  local maximum_output = RESULT.amount * (CRAFTS + maximum)
  if expected.minimum_output ~= minimum_output or expected.maximum_output ~= maximum_output then
    fail("configured production output arithmetic differs")
  end
  local raw_bonus_progress = CRAFTS * effective
  if raw_bonus_progress < minimum - ROUNDING or raw_bonus_progress > maximum + 1 + ROUNDING then
    fail("configured production bonus-craft range differs")
  end
  return base, minimum_output, maximum_output, minimum, maximum, raw_bonus_progress
end

function M.recipe_name() return RECIPE end
function M.machine_name() return MACHINE end
function M.crafts() return CRAFTS end
function M.inputs() return INPUTS end
function M.result() return RESULT end

function M.preflight(force, expected, label)
  local recipe = prototypes.recipe[RECIPE]
  local machine = prototypes.entity[MACHINE]
  if recipe == nil or recipe.name ~= RECIPE or recipe.category ~= CATEGORY or recipe.energy ~= ENERGY
      or not close(recipe.maximum_productivity, expected.cap) then
    fail(label .. " native solid route identity differs")
  end
  exact_entries(recipe.ingredients, INPUTS, label .. " native solid inputs")
  exact_entries(recipe.products, {RESULT}, label .. " native solid output")
  if machine == nil or machine.name ~= MACHINE or type(machine.crafting_categories) ~= "table"
      or machine.crafting_categories[CATEGORY] ~= true then
    fail(label .. " native production machine/category differs")
  end
  local force_recipe = force and force.recipes and force.recipes[RECIPE]
  if force_recipe == nil then fail(label .. " native force recipe is absent") end
  if expected.earned == nil then return nil end
  if not close(force_recipe.productivity_bonus, expected.earned) then
    fail(label .. " earned native recipe productivity differs")
  end
  local effective = math.min(force_recipe.productivity_bonus, expected.cap)
  batch(expected, effective)
  return effective
end

local function bonus_progress(machine, label)
  local value = machine.bonus_progress
  if type(value) ~= "number" or value < -ROUNDING or value > 1 + ROUNDING then
    fail(label .. " native assembler bonus progress is outside [0, 1]")
  end
  return value
end

local function inventories(machine, label)
  if machine == nil or machine.valid == false then fail(label .. " native production machine is absent") end
  machine.energy = POWER
  local input = machine.get_inventory(defines.inventory.crafter_input)
  local output = machine.get_inventory(defines.inventory.crafter_output)
  local modules = machine.get_inventory(defines.inventory.crafter_modules)
  if input == nil or output == nil then fail(label .. " native production inventories are absent") end
  if modules ~= nil and not modules.is_empty() then fail(label .. " native production machine has modules") end
  return input, output
end

function M.machine_for(force, expected, label)
  M.preflight(force, expected, label)
  local surface = game.surfaces[1]
  local machine = surface and surface.create_entity{name=MACHINE, position={8, 0}, force=force}
  if machine == nil or machine.valid == false then fail(label .. " could not create native production machine") end
  machine.set_recipe(RECIPE)
  local selected = machine.get_recipe()
  if selected == nil or selected.name ~= RECIPE then fail(label .. " could not select native solid recipe") end
  local input, output = inventories(machine, label)
  if not input.is_empty() or not output.is_empty() or machine.crafting_progress ~= 0
      or math.abs(bonus_progress(machine, label)) > ROUNDING then
    fail(label .. " native production machine was not clean")
  end
  return machine
end

local function refill(state, input, label)
  local production = state.production
  for _, item in ipairs(INPUTS) do
    local remaining = production.remaining[item.name]
    if remaining > 0 then
      local inserted = input.insert{name=item.name, count=remaining}
      if type(inserted) ~= "number" or inserted < 0 or inserted > remaining then
        fail(label .. " native production input insertion differs: " .. item.name)
      end
      production.remaining[item.name] = remaining - inserted
      production.inserted[item.name] = production.inserted[item.name] + inserted
    end
  end
end

function M.begin(state, force, expected, label)
  local machine = state.production_machine
  local effective = M.preflight(force, expected, label)
  local input, output = inventories(machine, label)
  if not input.is_empty() or not output.is_empty() or machine.crafting_progress ~= 0
      or math.abs(bonus_progress(machine, label)) > ROUNDING then
    fail(label .. " native production machine was not clean before batch")
  end
  local base, minimum_output, maximum_output, minimum_bonus, maximum_bonus, raw_progress = batch(expected, effective)
  local production = {
    label=label, cap=expected.cap, earned=expected.earned, effective=effective,
    base=base, minimum_output=minimum_output, maximum_output=maximum_output,
    minimum_bonus_crafts=minimum_bonus, maximum_bonus_crafts=maximum_bonus,
    raw_bonus_progress=raw_progress, bonus_crafts=0, remaining_productivity_progress=nil,
    native_bonus_progress=nil, output=0, finished=false, remaining={}, inserted={},
  }
  for _, item in ipairs(INPUTS) do
    production.remaining[item.name] = item.amount * CRAFTS
    production.inserted[item.name] = 0
  end
  state.production = production
  refill(state, input, label)
end

function M.tick(state)
  local production = state.production
  if type(production) ~= "table" or production.finished == true then return production and production.finished == true end
  local input, output = inventories(state.production_machine, production.label)
  refill(state, input, production.label)
  local count = output.get_item_count(RESULT.name)
  if count > 0 then
    if output.remove{name=RESULT.name, count=count} ~= count then fail(production.label .. " could not drain native solid output") end
    production.output = production.output + count
  end
  for _, item in ipairs(INPUTS) do
    if production.remaining[item.name] ~= 0 or input.get_item_count(item.name) ~= 0 then return false end
    if production.inserted[item.name] ~= item.amount * CRAFTS then
      fail(production.label .. " native solid input count differs: " .. item.name)
    end
  end
  if state.production_machine.crafting_progress ~= 0 then return false end
  if production.output < production.minimum_output then
    fail(production.label .. " native physical output missing after all named inputs completed: got "
      .. tostring(production.output) .. ", need at least " .. tostring(production.minimum_output))
  end
  if production.output > production.maximum_output or production.output % RESULT.amount ~= 0 then
    fail(production.label .. " native physical output differs: got " .. tostring(production.output))
  end
  local bonus_crafts = production.output / RESULT.amount - CRAFTS
  if bonus_crafts < production.minimum_bonus_crafts or bonus_crafts > production.maximum_bonus_crafts then
    fail(production.label .. " native bonus-craft count differs: " .. tostring(bonus_crafts))
  end
  -- LuaEntity.bonus_progress is the native CraftingMachine productivity bar.
  -- Match it against the independent whole-batch output mass balance; neither
  -- field is written by this fixture.
  local remaining = production.raw_bonus_progress - bonus_crafts
  local native_progress = bonus_progress(state.production_machine, production.label)
  if remaining < -ROUNDING or remaining > 1 + ROUNDING
      or math.abs(remaining - native_progress) > ROUNDING then
    fail(production.label .. " native productivity-progress mass balance differs: output="
      .. tostring(remaining) .. ", assembler=" .. tostring(native_progress))
  end
  production.bonus_crafts, production.remaining_productivity_progress = bonus_crafts, remaining
  production.native_bonus_progress = native_progress
  production.finished = true
  return true
end

function M.assert_complete(state, force, expected, label)
  local production = state.production
  if type(production) ~= "table" or production.finished ~= true then fail(label .. " native physical production did not complete") end
  local effective = M.preflight(force, expected, label)
  local base, minimum_output, maximum_output, minimum_bonus, maximum_bonus, raw_progress = batch(expected, effective)
  if production.base ~= base or production.minimum_output ~= minimum_output or production.maximum_output ~= maximum_output
      or production.output < minimum_output or production.output > maximum_output
      or production.bonus_crafts < minimum_bonus or production.bonus_crafts > maximum_bonus
      or not close(production.effective, effective) or math.abs(production.raw_bonus_progress - raw_progress) > ROUNDING
      or production.remaining_productivity_progress == nil or production.native_bonus_progress == nil then
    fail(label .. " native physical production witness differs")
  end
  local input, output_inventory = inventories(state.production_machine, label)
  local native_progress = bonus_progress(state.production_machine, label)
  if math.abs(production.remaining_productivity_progress - production.native_bonus_progress) > ROUNDING
      or math.abs(native_progress - production.native_bonus_progress) > ROUNDING then
    fail(label .. " native assembler productivity progress changed")
  end
  if not input.is_empty() or not output_inventory.is_empty() or state.production_machine.crafting_progress ~= 0 then
    fail(label .. " native production machine retained work")
  end
end

return M
