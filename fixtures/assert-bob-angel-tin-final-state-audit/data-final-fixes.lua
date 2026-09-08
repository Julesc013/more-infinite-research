local expected_recipe_ids = {
  "angels-ingot-tin", "angels-ingot-tin-2", "angels-ingot-tin-3", "angels-ingot-tin-recycling", "angels-liquid-molten-brass-2", "angels-liquid-molten-bronze", "angels-liquid-molten-bronze-2", "angels-liquid-molten-bronze-3", "angels-liquid-molten-gunmetal", "angels-liquid-molten-solder", "angels-liquid-molten-solder-2", "angels-liquid-molten-solder-3", "angels-liquid-molten-tin", "angels-liquid-molten-titanium-4", "angels-ore-crushed-mix4-processing", "angels-ore3-chunk-processing", "angels-ore3-crystal-processing", "angels-ore3-pure-processing", "angels-ore6-chunk-processing", "angels-ore6-crushed-processing", "angels-ore6-crystal-processing", "angels-ore6-pure-processing", "angels-ore9-crushed-processing", "angels-ore9-crystal-processing", "angels-ore9-dust-processing", "angels-ore9-powder-processing", "angels-pellet-tin", "angels-pellet-tin-recycling", "angels-plate-glass-3", "angels-plate-tin", "angels-plate-tin-2", "angels-plate-tin-recycling", "angels-powder-tin", "angels-powder-tin-recycling", "angels-processed-tin", "angels-processed-tin-recycling", "angels-roll-tin", "angels-roll-tin-2", "angels-roll-tin-recycling", "angels-tin-ore-recycling", "angels-wire-coil-tin", "angels-wire-coil-tin-2", "angels-wire-coil-tin-recycling", "angels-wire-tin", "angels-wire-tin-2", "angels-wire-tin-recycling", "bob-bronze-alloy", "bob-gunmetal-alloy", "bob-tin-ore-recycling", "bob-tin-plate", "bob-tin-plate-recycling"
}

local hidden_recipe_ids = {
  "angels-ingot-tin-recycling", "angels-liquid-molten-solder", "angels-liquid-molten-solder-2", "angels-liquid-molten-solder-3", "angels-pellet-tin-recycling", "angels-plate-tin-recycling", "angels-powder-tin", "angels-powder-tin-recycling", "angels-processed-tin-recycling", "angels-roll-tin-recycling", "angels-tin-ore-recycling", "angels-wire-coil-tin", "angels-wire-coil-tin-2", "angels-wire-coil-tin-recycling", "angels-wire-tin", "angels-wire-tin-2", "angels-wire-tin-recycling", "bob-bronze-alloy", "bob-gunmetal-alloy", "bob-tin-ore-recycling", "bob-tin-plate", "bob-tin-plate-recycling"
}

local productivity_recipe_ids = {
  "angels-ore-crushed-mix4-processing", "angels-ore3-chunk-processing", "angels-ore3-crystal-processing", "angels-ore3-pure-processing", "angels-ore6-chunk-processing", "angels-ore6-crushed-processing", "angels-ore6-crystal-processing", "angels-ore6-pure-processing", "angels-ore9-crushed-processing", "angels-ore9-crystal-processing", "angels-ore9-dust-processing", "angels-ore9-powder-processing", "angels-plate-glass-3", "angels-plate-tin", "angels-plate-tin-2", "angels-wire-tin-2", "bob-bronze-alloy", "bob-gunmetal-alloy", "bob-tin-plate"
}

local ore_producer_ids = {
  "angels-ore-crushed-mix4-processing", "angels-ore3-chunk-processing", "angels-ore3-crystal-processing", "angels-ore3-pure-processing", "angels-ore6-chunk-processing", "angels-ore6-crushed-processing", "angels-ore6-crystal-processing", "angels-ore6-pure-processing", "angels-ore9-crushed-processing", "angels-ore9-crystal-processing", "angels-ore9-dust-processing", "angels-ore9-powder-processing"
}

local tin_materials = {
  ["bob-tin-ore"] = true, ["angels-processed-tin"] = true, ["angels-pellet-tin"] = true, ["angels-ingot-tin"] = true, ["angels-liquid-molten-tin"] = true, ["angels-roll-tin"] = true, ["bob-tin-plate"] = true, ["angels-powder-tin"] = true, ["angels-wire-coil-tin"] = true, ["angels-wire-tin"] = true
}

local function fail(message) error("[mir-bob-angel-tin-audit] " .. message) end
local function set_of(values) local out = {}; for _, value in ipairs(values) do out[value] = true end; return out end
local function maps_equal(actual, expected, label)
  for name, amount in pairs(expected) do if actual[name] ~= amount then fail(label .. " missing-or-wrong " .. name) end end
  for name in pairs(actual) do if expected[name] == nil then fail(label .. " unexpected " .. name) end end
end
local function product_map(values, fallback_name, fallback_amount)
  local result = {}
  if values then
    for _, value in pairs(values) do
      local name = value.name or value[1]
      if name then result[name] = value.amount or value[2] or value.amount_min end
    end
  elseif fallback_name then result[fallback_name] = fallback_amount or 1 end
  return result
end
local function recipe_products(recipe) return product_map(recipe.results, recipe.result, recipe.result_count) end
local function contains_tin(value)
  if type(value) ~= "string" then return false end
  local lower = string.lower(value)
  local position = string.find(lower, "tin", 1, true)
  while position do
    local before = position == 1 and "" or string.sub(lower, position - 1, position - 1)
    local after = string.sub(lower, position + 3, position + 3)
    if (before == "" or not string.match(before, "[%a]")) and (after == "" or not string.match(after, "[%a]")) then return true end
    position = string.find(lower, "tin", position + 1, true)
  end
  return false
end
local function has_tin_material(values, fallback_name)
  if tin_materials[fallback_name] then return true end
  for _, value in pairs(values or {}) do if tin_materials[value.name or value[1]] then return true end end
  return false
end
local function assert_technology_chain(name, prerequisites)
  local technology = data.raw.technology[name]
  if not technology then fail("technology absent " .. name) end
  maps_equal(set_of(technology.prerequisites or {}), set_of(prerequisites), "technology prerequisites " .. name)
end

for _, name in ipairs({"base", "elevated-rails", "quality", "recycler", "space-age", "boblibrary", "bobores", "bobplates", "angelsrefining", "angelspetrochem", "angelssmelting", "more-infinite-research"}) do if not mods[name] then fail("required exact F210 closure mod absent " .. name) end end
if not data.raw.item["bob-tin-plate"] or data.raw.item["bob-tin-plate"].hidden then fail("Bob final Tin identity differs") end
if not data.raw.item["angels-plate-tin"] or data.raw.item["angels-plate-tin"].hidden ~= true then fail("hidden Angel Tin alias differs") end

local expected = set_of(expected_recipe_ids)
local observed = {}
for name, recipe in pairs(data.raw.recipe) do
  if contains_tin(name) or has_tin_material(recipe.ingredients) or has_tin_material(recipe.results, recipe.result) then observed[name] = true end
end
maps_equal(observed, expected, "exact Tin recipe identity set")
local hidden = set_of(hidden_recipe_ids)
local permitted = set_of(productivity_recipe_ids)
for _, name in ipairs(expected_recipe_ids) do
  local recipe = data.raw.recipe[name]
  if not recipe or recipe.enabled ~= false or recipe.category ~= nil then fail("raw recipe state differs " .. name) end
  if recipe.hidden ~= (hidden[name] and true or nil) then fail("raw recipe hidden state differs " .. name) end
  if recipe.auto_recycle == true then fail("automatic recycling unexpectedly present " .. name) end
  if (recipe.allow_productivity == true) ~= (permitted[name] == true) then fail("productivity permission differs " .. name) end
end

local non_recycling_final_plate_transformations = {
  ["angels-plate-tin"] = {hidden = nil, input = { ["angels-liquid-molten-tin"] = 40 }, output = { ["bob-tin-plate"] = 4 }},
  ["angels-plate-tin-2"] = {hidden = nil, input = { ["angels-roll-tin"] = 1 }, output = { ["bob-tin-plate"] = 4 }},
  ["bob-tin-plate"] = {hidden = true, input = { ["bob-tin-ore"] = 1 }, output = { ["bob-tin-plate"] = 1 }}
}
for name, expected_route in pairs(non_recycling_final_plate_transformations) do
  local recipe = data.raw.recipe[name]
  if recipe.hidden ~= expected_route.hidden or recipe.allow_productivity ~= true or recipe.auto_recycle ~= false then fail("key final plate state differs " .. name) end
  maps_equal(product_map(recipe.ingredients), expected_route.input, name .. " inputs")
  maps_equal(recipe_products(recipe), expected_route.output, name .. " products")
end
local observed_final_plate_producers = {}
local observed_recycling_final_plate_producers = {}
local observed_non_recycling_final_plate_transformations = {}
for name, recipe in pairs(data.raw.recipe) do
  if recipe_products(recipe)["bob-tin-plate"] ~= nil then
    observed_final_plate_producers[name] = true
    if string.match(name, "%-recycling$") then observed_recycling_final_plate_producers[name] = true else observed_non_recycling_final_plate_transformations[name] = true end
  end
end
maps_equal(observed_final_plate_producers, set_of({"angels-plate-tin", "angels-plate-tin-2", "angels-plate-tin-recycling", "angels-wire-tin-recycling", "bob-tin-plate", "bob-tin-plate-recycling"}), "exact all declared final plate producer set")
maps_equal(observed_recycling_final_plate_producers, set_of({"angels-plate-tin-recycling", "angels-wire-tin-recycling", "bob-tin-plate-recycling"}), "exact declared recycling final plate producer set")
maps_equal(observed_non_recycling_final_plate_transformations, set_of({"angels-plate-tin", "angels-plate-tin-2", "bob-tin-plate"}), "exact non-recycling final plate transformation set")

local expected_ore = set_of(ore_producer_ids)
local observed_ore = {}
for name, recipe in pairs(data.raw.recipe) do
  if recipe_products(recipe)["bob-tin-ore"] and not string.match(name, "recycling$") then observed_ore[name] = true end
end
maps_equal(observed_ore, expected_ore, "ordinary Tin ore producer set")
maps_equal(product_map(data.raw.recipe["angels-ore-crushed-mix4-processing"].ingredients), { ["angels-catalysator-brown"] = 1, ["angels-ore3-crushed"] = 2, ["angels-ore6-crushed"] = 2 }, "catalyst route inputs")
maps_equal(recipe_products(data.raw.recipe["angels-ore-crushed-mix4-processing"]), { ["bob-tin-ore"] = 4 }, "catalyst route products")

local route_checks = {
  ["angels-processed-tin"] = {input = { ["bob-tin-ore"] = 4 }, output = { ["angels-processed-tin"] = 2 }},
  ["angels-pellet-tin"] = {input = { ["angels-processed-tin"] = 3 }, output = { ["angels-pellet-tin"] = 4 }},
  ["angels-ingot-tin-3"] = {input = { ["angels-pellet-tin"] = 8, ["angels-solid-carbon"] = 2 }, output = { ["angels-ingot-tin"] = 24 }},
  ["angels-liquid-molten-tin"] = {input = { ["angels-ingot-tin"] = 12 }, output = { ["angels-liquid-molten-tin"] = 120 }},
  ["angels-roll-tin"] = {input = { ["angels-liquid-molten-tin"] = 80, water = 40 }, output = { ["angels-roll-tin"] = 2 }}
}
for name, expected_route in pairs(route_checks) do maps_equal(product_map(data.raw.recipe[name].ingredients), expected_route.input, name .. " inputs"); maps_equal(recipe_products(data.raw.recipe[name]), expected_route.output, name .. " products") end
local plate_consumers = {}
for name, recipe in pairs(data.raw.recipe) do if product_map(recipe.ingredients)["bob-tin-plate"] then plate_consumers[name] = true end end
maps_equal(plate_consumers, set_of({"angels-plate-tin-recycling", "angels-wire-tin", "bob-bronze-alloy", "bob-gunmetal-alloy", "bob-tin-plate-recycling"}), "final plate consumer set")
for name, recipe in pairs(data.raw.recipe) do
  if product_map(recipe.ingredients)["bob-tin-plate"] and recipe_products(recipe)["bob-tin-ore"] then fail("unexpected direct plate to ore recipe edge " .. name) end
end

maps_equal(recipe_products(data.raw.recipe["angels-roll-tin-2"]), { ["angels-roll-tin"] = 4, ["angels-liquid-coolant-used"] = 40 }, "roll coolant byproduct")
maps_equal(recipe_products(data.raw.recipe["angels-wire-coil-tin-2"]), { ["angels-wire-coil-tin"] = 8, ["angels-liquid-coolant-used"] = 40 }, "wire coil coolant byproduct")
local recycling = data.raw.technology.recycling
if not recycling or not set_of(recycling.prerequisites or {})["planet-discovery-fulgora"] then fail("Fulgora recycling disposition differs") end
for _, resource in pairs(data.raw.resource) do if recipe_products({results = resource.minable and resource.minable.results, result = resource.minable and resource.minable.result, result_count = resource.minable and resource.minable.count})["bob-tin-ore"] then fail("unexpected direct Tin ore resource producer") end end

for technology_name, technology in pairs(data.raw.technology) do
  for _, effect in pairs(technology.effects or {}) do if effect.type == "change-recipe-productivity" and expected[effect.recipe] then fail("native productivity owner unexpectedly present " .. technology_name) end end
end
if data.raw.technology["recipe-prod-research_material_tin-1"] then fail("MIR Tin technology unexpectedly present") end
assert_technology_chain("angels-basic-chemistry", {"automation"})
assert_technology_chain("angels-ore-crushing", {"angels-basic-chemistry"})
assert_technology_chain("angels-metallurgy-1", {"angels-ore-crushing"})
assert_technology_chain("angels-tin-smelting-1", {"angels-metallurgy-1"})
local frontier = data.raw.technology["angels-tin-smelting-1"]
if frontier.enabled ~= nil or frontier.hidden ~= nil or product_map(frontier.unit and frontier.unit.ingredients)["automation-science-pack"] ~= 1 then fail("Tin prototype frontier differs") end
local frontier_unlocks = {}
for _, effect in pairs(frontier.effects or {}) do if effect.type == "unlock-recipe" then frontier_unlocks[effect.recipe] = true end end
maps_equal(frontier_unlocks, set_of({"angels-ingot-tin", "angels-liquid-molten-tin", "angels-plate-tin"}), "Tin prototype unlock effects")
local accepts_automation = false
for _, pack in pairs(data.raw.lab.lab and data.raw.lab.lab.inputs or {}) do if pack == "automation-science-pack" then accepts_automation = true end end
if not accepts_automation then fail("lab prototype frontier differs") end
for _, machine in ipairs({"assembling-machine-1", "assembling-machine-2", "assembling-machine-3"}) do
  local crafting = false
  for _, category in pairs(data.raw["assembling-machine"][machine].crafting_categories or {}) do if category == "crafting" then crafting = true end end
  if not crafting then fail("conditional crafting capability differs " .. machine) end
end
log("[mir-bob-angel-tin-audit] DATA PASS final=bob-tin-plate recipes=51 ore-producers=12 productivity-owner=none mir-owner=absent gameplay-reachability=unclaimed")
