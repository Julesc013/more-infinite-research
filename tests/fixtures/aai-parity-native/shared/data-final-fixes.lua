-- This fixture validates retained published AAI facts before reducing only
-- disposable fixture workloads. It never changes a recipe, effect, setting,
-- owner, or prerequisite.
local FIXTURE = "mir-fixture-mir5-aai-parity-native"
local PLAN = require("__mir-fixture-mir5-aai-parity-native__/catalogue")
local function fail(message) error("[mir5-aai-parity-native] " .. message) end

local function equal(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .0000001
end

local function name(row) return type(row) == "table" and (row.name or row[1]) or nil end
local function amount(row) return type(row) == "table" and (row.amount or row[2]) or nil end

local function exact_names(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " cardinality differs") end
  for index, value in ipairs(expected) do
    if actual[index] ~= value then fail(label .. " differs at " .. tostring(index)) end
  end
end

local function exact_ingredients(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " cardinality differs") end
  for index, wanted in ipairs(expected) do
    local value = actual[index]
    if type(value) ~= "table" or (value.type or "item") ~= wanted.type or name(value) ~= wanted.name
        or amount(value) ~= wanted.amount or value.amount_min ~= nil or value.amount_max ~= nil
        or (value.probability ~= nil and value.probability ~= 1) or (value.catalyst_amount ~= nil and value.catalyst_amount ~= 0)
        or (value.ignored_by_productivity ~= nil and value.ignored_by_productivity ~= 0) then
      fail(label .. " differs at " .. tostring(index))
    end
  end
end

local function require_exact_closure()
  if mods.base ~= "2.1.23" or mods["aai-industry"] ~= "0.7.5" or mods["more-infinite-research"] ~= PLAN.mir_version
      or mods[FIXTURE] ~= PLAN.fixture_version then
    fail("AAI, MIR, fixture, or Base closure differs")
  end
  local space = mods["space-age"] ~= nil
  local companions = {"elevated-rails", "quality", "recycler", "space-age"}
  for _, member in ipairs(companions) do
    if space then
      if mods[member] ~= "2.1.23" then fail("Space Age closure differs: " .. member) end
    elseif mods[member] ~= nil then
      fail("Base closure unexpectedly enables " .. member)
    end
  end
  return space
end

local function technology(name)
  local value = data.raw.technology and data.raw.technology[name]
  if type(value) ~= "table" then fail("technology is absent: " .. name) end
  return value
end

local function assert_aai_stage(name, prerequisites, count, time)
  local value = technology(name)
  exact_names(value.prerequisites or {}, prerequisites, name .. " prerequisites")
  local unit = value.unit
  if type(unit) ~= "table" or unit.count ~= count or unit.count_formula ~= nil or unit.time ~= time then
    fail(name .. " workload differs")
  end
  exact_ingredients(unit.ingredients, {{type="item", name="automation-science-pack", amount=1}}, name .. " science")
  return value
end

local space = require_exact_closure()
local aai = {
  assert_aai_stage("fuel-processing", {"automation-science-pack"}, 10, 10),
  assert_aai_stage("sand-processing", {"automation-science-pack"}, 10, 10),
  assert_aai_stage("electricity", {"fuel-processing"}, 50, 10),
  assert_aai_stage("electronics", {"electricity"}, 30, 15),
  assert_aai_stage("glass-processing", {"sand-processing"}, 40, 10),
  assert_aai_stage("electric-lab", {"electronics", "glass-processing"}, 100, 10),
}

local burner = technology("burner-mechanics")
if burner.unit ~= nil then fail("burner mechanics is no longer an AAI starting technology") end
local burner_trigger = burner.research_trigger
if type(burner_trigger) ~= "table" or burner_trigger.type ~= "craft-item" or burner_trigger.item ~= "iron-plate"
    or burner_trigger.count ~= 10 then
  fail("burner mechanics craft trigger differs")
end
local burner_effects = burner.effects or {}
if #burner_effects < 1 then fail("burner mechanics lacks recipe effects") end
local has_burner_lab = false
for _, effect in ipairs(burner_effects) do
  if effect.type == "unlock-recipe" and effect.recipe == "burner-lab" then has_burner_lab = true end
end
if not has_burner_lab then fail("burner mechanics no longer unlocks burner lab") end

local automation = technology("automation-science-pack")
local automation_trigger = automation.research_trigger
if type(automation_trigger) ~= "table" or automation_trigger.type ~= "craft-item" or automation_trigger.item ~= "burner-lab"
    or automation_trigger.count ~= nil then
  fail("automation science craft trigger differs")
end
exact_names(automation.prerequisites or {}, {"burner-mechanics"}, "automation science prerequisites")

local burner_lab_recipe = data.raw.recipe and data.raw.recipe["burner-lab"]
if type(burner_lab_recipe) ~= "table" or burner_lab_recipe.enabled ~= false or burner_lab_recipe.energy_required ~= .5 then
  fail("burner lab recipe time differs")
end
exact_names(burner_lab_recipe.categories or {}, {"crafting"}, "burner lab recipe categories")
exact_ingredients(burner_lab_recipe.ingredients, {
  {type="item", name="motor", amount=10},
  {type="item", name="copper-plate", amount=10},
  {type="item", name="stone-brick", amount=5},
}, "burner lab recipe ingredients")
exact_ingredients(burner_lab_recipe.results, {{type="item", name="burner-lab", amount=1}}, "burner lab recipe result")

local iron_plate_recipe = data.raw.recipe and data.raw.recipe["iron-plate"]
if type(iron_plate_recipe) ~= "table" or iron_plate_recipe.energy_required ~= 3.2 then
  fail("iron plate recipe time differs")
end
exact_names(iron_plate_recipe.categories or {}, {"smelting"}, "iron plate recipe categories")
exact_ingredients(iron_plate_recipe.ingredients, {{type="item", name="iron-ore", amount=1}}, "iron plate recipe ingredients")
exact_ingredients(iron_plate_recipe.results, {{type="item", name="iron-plate", amount=1}}, "iron plate recipe result")

local owner = technology("recipe-prod-research_electric_engine-1")
local science = {
  {type="item", name="automation-science-pack", amount=1},
  {type="item", name="logistic-science-pack", amount=1},
  {type="item", name="chemical-science-pack", amount=1},
  {type="item", name="production-science-pack", amount=1},
}
if space then science[#science + 1] = {type="item", name="electromagnetic-science-pack", amount=1} end
local expected_prerequisites = {}
for _, row in ipairs(science) do expected_prerequisites[#expected_prerequisites + 1] = row.name end
exact_names(owner.prerequisites or {}, expected_prerequisites, "electric engine MIR prerequisites")
if owner.max_level ~= "infinite" or type(owner.unit) ~= "table" or owner.unit.count ~= nil
    or owner.unit.count_formula ~= "8000*2^(L-1)" or owner.unit.time ~= 60 then
  fail("electric engine MIR workload differs")
end
exact_ingredients(owner.unit.ingredients, science, "electric engine MIR science")
if type(owner.effects) ~= "table" or #owner.effects ~= 1 then fail("electric engine MIR effect cardinality differs") end
local effect = owner.effects[1]
if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity" or effect.recipe ~= "electric-engine-unit"
    or not equal(effect.change, .1) then
  fail("electric engine MIR productivity effect differs")
end

local recipe = data.raw.recipe and data.raw.recipe["electric-engine-unit"]
if type(recipe) ~= "table" or recipe.energy_required ~= 10 then fail("electric engine recipe time differs") end
exact_ingredients(recipe.ingredients, {
  {type="fluid", name="lubricant", amount=40},
  {type="item", name="steel-plate", amount=2},
  {type="item", name="electronic-circuit", amount=4},
  {type="item", name="electric-motor", amount=2},
}, "electric engine recipe ingredients")
exact_ingredients(recipe.results, {{type="item", name="electric-engine-unit", amount=1}}, "electric engine recipe result")

-- All facts above must pass before this fixture reduces a disposable lab cost.
for _, value in ipairs(aai) do value.unit.count, value.unit.time = 1, 1 end
owner.unit.count, owner.unit.count_formula, owner.unit.time = 1, nil, 1
