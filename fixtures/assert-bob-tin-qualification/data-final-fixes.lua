local recipe_name = "bob-tin-plate"
local technology_name = "recipe-prod-research_material_tin-1"

local function fail(message)
  error("MIR Bob Tin qualification failed: " .. message)
end

local function name_of(entry)
  return entry and (entry.name or entry[1])
end

local function amount_of(entry)
  return entry and (entry.amount or entry[2])
end

local function item_type_of(entry)
  return entry and (entry.type or "item")
end

local function contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

local function contains_nested(value, expected)
  if tostring(value) == tostring(expected) then return true end
  if type(value) ~= "table" then return false end
  for _, child in pairs(value) do
    if contains_nested(child, expected) then return true end
  end
  return false
end

local recipe = data.raw.recipe[recipe_name]
if not recipe then fail("final Bob Tin recipe is absent") end
if #recipe.categories ~= 1 or recipe.categories[1] ~= "smelting" then
  fail("Bob Tin recipe category set is not exactly smelting")
end
if recipe.allow_productivity ~= true then fail("Bob Tin recipe does not explicitly allow productivity") end
if recipe.auto_recycle ~= false then fail("Bob Tin recipe must explicitly reject automatic recycling") end
if recipe.normal or recipe.expensive then fail("Bob Tin route must use one final recipe form") end
if #recipe.ingredients ~= 1 or name_of(recipe.ingredients[1]) ~= "bob-tin-ore" or
    item_type_of(recipe.ingredients[1]) ~= "item" or amount_of(recipe.ingredients[1]) ~= 1 then
  fail("Bob Tin route must have exactly one bob-tin-ore input")
end
if #recipe.results ~= 1 or name_of(recipe.results[1]) ~= "bob-tin-plate" or
    item_type_of(recipe.results[1]) ~= "item" or amount_of(recipe.results[1]) ~= 1 then
  fail("Bob Tin route must have exactly one bob-tin-plate output")
end

local furnace = data.raw.furnace["stone-furnace"]
if not furnace or not contains(furnace.crafting_categories, "smelting") then
  fail("stone-furnace is not a final smelting machine witness")
end

for candidate_name, candidate in pairs(data.raw.recipe) do
  if candidate_name == "bob-tin-plate-recycling" then
    fail("Bob Tin recycling recipe must be absent")
  end
  local inputs = candidate.ingredients or {}
  local outputs = candidate.results or (candidate.result and {{name = candidate.result, amount = candidate.result_count or 1}}) or {}
  local consumes_plate = false
  local returns_ore = false
  for _, entry in ipairs(inputs) do
    if item_type_of(entry) == "item" and name_of(entry) == "bob-tin-plate" then consumes_plate = true end
  end
  for _, entry in ipairs(outputs) do
    if item_type_of(entry) == "item" and name_of(entry) == "bob-tin-ore" then returns_ore = true end
  end
  if consumes_plate and returns_ore then
    fail("Bob Tin return path is present: " .. candidate_name)
  end
end

local technology = data.raw.technology[technology_name]
if not technology then fail("finite MIR Tin technology is absent") end
if technology.max_level ~= "infinite" then fail("MIR Tin prototype must preserve lossless infinity") end
if technology.show_levels_info ~= false then fail("MIR Tin prototype still exposes a misleading infinity badge") end
if not contains_nested(technology.localised_description, 3) then
  fail("MIR Tin prototype does not disclose selected finite cap 3")
end
local owners = 0
for owner_name, candidate in pairs(data.raw.technology) do
  for _, effect in ipairs(candidate.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owners = owners + 1
      if owner_name ~= technology_name then fail("unexpected Tin productivity owner: " .. owner_name) end
    end
  end
end
if owners ~= 1 then fail("Bob Tin requires exactly one MIR productivity owner") end

log("[mir-bob-tin] DATA PASS final-route finite-owner no-return-path")
