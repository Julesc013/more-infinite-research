local expected_routes = {
  ["angels-processed-tin"] = {input = { ["angels-tin-ore"] = 4 }, output = { ["angels-processed-tin"] = 2 }},
  ["angels-pellet-tin"] = {input = { ["angels-processed-tin"] = 3 }, output = { ["angels-pellet-tin"] = 4 }},
  ["angels-ingot-tin"] = {input = { ["angels-tin-ore"] = 24 }, output = { ["angels-ingot-tin"] = 24 }},
  ["angels-ingot-tin-2"] = {input = { ["angels-processed-tin"] = 8, ["angels-solid-coke"] = 2 }, output = { ["angels-ingot-tin"] = 24 }},
  ["angels-ingot-tin-3"] = {input = { ["angels-pellet-tin"] = 8, ["angels-solid-carbon"] = 2 }, output = { ["angels-ingot-tin"] = 24 }},
  ["angels-liquid-molten-tin"] = {input = { ["angels-ingot-tin"] = 12 }, output = { ["angels-liquid-molten-tin"] = 120 }},
  ["angels-roll-tin"] = {input = { ["angels-liquid-molten-tin"] = 80, water = 40 }, output = { ["angels-roll-tin"] = 2 }},
  ["angels-roll-tin-2"] = {input = { ["angels-liquid-molten-tin"] = 140, ["angels-liquid-coolant"] = 40 }, output = { ["angels-roll-tin"] = 4, ["angels-liquid-coolant-used"] = 40 }},
  ["angels-plate-tin"] = {input = { ["angels-liquid-molten-tin"] = 40 }, output = { ["angels-plate-tin"] = 4 }, productivity = true},
  ["angels-plate-tin-2"] = {input = { ["angels-roll-tin"] = 1 }, output = { ["angels-plate-tin"] = 4 }, productivity = true}
}

local function fail(message)
  error("[mir-angel-tin-audit] " .. message)
end

local function product_map(values)
  local result = {}
  for _, value in pairs(values or {}) do
    local name = value.name or value[1]
    if name then result[name] = value.amount or value[2] or value.amount_min end
  end
  return result
end

local function recipe_products(recipe)
  if recipe.results then return recipe.results end
  if recipe.result then return {{name = recipe.result, amount = recipe.result_count or 1}} end
  return {}
end

local function equal_map(actual, expected, label)
  for name, amount in pairs(expected) do if actual[name] ~= amount then fail(label .. " missing-or-wrong " .. name) end end
  for name in pairs(actual) do if expected[name] == nil then fail(label .. " unexpected " .. name) end end
end

for name in pairs(mods) do if string.match(name, "^bob") then fail("Bob mod active " .. name) end end
for _, name in ipairs({"angelsrefining", "angelspetrochem", "angelssmelting"}) do if not mods[name] then fail("required Angel mod absent " .. name) end end
if data.raw.item["bob-tin-plate"] then fail("Bob Tin identity unexpectedly present") end
if not data.raw.item["angels-plate-tin"] then fail("Angel final Tin output absent") end

for name, expected in pairs(expected_routes) do
  local recipe = data.raw.recipe[name]
  if not recipe then fail("Tin transformation absent " .. name) end
  if recipe.category ~= nil or recipe.enabled ~= false or recipe.hidden ~= true or recipe.auto_recycle ~= false then fail("Tin route state differs " .. name .. " category=" .. tostring(recipe.category) .. " enabled=" .. tostring(recipe.enabled) .. " hidden=" .. tostring(recipe.hidden) .. " auto_recycle=" .. tostring(recipe.auto_recycle)) end
  if (recipe.allow_productivity == true) ~= (expected.productivity == true) then fail("Tin productivity permission differs " .. name) end
  equal_map(product_map(recipe.ingredients), expected.input, name .. " inputs")
  equal_map(product_map(recipe_products(recipe)), expected.output, name .. " outputs")
end

for _, machine in ipairs({"assembling-machine-1", "assembling-machine-2", "assembling-machine-3"}) do
  local entity = data.raw["assembling-machine"][machine]
  local has_crafting = false
  for _, category in pairs(entity and entity.crafting_categories or {}) do if category == "crafting" then has_crafting = true end end
  if not has_crafting then fail("crafting machine witness absent " .. machine) end
end

local function has_tin_ore(values)
  for _, value in pairs(values or {}) do if (value.name or value[1]) == "angels-tin-ore" then return true end end
  return false
end
for name, recipe in pairs(data.raw.recipe) do if has_tin_ore(recipe_products(recipe)) then fail("ordinary Tin-ore producer unexpectedly present " .. name) end end
for name, resource in pairs(data.raw.resource) do
  local minable = resource.minable or {}
  local products = minable.results or (minable.result and {{name = minable.result, amount = minable.count or 1}}) or {}
  if has_tin_ore(products) then fail("Tin-ore resource producer unexpectedly present " .. name) end
end
for _, technology in pairs(data.raw.technology) do
  for _, effect in pairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and (effect.recipe == "angels-plate-tin" or effect.recipe == "angels-plate-tin-2") then fail("native productivity owner unexpectedly present") end
  end
end
if data.raw.technology["recipe-prod-research_material_tin-1"] then fail("MIR Tin owner unexpectedly present") end

local frontier = data.raw.technology["angels-tin-smelting-1"]
if not frontier or frontier.enabled ~= false or frontier.hidden ~= true or (product_map(frontier.unit and frontier.unit.ingredients or {})["automation-science-pack"] ~= 1) then fail("Tin science frontier differs") end
local lab = data.raw.lab.lab
local accepts_automation = false
for _, pack in pairs(lab and lab.inputs or {}) do if pack == "automation-science-pack" then accepts_automation = true end end
if not accepts_automation then fail("lab frontier differs") end
log("[mir-angel-tin-audit] DATA PASS final=angels-plate-tin ordinary-acquisition=0 productivity-owner=none frontier-reachable=false")
