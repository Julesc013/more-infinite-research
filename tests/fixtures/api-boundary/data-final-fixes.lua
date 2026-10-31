-- Test-only caught boundary cases. Never import private MIR implementation.
local api = require("__more-infinite-research__.api.v1.data")
local version = api.get_version()
local capabilities = api.get_capabilities()
assert(version.major == 1 and version.minor == 0)
assert(capabilities.technology_creation and capabilities.technology_family)
version.major = 99
capabilities.technology_creation = false
assert(api.get_version().major == 1 and api.get_capabilities().technology_creation)

local single = "mir-api-boundary-single-1"
local family_a = "mir-api-boundary-family-a-1"
local family_b = "mir-api-boundary-family-b-1"
local refused_a = "mir-api-boundary-refused-a-1"
local refused_b = "mir-api-boundary-refused-b-1"
local sentinel = data.raw.technology.automation
assert(sentinel ~= nil)
local function definition(name)
  return {type = "technology", name = name, prerequisites = {"automation"},
    unit = {count = 10, ingredients = {{"automation-science-pack", 1}}, time = 15}, effects = {}}
end
-- Fixed fields from two named prototypes, never a traversal of data.raw.
local function snapshot(row)
  local unit = row.unit or {}
  local ingredients, effects, prerequisites = unit.ingredients or {}, row.effects or {}, row.prerequisites or {}
  local ingredient, effect = ingredients[1] or {}, effects[1] or {}
  return {name = row.name or false, kind = row.type or false,
    count = unit.count or false, time = unit.time or false, ingredient_count = #ingredients,
    first_ingredient = ingredient[1] or ingredient.name or false,
    first_amount = ingredient[2] or ingredient.amount or false,
    prerequisite_count = #prerequisites, first_prerequisite = prerequisites[1] or false,
    effect_count = #effects, first_effect = effect.type or false,
    first_modifier = effect.modifier or false, first_recipe = effect.recipe or false,
    first_change = effect.change or false}
end
local function unchanged_fields(row, before)
  local after = snapshot(row)
  for key, value in pairs(before) do
    assert(after[key] == value, "named prototype field changed: " .. key)
  end
end
local original_sentinel = snapshot(sentinel)
local submitted = definition(single)
submitted.effects = {{type = "character-crafting-speed", modifier = 0.03125}}
assert(api.add_technology(submitted) == single)
unchanged_fields(sentinel, original_sentinel)
local published = assert(data.raw.technology[single])
assert(published.unit.count == 10 and published.effects[1].modifier == 0.03125)
submitted.name = "mir-api-boundary-alias-1"
submitted.unit.count = 999
submitted.unit.ingredients[1][2] = 99
submitted.effects[1].modifier = 0.5
assert(published.name == single and published.unit.count == 10
  and published.unit.ingredients[1][2] == 1 and published.effects[1].modifier == 0.03125)

local function refused(callback, code)
  local before = data.raw.technology[single]
  local before_fields, sentinel_fields = snapshot(before), snapshot(sentinel)
  local ok, message = pcall(callback)
  assert(not ok and tostring(message):find("MIR_API:" .. code, 1, true), tostring(message))
  assert(data.raw.technology[single] == before and data.raw.technology.automation == sentinel)
  unchanged_fields(before, before_fields)
  unchanged_fields(sentinel, sentinel_fields)
  unchanged_fields(sentinel, original_sentinel)
  assert(data.raw.technology[refused_a] == nil and data.raw.technology[refused_b] == nil)
end
refused(function() api.add_technology(definition(single)) end, "duplicate_identity")
local first, invalid = definition(refused_a), definition(refused_b)
invalid.icon = "__base__/graphics/icons/automation-science-pack.png"
refused(function() api.add_technologies({first, invalid}) end, "invalid_definition")

local a, b = definition(family_a), definition(family_b)
a.prerequisites = {family_b}
local returned = api.add_technologies({a, b})
assert(returned[1] == family_a and returned[2] == family_b and #returned == 2)
returned[1] = "mir-api-boundary-mutated-result-1"
assert(data.raw.technology[family_a].name == family_a and data.raw.technology[family_b].name == family_b)
assert(data.raw.technology[family_a].prerequisites[1] == family_b)
assert(data.raw.technology.automation == sentinel)
unchanged_fields(sentinel, original_sentinel)
log("[MIR5_API_BOUNDARY] DATA single/immediate/input-isolation/duplicate/invalid-family/order/result-isolation/named-field-snapshots passed")
