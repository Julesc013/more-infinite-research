-- CreateOnly uses the public runtime prototype maps only. Data-stage checks
-- above establish fields not represented by a runtime prototype property.
local CASE = "module-permissions"
local ordinary_recipe_name = "mir5-module-permissions-recipe"
local parameter_recipe_name = "mir5-module-permissions-parameter-recipe"
local receiver_name = "mir5-module-permissions-receiver"
local expected_effects = {"speed", "productivity", "consumption", "pollution", "quality"}

local function fail(message)
  error("[mir5-module-permissions] " .. message)
end

local function exact_true_dictionary(actual, expected, label)
  local count = 0
  for name, value in pairs(actual or {}) do
    if value ~= true or expected[name] ~= true then
      fail(label .. " has an unexpected entry " .. tostring(name))
    end
    count = count + 1
  end
  local expected_count = 0
  for name in pairs(expected) do
    expected_count = expected_count + 1
    if actual == nil or actual[name] ~= true then fail(label .. " is missing " .. name) end
  end
  if count ~= expected_count then fail(label .. " cardinality differs") end
end

local function exact_effect_mask(actual, enabled, label)
  if actual == nil then fail(label .. " is absent") end

  local known = {}
  for _, name in ipairs(expected_effects) do
    known[name] = true
    local value = actual[name]
    if value == nil then fail(label .. " is missing " .. name) end
    if type(value) ~= "boolean" then fail(label .. " has a non-boolean " .. name) end
    if enabled[name] == true and value ~= true then
      fail(label .. " is missing " .. name)
    end
    if enabled[name] ~= true and value ~= false then
      fail(label .. " unexpectedly enables " .. name)
    end
  end

  for name, value in pairs(actual) do
    if type(value) ~= "boolean" then
      fail(label .. " has a non-boolean entry " .. tostring(name))
    end
    if value == true and (known[name] ~= true or enabled[name] ~= true) then
      fail(label .. " has an unexpected enabled effect " .. tostring(name))
    end
  end
end

local function discovered_categories()
  local categories = {}
  for name in pairs(prototypes.module_category) do categories[name] = true end
  if next(categories) == nil then fail("native module category map is empty") end
  return categories
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["more-infinite-research"] ~= "5.0.21000" then
    fail("fixture loaded with an unexpected Factorio or MIR version")
  end
  local ordinary = prototypes.recipe[ordinary_recipe_name]
  local parameter = prototypes.recipe[parameter_recipe_name]
  local receiver = prototypes.entity[receiver_name]
  if not ordinary or not parameter or not receiver then fail("native fixture probe prototype is absent") end

  local effects = {}
  for _, name in ipairs(expected_effects) do effects[name] = true end
  local categories = discovered_categories()
  exact_effect_mask(ordinary.allowed_effects, effects, "ordinary recipe native effects")
  exact_true_dictionary(ordinary.allowed_module_categories, categories, "ordinary recipe native categories")
  exact_effect_mask(receiver.allowed_effects, effects, "slot receiver native effects")
  exact_true_dictionary(receiver.allowed_module_categories, categories, "slot receiver native categories")
  exact_effect_mask(parameter.allowed_effects, {}, "parameter recipe native effects")
  exact_true_dictionary(parameter.allowed_module_categories, {speed = true}, "parameter recipe native categories")

  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = "init",
    case = CASE,
    status = "passed",
    witnesses = {
      public_runtime_recipe_permission_maps = true,
      public_runtime_receiver_permission_maps = true,
      public_runtime_category_map = true,
      data_stage_parameter_skip_required = true
    }
  }))
end)
