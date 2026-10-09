local recipe_name = "bob-tin-plate"
local technology_name = "recipe-prod-research_material_tin-1"
local expected = {
  {name = "bob-electric-mixing-furnace", entity_type = "assembling-machine", place_item = "bob-electric-mixing-furnace", energy_type = "electric", crafting_categories = {"smelting", "bob-mixing-furnace"}},
  {name = "bob-steel-mixing-furnace", entity_type = "assembling-machine", place_item = "bob-steel-mixing-furnace", energy_type = "burner", crafting_categories = {"smelting", "bob-mixing-furnace"}},
  {name = "bob-stone-mixing-furnace", entity_type = "assembling-machine", place_item = "bob-stone-mixing-furnace", energy_type = "burner", crafting_categories = {"smelting", "bob-mixing-furnace"}},
  {name = "electric-furnace", entity_type = "furnace", place_item = "electric-furnace", energy_type = "electric", crafting_categories = {"smelting"}},
  {name = "steel-furnace", entity_type = "furnace", place_item = "steel-furnace", energy_type = "burner", crafting_categories = {"smelting"}},
  {name = "stone-furnace", entity_type = "furnace", place_item = "stone-furnace", energy_type = "burner", crafting_categories = {"smelting"}},
}

local function fail(message) error("[mir-bob-tin-machine-matrix] " .. message) end
local function contains(values, expected_value)
  for _, value in ipairs(values or {}) do if value == expected_value then return true end end
  return false
end
local function sorted_copy(values)
  local copy = {}
  for _, value in ipairs(values or {}) do copy[#copy + 1] = value end
  table.sort(copy)
  return copy
end
local function equal_list(actual, expected_values)
  actual = sorted_copy(actual)
  expected_values = sorted_copy(expected_values)
  if #actual ~= #expected_values then return false end
  for index, value in ipairs(actual) do if value ~= expected_values[index] then return false end end
  return true
end
local function json_categories(categories)
  local rows = {}
  for _, category in ipairs(categories) do rows[#rows + 1] = '"' .. category .. '"' end
  return "[" .. table.concat(rows, ",") .. "]"
end
local function json_rows(rows)
  local encoded = {}
  for _, row in ipairs(rows) do
    encoded[#encoded + 1] = '{"name":"' .. row.name .. '","entity_type":"' .. row.entity_type .. '","place_item":"' .. row.place_item .. '","energy_type":"' .. row.energy_type .. '","crafting_categories":' .. json_categories(row.crafting_categories) .. '}'
  end
  return "[" .. table.concat(encoded, ",") .. "]"
end

if mods["angelssmelting"] or mods["angelsrefining"] or mods["angelspetrochem"] then fail("Bob-only fixture refuses Angel modules") end
local recipe = data.raw.recipe[recipe_name]
if not recipe or #recipe.categories ~= 1 or recipe.categories[1] ~= "smelting" or recipe.normal or recipe.expensive then fail("exact Bob Tin final recipe form differs") end
local ingredient = recipe.ingredients and recipe.ingredients[1]
local result = recipe.results and recipe.results[1]
if #recipe.ingredients ~= 1 or not ingredient or (ingredient.name or ingredient[1]) ~= "bob-tin-ore" or (ingredient.amount or ingredient[2]) ~= 1 then fail("exact Bob Tin input differs") end
if #recipe.results ~= 1 or not result or (result.name or result[1]) ~= "bob-tin-plate" or (result.amount or result[2]) ~= 1 then fail("exact Bob Tin output differs") end
if recipe.allow_productivity ~= true or recipe.auto_recycle ~= false then fail("Bob Tin productivity or recycling state differs") end

local owner_count, owner_change = 0, nil
for owner_name, technology in pairs(data.raw.technology) do
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owner_count = owner_count + 1
      if owner_name ~= technology_name or effect.change ~= 0.02 then fail("Tin productivity owner or exact change differs") end
      owner_change = effect.change
    end
  end
end
if owner_count ~= 1 then fail("Bob Tin requires exactly one productivity owner") end

local actual, unadmitted = {}, {}
for _, entity_type in ipairs({"assembling-machine", "furnace"}) do
  for name, entity in pairs(data.raw[entity_type] or {}) do
    if contains(entity.crafting_categories, "smelting") then
      local item = data.raw.item[name]
      local energy_type = entity.energy_source and entity.energy_source.type or nil
      if item and item.place_result == name and (energy_type == "burner" or energy_type == "electric") then
        actual[#actual + 1] = {name = name, entity_type = entity_type, place_item = name, energy_type = energy_type, crafting_categories = sorted_copy(entity.crafting_categories)}
      else
        unadmitted[#unadmitted + 1] = name .. ":place-item-or-supported-energy-missing"
      end
    end
  end
end
table.sort(actual, function(left, right) return left.name < right.name end)
table.sort(unadmitted)
if #actual ~= #expected then fail("admitted exact machine count differs: " .. #actual) end
for index, row in ipairs(expected) do
  local observed = actual[index]
  if not observed or observed.name ~= row.name or observed.entity_type ~= row.entity_type or observed.place_item ~= row.place_item or observed.energy_type ~= row.energy_type or not equal_list(observed.crafting_categories, row.crafting_categories) then
    fail("admitted machine matrix differs at " .. index)
  end
end
if #unadmitted ~= 0 then fail("matching machine lacks the required placeable/usable envelope: " .. table.concat(unadmitted, ",")) end

log("[mir-bob-tin-machine-matrix] DATA JSON {\"recipe\":\"" .. recipe_name .. "\",\"category\":\"smelting\",\"owner_count\":" .. owner_count .. ",\"effect_change\":" .. owner_change .. ",\"machines\":" .. json_rows(actual) .. ",\"unadmitted_matching_entities\":[]}")
