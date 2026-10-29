local ordinary_recipe_name = "mir5-module-permissions-recipe"
local parameter_recipe_name = "mir5-module-permissions-parameter-recipe"
local receiver_name = "mir5-module-permissions-receiver"
local fixture_category = "mir5-module-permissions-fixture"
local expected_effects = {"speed", "productivity", "consumption", "pollution", "quality"}

local function fail(message)
  error("[mir5-module-permissions] " .. message)
end

local function exact_array(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " cardinality differs") end
  for index, value in ipairs(expected) do
    if actual[index] ~= value then
      fail(label .. " differs at " .. index .. "; expected " .. value .. " got " .. tostring(actual[index]))
    end
  end
end

local function discovered_categories()
  local seen, categories = {}, {}
  for name in pairs(data.raw["module-category"] or {}) do
    if type(name) == "string" and not seen[name] then
      seen[name] = true
      categories[#categories + 1] = name
    end
  end
  for _, module in pairs(data.raw.module or {}) do
    local name = type(module) == "table" and module.category or nil
    if type(name) == "string" and not seen[name] then
      seen[name] = true
      categories[#categories + 1] = name
    end
  end
  table.sort(categories)
  return categories
end

local startup = settings.startup["mir-unrestricted-modules"]
if not startup or startup.value ~= true then fail("fixture startup setting did not enable unrestricted modules") end

local categories = discovered_categories()
local ordinary = data.raw.recipe and data.raw.recipe[ordinary_recipe_name]
local parameter = data.raw.recipe and data.raw.recipe[parameter_recipe_name]
local receiver = data.raw["assembling-machine"] and data.raw["assembling-machine"][receiver_name]
if not ordinary or not parameter or not receiver then fail("fixture probe prototypes are absent") end

if ordinary.allow_speed ~= true or ordinary.allow_productivity ~= true
    or ordinary.allow_consumption ~= true or ordinary.allow_pollution ~= true
    or ordinary.allow_quality ~= true then
  fail("ordinary recipe does not allow every published module effect")
end
exact_array(ordinary.allowed_module_categories, categories, "ordinary recipe module categories")
if ordinary.energy_required ~= 3 or ordinary.hide_from_player_crafting ~= true then
  fail("ordinary recipe unrelated fields changed")
end

if parameter.parameter ~= true or parameter.allow_speed ~= false or parameter.allow_productivity ~= false
    or parameter.allow_consumption ~= false or parameter.allow_pollution ~= false
    or parameter.allow_quality ~= false then
  fail("published parameter-recipe skip differs")
end
exact_array(parameter.allowed_module_categories, {"speed"}, "parameter recipe module categories")

exact_array(receiver.allowed_effects, expected_effects, "slot receiver module effects")
exact_array(receiver.allowed_module_categories, categories, "slot receiver module categories")
if receiver.module_slots ~= 2 or receiver.crafting_speed ~= 0.5 or receiver.energy_usage ~= "90kW" then
  fail("slot receiver unrelated fields changed")
end

local found_fixture_category = false
for _, category in ipairs(categories) do
  if category == fixture_category then found_fixture_category = true; break end
end
if not found_fixture_category then fail("fixture module category was not discovered") end

log("[MIR5_MODULE_PERMISSIONS_DATA] status=passed;categories=" .. tostring(#categories)
  .. ";fixture-category=" .. fixture_category)
