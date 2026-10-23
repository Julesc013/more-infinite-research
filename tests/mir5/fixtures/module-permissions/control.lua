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

local function exact_dictionary(actual, expected, label)
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
  exact_dictionary(ordinary.allowed_effects, effects, "ordinary recipe native effects")
  exact_dictionary(ordinary.allowed_module_categories, categories, "ordinary recipe native categories")
  exact_dictionary(receiver.allowed_effects, effects, "slot receiver native effects")
  exact_dictionary(receiver.allowed_module_categories, categories, "slot receiver native categories")
  exact_dictionary(parameter.allowed_effects, {}, "parameter recipe native effects")
  exact_dictionary(parameter.allowed_module_categories, {speed = true}, "parameter recipe native categories")

  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = "create",
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
