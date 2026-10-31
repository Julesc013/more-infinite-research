-- Shared data-stage preflight for the real solid-input Bob/Angel production
-- witness. The fixture clones only the captured oven class to bound elapsed
-- time; the named recipe remains untouched.
local M = {}

M.name = "bob-copper-tungsten-alloy"
M.source_machine_name = "angels-sintering-oven-4"
M.machine_name = "mir5-ba-cap-production-oven"
local CATEGORY = "angels-sintering-4"
local ENERGY = 8
local FIXTURE_CRAFTING_SPEED = 200
local INPUTS = {
  {name="bob-powdered-tungsten", amount=15},
  {name="angels-powder-copper", amount=10},
}
local RESULT = {name="bob-copper-tungsten-alloy", amount=25}

local function exact(entries, expected, label)
  assert(type(entries) == "table" and #entries == #expected, label .. " count changed")
  for index, wanted in ipairs(expected) do
    local actual = entries[index]
    assert(type(actual) == "table" and actual.type == "item" and actual.name == wanted.name
      and actual.amount == wanted.amount and actual.catalyst_amount == nil,
      label .. " changed at " .. tostring(index))
  end
end

function M.assert_recipe(recipe, cap)
  assert(type(recipe) == "table" and recipe.type == "recipe" and recipe.name == M.name
    and recipe.category == CATEGORY and recipe.energy_required == ENERGY and recipe.enabled == false
    and recipe.allow_productivity == true and recipe.maximum_productivity == cap,
    "captured solid production recipe identity changed")
  exact(recipe.ingredients, INPUTS, "captured solid production inputs")
  exact(recipe.results, {RESULT}, "captured solid production output")
  return recipe
end

function M.install_machine()
  local machines = assert(data.raw["assembling-machine"], "captured production machine type is absent")
  local source = assert(machines[M.source_machine_name], "captured production machine is absent")
  assert(source.type == "assembling-machine" and source.name == M.source_machine_name
    and source.crafting_speed == 2 and source.module_slots == 2,
    "captured production machine identity changed")
  assert(type(source.crafting_categories) == "table" and source.crafting_categories[4] == CATEGORY,
    "captured production machine category changed")
  local fixture = table.deepcopy(source)
  fixture.name = M.machine_name
  fixture.minable = nil
  fixture.next_upgrade = nil
  fixture.crafting_speed = FIXTURE_CRAFTING_SPEED
  fixture.module_slots = 0
  data:extend({fixture})
  return fixture
end

return M
